import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as ble;
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart' as classic;
import 'package:http/http.dart' as http;
import 'package:mfps/url_config.dart';

// ESP32 UUID 상수 정의
class ESP32UUIDs {
  static const String serviceUUID = "12345678-1234-1234-1234-1234567890ab";
  static const String txCharUUID = "abcdefab-1234-5678-1234-abcdefabcdef"; // ESP32 → Flutter (Notify)
  static const String rxCharUUID = "feedbeef-1234-5678-1234-feedbeeffeed"; // Flutter → ESP32 (Write)
}

enum BluetoothConnectionStatus { connected, disconnected, connecting }

class PatientBluetoothConnection {
  final int patientCode;
  final String deviceName;
  final String deviceId;
  final bool isBLE;
  final DateTime connectedAt;

  // BLE 연결
  ble.BluetoothDevice? bleDevice;
  StreamSubscription<ble.BluetoothConnectionState>? bleConnectionSub;

  // ESP32 BLE Characteristics
  ble.BluetoothCharacteristic? rxCharacteristic;
  ble.BluetoothCharacteristic? txCharacteristic;
  StreamSubscription<List<int>>? dataStreamSub;

  // Classic 연결
  classic.BluetoothConnection? classicConnection;

  PatientBluetoothConnection({
    required this.patientCode,
    required this.deviceName,
    required this.deviceId,
    required this.isBLE,
    required this.connectedAt,
    this.bleDevice,
    this.bleConnectionSub,
    this.rxCharacteristic,
    this.txCharacteristic,
    this.dataStreamSub,
    this.classicConnection,
  });
}

class BluetoothConnectionManager {
  static final BluetoothConnectionManager _instance = BluetoothConnectionManager
      ._internal();

  factory BluetoothConnectionManager() => _instance;

  BluetoothConnectionManager._internal();

  // 환자별 블루투스 연결 정보
  final Map<int, PatientBluetoothConnection> _connections = {};

  // 상태 변경 알림용 StreamController
  final _stateController = StreamController<
      Map<int, PatientBluetoothConnection>>.broadcast();

  // ESP32 데이터 수집용 변수들
  final Map<int, List<String>> _receivedDataLists = {};
  final Map<int, bool> _isReceivingData = {};

  // 자동 GET 요청용 타이머들
  final Map<int, Timer> _autoGetTimers = {};

  // 백엔드 POST 요청용 변수들
  final Map<int, int> _deviceCodeMapping = {};
  final Map<int, int> _bedCodeMapping = {}; // 🚀 추가: patient_code -> bed_code

  Stream<Map<int, PatientBluetoothConnection>> get stateStream =>
      _stateController.stream;

  Map<int, PatientBluetoothConnection> get connections =>
      Map.unmodifiable(_connections);

  bool isConnected(int patientCode) {
    return _connections.containsKey(patientCode);
  }

  PatientBluetoothConnection? getConnection(int patientCode) {
    return _connections[patientCode];
  }

  Future<List<ble.ScanResult>> scanBLEDevices(
      {Duration timeout = const Duration(seconds: 4),
      }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return [];

    try {
      // 1. 상태 체크
      if (await ble.FlutterBluePlus.adapterState.first !=
          ble.BluetoothAdapterState.on) {
        debugPrint('블루투스가 꺼져있습니다.');
        return [];
      }

      // 2. 스캔 시작
      await ble.FlutterBluePlus.startScan(timeout: timeout);
      // 3. 스캔이 끝날 때까지 대기 (가장 정확한 방법)
      await ble.FlutterBluePlus.isScanning
          .where((scanning) => !scanning)
          .first;

      // 4. 결과 반환 (ScanResult 리스트임에 주의!)
      return ble.FlutterBluePlus.lastScanResults;
    } catch (e) {
      debugPrint('BLE 스캔 오류: $e');
      return [];
    }
  }

