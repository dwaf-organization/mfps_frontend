import 'dart:async';
import 'package:flutter/material.dart';
import 'patient_list_card.dart'; // RiskStatus / statusColor / riskFromWarningInt 재사용
import '../services/bluetooth_connection_manager.dart';
import 'bluetooth_scan_dialog.dart';

/// ✅ 블루투스 연결 상태
enum BluetoothConnectionStatus { disconnected, connecting, connected }

/// ✅ /api/hospital/structure (beds[].patient) 에 맞춘 침대의 환자 요약
class BedPatientItem {
  final int patientCode;
  final String patientName;
  final int patientAge;
  final int patientWarning; // 0/1/2

  const BedPatientItem({
    required this.patientCode,
    required this.patientName,
    required this.patientAge,
    required this.patientWarning,
  });

  RiskStatus get status => riskFromWarningInt(patientWarning);
}

class BedTile extends StatefulWidget {
  final int bedNo;
  final BedPatientItem? patient;

  /// 빈 침대 탭
  final VoidCallback? onTap;

  /// 환자 정보 버튼 탭
  final VoidCallback? onInfoTap;

  /// 케어입력 버튼 탭
  final VoidCallback? onCareTap;

  const BedTile({
    super.key,
    required this.bedNo,
    required this.patient,
    this.onTap,
    this.onInfoTap,
    this.onCareTap,
  });

  @override
  State<BedTile> createState() => _BedTileState();
}

class _BedTileState extends State<BedTile> {
  final _btManager = BluetoothConnectionManager();
  StreamSubscription<Map<int, PatientBluetoothConnection>>? _btStateSub;

  BluetoothConnectionStatus _bluetoothStatus =
      BluetoothConnectionStatus.disconnected;
  String? _connectedDeviceName;

  @override
  void initState() {
    super.initState();
    _updateBluetoothStatus();

    // 블루투스 상태 변경 리스닝
    _btStateSub = _btManager.stateStream.listen((_) {
      if (mounted) {
        _updateBluetoothStatus();
      }
    });
  }

  @override
  void dispose() {
    _btStateSub?.cancel();
    super.dispose();
  }

