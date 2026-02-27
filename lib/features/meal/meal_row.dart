import 'package:flutter/material.dart';
import 'meal_chip.dart';
import 'meal_status.dart';

class MealRow extends StatelessWidget {
  final String title;
  final List<MealStatus> statuses;

  const MealRow({super.key, required this.title, required this.statuses});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _cell(title, width: 80),
        ...statuses.map((s) => Expanded(child: _cell(MealChip(status: s)))),
      ],
    );
  }

  Widget _cell(dynamic child, {double? width}) {
    return Container(
      width: width,
      height: 48,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        border: Border(
          right: BorderSide(color: Color(0xFFE5E7EB)),
          bottom: BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
      child: child is Widget ? child : Text(child),
    );
  }
}
