import 'package:flutter/material.dart';
import 'incontinence_bottom_sheet.dart';

class MonthCalendar extends StatefulWidget {
  const MonthCalendar({super.key});

  @override
  State<MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends State<MonthCalendar> {
  DateTime _focusedMonth = DateTime.now();

  final Map<DateTime, bool> _incontinenceMap = {};

  DateTime _normalize(DateTime d) {
    return DateTime(d.year, d.month, d.day);
  }

  void _onDateTap(DateTime date) async {
    final normalized = _normalize(date);

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return IncontinenceBottomSheet(
          date: normalized,
          initialValue: _incontinenceMap[normalized] ?? false,
        );
      },
    );

    if (result != null) {
      setState(() {
        _incontinenceMap[normalized] = result;
      });
    }
  }

  // 이전 달
  void _prevMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
    });
  }

  // 다음 달
  void _nextMonth() {
    setState(() {
      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final days = _buildCalendarDays(_focusedMonth);

    return Column(
      children: [
        _buildHeader(),
        const SizedBox(height: 12),
        _buildWeekHeader(),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: days.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
          ),
          itemBuilder: (context, index) {
            final date = days[index];
            final normalized = _normalize(date);

            return _CalendarCell(
              date: date,
              isCurrentMonth: date.month == _focusedMonth.month,
              hasIncontinence: _incontinenceMap[normalized] == true,
              onTap: () {
                _onDateTap(date);
              },
            );
          },
        ),
      ],
    );
  }

  // 상단 월 이동 헤더
  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(onPressed: _prevMonth, icon: const Icon(Icons.chevron_left)),
        Text(
          '${_focusedMonth.year}년 ${_focusedMonth.month}월',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        IconButton(
          onPressed: _nextMonth,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  // 요일 헤더
  Widget _buildWeekHeader() {
    const weekDays = ['월', '화', '수', '목', '금', '토', '일'];

    return Row(
      children: weekDays
          .map(
            (d) => Expanded(
              child: Center(
                child: Text(
                  d,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  /// 📌 달력에 들어갈 날짜 리스트 생성
  List<DateTime> _buildCalendarDays(DateTime month) {
    final firstDayOfMonth = DateTime(month.year, month.month, 1);
    final firstWeekday = firstDayOfMonth.weekday; // 1=월, 7=일

    final startDay = firstDayOfMonth.subtract(Duration(days: firstWeekday - 1));

    return List.generate(42, (index) {
      return startDay.add(Duration(days: index));
    });
  }
}

// 날짜 셀 위젯
class _CalendarCell extends StatelessWidget {
  final DateTime date;
  final bool isCurrentMonth;
  final VoidCallback onTap;
  final bool hasIncontinence;

  const _CalendarCell({
    required this.date,
    required this.isCurrentMonth,
    required this.onTap,
    required this.hasIncontinence,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Stack(
          children: [
            // 날짜 (왼쪽 위)
            Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  '${date.day}',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: isCurrentMonth
                        ? const Color(0xFF111827)
                        : const Color(0xFF9CA3AF),
                  ),
                ),
              ),
            ),

            // 🔴 실금 발생 뱃지 (중앙)
            if (hasIncontinence)
              Align(
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE4E6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    '실금 발생',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFEF4444),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
