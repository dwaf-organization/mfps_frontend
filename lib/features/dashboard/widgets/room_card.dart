// room_card.dart
import 'dart:async'; // ✅ 추가
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../urlConfig.dart';
import 'bed_tile.dart';
import '../services/bluetooth_connection_manager.dart'; // 🚀 추가

import 'dialogs/patient_add_dialog.dart';
import '../pages/patient_detail_page.dart';
import '../pages/patient_care_page.dart';
import '../../../api/http_helper.dart';

/// 명세 예시:
/// GET /api/hospital/structure?hospital_st_code=<floorStCode>
/// -> data.rooms[] 안에 beds[] 포함

// ===============================
// Models
// ===============================

class FloorStructureRoom {
  final int hospitalStCode; // room hospital_st_code
  final String categoryName; // "101호"
  final int sortOrder;
  final List<FloorStructureBed> beds;

  const FloorStructureRoom({
    required this.hospitalStCode,
    required this.categoryName,
    required this.sortOrder,
    required this.beds,
  });

  factory FloorStructureRoom.fromJson(Map<String, dynamic> j) {
    final bedsAny = j['beds'];
    final bedsList = (bedsAny is List) ? bedsAny : const [];

    return FloorStructureRoom(
      hospitalStCode:
          int.tryParse(j['hospital_st_code']?.toString() ?? '') ?? -1,
      categoryName: (j['category_name']?.toString() ?? '').trim(),
      sortOrder: int.tryParse(j['sort_order']?.toString() ?? '') ?? 0,
      beds:
          bedsList
              .whereType<Map>()
              .map(
                (e) => FloorStructureBed.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList()
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)),
    );
  }

  int get occupiedCount => beds.where((b) => b.patient != null).length;
}

class FloorStructureBed {
  final int hospitalStCode; // bed hospital_st_code
  final String categoryName; // "Bed-1"
  final int sortOrder;
  final BedPatientItem? patient;

  const FloorStructureBed({
    required this.hospitalStCode,
    required this.categoryName,
    required this.sortOrder,
    required this.patient,
  });

  factory FloorStructureBed.fromJson(Map<String, dynamic> j) {
    final pAny = j['patient'];
    final pMap = (pAny is Map) ? Map<String, dynamic>.from(pAny) : null;

    return FloorStructureBed(
      hospitalStCode:
          int.tryParse(j['hospital_st_code']?.toString() ?? '') ?? -1,
      categoryName: (j['category_name']?.toString() ?? '').trim(),
      sortOrder: int.tryParse(j['sort_order']?.toString() ?? '') ?? 0,
      patient: (pMap == null)
          ? null
          : BedPatientItem(
              patientCode:
                  int.tryParse(pMap['patient_code']?.toString() ?? '') ?? -1,
              patientName: (pMap['patient_name']?.toString() ?? '').trim(),
              patientAge:
                  int.tryParse(pMap['patient_age']?.toString() ?? '') ?? 0,
              patientWarning:
                  int.tryParse(pMap['patient_warning']?.toString() ?? '') ?? 0,
            ),
    );
  }

  int get bedNo => _parseNumber(categoryName) ?? 1;

  static int? _parseNumber(String s) {
    final m = RegExp(r'\d+').firstMatch(s);
    if (m == null) return null;
    return int.tryParse(m.group(0) ?? '');
  }
}

// ===============================
// ✅ RoomsSection (API + 박스/그리드 생성은 여기서)
// ===============================

class RoomsSection extends StatefulWidget {
  final int? floorStCode; // 선택된 층 hospital_st_code

  /// 필요하면 연결(없으면 null)
  final Future<void> Function(FloorStructureRoom room, FloorStructureBed bed)?
  onEmptyBedTap;
  final Future<void> Function(BedPatientItem patient)? onPatientTap;

  const RoomsSection({
    super.key,
    required this.floorStCode,
    this.onEmptyBedTap,
    this.onPatientTap,
  });

  @override
  State<RoomsSection> createState() => _RoomsSectionState();
}

class _RoomsSectionState extends State<RoomsSection> {
  bool _loading = false;
  String? _error;
  List<FloorStructureRoom> _rooms = const [];

  Timer? _poller;

