import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notifications with sound. Android channels are immutable once created,
/// so sound on / sound off use separate channel ids.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool sound = true;
  bool _ready = false;
  int _next = 1;

  Future<void> init() async {
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      );
      await _plugin.initialize(settings);
      _ready = true;
    } catch (e) {
      debugPrint('Notification init failed: $e');
    }
  }

  Future<void> requestPermission() async {
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    } catch (_) {}
  }

  Future<void> show(String title, String body, {bool alert = false}) async {
    if (!_ready) return;
    final kind = alert ? 'alerts' : 'payments';
    final channelId = '${kind}_${sound ? 'sound' : 'silent'}';
    final channelName = alert ? 'Duplicate & fraud alerts' : 'Payments & sync';
    final android = AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: 'Mela $kind',
      importance: Importance.max,
      priority: Priority.high,
      playSound: sound,
      enableVibration: true,
      styleInformation: BigTextStyleInformation(body),
    );
    final ios = DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: sound);
    try {
      await _plugin.show(_next++, title, body, NotificationDetails(android: android, iOS: ios));
    } catch (e) {
      debugPrint('Notification failed: $e');
    }
  }
}
