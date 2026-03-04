import 'package:flutter/material.dart';
import 'package:mfps/api/http_helper.dart';
import 'package:mfps/url_config.dart';
import 'incontinence_bottom_sheet.dart';

class MonthCalendar extends StatefulWidget {
  final int patientCode;
  const MonthCalendar({super.key, required this.patientCode});

  @override
  State<MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends State<MonthCalendar> {
  DateTime _focusedMonth = DateTime.now();
  late DateTime _selectedDate = _normalize(DateTime.now());

  final Map<DateTime, bool> _incontinenceMap = {};

  DateTime _normalize(DateTime d) {
    return DateTime(d.year, d.month, d.day);
  }

  @override
  void initState() {
    super.initState();
    _fetchIncontinenceData(_focusedMonth);
  }

  Future<void> _fetchIncontinenceData(DateTime month) async {
    final monthStr =
        '${month.year}${month.month.toString().padLeft(2, '0')}';
    try {
      final uri = Uri.parse(
        '${UrlConfig.serverUrl}/api/patient/incontinence/calendar'
        '?patient_code=${widget.patientCode}&month=$monthStr',
      );
      final res = await HttpHelper.getJson(uri);
      if (res['code'] != 1) return;
      final data = res['data'] as Map<String, dynamic>?;
      if (data == null) return;

      final dates = (data['incontinence_dates'] as List<dynamic>? ?? [])
          .map((e) {
            final parts = (e as String).split('-');
            if (parts.length < 3) return null;
            return DateTime(
              int.parse(parts[0]),
              int.parse(parts[1]),
              int.parse(parts[2]),
            );
          })
          .whereType<DateTime>()
          .toSet();

      if (!mounted) return;
      setState(() {
        _incontinenceMap.removeWhere(
          (d, _) => d.year == month.year && d.month == month.month,
        );
        for (final d in dates) {
          _incontinenceMap[d] = true;
        }
      });
    } catch (e) {
      debugPrint('[INCONTINENCE_FETCH] error: $e');
    }
  }

  void _onDateTap(DateTime date) async {
    final normalized = _normalize(date);

    final result = await showModalBottomSheet<bool>(
      constraints: const BoxConstraints(maxWidth: 800),
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        return IncontinenceBottomSheet(
          date: normalized,
          initialValue: _incontinenceMap[normalized] ?? false,
        );
      },
    );

    if (result != null) {
      await _saveIncontinenceData(normalized, result);
    }
  }

  Future<void> _saveIncontinenceData(DateTime date, bool hasIncontinence) async {
    final recordDate =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    try {
      final uri = Uri.parse('${UrlConfig.serverUrl}/api/patient/incontinence');
      await HttpHelper.postJson(uri, {
        'patient_code': widget.patientCode,
        'record_date': recordDate,
        'has_incontinence': hasIncontinence,
        'notes': null,
      });
    } catch (e) {
      debugPrint('[INCONTINENCE_SAVE] error: $e');
    }
    // 저장 성공 여부와 관계없이 해당 월 최신 데이터 반영
    await _fetchIncontinenceData(_focusedMonth);
  }

  // 이전 달
  void _prevMonth() {
    final prev = DateTime(_focusedMonth.year, _focusedMonth.month - 1);
    setState(() => _focusedMonth = prev);
    _fetchIncontinenceData(prev);
  }

  // 다음 달
  void _nextMonth() {
    final next = DateTime(_focusedMonth.year, _focusedMonth.month + 1);
    setState(() => _focusedMonth = next);
    _fetchIncontinenceData(next);
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

            final today = _normalize(DateTime.now());
            final isSelected = normalized == _selectedDate;

            return _CalendarCell(
              date: date,
              isCurrentMonth: date.month == _focusedMonth.month,
              isToday: normalized == today,
              isSelected: isSelected,
              hasIncontinence: _incontinenceMap[normalized] == true,
              onTap: () {
                setState(() => _selectedDate = normalized);
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
  final bool isToday;
  final bool isSelected;
  final VoidCallback onTap;
  final bool hasIncontinence;

  const _CalendarCell({
    required this.date,
    required this.isCurrentMonth,
    required this.isToday,
    required this.isSelected,
    required this.onTap,
    required this.hasIncontinence,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFEFF6FF) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF3B82F6)
                : const Color(0xFFE5E7EB),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Stack(
          children: [
            // 날짜 (왼쪽 위)
            Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: isSelected
                      ? BoxDecoration(
                          color: const Color(0xFF3B82F6),
                          borderRadius: BorderRadius.circular(12),
                        )
                      : isToday
                      ? BoxDecoration(
                          color: const Color(0xFF6DC16A),
                          borderRadius: BorderRadius.circular(12),
                        )
                      : null,
                  child: Text(
                    '${date.day}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: (isSelected || isToday)
                          ? Colors.white
                          : isCurrentMonth
                          ? const Color(0xFF111827)
                          : const Color(0xFF9CA3AF),
                    ),
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