  @override
  void initState() {
    super.initState();
    _loadRooms();

    // ✅ 추가: 1사간 마다 재조회(사이드 패널처럼 자동 갱신)
    _poller = Timer.periodic(const Duration(hours: 1), (_) {
      if (!mounted) return;
      if (_loading) return; // ✅ 겹침 방지
      _loadRooms();
    });
  }

  @override
  void didUpdateWidget(covariant RoomsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.floorStCode != widget.floorStCode) {
      _loadRooms();
    }
  }

  @override
  void dispose() {
    _poller?.cancel(); // ✅ 추가
    _poller = null;
    super.dispose();
  }

  Future<void> _loadRooms() async {
    final st = widget.floorStCode;
    if (st == null) {
      if (!mounted) return;
      setState(() {
        _rooms = const [];
        _error = null;
        _loading = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final base = Urlconfig.serverUrl;
      final uri = Uri.parse(
        '$base/api/hospital/structure?hospital_st_code=$st',
      );
      debugPrint('[ROOM_CARD] 호실 조회 URL: $uri');

      final res = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );
      final decoded = jsonDecode(res.body);

      if (!mounted) return;

      if (decoded is! Map<String, dynamic> || decoded['code'] != 1) {
        setState(() {
          _rooms = const [];
          _error = (decoded is Map && decoded['message'] != null)
              ? decoded['message'].toString()
              : '호실 조회 실패';
          _loading = false;
        });
        return;
      }

      final data = decoded['data'];
      final roomsAny = (data is Map) ? data['rooms'] : null;
      final list = (roomsAny is List) ? roomsAny : const [];

      final parsed =
          list
              .whereType<Map>()
              .map(
                (e) =>
                    FloorStructureRoom.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList()
            ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

      // 🚀 BluetoothConnectionManager에 매핑 데이터 전달
      final Map<int, int> deviceCodeMapping = {};
      final Map<int, int> bedCodeMapping = {};

      for (final room in parsed) {
        for (final bed in room.beds) {
          if (bed.patient != null) {
            final patientCode = bed.patient!.patientCode;
            // device_code는 BedPatientItem에 없으므로 원본 JSON에서 가져와야 함
            final bedCode = bed.hospitalStCode;

            if (bedCode > 0) {
              bedCodeMapping[patientCode] = bedCode;
            }
          }
        }
      }

      // 원본 JSON에서 device_code 추출
      for (final roomJson in list.whereType<Map>()) {
        final bedsJson = (roomJson['beds'] as List?) ?? [];
        for (final bedJson in bedsJson.whereType<Map>()) {
          final patientJson = bedJson['patient'] as Map?;
          if (patientJson != null) {
            final patientCode =
                int.tryParse(patientJson['patient_code']?.toString() ?? '') ??
                -1;
            final deviceCode =
                int.tryParse(patientJson['device_code']?.toString() ?? '') ?? 0;

            if (patientCode > 0 && deviceCode > 0) {
              deviceCodeMapping[patientCode] = deviceCode;
            }
          }
        }
      }

      // BluetoothConnectionManager에 매핑 전달
      if (deviceCodeMapping.isNotEmpty || bedCodeMapping.isNotEmpty) {
        final btManager = BluetoothConnectionManager();
        btManager.setPatientDeviceMapping(deviceCodeMapping);
        btManager.setBedCodeMapping(bedCodeMapping);
        debugPrint(
          '[ROOM_CARD] 매핑 전달: device=$deviceCodeMapping, bed=$bedCodeMapping',
        );
      }

      setState(() {
        _rooms = parsed;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rooms = const [];
        _error = '요청 실패: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          _error!,
          style: const TextStyle(
            color: Color(0xFFEF4444),
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    if (_rooms.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          '호실 정보가 없습니다.',
          style: TextStyle(
            color: Color(0xFF6B7280),
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    // ✅ 박스/그리드 레이아웃은 room_card.dart에서 관리
    return LayoutBuilder(
      builder: (context, c) {
        final twoCol = c.maxWidth >= 1200;
        final itemW = twoCol ? (c.maxWidth - 20) / 2 : c.maxWidth;

        return Wrap(
          spacing: 20,
          runSpacing: 20,
          children: [
            for (final r in _rooms)
              SizedBox(
                width: itemW,
                child: RoomCard(
                  room: r,
                  onEmptyBedTap: widget.onEmptyBedTap,
                  onPatientTap: widget.onPatientTap,
                  onRefresh: _loadRooms,
                ),
              ),
          ],
        );
      },
    );
  }
}

// ===============================
// RoomCard (UI만 담당 / room 필수)
// ===============================

class RoomCard extends StatefulWidget {
  final FloorStructureRoom room;

  /// 빈 침대 눌렀을 때
  final Future<void> Function(FloorStructureRoom room, FloorStructureBed bed)?
  onEmptyBedTap;

  /// 환자 눌렀을 때
  final Future<void> Function(BedPatientItem patient)? onPatientTap;

  final Future<void> Function()? onRefresh;

  const RoomCard({
    super.key,
    required this.room,
    this.onEmptyBedTap,
    this.onPatientTap,
    this.onRefresh,
  });

  @override
  State<RoomCard> createState() => _RoomCardState();
}

class _RoomCardState extends State<RoomCard> {
  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final beds = room.beds;
    final occupied = room.occupiedCount;
    final totalBeds = beds.length;

    return Container(
      padding: const EdgeInsets.all(14),
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
                  '호실 ${room.categoryName}',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              TextButton(
                onPressed: () async {
                  final updated = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => _RoomDetailDialog(room: room),
                  );
                  if (updated == true && widget.onRefresh != null) {
                    await widget.onRefresh!();
                  }
                },
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: const Color(0xFF65C466),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFFFFFF),
                  ),
                ),
                child: const Text('상세보기'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '입원 환자: $occupied/$totalBeds',
            style: const TextStyle(
              color: Color(0xFF6B7280),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Container(height: 2, color: const Color(0xFF111827)),
          const SizedBox(height: 14),
          if (beds.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 4),
              child: Center(
                child: Text(
                  '상세보기에서 침상 정보를 추가 해주세요.',
                  style: TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            )
          else
            GridView.builder(
              itemCount: beds.length,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.72,
              ),
              itemBuilder: (context, i) {
                final bed = beds[i];
                final bedNo = bed.bedNo;
                final patient = bed.patient;

                return BedTile(
                  bedNo: bedNo,
                  bedLabel: bed.categoryName,
                  patient: patient,
                  // ✅ 빈 침대 탭 → 환자 추가
                  onTap: () async {
                    if (widget.onEmptyBedTap != null) {
                      await widget.onEmptyBedTap!(room, bed);
                      if (widget.onRefresh != null) await widget.onRefresh!();
                    } else {
                      final ok = await showDialog<bool>(
                        context: context,
                        barrierDismissible: false,
                        builder: (ctx) => PatientAddDialog(),
                      );
                      if (ok == true && widget.onRefresh != null) {
                        await widget.onRefresh!();
                      }
                    }
                  },
                  // ✅ 정보 버튼 → PatientDetailDialog
                  onInfoTap: patient == null
                      ? null
                      : () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (ctx) => PatientDetailPage(
                                patientCode: patient.patientCode,
                                roomLabel: room.categoryName,
                                bedLabel: bed.categoryName,
                                onRefresh: null,
                              ),
                            ),
                          );
                          if (widget.onRefresh != null) {
                            await widget.onRefresh!();
                          }
                        },
                  // ✅ 케어 버튼 → PatientCarePage
                  onCareTap: patient == null
                      ? null
                      : () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (ctx) => PatientCarePage(
                                patientCode: patient.patientCode,
                                patientName: patient.patientName,
                                roomLabel: room.categoryName,
                                bedLabel: bed.categoryName,
                              ),
                            ),
                          );
                        },
                );
              },
            ),
        ],
      ),
    );
  }
}

