// room_card.dart
import 'dart:async'; // ✅ 추가
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../urlConfig.dart';
import 'bed_tile.dart';

import 'dialogs/patient_add_dialog.dart';
import 'dialogs/patient_detail_dialog.dart';
import 'dialogs/patient_care_dialog.dart';

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
      hospitalStCode: int.tryParse(j['hospital_st_code']?.toString() ?? '') ?? -1,
      categoryName: (j['category_name']?.toString() ?? '').trim(),
      sortOrder: int.tryParse(j['sort_order']?.toString() ?? '') ?? 0,
      beds: bedsList
          .whereType<Map>()
          .map((e) => FloorStructureBed.fromJson(Map<String, dynamic>.from(e)))
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
      hospitalStCode: int.tryParse(j['hospital_st_code']?.toString() ?? '') ?? -1,
      categoryName: (j['category_name']?.toString() ?? '').trim(),
      sortOrder: int.tryParse(j['sort_order']?.toString() ?? '') ?? 0,
      patient: (pMap == null)
          ? null
          : BedPatientItem(
        patientCode: int.tryParse(pMap['patient_code']?.toString() ?? '') ?? -1,
        patientName: (pMap['patient_name']?.toString() ?? '').trim(),
        patientAge: int.tryParse(pMap['patient_age']?.toString() ?? '') ?? 0,
        patientWarning: int.tryParse(pMap['patient_warning']?.toString() ?? '') ?? 0,
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
  final Future<void> Function(FloorStructureRoom room, FloorStructureBed bed)? onEmptyBedTap;
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
      final uri = Uri.parse('$base/api/hospital/structure?hospital_st_code=$st');

      final res = await http.get(uri, headers: {'Content-Type': 'application/json'});
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

      final parsed = list
          .whereType<Map>()
          .map((e) => FloorStructureRoom.fromJson(Map<String, dynamic>.from(e)))
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

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
          style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.w800),
        ),
      );
    }

    if (_rooms.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          '호실 정보가 없습니다.',
          style: TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w800),
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
  final Future<void> Function(FloorStructureRoom room, FloorStructureBed bed)? onEmptyBedTap;

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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '호실 ${room.categoryName}',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            '입원 환자: $occupied/$totalBeds',
            style: const TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          Container(height: 2, color: const Color(0xFF111827)),
          const SizedBox(height: 14),
          if (beds.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text(
                  '침대 정보가 없습니다.',
                  style: TextStyle(color: Color(0xFF9CA3AF), fontWeight: FontWeight.w800),
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
                childAspectRatio: 0.78,
              ),
              itemBuilder: (context, i) {
                final bed = beds[i];
                final bedNo = bed.bedNo;
                final patient = bed.patient;

                return BedTile(
                  bedNo: bedNo,
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
                          await showDialog(
                            context: context,
                            builder: (ctx) => PatientDetailDialog(
                              patientCode: patient.patientCode,
                              roomLabel: room.categoryName,
                              bedLabel: bed.categoryName,
                              onRefresh: null,
                            ),
                          );
                          if (widget.onRefresh != null) {
                            await widget.onRefresh!();
                          }
                        },
                  // ✅ 케어 버튼 → PatientCareDialog
                  onCareTap: patient == null
                      ? null
                      : () async {
                          await showDialog(
                            context: context,
                            builder: (ctx) => PatientCareDialog(
                              patientCode: patient.patientCode,
                              patientName: patient.patientName,
                              roomLabel: room.categoryName,
                              bedLabel: bed.categoryName,
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

  void _simpleInfoDialog(BuildContext context, BedPatientItem p) {
    const border = Color(0xFFE5E7EB);
    const text = Color(0xFF111827);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: border),
        ),
        title: const Text(
          '환자 정보',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: text),
        ),
        content: Text(
          '${p.patientName} (${p.patientAge}세)\npatient_code: ${p.patientCode}',
          style: const TextStyle(fontWeight: FontWeight.w700, height: 1.4, color: text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}
