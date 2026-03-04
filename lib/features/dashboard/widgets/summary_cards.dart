import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'package:mfps/url_config.dart';
import 'package:mfps/storage_keys.dart';

class SummaryCards extends StatefulWidget {
  /// 대시보드에서 선택된 층 hospital_st_code
  /// (없으면 스토리지에서 selectedFloorStCode 읽어서 시도)
  final int? floorStCode;

  const SummaryCards({
    super.key,
    required this.floorStCode,
  });

  @override
  State<SummaryCards> createState() => _SummaryCardsState();
}

class _SummaryCardsState extends State<SummaryCards> {
  static const _storage = FlutterSecureStorage();
  late final String _frontUrl;

  bool _loading = false;

  int total = 0;
  int danger = 0;
  int warning = 0;
  int stable = 0;

  @override
  void initState() {
    super.initState();
    _frontUrl = UrlConfig.serverUrl.toString();
    loadData();
  }

  @override
  void didUpdateWidget(covariant SummaryCards oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 층이 바뀌면 다시 조회
    if (oldWidget.floorStCode != widget.floorStCode) {
      loadData();
    }
  }

  Future<void> loadData() async {
    setState(() => _loading = true);
    await getData();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> getData() async {
    // 1) floorStCode 결정(부모값 우선, 없으면 스토리지 fallback)
    int? floorStCode = widget.floorStCode;
    if (floorStCode == null) {
      final saved = await _storage.read(key: StorageKeys.selectedFloorStCode);
      floorStCode = int.tryParse((saved ?? '').trim());
    }

    // 층 코드 없으면 0으로 유지
    if (floorStCode == null) {
      total = danger = warning = stable = 0;
      return;
    }

    try {
      final uri = Uri.parse('$_frontUrl/api/hospital/structure/patient-list?hospital_st_code=$floorStCode');
      final res = await http.get(uri, headers: {'Content-Type': 'application/json'});

      if (res.statusCode < 200 || res.statusCode >= 300) {
        total = danger = warning = stable = 0;
        return;
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        total = danger = warning = stable = 0;
        return;
      }

      if (decoded['code'] != 1) {
        total = danger = warning = stable = 0;
        return;
      }

      final data = decoded['data'];
      if (data is! Map<String, dynamic>) {
        total = danger = warning = stable = 0;
        return;
      }

      final patients = (data['patients'] as List?) ?? const [];
      int t = 0, d = 0, w = 0, s = 0;

      for (final p in patients) {
        if (p is! Map) continue;
        final warn = int.tryParse(p['patient_warning']?.toString() ?? '') ?? 0;

        t += 1;
        if (warn == 2) d += 1;
        else if (warn == 1) w += 1;
        else s += 1; // 0
      }

      total = t;
      danger = d;
      warning = w;
      stable = s;
    } catch (_) {
      total = danger = warning = stable = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    // UI는 그대로, 값만 API 결과로 바뀜
    return Row(
      children: [
        Expanded(
          child: _Card(
            title: _loading ? '총 환자 수 (로딩중)' : '총 환자 수',
            value: '${total}명',
            valueColor: const Color(0xFF111827),
          ),
        ),
        const SizedBox(width: 25),
        Expanded(child: _Card(title: '위험 상태', value: '${danger}명', valueColor: const Color(0xFFEF4444))),
        const SizedBox(width: 25),
        Expanded(child: _Card(title: '주의 필요', value: '${warning}명', valueColor: const Color(0xFFF59E0B))),
        const SizedBox(width: 25),
        Expanded(child: _Card(title: '안정 상태', value: '${stable}명', valueColor: const Color(0xFF22C55E))),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  final String title;
  final String value;
  final Color valueColor;

  const _Card({
    required this.title,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 120,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text(value, style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: valueColor)),
        ],
      ),
    );
  }
}
