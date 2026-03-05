import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;

import 'package:mfps/url_config.dart';
import 'package:mfps/storage_keys.dart';

import 'patient_list_card.dart';
import 'dialogs/patient_add_dialog.dart';
import 'side_panel_action_button.dart';
import '../pages/patient_detail_page.dart';

enum PatientTab { all, danger, warning, stable }

class SidePanel extends StatefulWidget {
  final int? floorStCode;

  const SidePanel({super.key, required this.floorStCode});

  @override
  State<SidePanel> createState() => _SidePanelState();
}

class _SidePanelState extends State<SidePanel> {
  static const _storage = FlutterSecureStorage();
  final ScrollController _scrollCtrl = ScrollController();

  late final String _frontUrl;

  bool _isLoading = true;

  // ✅ 층별 환자 목록(명세2)
  List<FloorPatientItem> _allPatients = [];

  // ✅ UI 상태
  PatientTab _tab = PatientTab.all;
  int? _selectedPatientCode;

  // ✅ 자동 재조회(폴링)
  Timer? _pollTimer;
  bool _refreshing = false;

  // 1시간마다 재조회
  static const Duration _pollInterval = Duration(hours: 1);

  @override
  void initState() {
    super.initState();
    _frontUrl = UrlConfig.serverUrl.toString();
    loadData(); // 최초 로딩
    _startPolling();
  }

  @override
  void didUpdateWidget(covariant SidePanel oldWidget) {
    super.didUpdateWidget(oldWidget);

    // ✅ 층이 바뀌면: 선택/탭 초기화 + 재조회 + 폴링 재시작
    if (oldWidget.floorStCode != widget.floorStCode) {
      setState(() {
        _tab = PatientTab.all;
        _selectedPatientCode = null;
      });

      loadData();
      _restartPolling();
    }
  }

