import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../risk_poller.dart';

class DangerAlertDialog extends StatelessWidget {
  final List<RiskPatient> patients;

  const DangerAlertDialog({super.key, required this.patients});

  @override
  Widget build(BuildContext context) {
    final dangerCount = patients.where((p) => p.warningState == 2).length;
    final warningCount = patients.where((p) => p.warningState == 1).length;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 360,
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '체위 변경 시간 초과 알림',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF111827)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (dangerCount > 0)
              _CountRow(
                label: '위험 환자',
                count: dangerCount,
                color: const Color(0xFFEF4444),
              ),
            if (dangerCount > 0 && warningCount > 0) const SizedBox(height: 6),
            if (warningCount > 0)
              _CountRow(
                label: '주의 환자',
                count: warningCount,
                color: const Color(0xFFF59E0B),
              ),
            const SizedBox(height: 16),
            const Text(
              '환자 확인 필요',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF3B82F6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                  textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  context.push('/notification');
                },
                child: const Text('확인'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountRow extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _CountRow({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          '$label ',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
        ),
        Text(
          '$count명',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: color),
        ),
        const Text(
          ' 발생',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF111827)),
        ),
      ],
    );
  }
}
