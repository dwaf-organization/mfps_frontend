import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'package:mfps/url_config.dart';
import 'package:mfps/storage_keys.dart';

import 'widgets/top_header.dart';
import 'widgets/summary_cards.dart';
import 'widgets/side_panel.dart';
import 'widgets/room_card.dart';
import 'package:mfps/api/http_helper.dart';

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState(
  );
}
class _DashboardPageState extends State<DashboardPage> {
  static const _storage = FlutterSecureStorage();
  final _scrollCtrl = ScrollController();

  late final String _frontUrl;
  Map<String, dynamic> data = {};

  bool _isLoading = true;

  String wardName = '전체';

  // ✅ (추가) TopHeader 층 드롭다운에 넣을 목록/로딩상태
  List<Map<String, dynamic>> floors = [];
  int? selectedFloorStCode; // 선택된 층의 hospital_st_code
  String selectedFloorLabel = ''; // 선택된 층의 category_name (예: "2층", "B1층")
  String floorLabel = '';

  bool floorsLoading = false;
  int? _hospitalCode;

  // TODO: rooms / counts는 기존 provider 로직을 옮기거나 API 나오면 여기서 채우면 됨
  int total = 0,
      danger = 0,
      warning = 0,
      stable = 0;
  List rooms = const [];

  @override
  void initState() {
    super.initState();
    _frontUrl = UrlConfig.serverUrl.toString();
    loadData();
  }

  Future<void> loadData() async {
    setState(() => _isLoading = true);
    await getData();
    setState(() => _isLoading = false);
  }

