import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as ble;
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart'
    as classic;
import '../services/bluetooth_connection_manager.dart';

/// 블루투스 디바이스 스캔 및 연결 다이얼로그
class BluetoothScanDialog extends StatefulWidget {
  final int patientCode;
  final String patientName;

  const BluetoothScanDialog({
    super.key,
    required this.patientCode,
    required this.patientName,
  });

  @override
  State<BluetoothScanDialog> createState() => _BluetoothScanDialogState();
}

class _BluetoothScanDialogState extends State<BluetoothScanDialog>
    with SingleTickerProviderStateMixin {
  final _btManager = BluetoothConnectionManager();

  late TabController _tabController;

  bool _isScanning = false;
  List<ble.ScanResult> _bleDevices = [];
  List<classic.BluetoothDiscoveryResult> _classicDevices = [];
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _startScan();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _errorMessage = null;
      _bleDevices = [];
      _classicDevices = [];
    });

    try {
      // BLE와 Classic 동시 스캔
      final futures = await Future.wait([
        _btManager.scanBLEDevices(),
        _btManager.scanClassicDevices(),
      ]);

      setState(() {
        _bleDevices = futures[0] as List<ble.ScanResult>;
        _classicDevices = futures[1] as List<classic.BluetoothDiscoveryResult>;
        _isScanning = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isScanning = false;
      });
    }
  }

  Future<void> _connectBLE(ble.BluetoothDevice device) async {
    setState(() => _isScanning = true);

    final success = await _btManager.connectBLE(
      patientCode: widget.patientCode,
      device: device,
    );

    setState(() => _isScanning = false);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${device.platformName}에 연결되었습니다.')),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('연결에 실패했습니다.')));
      }
    }
  }

  Future<void> _connectClassic(classic.BluetoothDevice device) async {
    setState(() => _isScanning = true);

    final success = await _btManager.connectClassic(
      patientCode: widget.patientCode,
      classicDevice: device,
    );

    setState(() => _isScanning = false);

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('${device.name}에 연결되었습니다.')));
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('연결에 실패했습니다.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bluetooth_searching, color: Color(0xFF3B82F6)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '블루투스 디바이스 스캔',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '환자: ${widget.patientName}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        height: 500,
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              labelColor: const Color(0xFF3B82F6),
              unselectedLabelColor: const Color(0xFF6B7280),
              indicatorColor: const Color(0xFF3B82F6),
              labelStyle: const TextStyle(fontWeight: FontWeight.w800),
              tabs: const [
                Tab(text: 'BLE'),
                Tab(text: 'Classic'),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [_buildBLEList(), _buildClassicList()],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _isScanning ? null : _startScan,
          icon: _isScanning
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh),
          label: Text(_isScanning ? '스캔 중...' : '다시 스캔'),
        ),
      ],
    );
  }

  Widget _buildBLEList() {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _errorMessage!,
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_isScanning && _bleDevices.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('BLE 디바이스를 검색 중...'),
          ],
        ),
      );
    }

    if (_bleDevices.isEmpty) {
      return const Center(
        child: Text(
          '검색된 BLE 디바이스가 없습니다.\n다시 스캔을 눌러주세요.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF6B7280)),
        ),
      );
    }

    return ListView.builder(
      itemCount: _bleDevices.length,
      itemBuilder: (context, index) {
        final result = _bleDevices[index];
        final device = result.device;
        final name = device.platformName.isEmpty
            ? '이름 없음'
            : device.platformName;
        final rssi = result.rssi;

        return ListTile(
          leading: const Icon(Icons.bluetooth, color: Color(0xFF3B82F6)),
          title: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            'ID: ${device.remoteId}\nRSSI: $rssi dBm',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: _isScanning
              ? null
              : ElevatedButton(
                  onPressed: () => _connectBLE(device),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B82F6),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('연결'),
                ),
        );
      },
    );
  }

  Widget _buildClassicList() {
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _errorMessage!,
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_isScanning && _classicDevices.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Classic 블루투스 디바이스를 검색 중...'),
          ],
        ),
      );
    }

    if (_classicDevices.isEmpty) {
      return const Center(
        child: Text(
          '검색된 Classic 디바이스가 없습니다.\n다시 스캔을 눌러주세요.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Color(0xFF6B7280)),
        ),
      );
    }

    return ListView.builder(
      itemCount: _classicDevices.length,
      itemBuilder: (context, index) {
        final result = _classicDevices[index];
        final device = result.device;
        final name = device.name ?? '이름 없음';
        final rssi = result.rssi;

        return ListTile(
          leading: const Icon(Icons.bluetooth, color: Color(0xFF10B981)),
          title: Text(
            name,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            'MAC: ${device.address}\nRSSI: $rssi',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: _isScanning
              ? null
              : ElevatedButton(
                  onPressed: () => _connectClassic(device),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('연결'),
                ),
        );
      },
    );
  }
}
