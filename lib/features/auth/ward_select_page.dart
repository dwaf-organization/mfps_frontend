import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:mfps/url_config.dart';
import 'package:mfps/storage_keys.dart';

import 'package:mfps/api/http_helper.dart';

/// =======================
/// Models
/// =======================
class WardItem {
  final int hospitalStCode;
  final String categoryName;
  final int sortOrder;

  const WardItem({
    required this.hospitalStCode,
    required this.categoryName,
    required this.sortOrder,
  });

  factory WardItem.fromJson(Map<String, dynamic> json) {
    return WardItem(
      hospitalStCode:
          int.tryParse(json['hospital_st_code']?.toString() ?? '') ?? 0,
      categoryName: (json['category_name'] ?? '').toString(),
      sortOrder: int.tryParse(json['sort_order']?.toString() ?? '') ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'hospital_st_code': hospitalStCode,
    'category_name': categoryName,
    'sort_order': sortOrder,
  };
}

class FloorItem {
  final int hospitalFlCode;
  final int hospitalStCode;
  final String floorName;
  final int sortOrder;

  const FloorItem({
    required this.hospitalFlCode,
    required this.hospitalStCode,
    required this.floorName,
    required this.sortOrder,
  });

  factory FloorItem.fromJson(Map<String, dynamic> json) {
    return FloorItem(
      hospitalFlCode:
          int.tryParse(json['hospital_fl_code']?.toString() ?? '') ?? 0,
      hospitalStCode:
          int.tryParse(json['hospital_st_code']?.toString() ?? '') ?? 0,
      floorName: (json['floor_name'] ?? json['category_name'] ?? '').toString(),
      sortOrder: int.tryParse(json['sort_order']?.toString() ?? '') ?? 0,
    );
  }
}

/// =======================
/// Page
/// =======================
class WardSelectPage extends StatefulWidget {
  const WardSelectPage({super.key});

  @override
  State<WardSelectPage> createState() => _WardSelectPageState();
}

class _WardSelectPageState extends State<WardSelectPage> {
  static const _storage = FlutterSecureStorage();

  static const _hospitalCodeStorageKey = 'hospital_code';
  static const _selectedWardStorageKey = 'selected_ward_json';

  late final String _frontUrl;

  int? hospitalCode;
  List<WardItem> wards = [];
  bool wardsLoading = false;
  bool _autoRouted = false;

  WardItem? _selectedWard;
  List<FloorItem> _floors = [];
  bool _floorsLoading = false;

  @override
  void initState() {
    super.initState();
    _frontUrl = UrlConfig.serverUrl.toString();
    _loadStoredHospitalCode();
  }

