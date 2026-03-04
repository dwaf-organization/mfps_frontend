import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:mfps/features/dashboard/widgets/patient_care_tabs/incontinence_tab.dart';
import 'package:mfps/features/dashboard/widgets/patient_care_tabs/patient_care_tab_header.dart';
import 'package:mfps/features/dashboard/widgets/patient_care_tabs/pressure_ulcer_info_tab.dart';
import 'package:mfps/features/meal/meal_tab.dart';
import 'package:mfps/url_config.dart';
import 'package:mfps/api/http_helper.dart';

part '../widgets/patient_care_tabs/pressure_ulcer_input_tab.dart';

/// 케어 입력 페이지 (욕창단계입력 / 욕창정보 / 식단 / 실금)
class PatientCarePage extends StatefulWidget {
  final int patientCode;
  final String patientName;
  final String? roomLabel;
  final String? bedLabel;

  const PatientCarePage({
    super.key,
    required this.patientCode,
    required this.patientName,
    this.roomLabel,
    this.bedLabel,
  });

  @override
  State<PatientCarePage> createState() => _PatientCarePageState();
}

class _PatientCarePageState extends State<PatientCarePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFFFF),
        elevation: 0,
        title: Text(
          '${widget.patientName} 케어 입력',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: Color(0xFF111827),
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF374151)),
          onPressed: () => Navigator.pop(context),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Color(0xFFE5E7EB)),
        ),
      ),
      body: Column(
        children: [
          PatientCareTabHeader(tabController: _tabController),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _PressureUlcerInputTab(patientCode: widget.patientCode),
                const PressureUlcerInfoTab(),
                Center(child: MealTab(patientCode: widget.patientCode)),
                IncontinenceTab(patientCode: widget.patientCode),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