// ===============================
// _BedItem (침상 편집용 임시 모델)
// ===============================

class _BedItem {
  final int? hospitalStCode; // 기존 침상은 코드 있음, 신규는 null
  final TextEditingController nameCtrl;
  final TextEditingController sortOrderCtrl;
  final bool isNew;

  _BedItem({
    this.hospitalStCode,
    required String bedName,
    required int sortOrder,
    this.isNew = false,
  }) : nameCtrl = TextEditingController(text: bedName),
       sortOrderCtrl = TextEditingController(text: sortOrder.toString());

  void dispose() {
    nameCtrl.dispose();
    sortOrderCtrl.dispose();
  }
}

// ===============================
// _RoomDetailDialog
// ===============================

class _RoomDetailDialog extends StatefulWidget {
  final FloorStructureRoom room;

  const _RoomDetailDialog({required this.room});

  @override
  State<_RoomDetailDialog> createState() => _RoomDetailDialogState();
}

class _RoomDetailDialogState extends State<_RoomDetailDialog> {
  bool _loading = true;
  String? _error;
  bool _saving = false;

  final _roomNameCtrl = TextEditingController();
  final _sortOrderCtrl = TextEditingController();
  final List<_BedItem> _beds = [];

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  @override
  void dispose() {
    _roomNameCtrl.dispose();
    _sortOrderCtrl.dispose();
    for (final b in _beds) {
      b.dispose();
    }
    super.dispose();
  }