  Future<void> _loadStoredHospitalCode() async {
    final storedHospitalCode = await _storage.read(
      key: _hospitalCodeStorageKey,
    );
    hospitalCode = int.tryParse(storedHospitalCode ?? '');
    if (hospitalCode != null) {
      await _loadWards();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.go('/login');
      });
    }
  }

  Future<void> _loadWards() async {
    if (hospitalCode == null) return;

    try {
      setState(() {
        wardsLoading = true;
        _autoRouted = false;
      });

      final uri = Uri.parse(
        '$_frontUrl/api/hospital/structure/part?hospital_code=$hospitalCode',
      );
      final decoded = await HttpHelper.getJson(uri);

      final ok = decoded['code'] == 1;
      if (!ok) throw Exception((decoded['message'] ?? '병동 조회 실패').toString());

      final data = decoded['data'];
      if (data is! Map) throw Exception('병동 조회 data가 비었습니다.');

      final parts = data['parts'];
      final List<WardItem> wardItems = [];
      if (parts is List) {
        for (final part in parts) {
          if (part is Map<String, dynamic>) {
            wardItems.add(WardItem.fromJson(part));
          } else if (part is Map) {
            wardItems.add(WardItem.fromJson(Map<String, dynamic>.from(part)));
          }
        }
      }
      wardItems.sort((leftWard, rightWard) {
        return leftWard.sortOrder.compareTo(rightWard.sortOrder);
      });

      if (!mounted) return;
      setState(() {
        wards = wardItems;
        wardsLoading = false;
      });

      // 병동이 없으면 대시보드로 바로 이동
      if (wards.isEmpty && !_autoRouted) {
        _autoRouted = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          context.go('/dashboard');
        });
      }
    } catch (e) {
      debugPrint('[WARDS] error=$e');
      if (!mounted) return;
      setState(() {
        wards = [];
        wardsLoading = false;
      });
      _snack('병동 조회 실패: $e');
    }
  }

  Future<void> _onWardTap(WardItem selectedWard) async {
    setState(() {
      _selectedWard = selectedWard;
      _floors = [];
      _floorsLoading = true;
    });

    try {
      final uri = Uri.parse(
        '$_frontUrl/api/hospital/structure/floor?hospital_st_code=${selectedWard.hospitalStCode}',
      );
      final decoded = await HttpHelper.getJson(uri);

      final ok = decoded['code'] == 1;
      if (!ok) throw Exception((decoded['message'] ?? '층 조회 실패').toString());

      final data = decoded['data'];
      if (data is! Map) throw Exception('층 조회 data가 비었습니다.');

      final rawFloors = data['floors'] ?? data['parts'];
      final List<FloorItem> floorItems = [];
      if (rawFloors is List) {
        for (final floor in rawFloors) {
          if (floor is Map<String, dynamic>) {
            floorItems.add(FloorItem.fromJson(floor));
          } else if (floor is Map) {
            floorItems.add(
              FloorItem.fromJson(Map<String, dynamic>.from(floor)),
            );
          }
        }
      }
      floorItems.sort((leftFloor, rightFloor) {
        return leftFloor.sortOrder.compareTo(rightFloor.sortOrder);
      });

      if (!mounted) return;
      setState(() {
        _floors = floorItems;
        _floorsLoading = false;
      });
    } catch (e) {
      debugPrint('[FLOORS] error=$e');
      if (!mounted) return;
      setState(() {
        _floors = [];
        _floorsLoading = false;
      });
      _snack('층 조회 실패: $e');
    }
  }

  Future<void> _confirmWard() async {
    final selectedWard = _selectedWard;
    if (selectedWard == null) {
      _snack('병동을 선택해 주세요.');
      return;
    }

    await _storage.write(
      key: _selectedWardStorageKey,
      value: jsonEncode(selectedWard.toJson()),
    );
    await _storage.write(
      key: StorageKeys.selectedWardStCode,
      value: selectedWard.hospitalStCode.toString(),
    );
    await _storage.write(
      key: StorageKeys.selectedWardName,
      value: selectedWard.categoryName,
    );

    if (!mounted) return;
    context.go('/dashboard');
  }

  Future<void> _showEditFloorSheet(FloorItem floor) async {
    final selectedWard = _selectedWard;
    if (selectedWard == null) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditFloorBottomSheet(
        frontUrl: _frontUrl,
        floor: floor,
        onUpdated: () => _onWardTap(selectedWard),
      ),
    );
  }

  Future<void> _showAddFloorSheet() async {
    final selectedWard = _selectedWard;
    if (selectedWard == null || hospitalCode == null) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddFloorBottomSheet(
        frontUrl: _frontUrl,
        hospitalCode: hospitalCode!,
        parentCode: selectedWard.hospitalStCode,
        onAdded: () => _onWardTap(selectedWard),
      ),
    );
  }

  Future<void> _showAddWardSheet() async {
    if (hospitalCode == null) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddWardBottomSheet(
        frontUrl: _frontUrl,
        hospitalCode: hospitalCode!,
        onAdded: _loadWards,
      ),
    );
  }

  Future<void> _backToLogin() async {
    await _storage.delete(key: _hospitalCodeStorageKey);
    await _storage.delete(key: _selectedWardStorageKey);
    await _storage.delete(key: StorageKeys.selectedWardStCode);
    await _storage.delete(key: StorageKeys.selectedWardName);

    if (!mounted) return;
    context.go('/login');
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: const Color(0xFFF3F4F6),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '병동 모니터링 시스템',
                  style: TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  '로그인 후 전체 환자 현황 및 건강 상태를 관리합니다.',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 왼쪽: 병동 선택 카드
                    Expanded(
                      child: _WardCard(
                        wards: wards,
                        loading: wardsLoading,
                        selectedWard: _selectedWard,
                        onWardTap: _onWardTap,
                        onRetry: _loadWards,
                        onAddWard: _showAddWardSheet,
                        onConfirm: _confirmWard,
                        onBackToLogin: _backToLogin,
                      ),
                    ),
                    const SizedBox(width: 16),
                    // 오른쪽: 층 정보 카드
                    Expanded(
                      child: _FloorCard(
                        selectedWard: _selectedWard,
                        floors: _floors,
                        loading: _floorsLoading,
                        onAddFloor: _showAddFloorSheet,
                        onEditFloor: _showEditFloorSheet,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// =======================
/// Card decoration helper
/// =======================
BoxDecoration _cardDecoration() => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(18),
  border: Border.all(color: const Color(0xFFE5E7EB)),
  boxShadow: const [
    BoxShadow(color: Color(0x14000000), blurRadius: 20, offset: Offset(0, 10)),
  ],
);

/// =======================
/// Ward Card
/// =======================
class _WardCard extends StatelessWidget {
  final List<WardItem> wards;
  final bool loading;
  final WardItem? selectedWard;
  final void Function(WardItem) onWardTap;
  final Future<void> Function() onRetry;
  final Future<void> Function() onAddWard;
  final Future<void> Function() onConfirm;
  final Future<void> Function() onBackToLogin;

  const _WardCard({
    required this.wards,
    required this.loading,
    required this.selectedWard,
    required this.onWardTap,
    required this.onRetry,
    required this.onAddWard,
    required this.onConfirm,
    required this.onBackToLogin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '병동 선택',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '병동을 선택하면 층 정보를 확인할 수 있습니다.',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 18),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final w in wards) ...[
                  _WardSelectButton(
                    ward: w,
                    isSelected:
                        selectedWard?.hospitalStCode == w.hospitalStCode,
                    onTap: () => onWardTap(w),
                  ),
                  const SizedBox(height: 8),
                ],
                // + 병동 추가 버튼
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF65C466),
                    minimumSize: const Size.fromHeight(48),
                    overlayColor: Colors.transparent,
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  onPressed: onAddWard,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('병동 추가'),
                ),
              ],
            ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: onBackToLogin,
              child: const Text('다른 계정으로 로그인'),
            ),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF65539F),
              foregroundColor: Colors.white,
              // disabledBackgroundColor: const Color(0xFFD1FAD1),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 15,
              ),
              elevation: 0,
            ),
            onPressed: selectedWard != null ? onConfirm : null,
            child: const Text('병동 접속하기'),
          ),
        ],
      ),
    );
  }
}

