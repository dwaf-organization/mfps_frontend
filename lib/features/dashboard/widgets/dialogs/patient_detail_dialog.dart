// patient_detail_dialog.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

// ✅ Bluetooth 추가
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart' as classic;
import 'package:permission_handler/permission_handler.dart';
import '../../../../urlConfig.dart';
import 'patient_edit_dialog.dart';

// ✅ BLE / Classic BT 통합 선택 결과
enum _BtType { ble, classic }

class _SelectedDevice {
  final _BtType type;
  final BluetoothDevice? bleDevice;
  final classic.BluetoothDevice? classicDevice;

  const _SelectedDevice.ble(this.bleDevice)
      : type = _BtType.ble,
        classicDevice = null;
  const _SelectedDevice.classic(this.classicDevice)
      : type = _BtType.classic,
        bleDevice = null;

  String get displayName {
    if (bleDevice != null) {
      final n = bleDevice!.platformName;
      return n.isNotEmpty ? n : 'BLE 기기';
    }
    return classicDevice?.name ?? 'Classic 기기';
  }
}

class _BlePacket {
  final int deviceCode;
  final double temperature;
  final double humidity;
  final double bodyTemperature;
  final List<int> weights; // 4개

  _BlePacket({
    required this.deviceCode,
    required this.temperature,
    required this.humidity,
    required this.bodyTemperature,
    required this.weights,
  });
}

class PatientDetailDialog extends ConsumerStatefulWidget {
  final int patientCode;

  /// UI 표시용(호실/침대 라벨) - room_card에서 넘기면 기존 UI 그대로 표현 가능
  final String? roomLabel; // 예: "101호"
  final String? bedLabel; // 예: "Bed-1"

  /// 필요하면 부모 새로고침 연결
  final Future<void> Function()? onRefresh;

  const PatientDetailDialog({
    super.key,
    required this.patientCode,
    this.roomLabel,
    this.bedLabel,
    this.onRefresh,
  });

  @override
  ConsumerState<PatientDetailDialog> createState() =>
      _PatientDetailDialogState();
}

class _PatientDetailDialogState extends ConsumerState<PatientDetailDialog> {
  static const _storage = FlutterSecureStorage();

  late final String _front_url;

  bool _loading = true;
  bool _deleting = false;

  PatientProfileDto? _profile; // ✅ GET /api/patient/profile 결과

  // ✅ 측정값(그래프 + 상단 값)
  List<MeasurementBasicDto> _measurements = const [];

  // ✅ 명세: /api/measurement/basic?device_code=...&patient_code=...
  int _deviceCode = 1;

  // ✅ (추가) warning state: /api/patient/warning?patient_code=...
  int? _warningState; // 0 안전, 1 주의, 2 위험

  // =========================================================
  // ✅ Bluetooth 상태/연결 로직 (추가된 부분)
  // =========================================================
  BluetoothDevice? _connectedDevice;
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;

  bool _isConnectingBle = false;
  String _connectionStatus = '연결 안됨';
  List<int> _latestBleData = [];

  StreamSubscription<BluetoothConnectionState>? _connSub;

  // ✅ BLE 수신값 POST 디바운스(너무 자주 POST/GET 방지)
  Timer? _blePostDebounce;
  bool _bleAutoPostEnabled = true;

  // ✅ Classic Bluetooth (SPP) 상태
  classic.BluetoothConnection? _classicConnection;
  StreamSubscription? _classicDataSub;
  // =========================================================

  // ✅ 비고 입력
  final TextEditingController _remarkController = TextEditingController();
  bool _savingRemark = false;

  @override
  void initState() {
    super.initState();
    _front_url = Urlconfig.serverUrl.toString();
    loadData();

    // ✅ 권한 요청 (추가)
    _checkBluetoothPermissions();
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
      _warningState = null;
      return;
    }

    // 1) 프로필 먼저 조회 (여기서 device_code 얻음)
    _profile = await _fetchPatientProfile(patientCode);

    final dc = _profile?.deviceCode;
    if (dc != null && dc > 0) {
      _deviceCode = dc;
    }

    // 2) 측정값 조회
    _measurements = await _fetchMeasurementBasic(
      deviceCode: _deviceCode,
      patientCode: patientCode,
    );
    debugPrint('_measurements_measurements $_measurements');
    // 서버가 응답 항목에 device_code를 내려주면 내부 값 갱신(구조/UI 변화 없음)
    if (_measurements.isNotEmpty) {
      _deviceCode = _measurements.last.deviceCode;
    }