  void _updateBluetoothStatus() {
    if (widget.patient == null) return;

    final connection = _btManager.getConnection(widget.patient!.patientCode);
    setState(() {
      if (connection != null) {
        _bluetoothStatus = BluetoothConnectionStatus.connected;
        _connectedDeviceName = connection.deviceName;
      } else {
        _bluetoothStatus = BluetoothConnectionStatus.disconnected;
        _connectedDeviceName = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final has = widget.patient != null;

    final RiskStatus? status = has ? widget.patient!.status : null;
    final Color border = has ? statusColor(status!) : const Color(0xFFD1D5DB);
    final Color bg = has
        ? statusColor(status!).withOpacity(0.06)
        : Colors.white;
    final bool showDangerBadge = has && status == RiskStatus.danger;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxHeight < 100;

        final pad = isCompact ? 8.0 : 12.0;
        final iconSize = isCompact ? 28.0 : 34.0;

        final bedTextStyle = TextStyle(
          color: const Color(0xFF6B7280),
          fontWeight: FontWeight.w800,
          fontSize: isCompact ? 12 : 13,
        );

        final nameStyle = TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: isCompact ? 13 : 14,
          height: 1.1,
        );

        final ageStyle = TextStyle(
          color: const Color(0xFF6B7280),
          fontWeight: FontWeight.w700,
          fontSize: isCompact ? 11 : 12,
          height: 1.1,
        );

        return InkWell(
          onTap: has ? null : widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: EdgeInsets.all(pad),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border, width: 1.6),
            ),
            child: Stack(
              children: [
                if (showDangerBadge)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isCompact ? 4 : 4,
                        vertical: isCompact ? 4 : 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: isCompact ? 12 : 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '위험',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: isCompact ? 11 : 12,
                              height: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                Column(
                  children: [
                    // const Spacer(),
                    Icon(
                      Icons.bed_outlined,
                      size: iconSize,
                      color: const Color(0xFF6B7280),
                    ),
                    SizedBox(height: isCompact ? 6 : 8),

                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('침대 ${widget.bedNo}', style: bedTextStyle),
                    ),

                    SizedBox(height: isCompact ? 6 : 8),

                    if (has) ...[
                      Icon(
                        Icons.person_outline,
                        size: isCompact ? 14 : 16,
                        color: const Color(0xFF6B7280),
                      ),
                      SizedBox(height: isCompact ? 4 : 6),

                      SizedBox(
                        width: double.infinity,
                        child: Text(
                          widget.patient!.patientName,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: nameStyle,
                        ),
                      ),

                      SizedBox(height: isCompact ? 2 : 4),

                      Text(
                        '${widget.patient!.patientAge}세',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ageStyle,
                        textAlign: TextAlign.center,
                      ),

                      SizedBox(height: isCompact ? 4 : 6),

                      // ✅ 블루투스 연결 상태 표시
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: isCompact ? 6 : 8,
                          vertical: isCompact ? 3 : 4,
                        ),
                        decoration: BoxDecoration(
                          color: _getBluetoothStatusColor().withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _getBluetoothStatusColor(),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _getBluetoothStatusIcon(),
                              size: isCompact ? 10 : 12,
                              color: _getBluetoothStatusColor(),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                _getBluetoothStatusText(),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _getBluetoothStatusColor(),
                                  fontWeight: FontWeight.w800,
                                  fontSize: isCompact ? 9 : 10,
                                  height: 1.0,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      SizedBox(height: isCompact ? 6 : 10),

                      // ✅ 정보 / 케어입력 버튼
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: isCompact ? 28 : 32,
                              child: OutlinedButton.icon(
                                onPressed: widget.onInfoTap,
                                icon: Icon(
                                  Icons.info_outline,
                                  size: isCompact ? 12 : 14,
                                ),
                                label: Text(
                                  '정보',
                                  style: TextStyle(
                                    fontSize: isCompact ? 10 : 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF3B82F6),
                                  side: const BorderSide(
                                    color: Color(0xFF3B82F6),
                                  ),
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: SizedBox(
                              height: isCompact ? 28 : 32,
                              child: OutlinedButton.icon(
                                onPressed: widget.onCareTap,
                                icon: Icon(
                                  Icons.medical_services_outlined,
                                  size: isCompact ? 12 : 14,
                                ),
                                label: Text(
                                  '케어',
                                  style: TextStyle(
                                    fontSize: isCompact ? 10 : 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF7C3AED),
                                  side: const BorderSide(
                                    color: Color(0xFF7C3AED),
                                  ),
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      SizedBox(height: isCompact ? 4 : 6),

                      // ✅ 블루투스 연결 버튼
                      SizedBox(
                        width: double.infinity,
                        height: isCompact ? 28 : 32,
                        child: OutlinedButton.icon(
                          onPressed: _handleBluetoothTap,
                          icon: Icon(
                            Icons.bluetooth,
                            size: isCompact ? 12 : 14,
                          ),
                          label: Text(
                            _bluetoothStatus ==
                                BluetoothConnectionStatus.connected
                                ? '연결해제'
                                : '블루투스',
                            style: TextStyle(
                              fontSize: isCompact ? 10 : 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _getBluetoothStatusColor(),
                            side: BorderSide(color: _getBluetoothStatusColor()),
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),

                      // ✅ ESP32 테스트 버튼들 (연결된 경우만)
                      // if (_bluetoothStatus == BluetoothConnectionStatus.connected) ...[
                      //   SizedBox(height: isCompact ? 4 : 6),
                      //
                      //   Row(
                      //     children: [
                      //       Expanded(
                      //         child: SizedBox(
                      //           height: isCompact ? 26 : 28,
                      //           child: ElevatedButton(
                      //             onPressed: () => _testTimeSync(),
                      //             style: ElevatedButton.styleFrom(
                      //               backgroundColor: Colors.blue,
                      //               foregroundColor: Colors.white,
                      //               padding: EdgeInsets.zero,
                      //               shape: RoundedRectangleBorder(
                      //                 borderRadius: BorderRadius.circular(6),
                      //               ),
                      //             ),
                      //             child: Text(
                      //               '시간',
                      //               style: TextStyle(
                      //                 fontSize: isCompact ? 9 : 10,
                      //                 fontWeight: FontWeight.w800,
                      //               ),
                      //             ),
                      //           ),
                      //         ),
                      //       ),
                      //       SizedBox(width: 4),
                      //       Expanded(
                      //         child: SizedBox(
                      //           height: isCompact ? 26 : 28,
                      //           child: ElevatedButton(
                      //             onPressed: () => _testGETCommand(),
                      //             style: ElevatedButton.styleFrom(
                      //               backgroundColor: Colors.green,
                      //               foregroundColor: Colors.white,
                      //               padding: EdgeInsets.zero,
                      //               shape: RoundedRectangleBorder(
                      //                 borderRadius: BorderRadius.circular(6),
                      //               ),
                      //             ),
                      //             child: Text(
                      //               'GET',
                      //               style: TextStyle(
                      //                 fontSize: isCompact ? 9 : 10,
                      //                 fontWeight: FontWeight.w800,
                      //               ),
                      //             ),
                      //           ),
                      //         ),
                      //       ),
                      //     ],
                      //   ),
                      // ],
                    ] else ...[
                      SizedBox(height: isCompact ? 10 : 18),
                      const Text(
                        '비어있음',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontWeight: FontWeight.w800,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],

                    // const Spacer(),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 블루투스 버튼 탭 핸들러
  Future<void> _handleBluetoothTap() async {
    if (widget.patient == null) return;

    if (_bluetoothStatus == BluetoothConnectionStatus.connected) {
      // 연결 해제
      await _btManager.disconnect(widget.patient!.patientCode);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('블루투스 연결이 해제되었습니다.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      // 블루투스 스캔 다이얼로그 표시
      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => BluetoothScanDialog(
          patientCode: widget.patient!.patientCode,
          patientName: widget.patient!.patientName,
        ),
      );

      if (result == true && mounted) {
        _updateBluetoothStatus();
      }
    }
  }

  /// 블루투스 상태별 색상
  Color _getBluetoothStatusColor() {
    switch (_bluetoothStatus) {
      case BluetoothConnectionStatus.disconnected:
        return const Color(0xFF9CA3AF); // Gray
      case BluetoothConnectionStatus.connecting:
        return const Color(0xFFF59E0B); // Amber
      case BluetoothConnectionStatus.connected:
        return const Color(0xFF10B981); // Green
    }
  }

  /// 블루투스 상태별 아이콘
  IconData _getBluetoothStatusIcon() {
    switch (_bluetoothStatus) {
      case BluetoothConnectionStatus.disconnected:
        return Icons.bluetooth_disabled;
      case BluetoothConnectionStatus.connecting:
        return Icons.bluetooth_searching;
      case BluetoothConnectionStatus.connected:
        return Icons.bluetooth_connected;
    }
  }

  /// 블루투스 상태별 텍스트
  String _getBluetoothStatusText() {
    switch (_bluetoothStatus) {
      case BluetoothConnectionStatus.disconnected:
        return '연결 안됨';
      case BluetoothConnectionStatus.connecting:
        return '연결 중...';
      case BluetoothConnectionStatus.connected:
        return _connectedDeviceName ?? '연결됨';
    }
  }

  /// ESP32 시간동기화 테스트
  Future<void> _testTimeSync() async {
    if (widget.patient == null) return;

    debugPrint('🧪 [UI] 시간동기화 버튼 클릭: 환자=${widget.patient!.patientCode}');

    final success = await _btManager.manualTimeSync(widget.patient!.patientCode);

    debugPrint('🧪 [UI] 시간동기화 결과: ${success ? "성공" : "실패"}');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '⏰ 시간동기화 전송 완료' : '❌ 시간동기화 전송 실패'),
          duration: const Duration(seconds: 2),
          backgroundColor: success ? Colors.blue : Colors.red,
        ),
      );
    }
  }

  /// ESP32 GET 명령 테스트
  Future<void> _testGETCommand() async {
    if (widget.patient == null) return;

    debugPrint('🧪 [UI] GET 명령 버튼 클릭: 환자=${widget.patient!.patientCode}');

    final success = await _btManager.manualDataRequest(widget.patient!.patientCode);

    debugPrint('🧪 [UI] GET 명령 결과: ${success ? "성공" : "실패"}');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? '📊 GET 명령 전송 완료' : '❌ GET 명령 전송 실패'),
          duration: const Duration(seconds: 2),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }
}