class _WardSelectButton extends StatelessWidget {
  final WardItem ward;
  final bool isSelected;
  final VoidCallback onTap;

  const _WardSelectButton({
    required this.ward,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (isSelected) {
            return const Color(0xFFF0FDF4);
          }
          return Colors.white;
        }),
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (isSelected) {
            return const Color(0xFF65C466);
          }
          return const Color(0xFF374151);
        }),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        side: WidgetStateProperty.resolveWith((states) {
          return BorderSide(
            color: isSelected
                ? const Color(0xFF65C466)
                : const Color(0xFFE5E7EB),
            width: isSelected ? 1.5 : 1.0,
          );
        }),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        elevation: const WidgetStatePropertyAll(0),
      ),
      onPressed: onTap,
      child: Text(ward.categoryName),
    );
  }
}

/// =======================
/// Floor Card
/// =======================
class _FloorCard extends StatelessWidget {
  final WardItem? selectedWard;
  final List<FloorItem> floors;
  final bool loading;
  final Future<void> Function()? onAddFloor;
  final void Function(FloorItem)? onEditFloor;

  const _FloorCard({
    required this.selectedWard,
    required this.floors,
    required this.loading,
    this.onAddFloor,
    this.onEditFloor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            selectedWard != null ? '${selectedWard!.categoryName} 정보' : '층 정보',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: Color(0xFF111827),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            selectedWard != null
                ? '${selectedWard!.categoryName}의 층 목록입니다.'
                : '왼쪽에서 병동을 선택해 주세요.',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 18),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (selectedWard == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  '병동을 선택하면 층 정보가 표시됩니다.',
                  style: TextStyle(
                    color: Color(0xFF9CA3AF),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            )
          else if (floors.isEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      '해당 병동에 층 정보가 없습니다.\n층을 추가해주세요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontWeight: FontWeight.w600,
                        height: 1.6,
                      ),
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF65C466),
                    foregroundColor: Color(0xFFFFFFFF),
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                    elevation: 0,
                  ),
                  onPressed: onAddFloor,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('추가'),
                ),
              ],
            )
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (int i = 0; i < floors.length; i++) ...[
                  _FloorRow(
                    floor: floors[i],
                    onEdit: onEditFloor != null
                        ? () => onEditFloor!(floors[i])
                        : null,
                  ),
                  if (i < floors.length - 1)
                    const Divider(height: 1, color: Color(0xFFF3F4F6)),
                ],
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF65C466),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                    elevation: 0,
                  ),
                  onPressed: onAddFloor,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('추가'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _FloorRow extends StatelessWidget {
  final FloorItem floor;
  final VoidCallback? onEdit;

  const _FloorRow({required this.floor, this.onEdit});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Icon(Icons.layers_outlined, size: 18, color: Color(0xFF9CA3AF)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              floor.floorName,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: Color(0xFF374151),
              ),
            ),
          ),
          IconButton(
            onPressed: onEdit,
            icon: const Icon(
              Icons.edit_outlined,
              size: 18,
              color: Color(0xFF9CA3AF),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            tooltip: '수정',
          ),
        ],
      ),
    );
  }
}

