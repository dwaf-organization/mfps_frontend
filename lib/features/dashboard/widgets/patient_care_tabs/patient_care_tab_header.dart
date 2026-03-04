import 'package:flutter/material.dart';

class PatientCareTabHeader extends StatelessWidget {
  final TabController tabController;

  const PatientCareTabHeader({super.key, required this.tabController});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFFFFFFF),
      child: AnimatedBuilder(
        animation: tabController,
        builder: (context, _) {
          final selected = tabController.index;
          const labels = ['욕창단계입력', '욕창정보', '식단', '실금'];

          return Padding(
            padding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
            child: Row(
              children: List.generate(labels.length, (index) {
                final isActive = selected == index;
                return Padding(
                  padding: EdgeInsets.only(
                    right: index < labels.length - 1 ? 8 : 0,
                  ),
                  child: GestureDetector(
                    onTap: () => tabController.animateTo(index),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0xFF7F9BD8)
                            : const Color(0xFFF3F4F6),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(10),
                          topRight: Radius.circular(10),
                        ),
                        border: Border(
                          top: BorderSide(
                            color: isActive
                                ? const Color(0xFF7F9BD8)
                                : const Color(0xFFE2E8F0),
                          ),
                          left: BorderSide(
                            color: isActive
                                ? const Color(0xFF7F9BD8)
                                : const Color(0xFFE2E8F0),
                          ),
                          right: BorderSide(
                            color: isActive
                                ? const Color(0xFF7F9BD8)
                                : const Color(0xFFE2E8F0),
                          ),
                        ),
                      ),
                      child: Text(
                        labels[index],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: isActive
                              ? Colors.white
                              : const Color(0xFF6B7280),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          );
        },
      ),
    );
  }
}
