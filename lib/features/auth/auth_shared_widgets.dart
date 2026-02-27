import 'package:flutter/material.dart';

class AuthLeftIntro extends StatelessWidget {
  const AuthLeftIntro({super.key});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            '병동 모니터링 시스템',
            style: TextStyle(fontSize: 44, fontWeight: FontWeight.w900, color: Color(0xFF111827)),
          ),
          SizedBox(height: 16),
          Text(
            '로그인 후 전체 환자 현황 및 건강 상태를 관리합니다.',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF6B7280)),
          ),
        ],
      ),
    );
  }
}

class AuthCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final Widget footer;

  const AuthCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.footer,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: const [
          BoxShadow(color: Color(0x14000000), blurRadius: 20, offset: Offset(0, 10)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Color(0xFF111827)),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF6B7280)),
          ),
          const SizedBox(height: 18),
          child,
          const SizedBox(height: 14),
          Center(child: footer),
        ],
      ),
    );
  }
}