  Future<void> _loadDetail() async {
    final roomCode = widget.room.hospitalStCode;
    final base = Urlconfig.serverUrl;
    final uri = Uri.parse('$base/api/hospital/structure/room/$roomCode');
    debugPrint('[ROOM_DETAIL] 조회 URL: $uri');

    try {
      final decoded = await HttpHelper.getJson(uri);

      if (!mounted) return;

      if (decoded['code'] != 1) {
        setState(() {
          _error = decoded['message']?.toString() ?? '조회 실패';
          _loading = false;
        });
        return;
      }

      final data = (decoded['data'] as Map?)?.cast<String, dynamic>();
      final roomInfo = (data?['room_info'] as Map?)?.cast<String, dynamic>();
      final bedsAny = data?['beds'] as List?;

      _roomNameCtrl.text = roomInfo?['room_name']?.toString() ?? '';
      _sortOrderCtrl.text = roomInfo?['sort_order']?.toString() ?? '';

      final newBeds = (bedsAny ?? []).map((e) {
        final m = (e as Map).cast<String, dynamic>();
        return _BedItem(
          hospitalStCode: int.tryParse(m['hospital_st_code']?.toString() ?? ''),
          bedName: m['bed_name']?.toString() ?? '',
          sortOrder: int.tryParse(m['sort_order']?.toString() ?? '') ?? 0,
        );
      }).toList();

      setState(() {
        _beds.addAll(newBeds);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '요청 실패: $e';
        _loading = false;
      });
    }
  }

  void _addBed() {
    setState(() {
      _beds.add(
        _BedItem(bedName: '', sortOrder: _beds.length + 1, isNew: true),
      );
    });
  }

