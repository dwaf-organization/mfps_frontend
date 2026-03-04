import 'package:flutter/material.dart';
import 'package:mfps/features/calender/widget/month_calendar.dart';

class IncontinenceTab extends StatelessWidget {
  const IncontinenceTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: MonthCalendar(),
    );
  }
}
