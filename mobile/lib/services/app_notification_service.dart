import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';

import '../models/repositories/notification_history_store.dart';
import 'notification_settings.dart';

/// Central local-notification helper. Every alert relevant to a deaf
/// traveller plays a notification sound and deep-links into the matching
/// screen through its [payload] route. Vibration follows the profile's
/// "Vibration Alerts" configuration and every raised notification is kept in
/// the device-local notification history (see NotificationHistoryStore).
class AppNotificationService {
  AppNotificationService._();

  static final instance = AppNotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  void Function(String route)? _onTap;
  String? _launchPayload;
  GoRouter? _router;

  /// The notification channels whose vibration must follow the profile
  /// setting. Android channels are immutable once created, so they are
  /// deleted and recreated whenever the setting changes.
  static const List<(String, String, String)> _channels = [
    ('queue_updates', 'Queue updates', 'Alerts for your tracked queue number'),
    (
      'official_announcements',
      'Official announcements',
      'Official announcements from your connected venue',
    ),
    (
      'captured_announcements',
      'Captured public announcements',
      'Public-address announcements captured from the environment',
    ),
    (
      'important_sounds',
      'Important sound alerts',
      'Visual and vibration alerts for important sounds',
    ),
    (
      'chat_messages',
      'Chat messages',
      'New messages from staff in your assistance chat',
    ),
  ];

  /// Route payload tapped while the app was fully closed, consumed once by
  /// the root widget after the router is ready.
  String? consumeLaunchPayload() {
    final payload = _launchPayload;
    _launchPayload = null;
    return payload;
  }

  Future<void> initialize({
    void Function(String route)? onNotificationTap,
    GoRouter? router,
  }) async {
    if (onNotificationTap != null) _onTap = onNotificationTap;
    if (router != null) _router = router;
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final payload = launchDetails?.notificationResponse?.payload;
    if (payload != null && payload.isNotEmpty) {
      _launchPayload = _routeForPayload(payload);
    }
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
    await _applyChannelVibration();
  }

  /// Stores the notification-related profile configuration and rebuilds the
  /// Android notification channels so their vibration matches it. Called
  /// when the traveller saves their profile preferences.
  Future<void> applyNotificationSettings({
    required bool vibration,
    required String vibrationStrength,
    required bool flash,
  }) async {
    await NotificationSettings.store(
      vibration: vibration,
      vibrationStrength: vibrationStrength,
      flash: flash,
    );
    await _applyChannelVibration();
  }

  Future<void> _applyChannelVibration() async {
    final vibration = await NotificationSettings.vibrationEnabled();
    final applied = await NotificationSettings.channelsVibration();
    if (applied == vibration) return;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      for (final (id, name, description) in _channels) {
        try {
          await android.deleteNotificationChannel(channelId: id);
          await android.createNotificationChannel(
            AndroidNotificationChannel(
              id,
              name,
              description: description,
              importance: Importance.max,
              playSound: true,
              enableVibration: vibration,
            ),
          );
        } catch (_) {
          // Channel setup is best-effort; showing still recreates channels.
        }
      }
    }
    await NotificationSettings.setChannelsVibration(vibration);
  }

  /// Keeps the device-local notification history in step with every raised
  /// notification so the in-app Notifications screen can list and navigate
  /// to it later. Best-effort; never breaks the notification itself.
  Future<void> _recordHistory({
    required String kind,
    required String title,
    required String body,
    required String? route,
  }) async {
    try {
      await NotificationHistoryStore.instance.add(
        NotificationHistoryEntry(
          id: '$kind-${DateTime.now().microsecondsSinceEpoch}',
          kind: kind,
          title: title,
          body: body,
          route: route,
          createdAt: DateTime.now(),
        ),
      );
    } catch (_) {
      // History is best-effort.
    }
  }

  void _handleResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    final route = _routeForPayload(payload);
    if (_onTap != null) {
      _onTap!.call(route);
    } else {
      _router?.push(route);
    }
  }

  String _routeForPayload(String payload) {
    if (!payload.startsWith('chat:')) return payload;
    final requestId = Uri.encodeQueryComponent(
      payload.replaceFirst('chat:', ''),
    );
    return '/chat?requestId=$requestId';
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
  }) async {
    final route = '/chat?requestId=${Uri.encodeQueryComponent(requestId)}';
    await _recordHistory(
      kind: 'request',
      title: '💬 $senderName',
      body: message,
      route: route,
    );
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
  }) async {
    await _recordHistory(
      kind: 'queue',
      title: 'Queue $number is being called',
      body: 'Please proceed to $counter.',
      route: '/queue',
    );
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
  }) async {
    await _recordHistory(
      kind: 'queue',
      title: 'Queue $number is coming up',
      body: 'Your number is about $minutes min away. Please stay nearby.',
      route: '/queue',
    );
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
  }) async {
    final route = '/announcement-details?id=$id';
    await _recordHistory(
      kind: 'announcement',
      title: title,
      body: message,
      route: route,
    );
    return _plugin.show(
      id: 'ann:$id'.hashCode & 0x7fffffff,
      title: title,
      body: message,
      payload: route,
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
  }) async {
    final route = '/announcement-details?id=$id';
    await _recordHistory(
      kind: 'captured',
      title: title,
      body: message,
      route: route,
    );
    return _plugin.show(
      id: 'cap:$id'.hashCode & 0x7fffffff,
      title: 'Captured announcement ($confidencePercent% confidence)',
      body: message,
      payload: route,
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
  }) async {
    await _recordHistory(
      kind: 'sound',
      title: title,
      body: details,
      route: null,
    );
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