  Future<List<classic.BluetoothDevice>> scanClassicDevices({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (!Platform.isAndroid) {
      return [];
    }

    try {
      return await classic.FlutterBluetoothSerial.instance.getBondedDevices();
    } catch (e) {
      debugPrint('Classic 스캔 오류: $e');
      return [];
    }
  }

  Future<bool> connectBLE({
    required int patientCode,
    required ble.BluetoothDevice device,
  }) async {
    try {
      if (_connections.containsKey(patientCode)) {
        await disconnect(patientCode);
      }

      await device.connect(timeout: const Duration(seconds: 15));

      final services = await device.discoverServices();

      ble.BluetoothService? esp32Service;
      for (final service in services) {
        if (service.uuid.toString().toLowerCase() ==
            ESP32UUIDs.serviceUUID.toLowerCase()) {
          esp32Service = service;
          break;
        }
      }

      ble.BluetoothCharacteristic? rxChar;
      ble.BluetoothCharacteristic? txChar;
      StreamSubscription<List<int>>? dataStreamSub;

      if (esp32Service != null) {
        debugPrint('[환자 $patientCode] ESP32 서비스 발견');

        for (final char in esp32Service.characteristics) {
          final uuid = char.uuid.toString().toLowerCase();
          if (uuid == ESP32UUIDs.rxCharUUID.toLowerCase()) {
            rxChar = char;
          } else if (uuid == ESP32UUIDs.txCharUUID.toLowerCase()) {
            txChar = char;
          }
        }

        if (txChar != null) {
          await txChar.setNotifyValue(true);
          dataStreamSub = txChar.onValueReceived.listen((data) {
            _handleReceivedData(patientCode, data);
          });
        }
      }

      final sub = device.connectionState.listen((state) {
        if (state == ble.BluetoothConnectionState.disconnected) {
          disconnect(patientCode);
        }
      });

      _connections[patientCode] = PatientBluetoothConnection(
        patientCode: patientCode,
        deviceName: device.platformName,
        deviceId: device.remoteId.toString(),
        isBLE: true,
        connectedAt: DateTime.now(),
        bleDevice: device,
        bleConnectionSub: sub,
        rxCharacteristic: rxChar,
        txCharacteristic: txChar,
        dataStreamSub: dataStreamSub,
      );

      _notifyStateChange();

      debugPrint('[환자 $patientCode] BLE 연결 성공: ${device.platformName}');

      if (rxChar != null) {
        // 1초 후: 시간 동기화
        Future.delayed(const Duration(seconds: 1), () async {
          await _sendTimeSync(patientCode);
        });

        // 🚀 2초 후: 디바이스 위치 연결 알림
        Future.delayed(const Duration(seconds: 2), () async {
          await _sendDevicePositionConnect(
              patientCode, device.remoteId.toString());
        });

        // 3초 후: GET 타이머 시작
        Future.delayed(const Duration(seconds: 3), () {
          _startAutoGetTimer(patientCode);
        });
      }

      return true;
    } catch (e) {
      debugPrint('[환자 $patientCode] BLE 연결 실패: $e');
      return false;
    }
  }

  Future<bool> connectClassic({
    required int patientCode,
    required classic.BluetoothDevice classicDevice,
  }) async {
    if (!Platform.isAndroid) return false;

    try {
      if (_connections.containsKey(patientCode)) {
        await disconnect(patientCode);
      }

      final connection = await classic.BluetoothConnection.toAddress(
          classicDevice.address);

      _connections[patientCode] = PatientBluetoothConnection(
        patientCode: patientCode,
        deviceName: classicDevice.name ?? "Unknown",
        deviceId: classicDevice.address,
        isBLE: false,
        connectedAt: DateTime.now(),
        classicConnection: connection,
      );

      _notifyStateChange();

      return true;
    } catch (e) {
      debugPrint('[환자 $patientCode] Classic 연결 실패: $e');
      return false;
    }
  }

  Future<void> disconnect(int patientCode) async {
    final connection = _connections[patientCode];
    if (connection == null) return;

    try {
      _isReceivingData.remove(patientCode);
      _receivedDataLists.remove(patientCode);
      _stopAutoGetTimer(patientCode);

      if (connection.isBLE) {
        await connection.dataStreamSub?.cancel();

        if (connection.txCharacteristic != null) {
          try {
            await connection.txCharacteristic!.setNotifyValue(false);
          } catch (e) {
            debugPrint('Notification 해제 오류: $e');
          }
        }

        await Future.delayed(const Duration(milliseconds: 200));

        try {
          await connection.bleDevice?.disconnect();
        } catch (e) {
          debugPrint('BLE 연결 해제 오류: $e');
        }

        await connection.bleConnectionSub?.cancel();
        await Future.delayed(const Duration(seconds: 1));
      } else {
        await connection.classicConnection?.close();
      }

      _connections.remove(patientCode);
      _notifyStateChange();

      debugPrint('블루투스 연결 해제: 환자 $patientCode');
    } catch (e) {
      debugPrint('연결 해제 오류: $e');
      _connections.remove(patientCode);
      _notifyStateChange();
    }
  }

  Future<void> disconnectAll() async {
    final codes = _connections.keys.toList();
    for (final code in codes) {
      await disconnect(code);
    }
  }

  void dispose() {
    disconnectAll();
    _stateController.close();

    for (final timer in _autoGetTimers.values) {
      timer.cancel();
    }
    _autoGetTimers.clear();
  }

  void _notifyStateChange() {
    if (!_stateController.isClosed) {
      _stateController.add(Map.from(_connections));
    }
  }

  // ESP32 통신 메소드들

  Future<bool> sendCommand(int patientCode, String command) async {
    final connection = _connections[patientCode];
    if (connection?.rxCharacteristic == null) {
      return false;
    }

    try {
      final data = utf8.encode(command);

      await connection!.rxCharacteristic!.write(
        data,
        withoutResponse: true,
        timeout: 5,
      );

      return true;
    } catch (e) {
      try {
        final data = utf8.encode(command);
        await connection!.rxCharacteristic!.write(
          data,
          withoutResponse: false,
          timeout: 10,
        );
        return true;
      } catch (e2) {
        return false;
      }
    }
  }

  Future<bool> _sendTimeSync(int patientCode) async {
    final now = DateTime.now();
    final timeString = "${now.year.toString().padLeft(4, '0')}-"
        "${now.month.toString().padLeft(2, '0')}-"
        "${now.day.toString().padLeft(2, '0')}T"
        "${now.hour.toString().padLeft(2, '0')}:"
        "${now.minute.toString().padLeft(2, '0')}";

    final command = "TIME:$timeString";
    final success = await sendCommand(patientCode, command);

    if (success) {
      debugPrint('[환자 $patientCode] 시간 동기화 완료');
    }

    return success;
  }

  Future<bool> sendGETCommand(int patientCode) async {
    return await sendCommand(patientCode, "GET");
  }

  void _handleReceivedData(int patientCode, List<int> data) {
    try {
      final message = utf8.decode(data).trim();

      if (message == 'BEGIN') {
        debugPrint('[환자 $patientCode] 데이터 수집 시작');
        _isReceivingData[patientCode] = true;
        _receivedDataLists[patientCode] = <String>[];
      } else if (message == 'END') {
        debugPrint('[환자 $patientCode] 데이터 수집 완료');
        _isReceivingData[patientCode] = false;

        final dataList = _receivedDataLists[patientCode];
        if (dataList != null && dataList.isNotEmpty) {
          debugPrint('[환자 $patientCode] 데이터 ${dataList.length}개 수집 완료');

          final deviceCode = _deviceCodeMapping[patientCode];
          if (deviceCode != null) {
            print("환자코드 $patientCode");
            print("디바이스코드 $deviceCode");
            print("데이터리스트 $dataList");
            _sendDataToBackend(patientCode, deviceCode, dataList);
          } else {
            debugPrint('[환자 $patientCode] device_code 매핑을 찾을 수 없음');
          }
        }

        _receivedDataLists.remove(patientCode);
      } else if (_isReceivingData[patientCode] == true) {
        _receivedDataLists[patientCode]?.add(message);
      } else {
        if (message.startsWith('TIME:')) {
          debugPrint('[환자 $patientCode] ESP32 시간 응답: $message');
        } else if (message == 'EMPTY') {
          debugPrint('[환자 $patientCode] 저장된 데이터 없음');
        }
      }
    } catch (e) {
      debugPrint('[환자 $patientCode] 데이터 처리 오류: $e');
    }
  }

  Future<bool> manualTimeSync(int patientCode) async {
    return await _sendTimeSync(patientCode);
  }

  Future<bool> manualDataRequest(int patientCode) async {
    return await sendGETCommand(patientCode);
  }

  // 자동 GET 요청 타이머 관리

  void _startAutoGetTimer(int patientCode) {
    _stopAutoGetTimer(patientCode);

    debugPrint('[환자 $patientCode] 자동 GET 타이머 시작 (5분 간격)');

    _autoGetTimers[patientCode] = Timer.periodic(
      const Duration(minutes: 5),
          (timer) async {
        final connection = _connections[patientCode];
        if (connection?.rxCharacteristic != null) {
          await sendGETCommand(patientCode);
        } else {
          _stopAutoGetTimer(patientCode);
        }
      },
    );

    Future.delayed(const Duration(seconds: 1), () async {
      await sendGETCommand(patientCode);
    });
  }

  void _stopAutoGetTimer(int patientCode) {
    final timer = _autoGetTimers[patientCode];
    if (timer != null) {
      timer.cancel();
      _autoGetTimers.remove(patientCode);
      debugPrint('[환자 $patientCode] 자동 GET 타이머 정지');
    }
  }

  int get activeAutoGetTimers => _autoGetTimers.length;

  // 백엔드 통신 관련 메소드들

  void setPatientDeviceMapping(Map<int, int> mapping) {
    _deviceCodeMapping.clear();
    _deviceCodeMapping.addAll(mapping);
    debugPrint('[CONFIG] Device 코드 매핑 저장: $mapping');
  }

  /// 🚀 환자별 bed_code 매핑 설정
  void setBedCodeMapping(Map<int, int> mapping) {
    _bedCodeMapping.clear();
    _bedCodeMapping.addAll(mapping);
    debugPrint('[CONFIG] Bed 코드 매핑 저장: $mapping');
  }

  /// 🚀 디바이스 위치 연결 알림
  Future<void> _sendDevicePositionConnect(int patientCode,
      String deviceMacAddress,) async {
    final bedCode = _bedCodeMapping[patientCode];
    if (bedCode == null) {
      debugPrint('[환자 $patientCode] bed_code 매핑을 찾을 수 없음');
      return;
    }

    final url = '${UrlConfig.serverUrl}/api/device/position/connect';
    final requestBody = {
      'bed_code': bedCode,
      'device_unique_id': deviceMacAddress,
    };

    try {
      debugPrint(
          '[환자 $patientCode] 디바이스 위치 연결: bed_code=$bedCode, mac=$deviceMacAddress');

      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestBody),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('[환자 $patientCode] 디바이스 위치 연결 성공');
      } else {
        debugPrint(
            '[환자 $patientCode] 디바이스 위치 연결 실패 - Status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('[환자 $patientCode] 디바이스 위치 연결 오류: $e');
    }
  }

  Future<void> _sendDataToBackend(int patientCode,
      int deviceCode,
      List<String> csvLines,) async {
    final url = '${UrlConfig.serverUrl}/api/measurement/basic';
    print("측정값POST URL $url");
    final requestBody = {
      'device_code': deviceCode,
      'patient_code': patientCode,
      'data': csvLines,
    };
    print("측정값 requestBody $requestBody");
    try {
      debugPrint(
          '[환자 $patientCode] 백엔드 전송: device_code=$deviceCode, data=${csvLines
              .length}줄');

      final response = await http.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode(requestBody),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('[환자 $patientCode] 백엔드 전송 성공');
      } else {
        debugPrint(
            '[환자 $patientCode] 백엔드 전송 실패 - Status: ${response.statusCode}');
        _retryBackendRequest(patientCode, deviceCode, csvLines, 1);
      }
    } catch (e) {
      debugPrint('[환자 $patientCode] 백엔드 전송 오류: $e');
      _retryBackendRequest(patientCode, deviceCode, csvLines, 1);
    }
  }

