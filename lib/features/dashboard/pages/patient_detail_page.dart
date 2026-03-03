// patient_detail_page.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'package:mfps/url_config.dart';
import '../widgets/dialogs/patient_edit_dialog.dart';

class PatientDetailPage extends ConsumerStatefulWidget {
  final int patientCode;

  /// UI 표시용(호실/침대 라벨) - room_card에서 넘기면 기존 UI 그대로 표현 가능
  final String? roomLabel; // 예: "101호"
  final String? bedLabel; // 예: "Bed-1"

  /// 필요하면 부모 새로고침 연결
  final Future<void> Function()? onRefresh;

  const PatientDetailPage({
    super.key,
    required this.patientCode,
    this.roomLabel,
    this.bedLabel,
    this.onRefresh,
  });

  @override
  ConsumerState<PatientDetailPage> createState() => _PatientDetailPageState();
}

class _PatientDetailPageState extends ConsumerState<PatientDetailPage> {
  static const _storage = FlutterSecureStorage();

  late final String _frontUrl;

  bool _loading = true;
  bool _deleting = false;

  PatientProfileDto? _profile; // ✅ GET /api/patient/profile 결과

  // ✅ 측정값(상단 카드용 - 최신값 하나만)
  List<MeasurementBasicDto> _measurements = const [];

  // 🚀 차트 데이터
  Map<String, List<ChartDataPoint>> _chartData = {};

  // ✅ 명세: /api/measurement/basic?device_code=...&patient_code=...
  int _deviceCode = 1;

  // ✅ (추가) warning state: /api/patient/warning?patient_code=...
  int? _warningState; // 0 안전, 1 주의, 2 위험

  // ✅ 비고 입력
  final TextEditingController _remarkController = TextEditingController();
  bool _savingRemark = false;

