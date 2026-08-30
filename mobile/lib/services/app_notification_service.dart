import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Central local-notification helper. Every alert relevant to a deaf
/// traveller plays a notification sound and can deep-link into the matching
/// screen through its [payload] route. Notification behaviour (sound, flash)
/// is hardcoded enabled for now; a settings section will come later.
class AppNotificationService {
  AppNotificationService._();

  static final instance = AppNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  void Function(String route)? _onTap;
  String? _launchPayload;

  /// Route payload tapped while the app was fully closed, consumed once by
  /// the root widget after the router is ready.
  String? consumeLaunchPayload() {
    final payload = _launchPayload;
    _launchPayload = null;
    return payload;
  }

  Future<void> initialize({
    void Function(String route)? onNotificationTap,
  }) async {
    _onTap = onNotificationTap;
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    _launchPayload =
        launchDetails?.notificationResponse?.payload;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: _handleResponse,
    );
  }

  void _handleResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    _onTap?.call(payload);
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
      payload: '/queue',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'queue_calls',
          'Queue calls',
          channelDescription: 'Alerts when a tracked queue number is called',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          enableLights: true,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
    );
  }

  /// One-time "get ready" alert when the traveller's estimated queue wait
  /// drops under ten minutes.
  Future<void> showQueueAlmostUp({
    required String number,
    required int minutes,
  }) {
    return _plugin.show(
      id: 'wait:$number'.hashCode & 0x7fffffff,
      title: 'Queue $number is coming up',
      body: 'Your number is about $minutes min away. Please stay nearby.',
      payload: '/queue',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'queue_calls',
          'Queue calls',
          channelDescription: 'Alerts when a tracked queue number is called',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          enableLights: true,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
    );
  }

  Future<void> showOfficialAnnouncement({
    required String id,
    required String title,
    required String message,
  }) {
    return _plugin.show(
      id: 'ann:$id'.hashCode & 0x7fffffff,
      title: title,
      body: message,
      payload: '/announcement-details?id=$id',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'official_announcements',
          'Official announcements',
          channelDescription:
              'Official announcements from your connected venue',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          enableLights: true,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
    );
  }

  Future<void> showCapturedAnnouncement({
    required String id,
    required String title,
    required String message,
    required int confidencePercent,
  }) {
    return _plugin.show(
      id: 'cap:$id'.hashCode & 0x7fffffff,
      title: 'Captured announcement ($confidencePercent% confidence)',
      body: message,
      payload: '/announcement-details?id=$id',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'captured_announcements',
          'Captured public announcements',
          channelDescription:
              'Public-address announcements captured from the environment',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          enableLights: true,
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
          playSound: true,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
    );
  }
}
