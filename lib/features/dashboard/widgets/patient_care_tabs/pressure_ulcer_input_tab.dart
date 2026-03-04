part of '../../pages/patient_care_page.dart';

class _PressurePoint {
  final String name;
  final double x; // 0..1 fraction of image width
  final double y; // 0..1 fraction of image height
  final bool labelLeft; // true -> label on left side
  const _PressurePoint(this.name, this.x, this.y, this.labelLeft);
}

class _PressureUlcerLogEntry {
  final int? historyId;
  final String dateText;
  final String bodyPartName;
  final int stage;

  const _PressureUlcerLogEntry({
    this.historyId,
    required this.dateText,
    required this.bodyPartName,
    required this.stage,
  });
}

class _PressureUlcerInputTab extends StatefulWidget {
  final int patientCode;
  const _PressureUlcerInputTab({required this.patientCode});

  @override
  State<_PressureUlcerInputTab> createState() => _PressureUlcerInputTabState();
}

class _PressureUlcerInputTabState extends State<_PressureUlcerInputTab> {
  final Map<String, int> _stages = {};
  final Map<String, String> _notes = {};
  final List<_PressureUlcerLogEntry> _pressureUlcerLogs = [];
  static const int _logRowsPerPage = 8;
  int _currentLogPage = 1;
  int _serverTotalPages = 1;
  bool _isLoading = false;
  bool _isLogLoading = false;
  Map<String, List<Map<String, dynamic>>> _chartData = {};

  static const _apiNameToPointName = <String, String>{
    '좌측 귀': '귀(좌)',
    '우측 귀': '귀(우)',
    '후두부': '후두부',
    '좌측 어깨뼈': '어깨뼈(좌)',
    '우측 어깨뼈': '어깨뼈(우)',
    '등': '등',
    '엉치뼈': '엉치뼈',
    '좌골': '좌골',
    '좌측 엉덩이옆': '엉덩이옆(좌)',
    '우측 엉덩이옆': '엉덩이옆(우)',
    '좌측 무릎': '무릎(좌)',
    '우측 무릎': '무릎(우)',
    '좌측 복숭아뼈': '복숭아뼈(좌)',
    '우측 복숭아뼈': '복숭아뼈(우)',
    '좌측 뒤꿈치': '뒷꿈치(좌)',
    '우측 뒤꿈치': '뒷꿈치(우)',
  };

  static const _partCodeToPointName = <int, String>{
    1: '귀(좌)',
    2: '귀(우)',
    3: '후두부',
    4: '어깨뼈(좌)',
    5: '어깨뼈(우)',
    6: '등',
    7: '엉치뼈',
    8: '좌골',
    9: '엉덩이옆(좌)',
    10: '엉덩이옆(우)',
    11: '무릎(좌)',
    12: '무릎(우)',
    13: '복숭아뼈(좌)',
    14: '복숭아뼈(우)',
    15: '뒷꿈치(좌)',
    16: '뒷꿈치(우)',
  };

  static const _pointNameToPartCode = <String, int>{
    '귀(좌)': 1,
    '귀(우)': 2,
    '후두부': 3,
    '어깨뼈(좌)': 4,
    '어깨뼈(우)': 5,
    '등': 6,
    '엉치뼈': 7,
    '좌골': 8,
    '엉덩이옆(좌)': 9,
    '엉덩이옆(우)': 10,
    '무릎(좌)': 11,
    '무릎(우)': 12,
    '복숭아뼈(좌)': 13,
    '복숭아뼈(우)': 14,
    '뒷꿈치(좌)': 15,
    '뒷꿈치(우)': 16,
  };

  static const _centerPoints = <String>{'후두부', '등', '엉치뼈', '좌골'};

  static const _centerOffsets = <String, Offset>{
    '엉치뼈': Offset(0, -10),
    '좌골': Offset(0, 20),
  };