  @override
  void initState() {
    super.initState();
    _frontUrl = UrlConfig.serverUrl.toString();
    loadData();
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<Map<String, String>> _headers() async {
    final token = await _storage.read(key: 'access_token');
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null && token.trim().isNotEmpty)
        'Authorization': 'Bearer ${token.trim()}',
    };
  }

  Future<void> loadData() async {
    setState(() => _loading = true);
    try {
      await getData();
      _remarkController.text = (_profile?.description ?? '').trim();
    } catch (e) {
      _snack('로딩 실패: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// ✅ StorageKeys/selected_patient_code 완전 제거 버전
  /// - patientCode는 widget.patientCode만 사용
  /// - deviceCode는 profile의 device_code로 세팅
  Future<void> getData() async {
    final patientCode = widget.patientCode;

    // 다이얼로그가 patientCode 없이 열리면 표시 불가
    if (patientCode <= 0) {
      _profile = null;
      _measurements = const [];
      _chartData = {};
      _warningState = null;
      return;
    }

    // 1) 프로필 먼저 조회 (여기서 device_code 얻음)
    _profile = await _fetchPatientProfile(patientCode);

    final dc = _profile?.deviceCode;
    if (dc != null && dc > 0) {
      _deviceCode = dc;
    }

    // 2) 최신 측정값 조회 (상단 카드용)
    _measurements = await _fetchMeasurementBasic(
      deviceCode: _deviceCode,
      patientCode: patientCode,
    );

    // 서버가 응답 항목에 device_code를 내려주면 내부 값 갱신(구조/UI 변화 없음)
    if (_measurements.isNotEmpty) {
      _deviceCode = _measurements.last.deviceCode;
    }

    // 🚀 3) 차트 데이터 조회 (그래프용)
    try {
      _chartData = await _fetchMeasurementChart(patientCode);
    } catch (e) {
      debugPrint('차트 데이터 로드 실패: $e');
      _chartData = {}; // 빈 데이터로 폴백
    }

    // 4) ✅ (추가) warning 상태 조회 -> 움직임 라벨에 사용
    _warningState = await _fetchPatientWarningState(patientCode);
  }

  MeasurementBasicDto? get _latestMeasurement {
    if (_measurements.isEmpty) return null;
    return _measurements.last;
  }

  /// 🚀 차트 데이터에서 최신값 가져오기
  String _getLatestValue(String dataType, String unit, int frac) {
    final data = _chartData[dataType];
    if (data == null || data.isEmpty) return '-';

    final latestValue = data.last.value;
    return '${latestValue.toStringAsFixed(frac)}$unit';
  }

  String _vitalValueOrDash({
    required double? value,
    required String unit,
    required int frac,
  }) {
    if (value == null) return '-';
    return '${value.toStringAsFixed(frac)}$unit';
  }

  // =========================
  // ✅ API (명세 반영)
  // =========================

  /// GET /api/patient/profile?patient_code=1
  Future<PatientProfileDto> _fetchPatientProfile(int patientCode) async {
    final uri = Uri.parse(
      '$_frontUrl/api/patient/profile?patient_code=$patientCode',
    );
    final res = await http.get(uri, headers: await _headers());

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('환자정보 조회 실패(HTTP ${res.statusCode})');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) throw Exception('환자정보 조회 응답 형식 오류');
    if (decoded['code'] != 1)
      throw Exception((decoded['message'] ?? '환자정보 조회 실패').toString());

    final data = decoded['data'];
    if (data is! Map<String, dynamic>) throw Exception('환자정보 조회 data 형식 오류');
    return PatientProfileDto.fromJson(data);
  }

  /// baseUrl에 /api 포함/미포함 섞여도 안전하게 합치기
  String _apiUrl(String pathAndQuery) {
    final base = _frontUrl.trim().replaceAll(RegExp(r'/+$'), ''); // 끝 / 제거
    final p = pathAndQuery.startsWith('/') ? pathAndQuery : '/$pathAndQuery';

    // base가 .../api 로 끝나고, p가 /api/... 로 시작하면 /api 중복 제거
    if (base.toLowerCase().endsWith('/api') &&
        p.toLowerCase().startsWith('/api/')) {
      return base + p.substring(4); // '/api' 제거
    }
    return base + p;
  }

  /// GET /api/measurement/basic?device_code=1&patient_code=1
  Future<List<MeasurementBasicDto>> _fetchMeasurementBasic({
    required int deviceCode,
    required int patientCode,
  }) async {
    final url = _apiUrl(
      '/api/measurement/basic?device_code=$deviceCode&patient_code=$patientCode',
    );
    final uri = Uri.parse(url);

    debugPrint('[MEASUREMENT] GET $uri');
    final res = await http.get(uri, headers: await _headers());
    debugPrint('[MEASUREMENT] status=${res.statusCode} body=${res.body}');

    // ✅ 측정 데이터 없음(서버가 404로 주는 경우) => 에러로 치지 않고 빈 값 처리
    if (res.statusCode == 404) {
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) {
          final code = int.tryParse(decoded['code']?.toString() ?? '');
          if (code == -1) return const <MeasurementBasicDto>[];
        }
      } catch (_) {}
      throw Exception('측정값 조회 실패(HTTP 404)\n$uri');
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('측정값 조회 실패(HTTP ${res.statusCode})\n$uri');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) throw Exception('측정값 조회 응답 형식 오류');
    if (decoded['code'] != 1) {
      final c = int.tryParse(decoded['code']?.toString() ?? '');
      if (c == -1) return const <MeasurementBasicDto>[];
      throw Exception((decoded['message'] ?? '측정값 조회 실패').toString());
    }

    final data = decoded['data'];
    if (data is! Map<String, dynamic>) throw Exception('측정값 조회 data 형식 오류');

    // 🚀 수정: 단일 객체를 직접 처리
    try {
      final measurement = MeasurementBasicDto.fromJson(data);
      return [measurement]; // 단일 항목을 리스트로 반환
    } catch (e) {
      throw Exception('측정값 파싱 오류: $e');
    }
  }

  /// 🚀 새로 추가: GET /api/measurement/basic/chart?patient_code=1
  Future<Map<String, List<ChartDataPoint>>> _fetchMeasurementChart(
    int patientCode,
  ) async {
    final url = _apiUrl(
      '/api/measurement/basic/chart?patient_code=$patientCode',
    );
    final uri = Uri.parse(url);

    debugPrint('[CHART] GET $uri');
    final res = await http.get(uri, headers: await _headers());
    debugPrint('[CHART] status=${res.statusCode}');

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('차트 데이터 조회 실패(HTTP ${res.statusCode})');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) throw Exception('차트 데이터 응답 형식 오류');
    if (decoded['code'] != 1) {
      throw Exception((decoded['message'] ?? '차트 데이터 조회 실패').toString());
    }

    final data = decoded['data'];
    if (data is! Map<String, dynamic>) throw Exception('차트 data 형식 오류');

    // 각 타입별로 파싱
    final result = <String, List<ChartDataPoint>>{};

    // temperature 파싱
    final tempList =
        (data['temperature'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    result['temperature'] = tempList
        .map((item) => ChartDataPoint.fromJson(item))
        .toList();

    // humidity 파싱
    final humList =
        (data['humidity'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    result['humidity'] = humList
        .map((item) => ChartDataPoint.fromJson(item))
        .toList();

    // body_temperature 파싱
    final bodyTempList =
        (data['body_temperature'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    result['body_temperature'] = bodyTempList
        .map((item) => ChartDataPoint.fromJson(item))
        .toList();

    // 시간순 정렬
    for (final list in result.values) {
      list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    }

    return result;
  }

  /// ✅ (추가) GET /api/patient/warning?patient_code=1
  Future<int?> _fetchPatientWarningState(int patientCode) async {
    final uri = Uri.parse(
      '$_frontUrl/api/patient/warning?patient_code=$patientCode',
    );
    final res = await http.get(uri, headers: await _headers());

    debugPrint('[WARNING] status=${res.statusCode} body=${res.body}');

    if (res.statusCode < 200 || res.statusCode >= 300) return null;

    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded['code'] != 1) return null;

    final data = decoded['data'];
    if (data is! Map<String, dynamic>) return null;

    final ws = data['warning_state'];
    return ws == null ? null : int.tryParse(ws.toString());
  }

  /// DELETE /api/patient/profile/delete/{patient_code}
  Future<void> _deletePatient(int patientCode) async {
    final uri = Uri.parse('$_frontUrl/api/patient/profile/delete/$patientCode');
    final res = await http.delete(uri, headers: await _headers());

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('환자정보 삭제 실패(HTTP ${res.statusCode})');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) throw Exception('환자정보 삭제 응답 형식 오류');
    if (decoded['code'] != 1)
      throw Exception((decoded['message'] ?? '환자정보 삭제 실패').toString());
  }

  // =========================
  // ✅ UI에 맞는 표시용 모델(레이아웃은 그대로, 데이터만 매핑)
  // =========================

  PatientUi get _ui {
    final api = _profile;

    // ✅ UI가 "호실 ${roomNo} · 침대 ${bedNo}"로 고정이라,
    // roomNo/bedNo는 최대한 짧게(숫자) 만들어야 ... 방지됨
    final roomNo = _compactRoom(widget.roomLabel ?? '');
    final bedNo = _compactBed(widget.bedLabel ?? '', api?.bedCode);

    return PatientUi(
      patientCode: widget.patientCode,
      name: (api?.patientName ?? '').trim(),
      age: api?.age ?? 0,
      roomNo: roomNo,
      bedNo: bedNo,
      nurse: (api?.nurse ?? '').toString(),
      diagnosis: (api?.diagnosis ?? '').toString(),
      physician: (api?.doctor ?? '').toString(),
      allergy: (api?.allergy ?? '').toString(),
      note: (api?.significant ?? '').toString(),
      bedCode: api?.bedCode ?? 0,
    );
  }

  String _compactRoom(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '-';
    final n = _parseDigits(s);
    if (n != null) return n.toString();
    return (s.length > 6) ? s.substring(0, 6) : s;
  }

  String _compactBed(String raw, int? fallbackBedCode) {
    final s = raw.trim();
    final n = _parseDigits(s);
    if (n != null) return n.toString();
    if (s.isEmpty && fallbackBedCode != null && fallbackBedCode > 0) {
      return fallbackBedCode.toString();
    }
    return s.isEmpty ? '-' : ((s.length > 6) ? s.substring(0, 6) : s);
  }

  int? _parseDigits(String s) {
    final m = RegExp(r'\d+').firstMatch(s);
    if (m == null) return null;
    return int.tryParse(m.group(0) ?? '');
  }

  // =========================
  // 🚀 새로운 그래프 시리즈 생성
  // =========================

  _ChartSeries _createChartSeries({
    required String dataType, // 'temperature', 'humidity', 'body_temperature'
    required String title,
    required String unit,
    required double yMin,
    required double yMax,
    required Color lineColor,
    required Color dotColor,
    bool isFullData = false, // false: 최신 10개, true: 전체
  }) {
    final chartPoints = _chartData[dataType] ?? [];

    // 최신 10개 vs 전체 선택
    final selectedPoints = isFullData
        ? chartPoints
        : (chartPoints.length > 10
              ? chartPoints.sublist(chartPoints.length - 10)
              : chartPoints);

    final points = selectedPoints
        .map((cp) => _ChartPoint(cp.timestamp, cp.value))
        .toList();

    return _ChartSeries(
      title: title,
      unit: unit,
      points: points,
      yMin: yMin,
      yMax: yMax,
      lineColor: lineColor,
      dotColor: dotColor,
      selectedDotColor: const Color(0xFF34D399),
    );
  }

  // =========================
  // Actions
  // =========================

  Future<void> _onDischarge() async {
    if (_deleting) return;

    final p = _ui;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE5E7EB), width: 1),
        ),
        backgroundColor: const Color(0xFFFAFAFA),
        title: const Text(
          '정말 퇴원하겠습니까?',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Text(
          '${p.name} 환자를 퇴원 처리하면 목록에서 제거됩니다.',
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            height: 1.4,
            color: Color(0xFF111827),
          ),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              '닫기',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF374151),
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '퇴원',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );

    if (ok != true) return;

    setState(() => _deleting = true);
    try {
      await _deletePatient(widget.patientCode);

      if (widget.onRefresh != null) {
        await widget.onRefresh!();
      }

      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      _snack('퇴원 실패: $e');
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<void> _onEdit() async {
    final p = _ui;

    await showDialog(
      context: context,
      builder: (_) => PatientEditDialog(
        patientCode: widget.patientCode,
        fromBedCode: p.bedCode,
        onRefresh: () async {
          await loadData();
          if (widget.onRefresh != null) await widget.onRefresh!();
        },
      ),
    );

    await loadData();
  }

  // =========================
  // Build
  // =========================

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: const Color(0xFFF3F4F6),
        appBar: AppBar(
          backgroundColor: const Color(0xFFFFFFFF),
          elevation: 0,
          title: const Text(
            '환자 상세',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Color(0xFF374151)),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final p = _ui;
    final latest = _latestMeasurement;

    // 🚀 차트 데이터에서 최신값 가져오기 (measurements 대신)
    final bodyTempText = _getLatestValue('body_temperature', '°C', 1);
    final roomTempText = _getLatestValue('temperature', ' °C', 1);
    final humidText = _getLatestValue('humidity', '%', 0);

    final ws = _warningState;
    final movementText = switch (ws) {
      0 => '안전',
      1 => '주의',
      2 => '위험',
      _ => '-',
    };
    final movementColor = switch (ws) {
      0 => const Color(0xFF22C55E),
      1 => const Color(0xFFF59E0B),
      2 => const Color(0xFFEF4444),
      _ => const Color(0xFF111827),
    };

    final hasChartData = _chartData.isNotEmpty;

    // 🚀 새로운 차트 시리즈 생성 (최신 10개)
    final bodyTempSeries = hasChartData
        ? _createChartSeries(
            dataType: 'body_temperature',
            title: '체온',
            unit: '°C',
            yMin: 35,
            yMax: 40,
            lineColor: const Color(0xFFEF4444),
            dotColor: const Color(0xFFB91C1C),
            isFullData: false,
          )
        : _emptyChartSeries('체온', '°C', 35, 40, const Color(0xFFEF4444));

    final roomTempSeries = hasChartData
        ? _createChartSeries(
            dataType: 'temperature',
            title: '병실온도',
            unit: '°C',
            yMin: 16,
            yMax: 32,
            lineColor: const Color(0xFF06B6D4),
            dotColor: const Color(0xFF0284C7),
            isFullData: false,
          )
        : _emptyChartSeries('병실온도', '°C', 16, 32, const Color(0xFF06B6D4));

    final humiditySeries = hasChartData
        ? _createChartSeries(
            dataType: 'humidity',
            title: '습도',
            unit: '%',
            yMin: 0,
            yMax: 100,
            lineColor: const Color(0xFF3B82F6),
            dotColor: const Color(0xFF1D4ED8),
            isFullData: false,
          )
        : _emptyChartSeries('습도', '%', 0, 100, const Color(0xFF3B82F6));

    // 🚀 확대용 차트 시리즈 (전체 데이터)
    final bodyTempSeriesFull = hasChartData
        ? _createChartSeries(
            dataType: 'body_temperature',
            title: '체온',
            unit: '°C',
            yMin: 35,
            yMax: 40,
            lineColor: const Color(0xFFEF4444),
            dotColor: const Color(0xFFB91C1C),
            isFullData: true,
          )
        : _emptyChartSeries('체온', '°C', 35, 40, const Color(0xFFEF4444));

    final roomTempSeriesFull = hasChartData
        ? _createChartSeries(
            dataType: 'temperature',
            title: '병실온도',
            unit: '°C',
            yMin: 16,
            yMax: 32,
            lineColor: const Color(0xFF06B6D4),
            dotColor: const Color(0xFF0284C7),
            isFullData: true,
          )
        : _emptyChartSeries('병실온도', '°C', 16, 32, const Color(0xFF06B6D4));

    final humiditySeriesFull = hasChartData
        ? _createChartSeries(
            dataType: 'humidity',
            title: '습도',
            unit: '%',
            yMin: 0,
            yMax: 100,
            lineColor: const Color(0xFF3B82F6),
            dotColor: const Color(0xFF1D4ED8),
            isFullData: true,
          )
        : _emptyChartSeries('습도', '%', 0, 100, const Color(0xFF3B82F6));

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFFFF),
        elevation: 0,
        title: Text(
          '${p.name} 환자 상세',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: Color(0xFF111827),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFEF4444),
              side: const BorderSide(color: Color(0xFFEF4444), width: 1.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
            onPressed: _deleting ? null : _onDischarge,
            child: const Text(
              '퇴원',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            onPressed: _onEdit,
            child: const Text(
              '수정',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(width: 18),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: const Divider(height: 1, color: Color(0xFFE5E7EB)),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상단 2개 카드(기본/진료)
            Row(
              children: [
                Expanded(child: _InfoCardBasic(p: p)),
                const SizedBox(width: 18),
                Expanded(child: _InfoCardMedical(p: p)),
              ],
            ),

            const SizedBox(height: 22),

            const Text(
              '실시간 바이탈 사인',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),

            // 바이탈 카드 4개
            Row(
              children: [
                Expanded(
                  child: _VitalMiniCard(
                    title: '체온',
                    value: bodyTempText,
                    icon: Icons.thermostat_outlined,
                    iconColor: const Color(0xFF2563EB),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _VitalMiniCard(
                    title: '병실온도',
                    value: roomTempText,
                    icon: Icons.thermostat_outlined,
                    iconColor: const Color(0xFFDC2626),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _VitalMiniCard(
                    title: '습도',
                    value: humidText,
                    icon: Icons.water_drop_outlined,
                    iconColor: const Color(0xFF0EA5E9),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _VitalMiniCard(
                    title: '움직임',
                    value: movementText,
                    valueColor: movementColor,
                    icon: Icons.accessibility_new_outlined,
                    iconColor: const Color(0xFF7C3AED),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // 그래프 영역
            Row(
              children: [
                Expanded(
                  child: _GraphCard(
                    title: '체온 그래프',
                    onOpenFull: () => _showChartFullScreen(
                      context,
                      title: '체온 그래프',
                      series: bodyTempSeriesFull,
                    ),
                    child: _StaticLineChart(series: bodyTempSeries),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _GraphCard(
                    title: '병실온도 그래프',
                    onOpenFull: () => _showChartFullScreen(
                      context,
                      title: '병실온도 그래프',
                      series: roomTempSeriesFull,
                    ),
                    child: _StaticLineChart(series: roomTempSeries),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _GraphCard(
                    title: '습도 그래프',
                    onOpenFull: () => _showChartFullScreen(
                      context,
                      title: '습도 그래프',
                      series: humiditySeriesFull,
                    ),
                    child: _StaticLineChart(series: humiditySeries),
                  ),
                ),
              ],
            ),
            SizedBox(height: 50),
          ],
        ),
      ),
    );
  }

  /// 🚀 빈 차트 시리즈 생성 (차트 데이터 없을 때 사용)
  _ChartSeries _emptyChartSeries(
    String title,
    String unit,
    double yMin,
    double yMax,
    Color color,
  ) {
    return _ChartSeries(
      title: title,
      unit: unit,
      points: [],
      yMin: yMin,
      yMax: yMax,
      lineColor: color,
      dotColor: color,
      selectedDotColor: color,
    );
  }

  @override
  void dispose() {
    _remarkController.dispose();
    super.dispose();
  }
}

// ===============================
// Models (API DTO + UI 모델)
// ===============================

class PatientProfileDto {
  final int patientCode;
  final String patientName;
  final int gender;
  final int? age;
  final String? birthDate;
  final int? bedCode;
  final int? deviceCode;
  final String? nurse;
  final String? doctor;
  final String? diagnosis;
  final String? allergy;
  final String? significant;
  final String? note;
  final String? description;

  const PatientProfileDto({
    required this.patientCode,
    required this.patientName,
    required this.gender,
    this.age,
    this.birthDate,
    this.bedCode,
    this.deviceCode,
    this.nurse,
    this.doctor,
    this.diagnosis,
    this.allergy,
    this.significant,
    this.note,
    this.description,
  });

  factory PatientProfileDto.fromJson(Map<String, dynamic> j) {
    return PatientProfileDto(
      patientCode: int.tryParse(j['patient_code']?.toString() ?? '') ?? -1,
      patientName: (j['patient_name']?.toString() ?? '').trim(),
      gender: int.tryParse(j['gender']?.toString() ?? '') ?? 0,
      age: int.tryParse(j['age']?.toString() ?? ''),
      birthDate: j['birth_date']?.toString(),
      bedCode: int.tryParse(j['bed_code']?.toString() ?? ''),
      deviceCode: int.tryParse(j['device_code']?.toString() ?? ''),
      nurse: j['nurse']?.toString(),
      doctor: j['doctor']?.toString(),
      diagnosis: j['diagnosis']?.toString(),
      allergy: j['allergy']?.toString(),
      significant: j['significant']?.toString(),
      note: j['note']?.toString(),
      description: j['description']?.toString(),
    );
  }
}

class MeasurementBasicDto {
  final int measurementCode;
  final int deviceCode;
  final int patientCode;
  final double temperature;
  final double bodyTemperature;
  final double humidity;
  final DateTime createdAt;
  final int? warningState;

  const MeasurementBasicDto({
    required this.measurementCode,
    required this.deviceCode,
    required this.patientCode,
    required this.temperature,
    required this.bodyTemperature,
    required this.humidity,
    required this.createdAt,
    this.warningState,
  });

  factory MeasurementBasicDto.fromJson(Map<String, dynamic> j) {
    int _i(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;
    double _d(dynamic v) => double.tryParse(v?.toString() ?? '') ?? 0.0;

    final createdAt = _parseFlexibleTimestamp(j['create_at']);

    return MeasurementBasicDto(
      measurementCode: _i(j['measurement_code']),
      deviceCode: _i(j['device_code']),
      patientCode: _i(j['patient_code']),
      temperature: _d(j['temperature']),
      bodyTemperature: _d(j['body_temperature']),
      humidity: _d(j['humidity']),
      createdAt: createdAt,
      warningState: j['warning_state'] == null ? null : _i(j['warning_state']),
    );
  }
}

// 🚀 차트 데이터 포인트 모델
class ChartDataPoint {
  final double value;
  final DateTime timestamp;

  const ChartDataPoint({required this.value, required this.timestamp});

  factory ChartDataPoint.fromJson(Map<String, dynamic> json) {
    final value = double.tryParse(json['value']?.toString() ?? '') ?? 0.0;
    final timestamp = _parseFlexibleTimestamp(json['timestamp']);

    return ChartDataPoint(value: value, timestamp: timestamp);
  }
}

DateTime _parseFlexibleTimestamp(dynamic rawValue) {
  if (rawValue == null) {
    return DateTime.now();
  }

  if (rawValue is int) {
    return _dateTimeFromEpoch(rawValue);
  }

  final rawText = rawValue.toString().trim();
  if (rawText.isEmpty) {
    return DateTime.now();
  }

  if (RegExp(r'^\d{10,13}$').hasMatch(rawText)) {
    final epoch = int.tryParse(rawText);
    if (epoch != null) {
      return _dateTimeFromEpoch(epoch);
    }
  }

  final compactDateTimeMatch = RegExp(
    r'^(\d{4})(\d{2})(\d{2})[T ]?(\d{2})(\d{2})(\d{2})?$',
  ).firstMatch(rawText);
  if (compactDateTimeMatch != null) {
    final second = compactDateTimeMatch.group(6) ?? '00';
    final normalizedText =
        '${compactDateTimeMatch.group(1)}-'
        '${compactDateTimeMatch.group(2)}-'
        '${compactDateTimeMatch.group(3)}T'
        '${compactDateTimeMatch.group(4)}:'
        '${compactDateTimeMatch.group(5)}:$second';

    final parsedDateTime = DateTime.tryParse(normalizedText);
    if (parsedDateTime != null) {
      return parsedDateTime;
    }
  }

  final normalizedText = rawText.contains(' ')
      ? rawText.replaceFirst(' ', 'T')
      : rawText;
  final parsedDateTime = DateTime.tryParse(normalizedText);
  if (parsedDateTime != null) {
    return parsedDateTime;
  }

  debugPrint('Timestamp 파싱 오류: $rawText');
  return DateTime.now();
}

DateTime _dateTimeFromEpoch(int epochValue) {
  final isMilliseconds = epochValue.abs() >= 1000000000000;
  return DateTime.fromMillisecondsSinceEpoch(
    isMilliseconds ? epochValue : epochValue * 1000,
  );
}

class PatientUi {
  final int patientCode;
  final String name;
  final int age;
  final String roomNo;
  final String bedNo;
  final String nurse;
  final String diagnosis;
  final String physician;
  final String allergy;
  final String note;
  final int bedCode;

  const PatientUi({
    required this.patientCode,
    required this.name,
    required this.age,
    required this.roomNo,
    required this.bedNo,
    required this.nurse,
    required this.diagnosis,
    required this.physician,
    required this.allergy,
    required this.note,
    required this.bedCode,
  });
}

/* ------------------ UI/차트 코드 ------------------ */

class _InfoCardBasic extends StatelessWidget {
  final PatientUi p;
  const _InfoCardBasic({required this.p});

  @override
  Widget build(BuildContext context) {
    return _BigCard(
      title: '기본 정보',
      titleIcon: Icons.calendar_today_outlined,
      titleIconColor: const Color(0xFF2563EB),
      rows: [
        _KV('환자명', p.name),
        _KV('나이', '${p.age}세'),
        _KV('병실', '호실 ${p.roomNo} · 침대 ${p.bedNo}'),
        _KV('담당 간호사', p.nurse.isEmpty ? '-' : p.nurse),
      ],
    );
  }
}

class _InfoCardMedical extends StatelessWidget {
  final PatientUi p;
  const _InfoCardMedical({required this.p});

  @override
  Widget build(BuildContext context) {
    return _BigCard(
      title: '진료 정보',
      titleIcon: Icons.medical_services_outlined,
      titleIconColor: const Color(0xFF16A34A),
      rows: [
        _KV('진단명', p.diagnosis.isEmpty ? '-' : p.diagnosis),
        _KV('주치의', p.physician.isEmpty ? '-' : p.physician),
        _KV('알레르기', p.allergy.isEmpty ? '-' : p.allergy),
        _KV(
          '특이사항',
          p.note.isEmpty ? '-' : p.note,
          valueColor: p.note.isEmpty ? null : const Color(0xFFDC2626),
        ),
      ],
    );
  }
}

class _BigCard extends StatelessWidget {
  final String title;
  final IconData titleIcon;
  final Color titleIconColor;
  final List<_KV> rows;

  const _BigCard({
    required this.title,
    required this.titleIcon,
    required this.titleIconColor,
    required this.rows,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(titleIcon, color: titleIconColor),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          for (int i = 0; i < rows.length; i++) ...[
            _KVRow(rows[i]),
            if (i != rows.length - 1)
              const Divider(height: 18, color: Color(0xFFE5E7EB)),
          ],
        ],
      ),
    );
  }
}

class _KV {
  final String k;
  final String v;
  final Color? valueColor;
  _KV(this.k, this.v, {this.valueColor});
}

class _KVRow extends StatelessWidget {
  final _KV kv;
  const _KVRow(this.kv);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            kv.k,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Color(0xFF374151),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            kv.v,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: kv.valueColor ?? const Color(0xFF111827),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _VitalMiniCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color iconColor;
  final Color? valueColor;

  const _VitalMiniCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.iconColor,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 34,
                    fontWeight: FontWeight.w900,
                    color: valueColor ?? const Color(0xFF111827),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GraphCard extends StatelessWidget {
  final String title;
  final Widget child;
  final VoidCallback onOpenFull;

  const _GraphCard({
    required this.title,
    required this.child,
    required this.onOpenFull,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onOpenFull,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '확대',
                  onPressed: onOpenFull,
                  icon: const Icon(
                    Icons.open_in_full,
                    size: 18,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(height: 180, child: child),
          ],
        ),
      ),
    );
  }
}

// =========================
// 차트
// =========================

class _ChartPoint {
  final DateTime t;
  final double v;
  const _ChartPoint(this.t, this.v);
}

class _ChartSeries {
  final String title;
  final String unit;
  final List<_ChartPoint> points;
  final double yMin;
  final double yMax;
  final Color lineColor;
  final Color dotColor;
  final Color selectedDotColor;

  const _ChartSeries({
    required this.title,
    required this.unit,
    required this.points,
    required this.yMin,
    required this.yMax,
    required this.lineColor,
    required this.dotColor,
    required this.selectedDotColor,
  });
}

class _StaticLineChart extends StatelessWidget {
  final _ChartSeries series;
  const _StaticLineChart({required this.series});

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: CustomPaint(
          painter: _LineChartPainter(
            series: series,
            selectedIndex: null,
            showTooltip: false,
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _InteractiveLineChart extends StatefulWidget {
  final _ChartSeries series;
  const _InteractiveLineChart({required this.series});

  @override
  State<_InteractiveLineChart> createState() => _InteractiveLineChartState();
}

class _InteractiveLineChartState extends State<_InteractiveLineChart> {
  int? selected;

  void _pick(Offset localPos, Size size) {
    const leftPad = 46.0;
    const rightPad = 16.0;
    final plotW = max(1.0, size.width - leftPad - rightPad);

    final n = widget.series.points.length;
    if (n <= 1) return;

    final x = (localPos.dx - leftPad).clamp(0.0, plotW);
    final t = x / plotW;
    final idx = (t * (n - 1)).round().clamp(0, n - 1);

    setState(() => selected = idx);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, c) {
        final size = Size(c.maxWidth, c.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _pick(d.localPosition, size),
          onPanDown: (d) => _pick(d.localPosition, size),
          onPanUpdate: (d) => _pick(d.localPosition, size),
          child: RepaintBoundary(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: CustomPaint(
                painter: _LineChartPainter(
                  series: widget.series,
                  selectedIndex: selected,
                  showTooltip: true,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final _ChartSeries series;
  final int? selectedIndex;
  final bool showTooltip;

  _LineChartPainter({
    required this.series,
    required this.selectedIndex,
    required this.showTooltip,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const bg = Color(0xFFFFFFFF);
    const border = Color(0xFFE5E7EB);
    const grid = Color(0xFFE5E7EB);
    const axisText = Color(0xFF9CA3AF);
    const tooltipBg = Color(0xCC111827);

    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(16),
    );
    canvas.drawRRect(rrect, Paint()..color = bg);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = border
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    const leftPad = 46.0;
    const rightPad = 16.0;
    const topPad = 12.0;
    const bottomPad = 26.0;

    final plot = Rect.fromLTWH(
      leftPad,
      topPad,
      max(1.0, size.width - leftPad - rightPad),
      max(1.0, size.height - topPad - bottomPad),
    );

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;

    const gridCount = 5;
    for (int i = 0; i <= gridCount; i++) {
      final y = plot.top + plot.height * (i / gridCount);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
    }

    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (int i = 0; i <= 2; i++) {
      final t = i / 2.0;
      final yVal = series.yMax + (series.yMin - series.yMax) * t;
      final y = plot.top + plot.height * t;
      tp.text = TextSpan(
        text: _fmtNum(yVal),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: axisText,
        ),
      );
      tp.layout(maxWidth: leftPad - 6);
      tp.paint(canvas, Offset(6, y - tp.height / 2));
    }

    final n = series.points.length;
    if (n >= 2) {
      final targetLabels = 6;
      final step = max(1, ((n - 1) / (targetLabels - 1)).round());

      for (int i = 0; i < n; i += step) {
        final x = plot.left + plot.width * (i / (n - 1));
        final d = series.points[i].t;
        // 🚀 MM/DD HH:mm 형식으로 변경
        final label =
            '${_fmt2(d.month)}/${_fmt2(d.day)} ${_fmt2(d.hour)}:${_fmt2(d.minute)}';

        tp.text = TextSpan(
          text: label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: axisText,
          ),
        );
        tp.layout();
        tp.paint(canvas, Offset(x - tp.width / 2, plot.bottom + 6));
      }
    }

    Offset ptToXY(int i) {
      final v = series.points[i].v;
      final t = i / (n - 1);
      final x = plot.left + plot.width * t;

      final yn = ((v - series.yMin) / (series.yMax - series.yMin)).clamp(
        0.0,
        1.0,
      );
      final y = plot.bottom - plot.height * yn;
      return Offset(x, y);
    }

    if (n >= 2) {
      final path = Path();
      final p0 = ptToXY(0);
      path.moveTo(p0.dx, p0.dy);

      // 🚀 직선 연결로 변경 (곡선 제거)
      for (int i = 1; i < n; i++) {
        final p = ptToXY(i);
        path.lineTo(p.dx, p.dy);
      }

      canvas.drawPath(
        path,
        Paint()
          ..color = series.lineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round,
      );

      for (int i = 0; i < n; i++) {
        final p = ptToXY(i);
        final isSel = selectedIndex == i;
        canvas.drawCircle(p, isSel ? 6 : 4.2, Paint()..color = series.dotColor);
        canvas.drawCircle(
          p,
          isSel ? 6 : 4.2,
          Paint()
            ..color = Colors.white
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }

    if (showTooltip &&
        selectedIndex != null &&
        n >= 2 &&
        selectedIndex! >= 0 &&
        selectedIndex! < n) {
      final idx = selectedIndex!;
      final p = ptToXY(idx);
      final t = series.points[idx].t;
      final v = series.points[idx].v;

      final line1 = _fmtDateTime(t);
      final line2 = '${series.title}: ${_fmtNum(v)}${series.unit}';

      final textStyle = const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      );
      final tp1 = TextPainter(textDirection: TextDirection.ltr)
        ..text = TextSpan(text: line1, style: textStyle)
        ..layout();
      final tp2 = TextPainter(textDirection: TextDirection.ltr)
        ..text = TextSpan(text: line2, style: textStyle)
        ..layout();

      final w = max(tp1.width, tp2.width) + 18;
      final h = tp1.height + tp2.height + 14;

      var bx = p.dx + 12;
      var by = p.dy - h - 12;

      if (bx + w > size.width - 8) bx = p.dx - w - 12;
      if (by < 8) by = p.dy + 12;
      bx = bx.clamp(8.0, size.width - w - 8);
      by = by.clamp(8.0, size.height - h - 8);

      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(bx, by, w, h),
        const Radius.circular(10),
      );
      canvas.drawRRect(rect, Paint()..color = tooltipBg);

      tp1.paint(canvas, Offset(bx + 9, by + 7));
      tp2.paint(canvas, Offset(bx + 9, by + 7 + tp1.height + 2));
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.series != series ||
        oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.showTooltip != showTooltip;
  }
}

// 🚀 확대 차트 화면 크기 자동 조절
void _showChartFullScreen(
  BuildContext context, {
  required String title,
  required _ChartSeries series,
}) {
  showDialog(
    context: context,
    barrierColor: const Color(0x99000000),
    builder: (ctx) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // 🚀 화면 크기에 맞춰서 자동 조절
            final dialogWidth = constraints.maxWidth - 32;
            final chartWidth = dialogWidth - 36; // padding 고려

            return Container(
              width: dialogWidth,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFE5E7EB)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x1A000000),
                    blurRadius: 18,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
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
                            horizontal: 16,
                            vertical: 10,
                          ),
                        ),
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text(
                          '닫기',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 🚀 스크롤 제거, 화면에 맞춰서 표시
                  SizedBox(
                    height: 520,
                    width: chartWidth,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: _InteractiveLineChart(series: series),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '점을 터치하면 상세 정보가 표시됩니다.',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      );
    },
  );
}

String _fmtNum(double v) {
  if ((v - v.roundToDouble()).abs() < 1e-9) return v.round().toString();
  return v.toStringAsFixed(1);
}

String _fmt2(int n) => n.toString().padLeft(2, '0');

String _fmtDateTime(DateTime t) {
  return '${t.year}-${_fmt2(t.month)}-${_fmt2(t.day)} ${_fmt2(t.hour)}:${_fmt2(t.minute)}:${_fmt2(t.second)}';
}
