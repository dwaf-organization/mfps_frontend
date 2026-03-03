import 'package:flutter/material.dart';
import 'week_meal_table.dart';
import 'meal_status.dart';

class MealTab extends StatefulWidget {
  const MealTab({super.key});

  @override
  State<MealTab> createState() => _MealTabState();
}

class _MealTabState extends State<MealTab> {
  // date → { '조식' | '중식' | '석식' → MealStatus }
  final Map<String, Map<String, MealStatus>> _data = {};

  static const _meals = ['조식', '중식', '석식'];

  static const _weeks = [
    ['01/01', '01/02', '01/03', '01/04', '01/05', '01/06', '01/07'],
    ['01/08', '01/09', '01/10', '01/11', '01/12', '01/13', '01/14'],
    ['01/15', '01/16', '01/17', '01/18', '01/19', '01/20', '01/21'],
    ['01/22', '01/23', '01/24', '01/25', '01/26', '01/27', '01/28'],
  ];

  MealStatus _getStatus(String date, String meal) {
    return _data[date]?[meal] ?? MealStatus.before;
  }

  Future<void> _onDateTap(String date) async {
    final current = Map<String, MealStatus>.from(
      _data[date] ?? {for (final m in _meals) m: MealStatus.before},
    );

    final updated = await showModalBottomSheet<Map<String, MealStatus>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      barrierColor: const Color(0x99000000),
      constraints: const BoxConstraints(maxWidth: 1300),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _MealInputSheet(date: date, initial: current),
    );

    if (updated != null) {
      setState(() => _data[date] = updated);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE5E7EB)),
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (final week in _weeks)
              WeekMealTable(
                dates: week,
                getStatus: _getStatus,
                onDateTap: _onDateTap,
              ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════
// 식사 입력 바텀시트
// ══════════════════════════════════════════════

class _MealInputSheet extends StatefulWidget {
  final String date;
  final Map<String, MealStatus> initial;

  const _MealInputSheet({required this.date, required this.initial});

  @override
  State<_MealInputSheet> createState() => _MealInputSheetState();
}

class _MealInputSheetState extends State<_MealInputSheet> {
  late Map<String, MealStatus> _statuses;

  static const _meals = ['조식', '중식', '석식'];

  @override
  void initState() {
    super.initState();
    _statuses = Map.from(widget.initial);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더
            Row(
              children: [
                const Text(
                  '식사 입력',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF111827),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: '닫기',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Colors.grey),
                ),
              ],
            ),
            const Divider(),
            // 날짜 표시
            Text(
              widget.date,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF7F9BD8),
              ),
            ),
            const SizedBox(height: 16),

            // 조식 / 중식 / 석식
            for (int i = 0; i < _meals.length; i++) ...[
              _buildMealSection(_meals[i]),
              if (i < _meals.length - 1) ...[
                const SizedBox(height: 4),
                const Divider(height: 24),
              ],
            ],

            const SizedBox(height: 24),

            // 저장 / 취소 버튼
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF374151),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  child: const Text(
                    '취소',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, _statuses),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6183EE),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  child: const Text(
                    '저장',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMealSection(String meal) {
    final current = _statuses[meal] ?? MealStatus.full;
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(
            meal,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111827),
            ),
          ),
        ),
        const SizedBox(width: 16),
        _buildSelectChip(meal, MealStatus.before, current),
        const SizedBox(width: 10),
        _buildSelectChip(meal, MealStatus.full, current),
        const SizedBox(width: 10),
        _buildSelectChip(meal, MealStatus.miss, current),
      ],
    );
  }

  Widget _buildSelectChip(String meal, MealStatus status, MealStatus current) {
    final isSelected = current == status;

    final Color activeColor = switch (status) {
      MealStatus.full => const Color(0xFF6183EE),
      MealStatus.miss => const Color(0xFFEF4444),
      MealStatus.before => const Color(0xFFD97706),
    };

    return GestureDetector(
      onTap: () => setState(() => _statuses[meal] = status),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? activeColor : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? activeColor : const Color(0xFFD1D5DB),
          ),
        ),
        child: Text(
          status.label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF6B7280),
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
