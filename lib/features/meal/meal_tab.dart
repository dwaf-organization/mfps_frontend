import 'package:flutter/material.dart';
import 'week_mael_table.dart';

class MealTab extends StatelessWidget {
  const MealTab({super.key});

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
          children: const [
            WeekMealTable(
              dates: [
                '01/01',
                '01/02',
                '01/03',
                '01/04',
                '01/05',
                '01/06',
                '01/07',
              ],
            ),
            WeekMealTable(
              dates: [
                '01/08',
                '01/09',
                '01/10',
                '01/11',
                '01/12',
                '01/13',
                '01/14',
              ],
            ),
            WeekMealTable(
              dates: [
                '01/15',
                '01/16',
                '01/17',
                '01/18',
                '01/19',
                '01/20',
                '01/21',
              ],
            ),
            WeekMealTable(
              dates: [
                '01/22',
                '01/23',
                '01/24',
                '01/25',
                '01/26',
                '01/27',
                '01/28',
              ],
            ),
          ],
        ),
      ),
    );
  }
}
