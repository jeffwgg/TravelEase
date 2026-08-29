import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';

class AppNotificationService {
  AppNotificationService._();

  static final instance = AppNotificationService._();
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  GoRouter? _router;

  Future<void> initialize({GoRouter? router}) async {
    _router = router;

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
  }

  /// Called when the user taps a notification (foreground or background).
  void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.startsWith('chat:') && _router != null) {
      final requestId = payload.replaceFirst('chat:', '');
      _router!.push('/chat?requestId=$requestId');
    }
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

  /// Show a notification for a new incoming staff chat message.
  /// Payload encodes `chat:<requestId>` so tapping navigates to the right chat.
  Future<void> showChatMessage({
    required String requestId,
    required String senderName,
    required String message,
  }) {
    return _plugin.show(
      id: requestId.hashCode & 0x7fffffff,
      title: '💬 $senderName',
      body: message,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'chat_messages',
          'Chat Messages',
          channelDescription: 'New messages from staff in your assistance chat',
          importance: Importance.high,
          priority: Priority.high,
          enableVibration: true,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: 'chat:$requestId',
    );
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
