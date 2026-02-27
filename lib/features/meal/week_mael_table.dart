import 'package:flutter/material.dart';
import 'meal_row.dart';
import 'meal_status.dart';

class WeekMealTable extends StatelessWidget {
  final List<String> dates;
  final MealStatus Function(String date, String mealType) getStatus;
  final void Function(String date) onDateTap;

  const WeekMealTable({
    super.key,
    required this.dates,
    required this.getStatus,
    required this.onDateTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _header(),
        MealRow(
          title: '조식',
          statuses: dates.map((d) => getStatus(d, '조식')).toList(),
          onCellTap: (i) => onDateTap(dates[i]),
        ),
        MealRow(
          title: '중식',
          statuses: dates.map((d) => getStatus(d, '중식')).toList(),
          onCellTap: (i) => onDateTap(dates[i]),
        ),
        MealRow(
          title: '석식',
          statuses: dates.map((d) => getStatus(d, '석식')).toList(),
          onCellTap: (i) => onDateTap(dates[i]),
        ),
      ],
    );
  }

  Widget _header() {
    return Row(
      children: [
        SizedBox(width: 80, child: _cell('구분', isHeader: true)),
        ...dates.map((d) => Expanded(child: _cell(d, isHeader: true))),
      ],
    );
  }

  Widget _cell(String text, {bool isHeader = false}) {
    return Container(
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isHeader ? const Color(0xFFF9FAFB) : Colors.white,
        border: const Border(
          right: BorderSide(color: Color(0xFFE5E7EB)),
          bottom: BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }
}
