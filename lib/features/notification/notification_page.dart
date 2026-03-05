import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:mfps/url_config.dart';

import 'notification_model.dart';
import 'notification_store.dart';

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF111827)),
          onPressed: () => context.pop(),
        ),
        title: const Text(
          '알림',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF111827)),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Color(0xFFE5E7EB)),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListenableBuilder(
        listenable: NotificationStore.instance,
        builder: (context, _) {
          final notifications = NotificationStore.instance.notifications;

          if (notifications.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.notifications_none, size: 64, color: Color(0xFFD1D5DB)),
                  SizedBox(height: 16),
                  Text(
                    '새로운 알림이 없습니다',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF9CA3AF)),
                  ),
                ],
              ),
            );
          }

          // 미확인 알림만 위험/주의 섹션에 표시
          final dangerList = notifications.where((n) => n.warningState == 2 && !n.isConfirmed).toList();
          final warningList = notifications.where((n) => n.warningState == 1 && !n.isConfirmed).toList();
          // 확인된 알림은 맨 아래에 표시
          final confirmedList = notifications.where((n) => n.isConfirmed).toList();

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (dangerList.isNotEmpty) ...[
                _SectionHeader(label: '위험 알림', count: dangerList.length, color: const Color(0xFFEF4444)),
                const SizedBox(height: 12),
                ...dangerList.map((n) => _NotificationCard(key: ValueKey(n.id), notification: n)),
                const SizedBox(height: 24),
              ],
              if (warningList.isNotEmpty) ...[
                _SectionHeader(label: '주의 알림', count: warningList.length, color: const Color(0xFFF59E0B)),
                const SizedBox(height: 12),
                ...warningList.map((n) => _NotificationCard(key: ValueKey(n.id), notification: n)),
                const SizedBox(height: 24),
              ],
              if (confirmedList.isNotEmpty) ...[
                const _SectionHeader(label: '안전확인 완료', count: null, color: Color(0xFF22C55E)),
                const SizedBox(height: 12),
                ...confirmedList.map((n) => _NotificationCard(key: ValueKey(n.id), notification: n)),
              ],
            ],
          );
        },
      ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String label;
  final int? count;
  final Color color;

  const _SectionHeader({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF111827))),
        if (count != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(999)),
            child: Text('$count', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12)),
          ),
        ],
      ],
    );
  }
}

class _NotificationCard extends StatefulWidget {
  final AppNotification notification;
  const _NotificationCard({super.key, required this.notification});

  @override
  State<_NotificationCard> createState() => _NotificationCardState();
}

class _NotificationCardState extends State<_NotificationCard> {
  bool _loading = false;

  Future<void> _confirmPatient() async {
    setState(() => _loading = true);
    try {
      final uri = Uri.parse('${UrlConfig.serverUrl}/api/patient/warning/safety-confirm');
      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'patient_code': widget.notification.patientCode}),
      );
      if (!mounted) return;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        NotificationStore.instance.confirmNotification(widget.notification.id);
        // 모든 알림이 확인 완료되면 읽음 처리 (벨 아이콘 dot 제거)
        final all = NotificationStore.instance.notifications;
        if (all.isNotEmpty && all.every((n) => n.isConfirmed)) {
          NotificationStore.instance.markAllRead();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('확인 처리에 실패했습니다.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('네트워크 오류가 발생했습니다.')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatTime(String lastChangeTime) {
    try {
      final dt = DateTime.parse(lastChangeTime.replaceAll(' ', 'T'));
      return '${dt.year.toString().substring(2)}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return lastChangeTime;
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.notification;
    final isDanger = n.warningState == 2;
    final badgeColor = isDanger ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);
    const grayColor = Color(0xFFD1D5DB);

    String durationText;
    if (n.durationHours == 0) {
      durationText = '${n.warningLabel} 상태 발생';
    } else {
      durationText = '${n.warningLabel} 상태 ${n.durationHours}시간 지속';
    }

    String? sensorText;
    if (n.temperature != null || n.humidity != null) {
      final parts = <String>[];
      if (n.temperature != null) parts.add('현재 체온 ${n.temperature}°C');
      if (n.humidity != null) parts.add('현재 습도 ${n.humidity}%');
      sensorText = parts.join(' / ');
    }

    final textColor = n.isConfirmed ? grayColor : null;
    final activeBadgeColor = n.isConfirmed ? grayColor : badgeColor;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: activeBadgeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: activeBadgeColor.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        n.warningLabel,
                        style: TextStyle(color: activeBadgeColor, fontSize: 11, fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(n.patientName, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: textColor)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _formatTime(n.lastChangeTime),
                        style: TextStyle(color: textColor ?? const Color(0xFF9CA3AF), fontSize: 12, fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  n.hospitalStructure,
                  style: TextStyle(color: textColor ?? const Color(0xFF6B7280), fontSize: 12, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  durationText,
                  style: TextStyle(
                    color: activeBadgeColor,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                if (sensorText != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    sensorText,
                    style: TextStyle(color: textColor ?? const Color(0xFF6B7280), fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (n.isConfirmed)
            const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Color(0xFF22C55E), size: 18),
                SizedBox(width: 4),
                Text('안전확인 완료', style: TextStyle(color: Color(0xFF22C55E), fontWeight: FontWeight.w700, fontSize: 13)),
              ],
            )
          else
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B82F6),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
              ),
              onPressed: _loading ? null : _confirmPatient,
              child: _loading
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('안전 확인'),
            ),
        ],
      ),
    );
  }
}
