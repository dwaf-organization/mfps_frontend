import 'package:flutter/material.dart';
import 'meal_chip.dart';
import 'meal_status.dart';

class MealRow extends StatelessWidget {
  final String title;
  final List<MealStatus> statuses;
  final void Function(int index)? onCellTap;

  const MealRow({
    super.key,
    required this.title,
    required this.statuses,
    this.onCellTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _labelCell(title),
        ...List.generate(statuses.length, (i) {
          return Expanded(
            child: _tappableCell(statuses[i], onTap: () => onCellTap?.call(i)),
          );
        }),
      ],
    );
  }

  Widget _labelCell(String text) {
    return Container(
      width: 80,
      height: 48,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        border: Border(
          right: BorderSide(color: Color(0xFFE5E7EB)),
          bottom: BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
      child: Text(text),
    );
  }

  Widget _tappableCell(MealStatus status, {required VoidCallback onTap}) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            border: Border(
              right: BorderSide(color: Color(0xFFE5E7EB)),
              bottom: BorderSide(color: Color(0xFFE5E7EB)),
            ),
          ),
          child: MealChip(status: status),
        ),
      ),
    );
  }
}
