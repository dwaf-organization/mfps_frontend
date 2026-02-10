import 'package:flutter/material.dart';

enum RiskStatus { danger, warning, stable }

RiskStatus riskFromWarningInt(int w) {
  if (w == 2) return RiskStatus.danger;
  if (w == 1) return RiskStatus.warning;
  return RiskStatus.stable; // 0
}

String statusLabel(RiskStatus s) {
  switch (s) {
    case RiskStatus.danger:
      return '위험';
    case RiskStatus.warning:
      return '주의';
    case RiskStatus.stable:
      return '안전';
  }
}

Color statusColor(RiskStatus s) {
  switch (s) {
    case RiskStatus.danger:
      return const Color(0xFFEF4444);
    case RiskStatus.warning:
      return const Color(0xFFF59E0B);
    case RiskStatus.stable:
      return const Color(0xFF22C55E);
  }
}

/// ✅ 명세2(patient-list)에서 내려오는 1명 요약
class FloorPatientItem {
  final int patientCode;
  final String patientName;
  final String patientRoom; // "101호"
  final String patientBed;  // "Bed-1"
  final int patientWarning; // 0/1/2

  const FloorPatientItem({
    required this.patientCode,
    required this.patientName,
    required this.patientRoom,
    required this.patientBed,
    required this.patientWarning,
  });

  RiskStatus get status => riskFromWarningInt(patientWarning);
}

class PatientListCard extends StatelessWidget {
  final FloorPatientItem patient;
  final bool selected;
  final VoidCallback onTap;

  const PatientListCard({
    super.key,
    required this.patient,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final s = patient.status;
    final c = statusColor(s);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE8F2FF) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFFDCFCE7) : const Color(0xFFE5E7EB),
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: c.withOpacity(0.15),
              child: Icon(Icons.person, color: c, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    patient.patientName,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '병실 ${patient.patientRoom} · ${patient.patientBed}',
                    style: const TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: c.withOpacity(0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                statusLabel(s),
                style: TextStyle(color: c, fontWeight: FontWeight.w900, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