  //데이터 셋업
  Future<void> getData() async {
    // 1) 로그인 화면에서 저장해 둔 병동명/코드 읽기
    final savedWardName = await _storage.read(
        key: StorageKeys.selectedWardName);
    final savedWardStCodeStr = await _storage.read(
        key: StorageKeys.selectedWardStCode);
    final savedHospitalCodeStr = await _storage.read(
        key: StorageKeys.hospitalCode);
    _hospitalCode = int.tryParse((savedHospitalCodeStr ?? '').trim());

    wardName = (savedWardName == null || savedWardName
        .trim()
        .isEmpty) ? '전체' : savedWardName.trim();
    final wardStCode = int.tryParse((savedWardStCodeStr ?? '').trim());
    debugPrint(
        'savedWardName=$savedWardName, savedWardStCode=$savedWardStCodeStr');

    // 병동 코드가 없으면 층 드롭다운 자체를 비워둠(예외 UI 없이)
    if (wardStCode == null) {
      floors = [];
      selectedFloorStCode = null;
      selectedFloorLabel = '';
      return;
    }


    // 2) ✅ 병동별 층 조회
    try {
      floorsLoading = true;

      final uri = Uri.parse(
          '$_frontUrl/api/hospital/structure/floor?hospital_st_code=$wardStCode');
      final res = await http.get(
          uri, headers: {'Content-Type': 'application/json'});

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return;
      if (decoded['code'] != 1) return;

      final body = decoded['data'] as Map<String, dynamic>;

      final listAny = (body['floors'] as List?) ?? [];
      floors = listAny.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      if (floors.isEmpty) {
        selectedFloorStCode = null;
        floorLabel = '';
        return;
      }

      // ✅ 기본 선택: sort_order가 가장 작은 것(없으면 첫 번째)
      floors.sort((a, b) {
        final sa = int.tryParse(a['sort_order']?.toString() ?? '') ?? 999999;
        final sb = int.tryParse(b['sort_order']?.toString() ?? '') ?? 999999;
        return sa.compareTo(sb);
      });

      final first = floors.first;
      selectedFloorStCode =
          int.tryParse(first['hospital_st_code']?.toString() ?? '');
      floorLabel = first['category_name']?.toString() ?? '';

      await _storage.write(key: StorageKeys.selectedFloorStCode,
          value: (selectedFloorStCode ?? '').toString());
      await _storage.write(key: StorageKeys.floorLabel, value: floorLabel);
    } catch (_) {
      floors = [];
      selectedFloorStCode = null;
      floorLabel = '';
    } finally {
      floorsLoading = false;
    }
  }


  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF3F4F6),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      body: SafeArea(
        child: Row(
          children: [
            _buildSidePanel(),
            Expanded(
              child: Column(
                children: [
                  _buildTopHeader(),
                  Expanded(
                    child: _buildMainScroll(
                      wardName: wardName,
                      floorLabel: floorLabel,
                      total: total,
                      danger: danger,
                      warning: warning,
                      stable: stable,
                      rooms: rooms,
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




  // ---------------- UI Builders ----------------

  Widget _buildSidePanel() {
    return SidePanel(
      key: ValueKey('side-${selectedFloorStCode ?? 'none'}'),
      floorStCode: selectedFloorStCode,
    );
  }


  //상단 타이틀
  Widget _buildTopHeader() {
    return TopHeader(
      floors: floors,
      selectedFloorStCode: selectedFloorStCode,
      floorLabel: floorLabel,
      loadingFloors: floorsLoading,
      onFloorChanged: (nextStCode) async {
        // 선택된 floor 찾기
        Map<String, dynamic>? picked;
        for (final f in floors) {
          final st = int.tryParse(f['hospital_st_code']?.toString() ?? '');
          if (st == nextStCode) {
            picked = f;
            break;
          }
        }
        if (picked == null) return;

        setState(() {
          selectedFloorStCode = nextStCode;
          floorLabel = picked!['category_name']?.toString() ?? '';
        });

        await _storage.write(
            key: StorageKeys.selectedFloorStCode, value: nextStCode.toString());
        await _storage.write(
            key: StorageKeys.floorLabel, value: floorLabel);

        // TODO: 여기서 “층 변경 시 rooms/summary 재조회” 붙이면 됨
        // await loadData();
      },
    );
  }




  Widget _buildMainScroll({
    required String wardName,
    required String floorLabel,
    required int total,
    required int danger,
    required int warning,
    required int stable,
    required List rooms,
  }) {
    return Scrollbar(
      controller: _scrollCtrl,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _scrollCtrl,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummaryCards(
                total: total, danger: danger, warning: warning, stable: stable),
            const SizedBox(height: 18),
            _buildWardTitle(wardName: wardName, floorLabel: floorLabel),
            const SizedBox(height: 10),
            RoomsSection(floorStCode: selectedFloorStCode),
          ],
        ),
      ),
    );
  }

//위험,주의,경고,카드
  Widget _buildSummaryCards({
    required int total,
    required int danger,
    required int warning,
    required int stable,
  }) {
    return SummaryCards(floorStCode: selectedFloorStCode);
  }

  // 룸 그리드
  Widget _buildRoomGrid({required List rooms}) {
    return LayoutBuilder(
      builder: (context, c) {
        final twoCol = c.maxWidth >= 1200;
        final itemW = twoCol ? (c.maxWidth - 20) / 2 : c.maxWidth;

        return Wrap(
          spacing: 20,
          runSpacing: 20,
          children: [
            for (final r in rooms)
              SizedBox(
                width: itemW,
                child: RoomCard(room: r),
              ),
          ],
        );
      },
    );
  }

  //타이틀
  Widget _buildWardTitle(
      {required String wardName, required String floorLabel}) {
    final floorText = floorLabel
        .trim()
        .isEmpty ? '층 정보 없음' : floorLabel.trim();

    return Row(
      children: [
        Text(
          '$floorText 병동',
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(width: 12),
        if (selectedFloorStCode != null && _hospitalCode != null)
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF65C466),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              elevation: 0,
            ),
            onPressed: _showAddRoomSheet,
            child: const Text('호실 추가'),
          ),
      ],
    );
  }

  Future<void> _showAddRoomSheet() async {
    final floorCode = selectedFloorStCode;
    final hospCode = _hospitalCode;
    if (floorCode == null || hospCode == null) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddRoomBottomSheet(
        frontUrl: _frontUrl,
        hospitalCode: hospCode,
        floorStCode: floorCode,
        onAdded: loadData,
      ),
    );
  }
}

class _AddRoomBottomSheet extends StatefulWidget {
  final String frontUrl;
  final int hospitalCode;
  final int floorStCode;
  final Future<void> Function() onAdded;

  const _AddRoomBottomSheet({
    required this.frontUrl,
    required this.hospitalCode,
    required this.floorStCode,
    required this.onAdded,
  });

  @override
  State<_AddRoomBottomSheet> createState() => _AddRoomBottomSheetState();
}

class _AddRoomBottomSheetState extends State<_AddRoomBottomSheet> {
  final _ctrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _ctrl.text.trim();
    if (name.isEmpty) return;

    setState(() => _loading = true);

    try {
      final uri = Uri.parse('${widget.frontUrl}/api/hospital/structure');
      final decoded = await HttpHelper.postJson(uri, {
        'hospital_code': widget.hospitalCode,
        'category_name': name,
        'parents_code': widget.floorStCode,
        'note': null,
      });

      final ok = decoded['code'] == 1;
      if (!ok) throw Exception((decoded['message'] ?? '호실 추가 실패').toString());

      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.onAdded();
    } catch (e) {
      debugPrint('[ADD_ROOM] error=$e');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('호실 추가 실패: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: const Color(0xFFE5E7EB),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Text(
            '호실 추가',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF111827)),
          ),
          const SizedBox(height: 6),
          const Text(
            '추가할 호실 이름을 입력해 주세요.',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              hintText: '예) 101호, 102호',
              filled: true,
              fillColor: const Color(0xFFF3F4F6),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE5E7EB)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFF93C5FD)),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _loading ? null : () => Navigator.of(context).pop(),
                  child: const Text('취소'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF65C466),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                    elevation: 0,
                  ),
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('추가'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