  static const _kPoints = <_PressurePoint>[
    _PressurePoint('후두부', 0.50, 0.05, true),
    _PressurePoint('귀(좌)', 0.38, 0.07, true),
    _PressurePoint('귀(우)', 0.62, 0.07, false),
    _PressurePoint('어깨뼈(좌)', 0.30, 0.19, true),
    _PressurePoint('어깨뼈(우)', 0.70, 0.19, false),
    _PressurePoint('등', 0.50, 0.30, true),
    _PressurePoint('엉치뼈', 0.50, 0.45, true),
    _PressurePoint('엉덩이옆(좌)', 0.23, 0.48, true),
    _PressurePoint('좌골', 0.50, 0.50, true),
    _PressurePoint('엉덩이옆(우)', 0.77, 0.48, false),
    _PressurePoint('무릎(좌)', 0.37, 0.68, true),
    _PressurePoint('무릎(우)', 0.63, 0.68, false),
    _PressurePoint('복숭아뼈(좌)', 0.38, 0.87, true),
    _PressurePoint('복숭아뼈(우)', 0.62, 0.87, false),
    _PressurePoint('뒷꿈치(좌)', 0.38, 0.95, true),
    _PressurePoint('뒷꿈치(우)', 0.62, 0.95, false),
  ];

  static const _stageColors = <Color>[
    Color(0xFF3B82F6),
    Color(0xFFFCA5A5),
    Color(0xFFF87171),
    Color(0xFFEF4444),
    Color(0xFFB91C1C),
  ];

  String? _activeCenterName;

  @override
  void initState() {
    super.initState();
    _fetchCurrentUlcerState();
    _fetchChartData();
    _fetchLogHistory();
  }

  Future<void> _fetchLogHistory({int page = 1}) async {
    setState(() => _isLogLoading = true);
    try {
      final uri = Uri.parse(
        '${UrlConfig.serverUrl}/api/patient/ulcer/history'
        '?patient_code=${widget.patientCode}&page=$page&size=$_logRowsPerPage',
      );
      final res = await HttpHelper.getJson(uri);
      if (res['code'] != 1) return;
      final data = res['data'] as Map<String, dynamic>?;
      if (data == null) return;

      final itemsRaw = data['records'] as List<dynamic>? ?? const [];
      final entries = itemsRaw.map((raw) {
        final item = raw as Map<String, dynamic>;
        return _PressureUlcerLogEntry(
          historyId: item['history_code'] as int?,
          dateText: item['record_date'] as String? ?? '',
          bodyPartName: item['part_name'] as String? ?? '',
          stage: item['stage_level'] as int? ?? 0,
        );
      }).toList();

      final serverTotalPages = data['total_pages'] as int? ?? 1;

      if (!mounted) return;
      setState(() {
        _serverTotalPages = serverTotalPages;
        _currentLogPage = page;
        _pressureUlcerLogs
          ..clear()
          ..addAll(entries);
      });
    } catch (e) {
      debugPrint('[ULCER_LOG_FETCH] error: $e');
    } finally {
      if (mounted) setState(() => _isLogLoading = false);
    }
  }

  Future<void> _fetchChartData() async {
    try {
      final uri = Uri.parse(
        '${UrlConfig.serverUrl}/api/patient/ulcer/history/chart?patient_code=${widget.patientCode}',
      );
      final res = await HttpHelper.getJson(uri);
      if (res['code'] != 1) return;
      final data = res['data'] as Map<String, dynamic>?;
      if (data == null) return;
      final raw = data['chart_data'] as Map<String, dynamic>?;
      if (raw == null) return;

      final newChartData = <String, List<Map<String, dynamic>>>{};
      for (final entry in raw.entries) {
        final localName = _apiNameToPointName[entry.key];
        if (localName == null) continue;
        newChartData[localName] =
            (entry.value as List).cast<Map<String, dynamic>>();
      }

      if (!mounted) return;
      setState(() {
        _chartData
          ..clear()
          ..addAll(newChartData);
      });
    } catch (e) {
      debugPrint('[ULCER_CHART_FETCH] error: $e');
    }
  }

