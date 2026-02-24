import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as ble;
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart'
    as classic;

/// 환자별 블루투스 연결 정보
class PatientBluetoothConnection {
  final int patientCode;
  final String deviceName;
  final String deviceId;
  final bool isBLE; // true: BLE, false: Classic
  final DateTime connectedAt;

  // BLE 연결
  ble.BluetoothDevice? bleDevice;
  StreamSubscription<ble.BluetoothConnectionState>? bleConnectionSub;

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
    this.classicConnection,
  });
}

/// 멀티 블루투스 연결 관리 서비스 (Singleton)
class BluetoothConnectionManager {
  static final BluetoothConnectionManager _instance =
      BluetoothConnectionManager._internal();
  factory BluetoothConnectionManager() => _instance;
  BluetoothConnectionManager._internal();

  // 환자별 블루투스 연결 정보 (patientCode -> connection)
  final Map<int, PatientBluetoothConnection> _connections = {};

  // 상태 변경 알림용 StreamController
  final _stateController =
      StreamController<Map<int, PatientBluetoothConnection>>.broadcast();

  Stream<Map<int, PatientBluetoothConnection>> get stateStream =>
      _stateController.stream;

  Map<int, PatientBluetoothConnection> get connections =>
      Map.unmodifiable(_connections);

  /// 특정 환자의 연결 상태 확인
  bool isConnected(int patientCode) {
    return _connections.containsKey(patientCode);
  }

  /// 특정 환자의 연결 정보 가져오기
  PatientBluetoothConnection? getConnection(int patientCode) {
    return _connections[patientCode];
  }

  /// BLE 디바이스 스캔
  Future<List<ble.ScanResult>> scanBLEDevices({
    Duration timeout = const Duration(seconds: 4),
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return [];
    }

    try {
      // BLE 사용 가능 여부 확인
      final adapterState = await ble.FlutterBluePlus.adapterState.first;
      if (adapterState != ble.BluetoothAdapterState.on) {
        throw Exception('블루투스가 꺼져있습니다. 블루투스를 켜주세요.');
      }

      await ble.FlutterBluePlus.startScan(timeout: timeout);
      await Future.delayed(timeout);
      await ble.FlutterBluePlus.stopScan();

      return ble.FlutterBluePlus.lastScanResults;
    } catch (e) {
      debugPrint('BLE 스캔 오류: $e');
      return [];
    }
  }

  /// Classic Bluetooth 디바이스 스캔
  Future<List<classic.BluetoothDiscoveryResult>> scanClassicDevices() async {
    if (!Platform.isAndroid) {
      return [];
    }

    try {
      final instance = classic.FlutterBluetoothSerial.instance;
      final isEnabled = await instance.isEnabled ?? false;

      if (!isEnabled) {
        throw Exception('블루투스가 꺼져있습니다. 블루투스를 켜주세요.');
      }

      final List<classic.BluetoothDiscoveryResult> results = [];
      final completer = Completer<List<classic.BluetoothDiscoveryResult>>();

      instance.startDiscovery().listen(
        (r) {
          results.add(r);
        },
        onDone: () {
          completer.complete(results);
        },
        onError: (e) {
          completer.completeError(e);
        },
      );

      return await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => results,
      );
    } catch (e) {
      debugPrint('Classic 스캔 오류: $e');
      return [];
    }
  }

  /// BLE 디바이스 연결
  Future<bool> connectBLE({
    required int patientCode,
    required ble.BluetoothDevice device,
  }) async {
    try {
      // 이미 연결되어 있으면 해제
      if (_connections.containsKey(patientCode)) {
        await disconnect(patientCode);
      }

      // 연결 시도
      await device.connect(timeout: const Duration(seconds: 15));

      // 연결 상태 모니터링
      final sub = device.connectionState.listen((state) {
        if (state == ble.BluetoothConnectionState.disconnected) {
          disconnect(patientCode);
        }
      });

      // 연결 정보 저장
      _connections[patientCode] = PatientBluetoothConnection(
        patientCode: patientCode,
        deviceName: device.platformName,
        deviceId: device.remoteId.toString(),
        isBLE: true,
        connectedAt: DateTime.now(),
        bleDevice: device,
        bleConnectionSub: sub,
      );

      _notifyStateChange();

      debugPrint('BLE 연결 성공: 환자 $patientCode, 디바이스 ${device.platformName}');
      return true;
    } catch (e) {
      debugPrint('BLE 연결 실패: $e');
      return false;
    }
  }

  /// Classic Bluetooth 디바이스 연결
  Future<bool> connectClassic({
    required int patientCode,
    required classic.BluetoothDevice classicDevice,
  }) async {
    try {
      // 이미 연결되어 있으면 해제
      if (_connections.containsKey(patientCode)) {
        await disconnect(patientCode);
      }

      // 연결 시도
      final connection = await classic.BluetoothConnection.toAddress(
        classicDevice.address,
      );

      // 연결 정보 저장
      _connections[patientCode] = PatientBluetoothConnection(
        patientCode: patientCode,
        deviceName: classicDevice.name ?? 'Unknown',
        deviceId: classicDevice.address,
        isBLE: false,
        connectedAt: DateTime.now(),
        classicConnection: connection,
      );

      _notifyStateChange();

      debugPrint('Classic 연결 성공: 환자 $patientCode, 디바이스 ${classicDevice.name}');
      return true;
    } catch (e) {
      debugPrint('Classic 연결 실패: $e');
      return false;
    }
  }

  /// 연결 해제
  Future<void> disconnect(int patientCode) async {
    final connection = _connections[patientCode];
    if (connection == null) return;

    try {
      if (connection.isBLE) {
        // BLE 연결 해제
        await connection.bleConnectionSub?.cancel();
        await connection.bleDevice?.disconnect();
      } else {
        // Classic 연결 해제
        await connection.classicConnection?.close();
      }

      _connections.remove(patientCode);
      _notifyStateChange();

      debugPrint('블루투스 연결 해제: 환자 $patientCode');
    } catch (e) {
      debugPrint('연결 해제 오류: $e');
    }
  }

  /// 모든 연결 해제
  Future<void> disconnectAll() async {
    final patientCodes = _connections.keys.toList();
    for (final code in patientCodes) {
      await disconnect(code);
    }
  }

  /// 상태 변경 알림
  void _notifyStateChange() {
    _stateController.add(Map.unmodifiable(_connections));
  }

  /// 리소스 정리
  void dispose() {
    disconnectAll();
    _stateController.close();
  }
}