    // 3) ✅ (추가) warning 상태 조회 -> 움직임 라벨에 사용
    _warningState = await _fetchPatientWarningState(patientCode);
  }

  MeasurementBasicDto? get _latestMeasurement {
    if (_measurements.isEmpty) return null;
    debugPrint('_measurements $_measurements');
    return _measurements.last;
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
      '$_front_url/api/patient/profile?patient_code=$patientCode',
    );
    final res = await http.get(uri, headers: await _headers());

    // debugPrint('[PROFILE] status=${res.statusCode} body=${res.body}'); // 디버그 프린트 (그래프 데이터)
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
    final base = _front_url.trim().replaceAll(RegExp(r'/+$'), ''); // 끝 / 제거
    final p = pathAndQuery.startsWith('/') ? pathAndQuery : '/$pathAndQuery';

    // base가 .../api 로 끝나고, p가 /api/... 로 시작하면 /api 중복 제거
    if (base.toLowerCase().endsWith('/api') &&
        p.toLowerCase().startsWith('/api/')) {
      return base + p.substring(4); // '/api' 제거
    }
    return base + p;
  }

  /// GET /api/measurement/basic?device_code=1&patient_code=1
  /// - 현재 서버 응답: data: {cursor:"", result:[...]}
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
    debugPrint('res.body: ${res.body}');
    debugPrint('jsonDecode(res.body): ${jsonDecode(res.body)}');
    debugPrint('decodeddecoded: ${decoded}');
    if (decoded is! Map<String, dynamic>) throw Exception('측정값 조회 응답 형식 오류');
    if (decoded['code'] != 1) {
      final c = int.tryParse(decoded['code']?.toString() ?? '');
      if (c == -1) return const <MeasurementBasicDto>[];
      throw Exception((decoded['message'] ?? '측정값 조회 실패').toString());
    }

    final data = decoded['data'];
    if (data is! Map<String, dynamic>) throw Exception('측정값 조회 data 형식 오류');
    debugPrint('datadata: ${data}');
    final rawList = data['result'];
    if (rawList is! List) throw Exception('측정값 조회 result 형식 오류');

    final list = rawList
        .whereType<Map<String, dynamic>>()
        .map(MeasurementBasicDto.fromJson)
        .toList();
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    debugPrint('listlist $list');
    return list;
  }

  /// ✅ (추가) GET /api/patient/warning?patient_code=1
  Future<int?> _fetchPatientWarningState(int patientCode) async {
    final uri = Uri.parse(
      '$_front_url/api/patient/warning?patient_code=$patientCode',
    );
    final res = await http.get(uri, headers: await _headers());
    print("상세res: $res");
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
    final uri = Uri.parse(
      '$_front_url/api/patient/profile/delete/$patientCode',
    );
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
  // ✅ 그래프 시리즈 생성
  // - 기존(기본): 10분 간격 30개 (기존 UI 그대로)
  // - 전체화면: windowPoints 늘려서 과거 데이터까지(좌우 스크롤)
  // =========================

  _ChartSeries _seriesFromMeasurements({
    required String title,
    required String unit,
    required double yMin,
    required double yMax,
    required Color lineColor,
    required Color dotColor,
    required double Function(MeasurementBasicDto m) pick,

    // ✅ 추가(기본값은 기존과 동일) : 구조/기능/기존 그래프 변화 없음
    int windowPoints = 30,
    Duration step = const Duration(minutes: 10),
    int maxSource = 200,
  }) {
    final sorted = [..._measurements]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    // ✅ 더미 제거: 데이터 없으면 "빈 그래프"
    if (sorted.isEmpty) {
      return _ChartSeries(
        title: title,
        unit: unit,
        points: const <_ChartPoint>[],
        yMin: yMin,
        yMax: yMax,
        lineColor: lineColor,
        dotColor: dotColor,
        selectedDotColor: const Color(0xFF34D399),
      );
    }

    // ✅ 최신 쪽 위주(과도한 데이터 방지) - 기본 200, 전체화면은 더 크게 줄 수 있음
    final src = sorted.length > maxSource
        ? sorted.sublist(sorted.length - maxSource)
        : sorted;

    final stepMs = step.inMilliseconds;

    DateTime floorToStep(DateTime d) {
      final minutes = step.inMinutes;
      if (minutes <= 0) return d;
      final m = (d.minute ~/ minutes) * minutes;
      return DateTime(d.year, d.month, d.day, d.hour, m);
    }

    // 끝 시간을 step 단위로 맞춤
    final end = floorToStep(src.last.createdAt);
    final start = end.subtract(step * (windowPoints - 1));

    // step 버킷 key -> 그 구간의 "마지막 값"
    final bucket = <int, double>{};
    for (final m in src) {
      final t = floorToStep(m.createdAt);
      final key = t.millisecondsSinceEpoch ~/ stepMs;
      bucket[key] = pick(m); // 같은 버킷이면 마지막 값으로 덮어씀
    }

    // 초기값: start 이전 가장 가까운 값(없으면 첫 값)
    double cur = pick(src.first);
    for (final m in src) {
      if (m.createdAt.isBefore(start) || m.createdAt.isAtSameMomentAs(start)) {
        cur = pick(m);
      } else {
        break;
      }
    }

    final pts = <_ChartPoint>[];
    for (int i = 0; i < windowPoints; i++) {
      final t = start.add(step * i);
      final key = t.millisecondsSinceEpoch ~/ stepMs;
      if (bucket.containsKey(key)) cur = bucket[key]!;
      final v = cur.clamp(yMin, yMax).toDouble();
      pts.add(_ChartPoint(t, v));
    }

    return _ChartSeries(
      title: title,
      unit: unit,
      points: pts,
      yMin: yMin,
      yMax: yMax,
      lineColor: lineColor,
      dotColor: dotColor,
      selectedDotColor: const Color(0xFF34D399),
    );
  }

  // =========================
  // ✅ Bluetooth (추가된 기능: 버튼/연결/스캔/notify 수신)
  // =========================

  Future<void> _checkBluetoothPermissions() async {
    // Android 12+ : bluetoothScan / bluetoothConnect
    if (await Permission.bluetoothScan.isDenied) {
      await Permission.bluetoothScan.request();
    }
    if (await Permission.bluetoothConnect.isDenied) {
      await Permission.bluetoothConnect.request();
    }
    // 기기/OS에 따라 위치 권한이 필요한 경우가 있어 유지
    if (await Permission.location.isDenied) {
      await Permission.location.request();
    }
  }

  bool get _isAnyConnected =>
      _connectedDevice != null || _classicConnection != null;

  Future<void> _onBleButtonPressed() async {
    if (_isConnectingBle) return;

    if (!_isAnyConnected) {
      await _connectBluetooth();
    } else {
      await _disconnectBluetooth();
    }
  }

  Future<void> _connectBluetooth() async {
    setState(() => _isConnectingBle = true);

    try {
      // 스캔 다이얼로그 (BLE + Classic 통합)
      final _SelectedDevice? selected = await _showScanningDialog();
      if (selected == null) return;

      if (selected.type == _BtType.ble && selected.bleDevice != null) {
        await _connectToDevice(selected.bleDevice!);
      } else if (selected.type == _BtType.classic &&
          selected.classicDevice != null) {
        await _connectToClassicDevice(selected.classicDevice!);
      }
    } catch (e) {
      _snack('블루투스 연결 실패: $e');
      debugPrint('블루투스 연결 오류: $e');
    } finally {
      if (mounted) setState(() => _isConnectingBle = false);
    }
  }

  Future<_SelectedDevice?> _showScanningDialog() async {
    return showDialog<_SelectedDevice>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ScanningDialog(),
    );
  }

  Future<void> _connectToDevice(BluetoothDevice device) async {
    try {
      _snack('${device.name.isEmpty ? '기기' : device.name}에 연결 중...');

      // 이미 연결된 상태면 connect가 예외를 낼 수 있어, 안전 처리
      try {
        await device.connect(timeout: const Duration(seconds: 10));
      } catch (_) {
        // 이미 연결 상태일 수 있음 -> 계속 진행
      }

      final services = await device.discoverServices();
      final ok = await _setupCharacteristics(device, services);

      if (!ok) {
        await device.disconnect();
        _snack('서비스/특성 설정 실패');
        return;
      }

      setState(() {
        _connectedDevice = device;
        _connectionStatus =
            '연결됨 (${device.name.isEmpty ? 'Unknown' : device.name})';
      });

      _snack('블루투스 연결 성공');

      _monitorConnection(device);
    } catch (e) {
      _snack('연결 실패: $e');
      debugPrint('기기 연결 오류: $e');
    }
  }

  // ✅ Classic Bluetooth (SPP) 연결
  Future<void> _connectToClassicDevice(classic.BluetoothDevice device) async {
    try {
      _snack('${device.name ?? '기기'}에 연결 중...');

      final connection = await classic.BluetoothConnection.toAddress(
        device.address,
      );

      _classicConnection = connection;

      if (!mounted) return;
      setState(() {
        _connectionStatus = '연결됨 (${device.name ?? 'Unknown'})';
      });

      _snack('블루투스 연결 성공');

      // Serial 데이터 수신 → 기존 _handleReceivedData 재사용
      List<int> buffer = [];
      _classicDataSub = connection.input?.listen(
        (data) {
          buffer.addAll(data);
          // 8바이트 패킷 단위로 파싱
          while (buffer.length >= 8) {
            final packet = buffer.sublist(0, 8);
            buffer = buffer.sublist(8);
            _handleReceivedData(packet);
          }
        },
        onDone: () {
          if (!mounted) return;
          setState(() {
            _classicConnection = null;
            _connectionStatus = '연결 끊김';
          });
        },
        onError: (e) {
          debugPrint('Classic BT 수신 오류: $e');
        },
      );
    } catch (e) {
      _snack('연결 실패: $e');
      debugPrint('Classic BT 연결 오류: $e');
    }
  }

  Future<bool> _setupCharacteristics(
    BluetoothDevice device,
    List<BluetoothService> services,
  ) async {
    try {
      BluetoothCharacteristic? writeChar;
      BluetoothCharacteristic? notifyChar;

      for (final s in services) {
        for (final c in s.characteristics) {
          if (c.properties.write && writeChar == null) {
            writeChar = c;
          }
          if (c.properties.notify && notifyChar == null) {
            notifyChar = c;
            await c.setNotifyValue(true);

            // 수신 리스너
            c.value.listen((data) {
              _handleReceivedData(data);
            });
          }
        }
      }

      debugPrint('쓰기 특성: ${writeChar?.uuid}');
      debugPrint('알림 특성: ${notifyChar?.uuid}');

      // 저장
      _writeChar = writeChar;
      _notifyChar = notifyChar;

      // notify 또는 write 중 하나라도 있으면 연결은 유지 (기기마다 다름)
      return writeChar != null || notifyChar != null;
    } catch (e) {
      debugPrint('특성 설정 오류: $e');
      return false;
    }
  }

  // ===== BLE 패킷 파싱/POST (추가) =====

  _BlePacket? _parseBlePacket(List<int> data) {
    if (data.length < 8) return null;

    int u8(int i) => data[i] & 0xFF;

    final dc = u8(0);

    // ✅ 스케일(필요 시 여기만 조정)
    const tempScale = 1.0;
    const bodyTempScale = 1.0;
    const humScale = 1.0;

    final temp = u8(1) / tempScale;
    final hum = u8(2) / humScale;
    final bodyTemp = u8(3) / bodyTempScale;

    final w1 = u8(4);
    final w2 = u8(5);
    final w3 = u8(6);
    final w4 = u8(7);

    return _BlePacket(
      deviceCode: dc,
      temperature: temp.toDouble(),
      humidity: hum.toDouble(),
      bodyTemperature: bodyTemp.toDouble(),
      weights: [w1, w2, w3, w4],
    );
  }

  Future<void> _postMeasurementFromBle(_BlePacket p) async {
    final url = _apiUrl('/api/measurement/basic');
    final uri = Uri.parse(url);

    final body = {
      "device_code": p.deviceCode,
      "measurements": [
        {
          "temperature": p.temperature,
          "body_temperature": p.bodyTemperature,
          "humidity": p.humidity,
          "weights": [
            {"sensor": 1, "value": p.weights[0]},
            {"sensor": 2, "value": p.weights[1]},
            {"sensor": 3, "value": p.weights[2]},
            {"sensor": 4, "value": p.weights[3]},
          ],
        },
      ],
    };

    debugPrint('[MEASUREMENT][POST] $uri');
    debugPrint('[MEASUREMENT][POST BODY] ${jsonEncode(body)}');

    final res = await http.post(
      uri,
      headers: await _headers(),
      body: jsonEncode(body),
    );
    debugPrint('[MEASUREMENT][POST] status=${res.statusCode} body=${res.body}');

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('측정값 저장 실패(HTTP ${res.statusCode})');
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! Map<String, dynamic>) throw Exception('측정값 저장 응답 형식 오류');
    if (decoded['code'] != 1)
      throw Exception((decoded['message'] ?? '측정값 저장 실패').toString());
  }

  void _handleReceivedData(List<int> data) {
    if (!mounted) return;
    setState(() => _latestBleData = data);

    debugPrint('=== BLE 수신 ===');
    debugPrint('bytes: $data / len=${data.length}');
    final hex = data
        .map((b) => (b & 0xFF).toRadixString(16).padLeft(2, '0'))
        .join(' ');
    debugPrint('hex: $hex');

    final pkt = _parseBlePacket(data);
    if (pkt == null) {
      debugPrint('BLE packet too short. need >= 8');
      return;
    }

    // ✅ 내부 deviceCode만 갱신(기존 UI/기능 영향 없음)
    _deviceCode = pkt.deviceCode;

    if (_bleAutoPostEnabled) {
      _blePostDebounce?.cancel();
      _blePostDebounce = Timer(const Duration(milliseconds: 600), () async {
        try {
          await _postMeasurementFromBle(pkt);
          if (mounted) await loadData(); // ✅ 기존 UI는 GET 결과로 그대로 갱신
        } catch (e) {
          debugPrint('BLE→POST 실패: $e');
        }
      });
    }
  }

  void _monitorConnection(BluetoothDevice device) {
    _connSub?.cancel();
    _connSub = device.connectionState.listen((state) {
      if (!mounted) return;
      setState(() {
        if (state == BluetoothConnectionState.connected) {
          _connectionStatus =
              '연결됨 (${device.name.isEmpty ? 'Unknown' : device.name})';
        } else {
          _connectionStatus = '연결 끊김';
          _connectedDevice = null;
          _writeChar = null;
          _notifyChar = null;
        }
      });
    });
  }

  Future<void> _disconnectBluetooth() async {
    // BLE 해제
    final d = _connectedDevice;
    if (d != null) {
      try {
        await d.disconnect();
      } catch (_) {}
    }

    // Classic BT 해제
    _classicDataSub?.cancel();
    _classicDataSub = null;
    try {
      _classicConnection?.finish();
    } catch (_) {}
    _classicConnection = null;

    if (!mounted) return;
    setState(() {
      _connectedDevice = null;
      _writeChar = null;
      _notifyChar = null;
      _connectionStatus = '연결 안됨';
      _latestBleData = [];
    });
    _snack('블루투스 연결이 해제되었습니다');
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
              // elevation: 0,
              // shape: RoundedRectangleBorder(
              //   borderRadius: BorderRadius.circular(12),
              // ),
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
  // Build (✅ UI 그대로 + BLE 버튼/상태만 추가)
  // + ✅ 전체화면 그래프는 좌우 스크롤로 과거 데이터까지
  // =========================

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Dialog(
        backgroundColor: Colors.transparent,
        child: SizedBox(
          width: 520,
          height: 220,
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    final p = _ui;
    final latest = _latestMeasurement;

    // ✅ 상단 텍스트(체온/병실온도/습도)도 API 최신값으로
    final bodyTempText = _vitalValueOrDash(
      value: latest?.bodyTemperature,
      unit: '°C',
      frac: 1,
    );
    final roomTempText = _vitalValueOrDash(
      value: latest?.temperature,
      unit: ' °C',
      frac: 1,
    );
    final humidText = _vitalValueOrDash(
      value: latest?.humidity,
      unit: '%',
      frac: 0,
    );

    // ✅ (변경) 움직임 라벨: warning API 기준
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

    // ✅ 그래프 데이터(기본 30개, 기존 그대로)
    final bodyTempSeries = _seriesFromMeasurements(
      title: '체온',
      unit: '°C',
      yMin: 35,
      yMax: 40,
      lineColor: const Color(0xFFEF4444),
      dotColor: const Color(0xFFB91C1C),
      pick: (m) => m.bodyTemperature,
    );

    final roomTempSeries = _seriesFromMeasurements(
      title: '병실온도',
      unit: '°C',
      yMin: 16,
      yMax: 32,
      lineColor: const Color(0xFF06B6D4),
      dotColor: const Color(0xFF0284C7),
      pick: (m) => m.temperature,
    );

    final humiditySeries = _seriesFromMeasurements(
      title: '습도',
      unit: '%',
      yMin: 0,
      yMax: 100,
      lineColor: const Color(0xFF3B82F6),
      dotColor: const Color(0xFF1D4ED8),
      pick: (m) => m.humidity,
    );

    // ✅ 전체화면(과거 데이터 더 보기)용: windowPoints 늘리고, src cap도 크게
    // - UI/구조 변경 없이 "전체화면에서만" 더 길게 보이도록
    final bodyTempSeriesFull = _seriesFromMeasurements(
      title: '체온',
      unit: '°C',
      yMin: 35,
      yMax: 40,
      lineColor: const Color(0xFFEF4444),
      dotColor: const Color(0xFFB91C1C),
      pick: (m) => m.bodyTemperature,
      windowPoints: 180, // 10분 간격 * 180 = 30시간
      step: const Duration(minutes: 10),
      maxSource: 3000,
    );

    final roomTempSeriesFull = _seriesFromMeasurements(
      title: '병실온도',
      unit: '°C',
      yMin: 16,
      yMax: 32,
      lineColor: const Color(0xFF06B6D4),
      dotColor: const Color(0xFF0284C7),
      pick: (m) => m.temperature,
      windowPoints: 180,
      step: const Duration(minutes: 10),
      maxSource: 3000,
    );

    final humiditySeriesFull = _seriesFromMeasurements(
      title: '습도',
      unit: '%',
      yMin: 0,
      yMax: 100,
      lineColor: const Color(0xFF3B82F6),
      dotColor: const Color(0xFF1D4ED8),
      pick: (m) => m.humidity,
      windowPoints: 180,
      step: const Duration(minutes: 10),
      maxSource: 3000,
    );

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
                    '${p.name} 환자 상세',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 10),

                  // ✅ BLE 상태 칩 (추가)
                  // Container(
                  //   padding: const EdgeInsets.symmetric(
                  //     horizontal: 10,
                  //     vertical: 6,
                  //   ),
                  //   decoration: BoxDecoration(
                  //     color: _connectedDevice != null
                  //         ? const Color(0xFF10B981)
                  //         : const Color(0xFFEF4444),
                  //     borderRadius: BorderRadius.circular(999),
                  //   ),
                  // child: Row(
                  //   mainAxisSize: MainAxisSize.min,
                  //   children: [
                  //     Icon(
                  //       _connectedDevice != null
                  //           ? Icons.bluetooth_connected
                  //           : Icons.bluetooth_disabled,
                  //       size: 16,
                  //       color: Colors.white,
                  //     ),
                  //     const SizedBox(width: 6),
                  //     Text(
                  //       _connectedDevice != null ? '연결됨' : '연결 안됨',
                  //       style: const TextStyle(
                  //         color: Colors.white,
                  //         fontWeight: FontWeight.w900,
                  //         fontSize: 12,
                  //       ),
                  //     ),
                  //   ],
                  // ),
                  // ),
                  const SizedBox(width: 10),

                  // ✅ BLE / Classic BT 버튼
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: !_isAnyConnected
                          ? const Color.fromARGB(255, 96, 134, 218)
                          : const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                    ),
                    onPressed: _isConnectingBle ? null : _onBleButtonPressed,
                    icon: _isConnectingBle
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Icon(
                            _isAnyConnected
                                ? Icons.bluetooth_connected
                                : Icons.bluetooth_disabled,
                          ),
                    label: Text(
                      _isConnectingBle
                          ? '연결 중...'
                          : (!_isAnyConnected ? '연결' : '연결 해제'),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),

                  const SizedBox(width: 10),

                  // ✅ 퇴원 버튼(빨간색) - 명세 DELETE 호출 (원본 그대로)
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(
                        color: Color(0xFFEF4444),
                        width: 1.4,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                    ),
                    onPressed: _deleting ? null : _onDischarge,
                    child: const Text(
                      '퇴원',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),

                  const Spacer(),

                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF22C55E),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                    ),
                    onPressed: _onEdit,
                    child: const Text(
                      '수정',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(width: 10),
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

            // 정보 내용
            Flexible(
              child: Container(
                color: const Color(0xFFF3F4F6),
                child: SingleChildScrollView(
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

                      // BLE 연결 상태 텍스트
                      const SizedBox(height: 12),
                      Text(
                        '블루투스: $_connectionStatus${_latestBleData.isNotEmpty ? ' · 최신데이터 ${_latestBleData.length}B' : ''}',
                        style: const TextStyle(
                          color: Color(0xFF6B7280),
                          fontWeight: FontWeight.w800,
                        ),
                      ),

                      const SizedBox(height: 22),

                      const Text(
                        '실시간 바이탈 사인',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
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
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _remarkController.dispose();
    _blePostDebounce?.cancel();
    _connSub?.cancel();
    _connectedDevice?.disconnect();
    // Classic BT 정리
    _classicDataSub?.cancel();
    try {
      _classicConnection?.finish();
    } catch (_) {}
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

  /// ✅ 명세 추가: device_code
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
      deviceCode: int.tryParse(j['device_code']?.toString() ?? ''), // ✅ 추가
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

// ✅ /api/measurement/basic 명세 그대로 매핑
class MeasurementBasicDto {
  final int measurementCode;
  final int deviceCode;
  final int patientCode;
  final double temperature; // 병실온도
  final double bodyTemperature; // 체온
  final double humidity; // 습도
  final DateTime createdAt; // create_at
  final int? warningState; // (있으면 받음)

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

    final rawTime = (j['create_at'] ?? '').toString();
    DateTime parsed;
    try {
      parsed = DateTime.parse(rawTime);
    } catch (_) {
      parsed = DateTime.now();
    }

    return MeasurementBasicDto(
      measurementCode: _i(j['measurement_code']),
      deviceCode: _i(j['device_code']),
      patientCode: _i(j['patient_code']),
      temperature: _d(j['temperature']),
      bodyTemperature: _d(j['body_temperature']),
      humidity: _d(j['humidity']),
      createdAt: parsed,
      warningState: j['warning_state'] == null ? null : _i(j['warning_state']),
    );
  }
}

class PatientUi {
  final int patientCode;
  final String name;
  final int age;

  /// 기존 UI가 roomNo/bedNo를 사용하므로 그대로 유지
  final String roomNo;
  final String bedNo;

  final String nurse;
  final String diagnosis;
  final String physician;
  final String allergy;
  final String note;

  /// 수정 다이얼로그에 전달용
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

/* ------------------ 이하 UI/차트 코드는 원본 그대로 ------------------ */

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

  // ✅ (추가) 값 텍스트 색상만 옵션으로 (기존 사용처 영향 없음)
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
// 차트 (원본 그대로 + x축 시간표시 HH:mm)
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

    // y축 값
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

    // x축 시간(HH:mm)
    final n = series.points.length;
    if (n >= 2) {
      final targetLabels = 6;
      final step = max(1, ((n - 1) / (targetLabels - 1)).round());

      for (int i = 0; i < n; i += step) {
        final x = plot.left + plot.width * (i / (n - 1));
        final d = series.points[i].t;
        final label = '${_fmt2(d.hour)}:${_fmt2(d.minute)}';

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

    // 선/점 (데이터 없으면 안그려짐)
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

      for (int i = 1; i < n - 1; i++) {
        final p1 = ptToXY(i);
        final p2 = ptToXY(i + 1);
        final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
        path.quadraticBezierTo(p1.dx, p1.dy, mid.dx, mid.dy);
      }
      final pn = ptToXY(n - 1);
      path.lineTo(pn.dx, pn.dy);

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
      final line2 = '${series.title}:${_fmtNum(v)}${series.unit}';

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

void _showChartFullScreen(
  BuildContext context, {
  required String title,
  required _ChartSeries series,
}) {
  showDialog(
    context: context,
    barrierColor: const Color(0x99000000),
    builder: (ctx) {
      // ✅ 좌우 스크롤 폭: 점 개수에 비례해서 넓혀줌 (UI 톤/구성은 그대로)
      final w = max(1100.0, series.points.length * 18.0 + 120.0);

      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Container(
          width: 1100,
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

              // ✅ 전체화면 차트: 좌우 스크롤로 과거 데이터까지
              SizedBox(
                height: 520,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: w,
                      height: 520,
                      child: _InteractiveLineChart(series: series),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 10),
              const Text(
                '점을 터치 하면 상세 정보가 표시됩니다.',
                style: TextStyle(
                  color: Color(0xFF6B7280),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
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

// =========================================================
// ✅ BLE + Classic BT 통합 스캔 다이얼로그
// =========================================================

/// 통합 스캔 리스트 아이템
class _ScannedItem {
  final _BtType type;
  final String name;
  final String address;
  final int rssi;

  // 선택 시 반환용
  final BluetoothDevice? bleDevice;
  final classic.BluetoothDevice? classicDevice;

  const _ScannedItem({
    required this.type,
    required this.name,
    required this.address,
    required this.rssi,
    this.bleDevice,
    this.classicDevice,
  });

  bool get hasName => name.isNotEmpty && !name.startsWith('알 수 없는');
}

class _ScanningDialog extends StatefulWidget {
  @override
  _ScanningDialogState createState() => _ScanningDialogState();
}

class _ScanningDialogState extends State<_ScanningDialog> {
  final List<_ScannedItem> _items = [];
  bool _isScanning = true;

  static const _cBg = Color(0xFFFAFAFA);
  static const _cCard = Colors.white;
  static const _cBorder = Color(0xFFE5E7EB);
  static const _cText = Color(0xFF111827);
  static const _cSub = Color(0xFF6B7280);
  static const _cGreen = Color(0xFF22C55E);
  static const _cBlue = Color(0xFF3B82F6);

  StreamSubscription<List<ScanResult>>? _bleScanSub;
  StreamSubscription<classic.BluetoothDiscoveryResult>? _classicScanSub;

  @override
  void initState() {
    super.initState();
    _startScanning();
  }

  @override
  void dispose() {
    _bleScanSub?.cancel();
    _classicScanSub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> _startScanning() async {
    setState(() {
      _isScanning = true;
      _items.clear();
    });

    // ✅ 1) 이미 페어링된(bonded) Classic 기기를 먼저 표시
    try {
      final bonded =
          await classic.FlutterBluetoothSerial.instance.getBondedDevices();
      debugPrint('[CLASSIC] bonded devices: ${bonded.length}');
      if (mounted) {
        setState(() {
          for (final d in bonded) {
            final addr = d.address;
            if (addr.isEmpty) continue;
            final deviceName = d.name;
            _items.add(_ScannedItem(
              type: _BtType.classic,
              name: (deviceName == null || deviceName.isEmpty)
                  ? '페어링된 기기'
                  : '$deviceName (페어링됨)',
              address: addr,
              rssi: 0,
              classicDevice: d,
            ));
          }
        });
      }
    } catch (e) {
      debugPrint('[CLASSIC BONDED] error: $e');
    }

    // ✅ 2) BLE 스캔 (이름 있는 기기만 표시)
    _bleScanSub?.cancel();
    _bleScanSub = FlutterBluePlus.scanResults.listen((results) {
      if (!mounted) return;
      setState(() {
        for (final r in results) {
          final advName = r.advertisementData.advName;
          final platName = r.device.platformName;
          final name = advName.isNotEmpty
              ? advName
              : (platName.isNotEmpty ? platName : '');

          // ✅ 이름 없는 BLE 기기는 목록에서 제외
          if (name.isEmpty) continue;

          final addr = r.device.remoteId.str;
          final idx = _items.indexWhere((i) => i.address == addr);

          final item = _ScannedItem(
            type: _BtType.ble,
            name: name,
            address: addr,
            rssi: r.rssi,
            bleDevice: r.device,
          );

          if (idx >= 0) {
            _items[idx] = item;
          } else {
            _items.add(item);
          }
        }
        _sortItems();
      });
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[BLE SCAN] error: $e');
    }

    // ✅ 3) Classic Bluetooth 검색 (새로 발견되는 기기)
    _classicScanSub?.cancel();
    try {
      debugPrint('[CLASSIC] starting discovery...');
      _classicScanSub = classic.FlutterBluetoothSerial.instance
          .startDiscovery()
          .listen(
        (r) {
          if (!mounted) return;
          debugPrint(
              '[CLASSIC] found: ${r.device.name} / ${r.device.address}');
          setState(() {
            final addr = r.device.address;
            if (addr.isEmpty) return;

            // 이미 같은 MAC이면 업데이트
            final idx = _items.indexWhere((i) => i.address == addr);
            final deviceName = r.device.name;
            final item = _ScannedItem(
              type: _BtType.classic,
              name: (deviceName == null || deviceName.isEmpty)
                  ? '알 수 없는 기기'
                  : deviceName,
              address: addr,
              rssi: r.rssi,
              classicDevice: r.device,
            );

            if (idx >= 0) {
              _items[idx] = item; // 페어링 목록의 것을 갱신
            } else {
              _items.add(item);
            }
            _sortItems();
          });
        },
        onError: (e) {
          debugPrint('[CLASSIC DISCOVERY] stream error: $e');
        },
        onDone: () {
          debugPrint('[CLASSIC DISCOVERY] done');
        },
      );
    } catch (e) {
      debugPrint('[CLASSIC SCAN] error: $e');
    }

    // 스캔 종료 대기
    await Future.delayed(const Duration(seconds: 12));
    if (mounted) setState(() => _isScanning = false);
  }

  void _sortItems() {
    _items.sort((a, b) {
      // 이름 있는 기기 상단
      if (a.hasName && !b.hasName) return -1;
      if (!a.hasName && b.hasName) return 1;
      return b.rssi.compareTo(a.rssi);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Container(
        width: 560,
        decoration: BoxDecoration(
          color: _cBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _cBorder, width: 1),
          boxShadow: const [
            BoxShadow(
              color: Color(0x14000000),
              blurRadius: 18,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 12, 12),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _cGreen.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _cBorder),
                    ),
                    child: const Icon(
                      Icons.bluetooth_searching,
                      color: _cGreen,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      '블루투스 기기 선택',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: _cText,
                      ),
                    ),
                  ),
                  if (_isScanning)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '닫기',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: _cSub),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: _cBorder),

            // Body
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: Column(
                children: [
                  // 상태 배너
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _cBorder),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: _cGreen.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _cBorder),
                          ),
                          child: Icon(
                            _isScanning ? Icons.search : Icons.check_circle,
                            size: 16,
                            color: _cGreen,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _isScanning
                                ? '검색 중입니다...  (${_items.length}개 발견)'
                                : '검색 완료  (${_items.length}개)',
                            style: const TextStyle(
                              color: _cText,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (!_isScanning)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _cGreen,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Text(
                              '완료',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // ✅ 안내 문구
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFFFCD34D),
                      ),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: Color(0xFFB45309),
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '기기가 안 보이면 태블릿 설정 → 블루투스에서 먼저 페어링하세요',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFB45309),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 8),

                  // 목록 컨테이너
                  Container(
                    height: 420,
                    decoration: BoxDecoration(
                      color: _cCard,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: _cBorder),
                    ),
                    child: _items.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _isScanning
                                        ? Icons.bluetooth_searching
                                        : Icons.bluetooth_disabled,
                                    size: 44,
                                    color: const Color(0xFF9CA3AF),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    _isScanning
                                        ? '기기를 검색하고 있습니다...'
                                        : '발견된 기기가 없습니다',
                                    style: const TextStyle(
                                      color: _cSub,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(
                                    '기기 전원이 켜져있는지, 블루투스 기기를 확인해 주세요.',
                                    style: TextStyle(
                                      color: _cSub,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(12),
                            itemCount: _items.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final item = _items[index];
                              final isBle = item.type == _BtType.ble;
                              final typeLabel = isBle ? 'BLE' : 'Classic';
                              final typeColor = isBle ? _cBlue : _cGreen;

                              return InkWell(
                                onTap: () {
                                  final selected = isBle
                                      ? _SelectedDevice.ble(item.bleDevice)
                                      : _SelectedDevice.classic(
                                          item.classicDevice);
                                  Navigator.of(context).pop(selected);
                                },
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFFFFF),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: _cBorder),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: typeColor.withOpacity(0.10),
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          border:
                                              Border.all(color: _cBorder),
                                        ),
                                        child: Icon(
                                          Icons.bluetooth,
                                          color: typeColor,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Flexible(
                                                  child: Text(
                                                    item.name,
                                                    style: const TextStyle(
                                                      fontSize: 15,
                                                      fontWeight:
                                                          FontWeight.w900,
                                                      color: _cText,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 6,
                                                    vertical: 2,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: typeColor
                                                        .withOpacity(0.12),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            6),
                                                  ),
                                                  child: Text(
                                                    typeLabel,
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color: typeColor,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              'MAC  ${item.address}  ·  신호 ${item.rssi}dBm',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: _cSub,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _cGreen,
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: const Text(
                                          '선택',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),

            const Divider(height: 1, color: _cBorder),

            // Footer Buttons
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
              child: Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _isScanning ? null : _startScanning,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _cText,
                      side: const BorderSide(color: _cBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text(
                      '다시 검색',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  const Spacer(),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF374151),
                      side: const BorderSide(color: _cBorder),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                    ),
                    child: const Text(
                      '취소',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// (욕창단계입력 관련 클래스는 patient_care_dialog.dart로 이동됨)