  Future<void> _removeBed(int index) async {
    final bed = _beds[index];

    // 신규 침상(코드 없음)은 바로 제거
    if (bed.hospitalStCode == null) {
      bed.dispose();
      setState(() => _beds.removeAt(index));
      return;
    }

    // 기존 침상은 확인 후 API 호출
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        title: const Text(
          '침상 삭제',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        content: Text(
          '"${bed.nameCtrl.text.trim()}" 침상을 삭제하시겠습니까?',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              '취소',
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              '삭제',
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    try {
      final base = Urlconfig.serverUrl;
      final uri = Uri.parse(
        '$base/api/hospital/structure/bed/${bed.hospitalStCode}',
      );
      debugPrint('[BED_DELETE] URL: $uri');

      final decoded = await HttpHelper.sendJsonAllowError('DELETE', uri);

      if (!mounted) return;

      if (decoded['code'] != 1) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            title: const Text(
              '침상 삭제 불가',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            content: Text(
              decoded['message']?.toString() ?? '침상 삭제에 실패했습니다.',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text(
                  '확인',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3B82F6),
                  ),
                ),
              ),
            ],
          ),
        );
        return;
      }

      bed.dispose();
      setState(() => _beds.removeAt(index));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('침상 삭제 실패: $e')));
    }
  }

  Future<void> _deleteRoom() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
        title: const Text(
          '호실 삭제',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        content: Text(
          '"${widget.room.categoryName}" 호실을 삭제하시겠습니까?\n호실 내 모든 침상 정보도 함께 삭제됩니다.',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Color(0xFF374151),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              '취소',
              style: TextStyle(
                color: Color(0xFF6B7280),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              '삭제',
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    try {
      final base = Urlconfig.serverUrl;
      final uri = Uri.parse(
        '$base/api/hospital/structure/room/${widget.room.hospitalStCode}',
      );
      debugPrint('[ROOM_DELETE] URL: $uri');

      final decoded = await HttpHelper.sendJsonAllowError('DELETE', uri);

      if (!mounted) return;

      if (decoded['code'] != 1) {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFFE5E7EB)),
            ),
            title: const Text(
              '호실 삭제 불가',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            content: Text(
              decoded['message']?.toString() ?? '호실 삭제에 실패했습니다.',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF374151),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text(
                  '확인',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3B82F6),
                  ),
                ),
              ),
            ],
          ),
        );
        return;
      }

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('호실 삭제 실패: $e')));
    }
  }

  Future<void> _save() async {
    final roomCode = widget.room.hospitalStCode;
    final roomName = _roomNameCtrl.text.trim();
    final sortOrder = int.tryParse(_sortOrderCtrl.text.trim()) ?? 0;

    if (roomName.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('호실 이름을 입력해 주세요.')));
      return;
    }

    setState(() => _saving = true);

    try {
      final base = Urlconfig.serverUrl;
      final uri = Uri.parse('$base/api/hospital/structure/room/update');

      final bedsList = _beds
          .map(
            (b) => {
              'hospital_st_code': b.hospitalStCode, // 기존: 코드 있음, 신규: null
              'bed_name': b.nameCtrl.text.trim(),
              'sort_order': int.tryParse(b.sortOrderCtrl.text.trim()) ?? 0,
            },
          )
          .toList();

      final decoded = await HttpHelper.putJson(uri, {
        'room_info': {
          'hospital_st_code': roomCode,
          'room_name': roomName,
          'sort_order': sortOrder,
        },
        'beds': bedsList,
      });

      if (!mounted) return;

      if (decoded['code'] != 1) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(decoded['message']?.toString() ?? '수정 실패')),
        );
        return;
      }

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('수정 실패: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
        child: _loading
            ? const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            : _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFFEF4444),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('닫기'),
                    ),
                  ],
                ),
              )
            : _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    const labelStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: Color(0xFF374151),
    );
    const sectionStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w900,
      color: Color(0xFF111827),
    );

    InputDecoration inputDeco(String hint) => InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: Color(0xFF93C5FD)),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 헤더
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  '호실 상세 정보',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.of(context).pop(),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 12, 24, 0),
          child: Divider(height: 1, color: Color(0xFFE5E7EB)),
        ),

        // 스크롤 컨텐츠
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 기본 정보
                const Text('기본 정보', style: sectionStyle),
                const SizedBox(height: 12),
                const Text('호실 이름', style: labelStyle),
                const SizedBox(height: 6),
                TextField(
                  controller: _roomNameCtrl,
                  decoration: inputDeco('예) 101호'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                const Text('정렬 순서', style: labelStyle),
                const SizedBox(height: 6),
                TextField(
                  controller: _sortOrderCtrl,
                  keyboardType: TextInputType.number,
                  decoration: inputDeco('예) 1'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 24),

                // 침상 정보
                Row(
                  children: [
                    const Expanded(child: Text('침상 정보', style: sectionStyle)),
                    TextButton.icon(
                      onPressed: _addBed,
                      icon: const Icon(Icons.add, size: 16),
                      label: const Text(
                        '침상 추가',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF65C466),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (_beds.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: Text(
                        '등록된 침상이 없습니다.',
                        style: TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                else
                  ...List.generate(_beds.length, (i) {
                    final bed = _beds[i];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: bed.nameCtrl,
                              decoration: inputDeco('침상 이름'),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            width: 72,
                            child: TextField(
                              controller: bed.sortOrderCtrl,
                              keyboardType: TextInputType.number,
                              decoration: inputDeco('순서'),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            onPressed: () {
                              _removeBed(i);
                            },
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: Color(0xFFEF4444),
                            ),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),

        // 하단 버튼
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          child: Row(
            children: [
              OutlinedButton(
                onPressed: _saving ? null : _deleteRoom,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(44, 44),
                  foregroundColor: const Color(0xFFEF4444),
                  side: const BorderSide(color: Color(0xFFEF4444)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                child: const Text('호실 삭제'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF65C466),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(44),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                    elevation: 0,
                  ),
                  child: _saving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('수정'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
