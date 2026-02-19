import 'package:flutter/material.dart';
import 'patient_list_card.dart'; // RiskStatus / statusColor / riskFromWarningInt 재사용

/// ✅ /api/hospital/structure (beds[].patient) 에 맞춘 침대의 환자 요약
class BedPatientItem {
  final int patientCode;
  final String patientName;
  final int patientAge;
  final int patientWarning; // 0/1/2

  const BedPatientItem({
    required this.patientCode,
    required this.patientName,
    required this.patientAge,
    required this.patientWarning,
  });

  RiskStatus get status => riskFromWarningInt(patientWarning);
}

class BedTile extends StatelessWidget {
  final int bedNo;
  final BedPatientItem? patient;

  /// 빈 침대 탭
  final VoidCallback? onTap;

  /// 환자 정보 버튼 탭
  final VoidCallback? onInfoTap;

  /// 케어입력 버튼 탭
  final VoidCallback? onCareTap;

  const BedTile({
    super.key,
    required this.bedNo,
    required this.patient,
    this.onTap,
    this.onInfoTap,
    this.onCareTap,
  });

  @override
  Widget build(BuildContext context) {
    final has = patient != null;

    final RiskStatus? status = has ? patient!.status : null;
    final Color border = has ? statusColor(status!) : const Color(0xFFD1D5DB);
    final Color bg = has
        ? statusColor(status!).withOpacity(0.06)
        : Colors.white;
    final bool showDangerBadge = has && status == RiskStatus.danger;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isCompact = constraints.maxHeight < 100;

        final pad = isCompact ? 8.0 : 12.0;
        final iconSize = isCompact ? 28.0 : 34.0;

        final bedTextStyle = TextStyle(
          color: const Color(0xFF6B7280),
          fontWeight: FontWeight.w800,
          fontSize: isCompact ? 12 : 13,
        );

        final nameStyle = TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: isCompact ? 13 : 14,
          height: 1.1,
        );

        final ageStyle = TextStyle(
          color: const Color(0xFF6B7280),
          fontWeight: FontWeight.w700,
          fontSize: isCompact ? 11 : 12,
          height: 1.1,
        );

        return InkWell(
          onTap: has ? null : onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: EdgeInsets.all(pad),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border, width: 1.6),
            ),
            child: Stack(
              children: [
                if (showDangerBadge)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isCompact ? 4 : 4,
                        vertical: isCompact ? 4 : 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: isCompact ? 12 : 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '위험',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: isCompact ? 11 : 12,
                              height: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                Column(
                  children: [
                    // const Spacer(),
                    Icon(
                      Icons.bed_outlined,
                      size: iconSize,
                      color: const Color(0xFF6B7280),
                    ),
                    SizedBox(height: isCompact ? 6 : 8),

                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text('침대 $bedNo', style: bedTextStyle),
                    ),

                    SizedBox(height: isCompact ? 6 : 8),

                    if (has) ...[
                      Icon(
                        Icons.person_outline,
                        size: isCompact ? 14 : 16,
                        color: const Color(0xFF6B7280),
                      ),
                      SizedBox(height: isCompact ? 4 : 6),

                      SizedBox(
                        width: double.infinity,
                        child: Text(
                          patient!.patientName,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: nameStyle,
                        ),
                      ),

                      SizedBox(height: isCompact ? 2 : 4),

                      Text(
                        '${patient!.patientAge}세',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ageStyle,
                        textAlign: TextAlign.center,
                      ),

                      SizedBox(height: isCompact ? 6 : 10),

                      // ✅ 정보 / 케어입력 버튼
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: isCompact ? 28 : 32,
                              child: OutlinedButton.icon(
                                onPressed: onInfoTap,
                                icon: Icon(
                                  Icons.info_outline,
                                  size: isCompact ? 12 : 14,
                                ),
                                label: Text(
                                  '정보',
                                  style: TextStyle(
                                    fontSize: isCompact ? 10 : 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF3B82F6),
                                  side: const BorderSide(
                                    color: Color(0xFF3B82F6),
                                  ),
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: SizedBox(
                              height: isCompact ? 28 : 32,
                              child: OutlinedButton.icon(
                                onPressed: onCareTap,
                                icon: Icon(
                                  Icons.medical_services_outlined,
                                  size: isCompact ? 12 : 14,
                                ),
                                label: Text(
                                  '케어',
                                  style: TextStyle(
                                    fontSize: isCompact ? 10 : 11,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF7C3AED),
                                  side: const BorderSide(
                                    color: Color(0xFF7C3AED),
                                  ),
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      SizedBox(height: isCompact ? 10 : 18),
                      const Text(
                        '비어있음',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontWeight: FontWeight.w800,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],

                    // const Spacer(),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
