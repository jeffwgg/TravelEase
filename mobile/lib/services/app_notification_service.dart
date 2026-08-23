import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class AppNotificationService {
  AppNotificationService._();

  static final instance = AppNotificationService._();
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  Future<void> initialize() async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
  }

  Future<void> requestPermission() async {
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  Future<void> showQueueCalled({
    required String number,
    required String counter,
  }) {
    return _plugin.show(
      id: number.hashCode & 0x7fffffff,
      title: 'Queue $number is being called',
      body: 'Please proceed to $counter.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'queue_calls',
          'Queue calls',
          channelDescription: 'Alerts when a tracked queue number is called',
          importance: Importance.max,
          priority: Priority.high,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
    );
  }

  Future<void> showImportantSound({
    required String title,
    required String details,
  }) {
    return _plugin.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(0x7fffffff),
      title: title,
      body: details,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'important_sounds',
          'Important sound alerts',
          channelDescription:
              'Visual and vibration alerts for important sounds',
          importance: Importance.max,
          priority: Priority.high,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
    );
  }
}
