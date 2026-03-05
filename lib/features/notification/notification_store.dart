import 'package:flutter/foundation.dart';
import 'notification_model.dart';

class NotificationStore extends ChangeNotifier {
  static final NotificationStore instance = NotificationStore._();
  NotificationStore._();

  final List<AppNotification> _notifications = [];

  List<AppNotification> get notifications => List.unmodifiable(_notifications);

  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  void addAll(List<AppNotification> items) {
    _notifications.insertAll(0, items);
    if (_notifications.length > 100) {
      _notifications.removeRange(100, _notifications.length);
    }
    notifyListeners();
  }

  void markAllRead() {
    for (final n in _notifications) {
      n.isRead = true;
    }
    notifyListeners();
  }

  void confirmNotification(String id) {
    final target = _notifications.where((n) => n.id == id).firstOrNull;
    if (target == null) return;
    // 같은 환자의 모든 알림을 함께 확인 처리
    for (final n in _notifications) {
      if (n.patientCode == target.patientCode) {
        n.isConfirmed = true;
      }
    }
    notifyListeners();
  }

  void clear() {
    _notifications.clear();
    notifyListeners();
  }
}
