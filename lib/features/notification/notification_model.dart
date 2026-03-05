class AppNotification {
  final String id;
  final String patientCode;
  final String patientName;
  final int patientAge;
  final String hospitalStructure;
  final int warningState; // 1=주의, 2=위험
  final int durationHours;
  final double? temperature;
  final double? humidity;
  final String lastChangeTime;
  final DateTime createdAt;
  bool isRead;
  bool isConfirmed;

  AppNotification({
    required this.id,
    required this.patientCode,
    required this.patientName,
    required this.patientAge,
    required this.hospitalStructure,
    required this.warningState,
    required this.durationHours,
    required this.temperature,
    required this.humidity,
    required this.lastChangeTime,
    required this.createdAt,
    this.isRead = false,
    this.isConfirmed = false,
  });

  String get warningLabel => warningState == 2 ? '위험' : '주의';
}
