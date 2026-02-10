import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

/// 케어 입력 다이얼로그 (욕창단계입력 / 욕창정보 / 식단 / 실금)
class PatientCareDialog extends StatefulWidget {
  final int patientCode;
  final String patientName;
  final String? roomLabel;
  final String? bedLabel;

  const PatientCareDialog({
    super.key,
    required this.patientCode,
    required this.patientName,
    this.roomLabel,
    this.bedLabel,
  });

  @override
  State<PatientCareDialog> createState() => _PatientCareDialogState();
}

class _PatientCareDialogState extends State<PatientCareDialog>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Container(
        width: 1120,
        decoration: BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 헤더
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 18, 12),
              child: Row(
                children: [
                  Text(
                    '${widget.patientName} 케어 입력',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF374151),
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text(
                      '닫기',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE5E7EB)),

            // 탭 바
            AnimatedBuilder(
              animation: _tabController,
              builder: (context, _) {
                final selected = _tabController.index;
                const labels = ['욕창단계입력', '욕창정보', '식단', '실금'];

                return Padding(
                  padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
                  child: Row(
                    children: List.generate(labels.length, (i) {
                      final isActive = selected == i;
                      return Padding(
                        padding: EdgeInsets.only(
                          right: i < labels.length - 1 ? 8 : 0,
                        ),
                        child: GestureDetector(
                          onTap: () => _tabController.animateTo(i),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? const Color(0xFF7F9BD8)
                                  : const Color(0xFFF3F4F6),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(10),
                                topRight: Radius.circular(10),
                              ),
                              border: Border(
                                top: BorderSide(
                                  color: isActive
                                      ? const Color(0xFF7F9BD8)
                                      : const Color(0xFFE2E8F0),
                                ),
                                left: BorderSide(
                                  color: isActive
                                      ? const Color(0xFF7F9BD8)
                                      : const Color(0xFFE2E8F0),
                                ),
                                right: BorderSide(
                                  color: isActive
                                      ? const Color(0xFF7F9BD8)
                                      : const Color(0xFFE2E8F0),
                                ),
                              ),
                            ),
                            child: Text(
                              labels[i],
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: isActive
                                    ? Colors.white
                                    : const Color(0xFF6B7280),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                );
              },
            ),

            // 탭 내용
            Flexible(
              child: Container(
                color: const Color(0xFFF3F4F6),
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // 탭 1: 욕창단계입력
                    const _PressureUlcerInputTab(),

                    // 탭 2: 욕창정보
                    const Center(
                      child: Text(
                        '욕창단계정보',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ),

                    // 탭 3: 식단
                    const Center(
                      child: Text(
                        '식단',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ),

                    // 탭 4: 실금
                    const Center(
                      child: Text(
                        '실금',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 욕창단계입력 (Pressure Ulcer Stage Input)
// ══════════════════════════════════════════════════════════════

class _PressurePoint {
  final String name;
  final double x; // 0..1 fraction of image width
  final double y; // 0..1 fraction of image height
  final bool labelLeft; // true → label on left side
  const _PressurePoint(this.name, this.x, this.y, this.labelLeft);
}

class _PressureUlcerInputTab extends StatefulWidget {
  const _PressureUlcerInputTab();

  @override
  State<_PressureUlcerInputTab> createState() => _PressureUlcerInputTabState();
}

class _PressureUlcerInputTabState extends State<_PressureUlcerInputTab> {
  final Map<String, int> _stages = {};

  static const _centerPoints = <String>{'후두부', '등', '엉치뼈', '좌골'};
  String? _activeCenterName;

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
    Color(0xFF3B82F6), // 미선택 — blue
    Color(0xFFFCA5A5), // 1단계 — light red
    Color(0xFFF87171), // 2단계 — medium red
    Color(0xFFEF4444), // 3단계 — strong red
    Color(0xFFB91C1C), // 4단계 — dark red
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        children: [
          SizedBox(
            height: 600,
            child: LayoutBuilder(
              builder: (context, box) {
                return _buildBody(box);
              },
            ),
          ),
          const SizedBox(height: 24),
          _buildPressureGraphs(),
        ],
      ),
    );
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
          crossAxisCount: 2,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 1.8,
        ),
        itemBuilder: (context, index) {
          final part = parts[index];
          return _PressureGraphCard(title: part);
        },
      ),
    );
  }

  Future<void> _showStageMenu(String name, Offset globalPos) async {
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
        final remarkCtrl = TextEditingController();
        int? selectedStage = _stages[name];

        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
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
                          fontSize: 20, fontWeight: FontWeight.w800),
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
                      children: List.generate(4, (index) {
                        final stage = index + 1;
                        final isSelected = selectedStage == stage;

                        return OutlinedButton(
                          onPressed: () {
                            setSheetState(() {
                              selectedStage = stage;
                            });
                          },
                          style: OutlinedButton.styleFrom(
                            backgroundColor: isSelected
                                ? const Color(0xFF6183EE)
                                : Colors.white,
                            foregroundColor: isSelected
                                ? Colors.white
                                : const Color(0xFF374151),
                            side: const BorderSide(
                              color: Color(0xFF6183EE),
                            ),
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
                            style:
                                const TextStyle(fontWeight: FontWeight.w500),
                          ),
                        );
                      }),
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
                        hintStyle: const TextStyle(
                          color: Color(0xFF9CA3AF),
                        ),
                        filled: true,
                        fillColor: const Color(0xFFF9FAFB),
                        contentPadding: const EdgeInsets.all(14),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: Color(0xFFE5E7EB)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: Color(0xFF6183EE), width: 1.5),
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
                            side:
                                const BorderSide(color: Color(0xFFE5E7EB)),
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
                          onPressed: () {
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

    if (result != null && result > 0) {
      setState(() {
        _stages[name] = result;
      });
    }
  }
}

/// 도트 ↔ 라벨 버튼 사이의 연결선만 그리는 페인터
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
        canvas.drawLine(
            Offset(dotX, dotY), Offset(lineEndX, dotY), linePaint);
      } else {
        final lineEndX = imgLeft + imgW + 10;
        canvas.drawLine(
            Offset(dotX, dotY), Offset(lineEndX, dotY), linePaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ConnectionLinePainter old) => true;
}

class _PressureGraphCard extends StatelessWidget {
  final String title;

  const _PressureGraphCard({required this.title});

  @override
  Widget build(BuildContext context) {
    final dates = ['1/1', '2/1', '3/1', '4/1'];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style:
                const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: 4,
                gridData: FlGridData(show: true),
                titlesData: FlTitlesData(
                  topTitles: AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: AxisTitles(
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
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF6B7280),
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
                          style: const TextStyle(fontSize: 10),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: const [
                      FlSpot(0, 1),
                      FlSpot(1, 2.5),
                      FlSpot(2, 1.2),
                      FlSpot(3, 0.5),
                    ],
                    isCurved: true,
                    barWidth: 2,
                    color: const Color(0xFF4F83C1),
                    dotData: FlDotData(show: true),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
