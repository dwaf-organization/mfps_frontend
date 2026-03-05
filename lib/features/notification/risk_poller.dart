import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'notification_model.dart';
import 'notification_store.dart';

class RiskPatient {
  final String patientCode;
  final String patientName;
  final int patientAge;
  final String hospitalStructure;
  final int warningState;
  final int durationHours;
  final double? temperature;
  final double? humidity;
  final String lastChangeTime;

  const RiskPatient({
    required this.patientCode,
    required this.patientName,
    required this.patientAge,
    required this.hospitalStructure,
    required this.warningState,
    required this.durationHours,
    required this.temperature,
    required this.humidity,
    required this.lastChangeTime,
  });

  factory RiskPatient.fromJson(Map<String, dynamic> json) {
    return RiskPatient(
      patientCode: json['patient_code']?.toString() ?? '',
      patientName: json['patient_name']?.toString() ?? '',
      patientAge: int.tryParse(json['patient_age']?.toString() ?? '') ?? 0,
      hospitalStructure: json['hospital_structure']?.toString() ?? '',
      warningState: int.tryParse(json['warning_state']?.toString() ?? '') ?? 1,
      durationHours:
          int.tryParse(json['duration_hours']?.toString() ?? '') ?? 0,
      temperature: double.tryParse(json['temperature']?.toString() ?? ''),
      humidity: double.tryParse(json['humidity']?.toString() ?? ''),
      lastChangeTime: json['last_change_time']?.toString() ?? '',
    );
  }
}

class RiskPoller {
  static final RiskPoller instance = RiskPoller._();
  RiskPoller._();

  Timer? _timer;
  final _controller = StreamController<List<RiskPatient>>.broadcast();

  Stream<List<RiskPatient>> get stream => _controller.stream;

  void start(String baseUrl) {
    _timer?.cancel();
    debugPrint(
      '[RISK_POLLER] 폴링 시작 → $baseUrl/api/patient/warning/risk-list (1분 간격)',
    );
    _poll(baseUrl);
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => _poll(baseUrl));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll(String baseUrl) async {
    try {
      final uri = Uri.parse('$baseUrl/api/patient/warning/risk-list');
      debugPrint('[RISK_POLLER] ▶ 요청: GET $uri');
      final res = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      );

      debugPrint('[RISK_POLLER] ◀ 응답: status=${res.statusCode}');
      debugPrint('[RISK_POLLER] body=${res.body}');

      if (res.statusCode < 200 || res.statusCode >= 300) return;

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) return;
      if (decoded['code'] != 1) {
        debugPrint('[RISK_POLLER] code != 1, 무시');
        return;
      }

      final data = decoded['data'];
      if (data is! List || data.isEmpty) {
        debugPrint('[RISK_POLLER] 위험 환자 없음 (data 비어있음)');
        return;
      }

      final patients = data
          .whereType<Map<String, dynamic>>()
          .map((p) => RiskPatient.fromJson(p))
          .toList();

      debugPrint('[RISK_POLLER] 위험 환자 ${patients.length}명 감지 → 알림 추가');

      final now = DateTime.now();
      final notifications = patients
          .map(
            (p) => AppNotification(
              id: '${p.patientCode}_${now.millisecondsSinceEpoch}',
              patientCode: p.patientCode,
              patientName: p.patientName,
              patientAge: p.patientAge,
              hospitalStructure: p.hospitalStructure,
              warningState: p.warningState,
              durationHours: p.durationHours,
              temperature: p.temperature,
              humidity: p.humidity,
              lastChangeTime: p.lastChangeTime,
              createdAt: now,
            ),
          )
          .toList();

      NotificationStore.instance.addAll(notifications);

      if (!_controller.isClosed) {
        _controller.add(patients);
      }
    } catch (e) {
      debugPrint('[RISK_POLLER] error=$e');
    }
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