/// =======================
/// Add Ward Bottom Sheet
/// =======================
class _AddWardBottomSheet extends StatefulWidget {
  final String frontUrl;
  final int hospitalCode;
  final Future<void> Function() onAdded;

  const _AddWardBottomSheet({
    required this.frontUrl,
    required this.hospitalCode,
    required this.onAdded,
  });

  @override
  State<_AddWardBottomSheet> createState() => _AddWardBottomSheetState();
}

class _AddWardBottomSheetState extends State<_AddWardBottomSheet> {
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
        'parents_code': null,
        'note': null,
      });

      final ok = decoded['code'] == 1;
      if (!ok) throw Exception((decoded['message'] ?? '병동 추가 실패').toString());

      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.onAdded();
    } catch (e) {
      debugPrint('[ADD_WARD] error=$e');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('병동 추가 실패: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 핸들바
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
                  '병동 추가',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '추가할 병동 이름을 입력해 주세요.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _ctrl,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: '예) 1병동, 내과 병동',
                    filled: true,
                    fillColor: const Color(0xFFF3F4F6),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _loading
                            ? null
                            : () => Navigator.of(context).pop(),
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                          elevation: 0,
                        ),
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('추가'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// =======================
/// Add Floor Bottom Sheet
/// =======================
class _AddFloorBottomSheet extends StatefulWidget {
  final String frontUrl;
  final int hospitalCode;
  final int parentCode;
  final Future<void> Function() onAdded;

  const _AddFloorBottomSheet({
    required this.frontUrl,
    required this.hospitalCode,
    required this.parentCode,
    required this.onAdded,
  });

  @override
  State<_AddFloorBottomSheet> createState() => _AddFloorBottomSheetState();
}

class _AddFloorBottomSheetState extends State<_AddFloorBottomSheet> {
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
        'parents_code': widget.parentCode,
        'note': null,
      });

      final ok = decoded['code'] == 1;
      if (!ok) throw Exception((decoded['message'] ?? '층 추가 실패').toString());

      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.onAdded();
    } catch (e) {
      debugPrint('[ADD_FLOOR] error=$e');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('층 추가 실패: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
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
                  '층 추가',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  '추가할 층 이름을 입력해 주세요.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _ctrl,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    hintText: '예) 1층, 2층, 옥상',
                    filled: true,
                    fillColor: const Color(0xFFF3F4F6),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _loading
                            ? null
                            : () => Navigator.of(context).pop(),
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                          elevation: 0,
                        ),
                        onPressed: _loading ? null : _submit,
                        child: _loading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('추가'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// =======================
/// Edit Floor Bottom Sheet
/// =======================
class _EditFloorBottomSheet extends StatefulWidget {
  final String frontUrl;
  final FloorItem floor;
  final Future<void> Function() onUpdated;

  const _EditFloorBottomSheet({
    required this.frontUrl,
    required this.floor,
    required this.onUpdated,
  });

  @override
  State<_EditFloorBottomSheet> createState() => _EditFloorBottomSheetState();
}

class _EditFloorBottomSheetState extends State<_EditFloorBottomSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _orderCtrl;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.floor.floorName);
    _orderCtrl = TextEditingController(text: widget.floor.sortOrder.toString());
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _orderCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    final orderStr = _orderCtrl.text.trim();
    if (name.isEmpty) return;

    final order = int.tryParse(orderStr) ?? widget.floor.sortOrder;
    setState(() => _loading = true);

    try {
      final uri = Uri.parse(
        '${widget.frontUrl}/api/hospital/structure/reorder',
      );
      final decoded = await HttpHelper.putJson(uri, {
        'hospital_st_code': widget.floor.hospitalStCode,
        'category_name': name,
        'sort_order': order,
      });

      final ok = decoded['code'] == 1;
      if (!ok) throw Exception((decoded['message'] ?? '층 수정 실패').toString());

      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.onUpdated();
    } catch (e) {
      debugPrint('[EDIT_FLOOR] error=$e');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('층 수정 실패: $e')));
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('층 삭제'),
        content: Text('\'${widget.floor.floorName}\'을(를) 정말 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() => _loading = true);

    try {
      final uri = Uri.parse(
        '${widget.frontUrl}/api/hospital/structure/floor/${widget.floor.hospitalStCode}',
      );
      final decoded = await HttpHelper.sendJson('DELETE', uri);

      final ok = decoded['code'] == 1;
      if (!ok) throw Exception((decoded['message'] ?? '층 삭제 실패').toString());

      if (!mounted) return;
      Navigator.of(context).pop();
      await widget.onUpdated();
    } catch (e) {
      debugPrint('[DELETE_FLOOR] error=$e');
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('층 삭제 실패: $e')));
    }
  }

  InputDecoration _deco(String hint) => InputDecoration(
    hintText: hint,
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
  );

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      '층 수정',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF111827),
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      onPressed: _loading ? null : _delete,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('삭제'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  '층 이름과 정렬 순서를 수정해 주세요.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  '층 이름',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFF374151),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameCtrl,
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: _deco('예) 1층, 2층'),
                ),
                const SizedBox(height: 14),
                const Text(
                  '정렬 순서',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: Color(0xFF374151),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _orderCtrl,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  decoration: _deco('예) 1, 2, 3'),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          side: const BorderSide(color: Color(0xFFE5E7EB)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _loading
                            ? null
                            : () => Navigator.of(context).pop(),
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                          elevation: 0,
                        ),
                        onPressed: _loading ? null : _submit,
                        child: _loading
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}
