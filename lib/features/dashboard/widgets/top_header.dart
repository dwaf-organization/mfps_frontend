import 'package:flutter/material.dart';
import './dialogs/settings_dialog.dart';

class TopHeader extends StatefulWidget {
  /// ✅ API에서 내려온 floors 원본 그대로 받기
  /// 예) [{"hospital_st_code":4,"category_name":"1층","sort_order":1}, ...]
  final List<Map<String, dynamic>> floors;

  /// ✅ 현재 선택된 층 st_code (Dropdown의 value)
  final int? selectedFloorStCode;

  /// ✅ 현재 선택된 층 라벨 (표시용)
  final String floorLabel;

  /// ✅ 층 로딩중이면 true
  final bool loadingFloors;

  /// ✅ 층 선택 변경 시 (hospital_st_code 전달)
  final ValueChanged<int> onFloorChanged;

  const TopHeader({
    super.key,
    required this.floors,
    required this.selectedFloorStCode,
    required this.floorLabel,
    required this.onFloorChanged,
    this.loadingFloors = false,
  });

  @override
  State<TopHeader> createState() => _TopHeaderState();
}

class _TopHeaderState extends State<TopHeader> {
  @override
  Widget build(BuildContext context) {
    final hasFloors = widget.floors.isNotEmpty;

    // ✅ Dropdown value는 반드시 items 중 하나여야 해서, 없으면 첫 번째로 보정
    int? selected = widget.selectedFloorStCode;
    if (hasFloors) {
      final stCodes = widget.floors
          .map((f) => int.tryParse(f['hospital_st_code']?.toString() ?? ''))
          .whereType<int>()
          .toList();

      if (stCodes.isEmpty) {
        selected = null;
      } else {
        if (selected == null || !stCodes.contains(selected)) {
          selected = stCodes.first;
        }
      }
    } else {
      selected = null;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('병동 모니터링 시스템', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
              SizedBox(height: 4),
              Text(
                '전체 환자 현황 및 건강 상태 관리',
                style: TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(width: 28),

          const Text('층수:', style: TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w700)),
          const SizedBox(width: 10),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(14),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: selected,
                hint: Text(
                  widget.floorLabel.trim().isEmpty ? '층 없음' : widget.floorLabel,
                  style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF111827)),
                ),
                dropdownColor: const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(16),
                elevation: 2,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827),
                ),
                items: hasFloors
                    ? [
                  for (final f in widget.floors)
                    if (int.tryParse(f['hospital_st_code']?.toString() ?? '') != null)
                      DropdownMenuItem<int>(
                        value: int.parse(f['hospital_st_code'].toString()),
                        child: Text(
                          (f['category_name']?.toString().trim().isEmpty ?? true)
                              ? '-'
                              : f['category_name'].toString(),
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                ]
                    : const [],
                onChanged: (!hasFloors || widget.loadingFloors)
                    ? null
                    : (v) {
                  if (v == null) return;
                  widget.onFloorChanged(v);
                },
              ),
            ),
          ),

          if (widget.loadingFloors) ...[
            const SizedBox(width: 10),
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],

          const Spacer(),

          _IconWithDot(
            icon: Icons.settings_outlined,
            dot: true,
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => const SettingsDialog(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _IconWithDot extends StatefulWidget {
  final IconData icon;
  final bool dot;
  final VoidCallback onTap;

  const _IconWithDot({
    required this.icon,
    required this.dot,
    required this.onTap,
  });

  @override
  State<_IconWithDot> createState() => _IconWithDotState();
}

class _IconWithDotState extends State<_IconWithDot> {
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IconButton(onPressed: widget.onTap, icon: Icon(widget.icon)),
        if (widget.dot)
          const Positioned(
            right: 10,
            top: 10,
            child: CircleAvatar(radius: 4, backgroundColor: Color(0xFFEF4444)),
          ),
      ],
    );
  }
}