  Future<void> _fetchCurrentUlcerState() async {
    setState(() => _isLoading = true);
    try {
      final uri = Uri.parse(
        '${UrlConfig.serverUrl}/api/patient/ulcer/history/current?patient_code=${widget.patientCode}',
      );
      final res = await HttpHelper.getJson(uri);
      if (res['code'] != 1) return;
      final dataList = res['data'] as List?;
      if (dataList == null) return;

      final newStages = <String, int>{};
      final newNotes = <String, String>{};
      for (final raw in dataList) {
        final item = raw as Map<String, dynamic>;
        final partCode = item['part_code'] as int?;
        final stageLevel = item['stage_level'] as int?;
        if (partCode == null || stageLevel == null || stageLevel == 0) continue;
        final pointName = _partCodeToPointName[partCode];
        if (pointName == null) continue;
        newStages[pointName] = stageLevel;
        final note = item['notes'] as String?;
        if (note != null && note.isNotEmpty) newNotes[pointName] = note;
      }

      if (!mounted) return;
      setState(() {
        _stages
          ..clear()
          ..addAll(newStages);
        _notes
          ..clear()
          ..addAll(newNotes);
      });
    } catch (e) {
      debugPrint('[ULCER_FETCH] error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: SizedBox(
                  height: 600,
                  child: LayoutBuilder(
                    builder: (context, box) {
                      return _buildBody(box);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                child: SizedBox(
                  height: 600,
                  child: _buildPressureUlcerLogPanel(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _buildPressureGraphs(),
        ],
      ),
    );
  }

  Widget _buildPressureUlcerLogPanel() {
    final totalPages = _totalLogPages;
    final visibleLogs = _visiblePressureUlcerLogs;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 7),
              decoration: BoxDecoration(
                color: const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFF6DC16A)),
              ),
              child: const Text(
                '욕창 단계 내역',
                style: TextStyle(
                  color: Color(0xFF6DC16A),
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                SizedBox(
                  width: 88,
                  child: Text(
                    '날짜',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    '부위별 단계',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                    ),
                  ),
                ),
                SizedBox(width: 28),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: Color(0xFFE5E7EB)),
          Expanded(
            child: visibleLogs.isEmpty
                ? const Center(
                    child: Text(
                      '아직 입력된 욕창 단계 로그가 없습니다.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF9CA3AF),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  )
                : Column(
                    children: [
                      for (final logEntry in visibleLogs)
                        _buildPressureUlcerLogRow(logEntry),
                    ],
                  ),
          ),
          if (totalPages > 1) ...[
            const Divider(height: 1, color: Color(0xFFE5E7EB)),
            const SizedBox(height: 10),
            _buildPagination(totalPages),
          ],
        ],
      ),
    );
  }

  Widget _buildPressureUlcerLogRow(_PressureUlcerLogEntry logEntry) {
    return Container(
      height: 46,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 88,
            child: Text(
              logEntry.dateText,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF374151),
              ),
            ),
          ),
          Expanded(
            child: Text(
              '${logEntry.bodyPartName} - ${logEntry.stage}단계',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF111827),
              ),
            ),
          ),
          SizedBox(
            width: 28,
            child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: '삭제',
              onPressed: () => _handleDeleteLog(logEntry),
              icon: const Icon(Icons.close, size: 16, color: Color(0xFF9CA3AF)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPagination(int totalPages) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          onPressed: _currentLogPage > 1
              ? () => _fetchLogHistory(page: _currentLogPage - 1)
              : null,
          icon: const Icon(Icons.chevron_left, size: 18),
          color: const Color(0xFF6B7280),
        ),
        for (int pageNumber = 1; pageNumber <= totalPages; pageNumber++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => _fetchLogHistory(page: pageNumber),
              child: Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _currentLogPage == pageNumber
                      ? const Color(0xFFE5E7EB)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$pageNumber',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _currentLogPage == pageNumber
                        ? const Color(0xFF111827)
                        : const Color(0xFF6B7280),
                  ),
                ),
              ),
            ),
          ),
        IconButton(
          onPressed: _currentLogPage < totalPages
              ? () => _fetchLogHistory(page: _currentLogPage + 1)
              : null,
          icon: const Icon(Icons.chevron_right, size: 18),
          color: const Color(0xFF6B7280),
        ),
      ],
    );
  }

  int get _totalLogPages => _serverTotalPages.clamp(1, 9999);

  List<_PressureUlcerLogEntry> get _visiblePressureUlcerLogs =>
      _pressureUlcerLogs;

  Future<void> _handleDeleteLog(_PressureUlcerLogEntry logEntry) async {
    final historyCode = logEntry.historyId;
    if (historyCode == null) return;

    try {
      final uri = Uri.parse(
        '${UrlConfig.serverUrl}/api/patient/ulcer/history/$historyCode',
      );
      final res = await HttpHelper.sendJson('DELETE', uri);
      if (res['code'] != 1) return;
    } catch (e) {
      debugPrint('[ULCER_DELETE] error: $e');
      return;
    }

    final targetPage =
        _pressureUlcerLogs.length == 1 && _currentLogPage > 1
            ? _currentLogPage - 1
            : _currentLogPage;
    _fetchLogHistory(page: targetPage);
    _fetchCurrentUlcerState();
    _fetchChartData();
  }

  Widget _buildBody(BoxConstraints box) {
    final totalW = box.maxWidth;
    final totalH = box.maxHeight;

    const imgAR = 0.455;
    final maxImgW = totalW * 0.40;
    final maxImgH = totalH * 0.92;

    double imgW, imgH;
    if (maxImgW / maxImgH > imgAR) {
      imgH = maxImgH;
      imgW = imgH * imgAR;
    } else {
      imgW = maxImgW;
      imgH = imgW / imgAR;
    }

    final imgLeft = (totalW - imgW) / 2;
    final imgTop = (totalH - imgH) / 2;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          left: imgLeft,
          top: imgTop,
          width: imgW,
          height: imgH,
          child: Opacity(
            opacity: 0.25,
            child: Image.asset(
              'assets/images/person_img.png',
              fit: BoxFit.fill,
            ),
          ),
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: _ConnectionLinePainter(
              points: _kPoints,
              stages: _stages,
              stageColors: _stageColors,
              imgLeft: imgLeft,
              imgTop: imgTop,
              imgW: imgW,
              imgH: imgH,
            ),
          ),
        ),
        for (final p in _kPoints)
          if (!_centerPoints.contains(p.name))
            _buildDot(p, imgLeft, imgTop, imgW, imgH),
        for (final p in _kPoints)
          if (_centerPoints.contains(p.name))
            _buildCenterButton(p, imgLeft, imgTop, imgW, imgH),
        for (final p in _kPoints)
          if (!_centerPoints.contains(p.name))
            _buildLabelButton(p, imgLeft, imgTop, imgW, imgH, totalW),
      ],
    );
  }

  Widget _buildDot(
    _PressurePoint p,
    double imgLeft,
    double imgTop,
    double imgW,
    double imgH,
  ) {
    final dotX = imgLeft + imgW * p.x;
    final dotY = imgTop + imgH * p.y;
    final stage = _stages[p.name];
    final color = _stageColors[stage ?? 0];

    return Positioned(
      left: dotX - 8,
      top: dotY - 8,
      child: GestureDetector(
        onTapUp: (d) => _showStageMenu(p.name, d.globalPosition),
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabelButton(
    _PressurePoint p,
    double imgLeft,
    double imgTop,
    double imgW,
    double imgH,
    double totalW,
  ) {
    final dotY = imgTop + imgH * p.y;
    final stage = _stages[p.name];
    final color = _stageColors[stage ?? 0];
    final label = stage != null ? '${p.name} ($stage단계)' : p.name;
    final isActive = _activeCenterName == p.name;

    const btnH = 36.0;

    final button = GestureDetector(
      onTapUp: (d) async {
        setState(() => _activeCenterName = p.name);
        await _showStageMenu(p.name, d.globalPosition);
        if (!mounted) return;
        setState(() => _activeCenterName = null);
      },
      child: Container(
        height: btnH,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF4F83C1)
              : stage != null
                  ? color
                  : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? const Color(0xFF4F83C1)
                : stage != null
                    ? color
                    : const Color(0xFF4F83C1),
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x22000000),
              blurRadius: 6,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive
                ? Colors.white
                : stage != null
                    ? Colors.white
                    : const Color(0xFF4F83C1),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );

    if (p.labelLeft) {
      return Positioned(
        right: totalW - imgLeft + 12,
        top: dotY - btnH / 2,
        child: button,
      );
    } else {
      return Positioned(
        left: imgLeft + imgW + 12,
        top: dotY - btnH / 2,
        child: button,
      );
    }
  }

  Widget _buildCenterButton(
    _PressurePoint p,
    double imgLeft,
    double imgTop,
    double imgW,
    double imgH,
  ) {
    final baseX = imgLeft + imgW * p.x;
    final baseY = imgTop + imgH * p.y;
    final offset = _centerOffsets[p.name] ?? Offset.zero;
    final x = baseX + offset.dx;
    final y = baseY + offset.dy;
    final stage = _stages[p.name];
    final color = _stageColors[stage ?? 0];
    final label = stage != null ? '${p.name} ($stage단계)' : p.name;
    final isActive = _activeCenterName == p.name;

    return Positioned(
      left: x,
      top: y,
      child: Transform.translate(
        offset: const Offset(-0.5, -0.5),
        child: FractionalTranslation(
          translation: const Offset(-0.5, -0.5),
          child: GestureDetector(
            onTapUp: (d) async {
              setState(() {
                _activeCenterName = p.name;
              });

              await _showStageMenu(p.name, d.globalPosition);

              if (!mounted) return;
              setState(() {
                _activeCenterName = null;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: isActive
                    ? const Color(0xFF4F83C1)
                    : stage != null
                        ? color
                        : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isActive
                      ? const Color(0xFF4F83C1)
                      : stage != null
                          ? color
                          : const Color(0xFF4F83C1),
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: isActive
                      ? Colors.white
                      : stage != null
                          ? Colors.white
                          : const Color(0xFF4F83C1),
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPressureGraphs() {
    final parts = _kPoints.map((p) => p.name).toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: parts.length,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1.8,
        ),
        itemBuilder: (context, index) {
          final part = parts[index];
          return _PressureGraphCard(
            title: part,
            chartData: _chartData[part] ?? [],
          );
        },
      ),
    );
  }

  Future<void> _showStageMenu(String name, Offset globalPos) async {
    String? capturedNote;

    final result = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      barrierColor: const Color(0x99000000),
      constraints: const BoxConstraints(maxWidth: 1300),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final remarkCtrl = TextEditingController(text: _notes[name] ?? '');
        int? selectedStage = _stages[name];

        return StatefulBuilder(
          builder: (context, setSheetState) {
            final keyboardH = MediaQuery.of(context).viewInsets.bottom;
            return SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + keyboardH),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          '욕창 단계 입력',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: '닫기',
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close, color: Colors.grey),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Divider(),
                    const Text(
                      '선택 부위',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Color.fromARGB(255, 85, 118, 191),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '단계 선택',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        OutlinedButton(
                          onPressed: () {
                            setSheetState(() => selectedStage = 0);
                          },
                          style: OutlinedButton.styleFrom(
                            backgroundColor: selectedStage == 0
                                ? const Color(0xFF6B7280)
                                : Colors.white,
                            foregroundColor: selectedStage == 0
                                ? Colors.white
                                : const Color(0xFF6B7280),
                            side: const BorderSide(color: Color(0xFF6B7280)),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            '없음',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                        ),
                        ...List.generate(4, (index) {
                          final stage = index + 1;
                          final isSelected = selectedStage == stage;
                          return OutlinedButton(
                            onPressed: () {
                              setSheetState(() => selectedStage = stage);
                            },
                            style: OutlinedButton.styleFrom(
                              backgroundColor: isSelected
                                  ? const Color(0xFF6183EE)
                                  : Colors.white,
                              foregroundColor: isSelected
                                  ? Colors.white
                                  : const Color(0xFF374151),
                              side: const BorderSide(color: Color(0xFF6183EE)),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            child: Text(
                              '$stage단계',
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      '비고',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: remarkCtrl,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: '비고를 입력하세요',
                        hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                        filled: true,
                        fillColor: const Color(0xFFF9FAFB),
                        contentPadding: const EdgeInsets.all(14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFFE5E7EB),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFFE5E7EB),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: Color(0xFF6183EE),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF374151),
                            side: const BorderSide(color: Color(0xFFE5E7EB)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                          child: const Text(
                            '취소',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: () async {
                            if (selectedStage == null) {
                              Navigator.pop(context);
                              return;
                            }
                            final partCode = _pointNameToPartCode[name];
                            if (partCode != null) {
                              try {
                                final now = DateTime.now();
                                final recordDate =
                                    '${now.year.toString().padLeft(4, '0')}-'
                                    '${now.month.toString().padLeft(2, '0')}-'
                                    '${now.day.toString().padLeft(2, '0')}';
                                final uri = Uri.parse(
                                  '${UrlConfig.serverUrl}/api/patient/ulcer/history',
                                );
                                await HttpHelper.postJson(uri, {
                                  'patient_code': widget.patientCode,
                                  'record_date': recordDate,
                                  'part_code': partCode,
                                  'stage_code': selectedStage,
                                  'notes': remarkCtrl.text.trim().isEmpty
                                      ? null
                                      : remarkCtrl.text.trim(),
                                });
                                capturedNote = remarkCtrl.text.trim();
                              } catch (e) {
                                debugPrint('[ULCER_SAVE] error: $e');
                              }
                            }
                            if (!context.mounted) return;
                            Navigator.pop(context, selectedStage);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6183EE),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                          child: const Text(
                            '저장',
                            style: TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (result != null) {
      setState(() {
        if (result == 0) {
          _stages.remove(name);
          _notes.remove(name);
        } else {
          _stages[name] = result;
          if (capturedNote != null && capturedNote!.isNotEmpty) {
            _notes[name] = capturedNote!;
          } else {
            _notes.remove(name);
          }
        }
      });
      _fetchLogHistory(page: 1);
      _fetchChartData();
    }
  }
}

class _ConnectionLinePainter extends CustomPainter {
  final List<_PressurePoint> points;
  final Map<String, int> stages;
  final List<Color> stageColors;
  final double imgLeft, imgTop, imgW, imgH;

  _ConnectionLinePainter({
    required this.points,
    required this.stages,
    required this.stageColors,
    required this.imgLeft,
    required this.imgTop,
    required this.imgW,
    required this.imgH,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in points) {
      if (_PressureUlcerInputTabState._centerPoints.contains(p.name)) {
        continue;
      }

      final dotX = imgLeft + imgW * p.x;
      final dotY = imgTop + imgH * p.y;
      final stage = stages[p.name];
      final color = stageColors[stage ?? 0];

      final linePaint = Paint()
        ..color = stage != null
            ? color.withValues(alpha: 0.5)
            : const Color(0xFFB0B8C4)
        ..strokeWidth = 1;

      if (p.labelLeft) {
        final lineEndX = imgLeft - 10;
        canvas.drawLine(Offset(dotX, dotY), Offset(lineEndX, dotY), linePaint);
      } else {
        final lineEndX = imgLeft + imgW + 10;
        canvas.drawLine(Offset(dotX, dotY), Offset(lineEndX, dotY), linePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectionLinePainter old) => true;
}

class _PressureGraphCard extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> chartData;

  const _PressureGraphCard({required this.title, required this.chartData});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _showPressureGraphDialog(context, title, chartData),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.open_in_full,
                  size: 16,
                  color: Color(0xFF9CA3AF),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(child: _buildPressureLineChart(chartData: chartData)),
          ],
        ),
      ),
    );
  }
}

void _showPressureGraphDialog(
  BuildContext context,
  String title,
  List<Map<String, dynamic>> chartData,
) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 36, vertical: 28),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 1080, maxHeight: 760),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFE5E7EB)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 20,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '$title 그래프',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: '닫기',
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    icon: const Icon(Icons.close, color: Color(0xFF6B7280)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Divider(height: 1, color: Color(0xFFE5E7EB)),
              const SizedBox(height: 20),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
                  child: _PressureGraphExpandedView(chartData: chartData),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _PressureGraphExpandedView extends StatelessWidget {
  final List<Map<String, dynamic>> chartData;
  const _PressureGraphExpandedView({required this.chartData});

  @override
  Widget build(BuildContext context) {
    return _buildPressureLineChart(
      chartData: chartData,
      showLargeLabels: true,
      lineWidth: 3,
      dotRadius: 4,
    );
  }
}

Color _ulcerStageColor(int maxStage) {
  const colors = [
    Color(0xFFD1D5DB),
    Color(0xFFFCA5A5),
    Color(0xFFF87171),
    Color(0xFFEF4444),
    Color(0xFFB91C1C),
  ];
  if (maxStage < 1 || maxStage > 4) return colors[0];
  return colors[maxStage];
}

Widget _buildPressureLineChart({
  required List<Map<String, dynamic>> chartData,
  bool showLargeLabels = false,
  double lineWidth = 2,
  double dotRadius = 3,
}) {
  final effectiveData = chartData.isEmpty
      ? [<String, dynamic>{'date': '', 'stage_level': 0}]
      : chartData;

  final spots = <FlSpot>[
    for (int i = 0; i < effectiveData.length; i++)
      FlSpot(
        i.toDouble(),
        (effectiveData[i]['stage_level'] as int? ?? 0).toDouble(),
      ),
  ];

  final latestStage = effectiveData.last['stage_level'] as int? ?? 0;
  final lineColor = _ulcerStageColor(latestStage);

  final dates = effectiveData.map((e) {
    final raw = e['date'] as String? ?? '';
    final parts = raw.split('-');
    return parts.length >= 3 ? '${parts[1]}/${parts[2]}' : '—';
  }).toList();

  return LineChart(
    LineChartData(
      minY: 0,
      maxY: 4,
      gridData: FlGridData(show: true),
      titlesData: FlTitlesData(
        topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        rightTitles: const AxisTitles(
          sideTitles: SideTitles(showTitles: false),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 1,
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index < 0 || index >= dates.length) {
                return const SizedBox.shrink();
              }
              return Text(
                dates[index],
                style: TextStyle(
                  fontSize: showLargeLabels ? 12 : 10,
                  color: const Color(0xFF6B7280),
                  fontWeight:
                      showLargeLabels ? FontWeight.w700 : FontWeight.w500,
                ),
              );
            },
          ),
        ),
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            interval: 1,
            getTitlesWidget: (value, meta) {
              return Text(
                value.toInt().toString(),
                style: TextStyle(
                  fontSize: showLargeLabels ? 12 : 10,
                  fontWeight:
                      showLargeLabels ? FontWeight.w700 : FontWeight.w500,
                ),
              );
            },
          ),
        ),
      ),
      borderData: FlBorderData(show: false),
      lineBarsData: [
        LineChartBarData(
          spots: spots,
          isCurved: true,
          barWidth: lineWidth,
          color: lineColor,
          dotData: FlDotData(
            show: true,
            getDotPainter: (spot, percent, barData, index) {
              return FlDotCirclePainter(
                radius: dotRadius,
                color: lineColor,
                strokeWidth: 1.5,
                strokeColor: Colors.white,
              );
            },
          ),
        ),
      ],
    ),
  );
}
