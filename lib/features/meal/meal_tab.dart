import 'package:flutter/material.dart';

import 'week_meal_table.dart';
import 'meal_status.dart';

class MealTab extends StatefulWidget {
  const MealTab({super.key});

  @override
  State<MealTab> createState() => _MealTabState();
}

class _MealTabState extends State<MealTab> {
  // yyyy-MM-dd -> { '조식' | '중식' | '석식' -> MealStatus }
  final Map<String, Map<String, MealStatus>> _data = {};
  late DateTime _selectedMonth;

  static const _meals = ['조식', '중식', '석식'];

  MealStatus _getStatus(String date, String meal) {
    return _data[date]?[meal] ?? MealStatus.before;
  }

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
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

  Future<void> _selectMonth() async {
    final pickedMonth = await showDialog<DateTime>(
      context: context,
      builder: (context) {
        return _MonthPickerDialog(initialMonth: _selectedMonth);
      },
    );

    if (pickedMonth == null) {
      return;
    }

    setState(() {
      _selectedMonth = DateTime(pickedMonth.year, pickedMonth.month);
    });
  }

  void _moveMonth(int monthOffset) {
    setState(() {
      _selectedMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month + monthOffset,
      );
    });
  }

  List<List<MealDateItem>> _buildWeeks() {
    final lastDay = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    final totalDays = lastDay.day;

    final weeks = <List<MealDateItem>>[];
    var currentWeek = <MealDateItem>[];

    for (int day = 1; day <= totalDays; day++) {
      final date = DateTime(_selectedMonth.year, _selectedMonth.month, day);
      currentWeek.add(
        MealDateItem(
          key: _toStorageKey(date),
          label:
              '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}',
        ),
      );

      if (currentWeek.length == 7 || day == totalDays) {
        weeks.add(currentWeek);
        currentWeek = <MealDateItem>[];
      }
    }

    return weeks;
  }

  String _toStorageKey(DateTime date) {
    return '${date.year.toString().padLeft(4, '0')}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final monthText =
        '${_selectedMonth.year}.${_selectedMonth.month.toString().padLeft(2, '0')}';
    final weeks = _buildWeeks();
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset + 24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: () => _moveMonth(-1),
                  icon: const Icon(Icons.chevron_left),
                  color: const Color(0xFF6B7280),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: _selectMonth,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF111827),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                  ),
                  child: Text(
                    '$monthText 월 선택',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _moveMonth(1),
                  icon: const Icon(Icons.chevron_right),
                  color: const Color(0xFF6B7280),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFFE5E7EB)),
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final week in weeks)
                  WeekMealTable(
                    dates: week,
                    getStatus: _getStatus,
                    onDateTap: _onDateTap,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthPickerDialog extends StatefulWidget {
  final DateTime initialMonth;

  const _MonthPickerDialog({required this.initialMonth});

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  late int _selectedYear;
  late int _selectedMonth;

  static const _monthLabels = <String>[
    '1월',
    '2월',
    '3월',
    '4월',
    '5월',
    '6월',
    '7월',
    '8월',
    '9월',
    '10월',
    '11월',
    '12월',
  ];

  @override
  void initState() {
    super.initState();
    _selectedYear = widget.initialMonth.year;
    _selectedMonth = widget.initialMonth.month;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 420,
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  '월 선택',
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
                  icon: const Icon(Icons.close, color: Color(0xFF6B7280)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  onPressed: () {
                    setState(() {
                      _selectedYear -= 1;
                    });
                  },
                  icon: const Icon(Icons.chevron_left),
                  color: const Color(0xFF6B7280),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '$_selectedYear년',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() {
                      _selectedYear += 1;
                    });
                  },
                  icon: const Icon(Icons.chevron_right),
                  color: const Color(0xFF6B7280),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _monthLabels.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.2,
              ),
              itemBuilder: (context, index) {
                final month = index + 1;
                final isSelected = _selectedMonth == month;

                return InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    setState(() {
                      _selectedMonth = month;
                    });
                  },
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF6183EE)
                          : const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF6183EE)
                            : const Color(0xFFE5E7EB),
                      ),
                    ),
                    child: Text(
                      _monthLabels[index],
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: isSelected
                            ? Colors.white
                            : const Color(0xFF374151),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF374151),
                    side: const BorderSide(color: Color(0xFFE5E7EB)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    '취소',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(
                      context,
                    ).pop(DateTime(_selectedYear, _selectedMonth));
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6183EE),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    '선택',
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
