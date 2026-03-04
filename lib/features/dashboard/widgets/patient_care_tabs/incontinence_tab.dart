import 'package:flutter/material.dart';
import 'package:mfps/features/calender/widget/month_calendar.dart';

class IncontinenceTab extends StatelessWidget {
  final int patientCode;
  const IncontinenceTab({super.key, required this.patientCode});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: MonthCalendar(patientCode: patientCode),
    );
  }
}