  Future<void> _retryBackendRequest(int patientCode,
      int deviceCode,
      List<String> csvLines,
      int attempt,) async {
    const maxAttempts = 3;

    if (attempt > maxAttempts) {
      debugPrint('[환자 $patientCode] 백엔드 전송 최종 실패');
      return;
    }

    final delaySeconds = 2 * attempt;
    await Future.delayed(Duration(seconds: delaySeconds));

    final url = '${UrlConfig.serverUrl}/api/measurement/basic';
    final requestBody = {
      'device_code': deviceCode,
      'patient_code': patientCode,
      'data': csvLines,
    };

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(requestBody),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('[환자 $patientCode] 재시도 $attempt 성공');
      } else {
        debugPrint('[환자 $patientCode] 재시도 $attempt 실패 - Status: ${response
            .statusCode}');
        await _retryBackendRequest(
            patientCode, deviceCode, csvLines, attempt + 1);
      }
    } catch (e) {
      debugPrint('[환자 $patientCode] 재시도 $attempt 오류: $e');
      await _retryBackendRequest(
          patientCode, deviceCode, csvLines, attempt + 1);
    }
  }

  Map<String, dynamic> getBackendConfig() {
    return {
      'serverUrl': UrlConfig.serverUrl,
      'deviceMappingCount': _deviceCodeMapping.length,
      'deviceMapping': Map<String, dynamic>.from(
          _deviceCodeMapping.map((k, v) => MapEntry(k.toString(), v))),
    };
  }
}