  @override
  void dispose() {
    _stopPolling();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) async {
      // 폴링은 UI 로딩 스피너 깜빡이지 않게 silent로
      await loadData(silent: true);
    });
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _restartPolling() {
    _stopPolling();
    _startPolling();
  }

  Future<void> loadData({bool silent = false}) async {
    if (_refreshing) return; // 중복 호출 방지
    _refreshing = true;

    if (!silent && mounted) {
      setState(() => _isLoading = true);
    }

    await getData();

    if (!mounted) {
      _refreshing = false;
      return;
    }

    if (!silent) {
      setState(() => _isLoading = false);
    } else {
      // silent라도 데이터는 새로 반영되어야 하므로 build 트리거
      setState(() {});
    }

    _refreshing = false;
  }

  /// ✅ widget.floorStCode로 조회 (storage 읽기 X)
  Future<void> getData() async {
    final floorStCode = widget.floorStCode;

    if (floorStCode == null) {
      _allPatients = [];
      return;
    }

    // (선택) 다른 화면에서 필요하면 storage도 최신으로 유지
    await _storage.write(
      key: StorageKeys.selectedFloorStCode,
      value: floorStCode.toString(),
    );

    try {
      final uri = Uri.parse(
        '$_frontUrl/api/hospital/structure/patient-list?hospital_st_code=$floorStCode',
      );
      final res = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      debugPrint('[PATIENT_LIST] status=${res.statusCode}');
      debugPrint('[PATIENT_LIST] body=${res.body}');

      if (res.statusCode < 200 || res.statusCode >= 300) {
        _allPatients = [];
        return;
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        _allPatients = [];
        return;
      }
      if (decoded['code'] != 1) {
        _allPatients = [];
        return;
      }

      final data = decoded['data'];
      if (data is! Map<String, dynamic>) {
        _allPatients = [];
        return;
      }

      final patientsAny = data['patients'];
      final list = <FloorPatientItem>[];

      if (patientsAny is List) {
        for (final p in patientsAny) {
          if (p is! Map) continue;

          final code = int.tryParse(p['patient_code']?.toString() ?? '') ?? -1;
          final name = (p['patient_name']?.toString() ?? '').trim();
          final room = (p['patient_room']?.toString() ?? '').trim();
          final bed = (p['patient_bed']?.toString() ?? '').trim();
          final warn =
              int.tryParse(p['patient_warning']?.toString() ?? '') ?? 0;

          if (code <= 0) continue;

          list.add(
            FloorPatientItem(
              patientCode: code,
              patientName: name.isEmpty ? '이름없음' : name,
              patientRoom: room.isEmpty ? '-' : room,
              patientBed: bed.isEmpty ? '-' : bed,
              patientWarning:
                  warn, // ✅ 0=안전, 1=경고, 2=위험 (아이콘 색은 PatientListCard에서 매핑)
            ),
          );
        }
      }

      _allPatients = list;

      // 선택 환자가 사라졌으면 선택 해제 (조용히 정리)
      if (_selectedPatientCode != null &&
          !_allPatients.any((e) => e.patientCode == _selectedPatientCode)) {
        _selectedPatientCode = null;
      }
    } catch (e) {
      debugPrint('[PATIENT_LIST] error=$e');
      _allPatients = [];
    }
  }

  List<FloorPatientItem> get _filteredPatients {
    switch (_tab) {
      case PatientTab.all:
        return _allPatients;
      case PatientTab.danger:
        return _allPatients.where((p) => p.patientWarning == 2).toList();
      case PatientTab.warning:
        return _allPatients.where((p) => p.patientWarning == 1).toList();
      case PatientTab.stable:
        return _allPatients.where((p) => p.patientWarning == 0).toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final patients = _filteredPatients;

    return Container(
      width: 300,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '환자 목록',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '총 ${_allPatients.length}명',
                      style: const TextStyle(
                        color: Color(0xFF6B7280),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (_) => const PatientAddDialog(),
                    );
                    if (ok == true) {
                      await loadData(); // ✅ 추가 후 재조회 유지
                    }
                  },
                  icon: const Icon(Icons.add),
                  label: const Text(
                    '추가',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            child: _Tabs(tab: _tab, onChanged: (t) => setState(() => _tab = t)),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Scrollbar(
                    controller: _scrollCtrl,
                    thumbVisibility: true,
                    child: ListView.separated(
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                      itemCount: patients.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, i) {
                        final p = patients[i];
                        return PatientListCard(
                          patient: p,
                          selected: _selectedPatientCode == p.patientCode,
                          onTap: () async {
                            setState(
                              () => _selectedPatientCode = p.patientCode,
                            );
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => PatientDetailPage(
                                  patientCode: p.patientCode,
                                  roomLabel: p.patientRoom,
                                  bedLabel: p.patientBed,
                                  onRefresh: loadData,
                                ),
                              ),
                            );
                            setState(() => _selectedPatientCode = null);
                            await loadData();
                          },
                        );
                      },
                    ),
                  ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 18),
            child: Divider(height: 1, color: Color(0xFFE5E7EB)),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: SidePanelActionButton(
              label: '병동 선택',
              icon: Icons.apartment_rounded,
              onTap: () async {
                final storage = FlutterSecureStorage();
                await storage.delete(key: 'selected_ward_json');
                await storage.delete(key: StorageKeys.selectedWardStCode);
                await storage.delete(key: StorageKeys.selectedWardName);
                await storage.delete(key: StorageKeys.selectedFloorStCode);
                await storage.delete(key: StorageKeys.floorLabel);

                if (!context.mounted) return;
                context.go('/login');
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _Tabs extends StatelessWidget {
  final PatientTab tab;
  final ValueChanged<PatientTab> onChanged;

  const _Tabs({required this.tab, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, PatientTab v) {
      final selected = tab == v;
      return InkWell(
        onTap: () => onChanged(v),
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.white : const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected ? const Color(0xFFE5E7EB) : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F4F6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        children: [
          chip('전체', PatientTab.all),
          const SizedBox(width: 8),
          chip('위험', PatientTab.danger),
          const SizedBox(width: 8),
          chip('주의', PatientTab.warning),
          const SizedBox(width: 8),
          chip('안전', PatientTab.stable),
        ],
      ),
    );
  }
}
