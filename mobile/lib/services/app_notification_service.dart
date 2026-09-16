import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';

import '../models/repositories/notification_repository.dart';
import 'notification_settings.dart';

/// Central local-notification helper. Every alert relevant to a deaf
/// traveller deep-links into the matching screen through its [payload]
/// route. Behaviour follows the profile configuration: the master
/// "Enable Notifications" switch suppresses the push entirely (the
/// device-local notification history is still updated), vibration follows
/// "Vibration Alerts", and the torch flash follows "Flash Alerts".
///
/// Payloads are encoded as `entryId|route` so taps and the "Mark as read"
/// action can mark the matching history entry as read. Android channel ids
/// carry a generation suffix because the OS keeps the settings of deleted
/// channel ids — recreating the same id never applies new settings.
class AppNotificationService {
  AppNotificationService._();

  static final instance = AppNotificationService._();

  static const _markReadActionId = 'travelease_mark_read';
  static const _markReadAction = AndroidNotificationAction(
    _markReadActionId,
    'Mark as read',
    cancelNotification: true,
    semanticAction: SemanticAction.markAsRead,
  );

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  void Function(String route)? _onTap;
  String? _launchPayload;
  GoRouter? _router;
  String? _channelSuffix;

  /// The notification channels whose vibration must follow the profile
  /// setting. The current generation suffix is appended to each base id.
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

  String _channelId(String baseId) {
    final suffix = _channelSuffix;
    return suffix == null || suffix.isEmpty ? baseId : '${baseId}_$suffix';
  }

  /// Route payload tapped while the app was fully closed, consumed once by
  /// the root widget after the router is ready. Marks the history entry as
  /// read — opening a notification counts as reading it.
  String? consumeLaunchPayload() {
    final payload = _launchPayload;
    _launchPayload = null;
    if (payload == null) return null;
    final separator = payload.indexOf('|');
    if (separator > 0) {
      NotificationHistoryStore.instance
          .markRead(payload.substring(0, separator))
          .catchError((Object _) {});
      return _routeForPayload(payload.substring(separator + 1));
    }
    return _routeForPayload(payload);
  }

  Future<void> initialize({
    void Function(String route)? onNotificationTap,
    GoRouter? router,
  }) async {
    if (onNotificationTap != null) _onTap = onNotificationTap;
    if (router != null) _router = router;
    final generation = await NotificationSettings.channelsGeneration();
    _channelSuffix = generation == 0 ? '' : '$generation';
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    final payload = launchDetails?.notificationResponse?.payload;
    if (payload != null && payload.isNotEmpty) {
      _launchPayload = payload;
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
      onDidReceiveBackgroundNotificationResponse: notificationBackgroundHandler,
    );
    await _ensureChannels();
  }

  /// Stores the notification-related profile configuration and bumps the
  /// channel generation so the Android channels apply the new vibration
  /// settings (same-id recreation is ignored by Android). Called when the
  /// traveller saves their profile preferences.
  Future<void> applyNotificationSettings({
    required bool alertPush,
    required bool alertVibration,
    required bool alertFlash,
    required bool generalPush,
    required bool generalVibration,
    required bool generalFlash,
  }) async {
    await NotificationSettings.store(
      alertPush: alertPush,
      alertVibration: alertVibration,
      alertFlash: alertFlash,
      generalPush: generalPush,
      generalVibration: generalVibration,
      generalFlash: generalFlash,
    );
    final generation = await NotificationSettings.channelsGeneration();
    final oldSuffix = generation == 0 ? '' : '$generation';
    final newGeneration = generation + 1;
    _channelSuffix = '$newGeneration';
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      for (final (baseId, name, description) in _channels) {
        try {
          await android.createNotificationChannel(
            AndroidNotificationChannel(
              _channelId(baseId),
              name,
              description: description,
              importance: Importance.max,
              playSound: true,
              enableVibration: await _channelVibration(baseId),
            ),
          );
          if (oldSuffix.isNotEmpty) {
            await android.deleteNotificationChannel(
              channelId: '${baseId}_$oldSuffix',
            );
          }
        } catch (_) {
          // Channel setup is best-effort; showing still recreates channels.
        }
      }
    }
    await NotificationSettings.setChannelsGeneration(newGeneration);
  }

  /// Vibration follows the section that owns the channel: the important
  /// sounds channel belongs to Alert Preferences, every other channel to
  /// General Notification Preference.
  Future<bool> _channelVibration(String baseId) async =>
      baseId == 'important_sounds'
      ? NotificationSettings.alertVibrationEnabled()
      : NotificationSettings.generalVibrationEnabled();

  Future<void> _ensureChannels() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;
    for (final (baseId, name, description) in _channels) {
      try {
        await android.createNotificationChannel(
          AndroidNotificationChannel(
            _channelId(baseId),
            name,
            description: description,
            importance: Importance.max,
            playSound: true,
            enableVibration: await _channelVibration(baseId),
          ),
        );
      } catch (_) {
        // Channel setup is best-effort.
      }
    }
  }

  /// Keeps the device-local notification history in step with every raised
  /// notification so the in-app Notifications screen can list and navigate
  /// to it later — even when the push itself is disabled by the profile.
  /// Returns the history entry id embedded into the payload. Best-effort;
  /// never breaks the notification itself.
  Future<String> _recordHistory({
    required String entryId,
    required int notificationId,
    required String kind,
    required String title,
    required String body,
    required String? route,
  }) async {
    try {
      await NotificationHistoryStore.instance.add(
        NotificationHistoryEntry(
          id: entryId,
          kind: kind,
          title: title,
          body: body,
          route: route,
          notificationId: notificationId,
          createdAt: DateTime.now(),
        ),
      );
    } catch (_) {
      // History is best-effort.
    }
    return entryId;
  }

  /// Maps each posted notification id to its history entry id. Some devices
  /// deliver action presses with an empty payload, so the id mapping is the
  /// fallback that still lets "Mark as read" resolve the history entry.
  final Map<int, String> _entryIdByNotificationId = {};

  void _rememberEntry(int notificationId, String entryId) {
    _entryIdByNotificationId[notificationId] = entryId;
  }

  /// Resolves the history entry for a notification response: prefer the
  /// `entryId|route` payload, fall back to the notification-id map.
  String? _resolveEntryId(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      final separator = payload.indexOf('|');
      if (separator > 0) return payload.substring(0, separator);
    }
    final id = response.id;
    if (id != null) return _entryIdByNotificationId[id];
    return null;
  }

  Future<void> _handleResponse(NotificationResponse response) async {
    final isMarkRead =
        response.actionId == _markReadActionId ||
        response.notificationResponseType ==
            NotificationResponseType.selectedNotificationAction;
    if (isMarkRead) {
      // The "Mark as read" action: mark the entry, dismiss the
      // notification, and do not navigate.
      final entryId = _resolveEntryId(response);
      if (entryId != null) {
        await NotificationHistoryStore.instance.markRead(entryId);
      }
      final id = response.id;
      if (id != null) {
        await _plugin.cancel(id: id);
        _entryIdByNotificationId.remove(id);
      }
      return;
    }
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    final entryId = _resolveEntryId(response);
    if (entryId != null) {
      await NotificationHistoryStore.instance.markRead(entryId);
    }
    final route = _routeForPayload(payload);
    if (_onTap != null) {
      _onTap!.call(route);
    } else {
      _router?.push(route);
    }
  }

  String _routeForPayload(String payload) {
    final separator = payload.indexOf('|');
    final route = separator > 0 ? payload.substring(separator + 1) : payload;
    if (!route.startsWith('chat:')) return route;
    final requestId = Uri.encodeQueryComponent(route.replaceFirst('chat:', ''));
    return '/chat?requestId=$requestId';
  }

  /// Marks an in-app history item read and removes the same notification
  /// from the phone tray, even after the app has restarted.
  Future<void> markAsRead(NotificationHistoryEntry entry) async {
    await NotificationHistoryStore.instance.markRead(entry.id);
    final notificationId = entry.notificationId;
    if (notificationId != null) {
      await _plugin.cancel(id: notificationId);
      _entryIdByNotificationId.remove(notificationId);
    }
  }

  /// Marks the complete history read and clears every linked phone
  /// notification. Old entries created before notification ids were stored
  /// remain backward-compatible.
  Future<void> markAllAsRead() async {
    final entries = await NotificationHistoryStore.instance.entries();
    await NotificationHistoryStore.instance.markAllRead();
    for (final notificationId
        in entries
            .map((entry) => entry.notificationId)
            .whereType<int>()
            .toSet()) {
      await _plugin.cancel(id: notificationId);
      _entryIdByNotificationId.remove(notificationId);
    }
  }

  /// Removes one in-app history record and its linked phone notification.
  Future<void> deleteHistoryEntry(NotificationHistoryEntry entry) async {
    await NotificationHistoryStore.instance.delete(entry.id);
    final notificationId = entry.notificationId;
    if (notificationId != null) {
      await _plugin.cancel(id: notificationId);
      _entryIdByNotificationId.remove(notificationId);
    }
  }

  /// Clears all in-app history records and linked phone notifications.
  Future<void> clearNotificationHistory() async {
    final entries = await NotificationHistoryStore.instance.entries();
    await NotificationHistoryStore.instance.clear();
    for (final notificationId
        in entries
            .map((entry) => entry.notificationId)
            .whereType<int>()
            .toSet()) {
      await _plugin.cancel(id: notificationId);
      _entryIdByNotificationId.remove(notificationId);
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
  }) async {
    final entryId = 'request-$requestId';
    final route = '/chat?requestId=${Uri.encodeQueryComponent(requestId)}';
    final notificationId = requestId.hashCode & 0x7fffffff;
    await _recordHistory(
      entryId: entryId,
      notificationId: notificationId,
      kind: 'request',
      title: '💬 $senderName',
      body: message,
      route: route,
    );
    if (!await NotificationSettings.generalPushEnabled()) return;
    final vibration = await NotificationSettings.generalVibrationEnabled();
    _rememberEntry(notificationId, entryId);
    return _plugin.show(
      id: notificationId,
      title: '💬 $senderName',
      body: message,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId('chat_messages'),
          'Chat Messages',
          channelDescription: 'New messages from staff in your assistance chat',
          importance: Importance.high,
          priority: Priority.high,
          enableVibration: vibration,
          icon: '@mipmap/ic_launcher',
          actions: [_markReadAction],
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: '$entryId|chat:$requestId',
    );
  }

  Future<void> showQueueCalled({
    required String number,
    required String counter,
    String? notificationEventId,
  }) async {
    final suffix = notificationEventId == null ? '' : '-$notificationEventId';
    final entryId = 'queue-called-$number$suffix';
    final notificationId = entryId.hashCode & 0x7fffffff;
    await _recordHistory(
      entryId: entryId,
      notificationId: notificationId,
      kind: 'queue',
      title: 'Queue $number is being called',
      body: 'Please proceed to $counter.',
      route: '/queue',
    );
    if (!await NotificationSettings.generalPushEnabled()) return;
    final vibration = await NotificationSettings.generalVibrationEnabled();
    final flash = await NotificationSettings.generalFlashEnabled();
    _rememberEntry(notificationId, entryId);
    return _plugin.show(
      id: notificationId,
      title: 'Queue $number is being called',
      body: 'Please proceed to $counter.',
      payload: '$entryId|/queue',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId('queue_updates'),
          'Queue updates',
          channelDescription: 'Alerts for your tracked queue number',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: vibration,
          enableLights: flash,
          actions: [_markReadAction],
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
    final entryId = 'queue-wait-$number';
    final notificationId = 'wait:$number'.hashCode & 0x7fffffff;
    await _recordHistory(
      entryId: entryId,
      notificationId: notificationId,
      kind: 'queue',
      title: 'Queue $number is coming up',
      body: 'Your number is about $minutes min away. Please stay nearby.',
      route: '/queue',
    );
    if (!await NotificationSettings.generalPushEnabled()) return;
    final vibration = await NotificationSettings.generalVibrationEnabled();
    final flash = await NotificationSettings.generalFlashEnabled();
    _rememberEntry(notificationId, entryId);
    return _plugin.show(
      id: notificationId,
      title: 'Queue $number is coming up',
      body: 'Your number is about $minutes min away. Please stay nearby.',
      payload: '$entryId|/queue',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId('queue_updates'),
          'Queue updates',
          channelDescription: 'Alerts for your tracked queue number',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: vibration,
          enableLights: flash,
          actions: [_markReadAction],
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
    final entryId = 'ann-$id';
    final route = '/announcement-details?id=$id';
    final notificationId = 'ann:$id'.hashCode & 0x7fffffff;
    await _recordHistory(
      entryId: entryId,
      notificationId: notificationId,
      kind: 'announcement',
      title: title,
      body: message,
      route: route,
    );
    if (!await NotificationSettings.generalPushEnabled()) return;
    final vibration = await NotificationSettings.generalVibrationEnabled();
    final flash = await NotificationSettings.generalFlashEnabled();
    _rememberEntry(notificationId, entryId);
    return _plugin.show(
      id: notificationId,
      title: title,
      body: message,
      payload: '$entryId|$route',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId('official_announcements'),
          'Official announcements',
          channelDescription:
              'Official announcements from your connected venue',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: vibration,
          enableLights: flash,
          actions: [_markReadAction],
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
    final entryId = 'cap-$id';
    final route = '/announcement-details?id=$id';
    final notificationId = 'cap:$id'.hashCode & 0x7fffffff;
    await _recordHistory(
      entryId: entryId,
      notificationId: notificationId,
      kind: 'captured',
      title: title,
      body: message,
      route: route,
    );
    if (!await NotificationSettings.generalPushEnabled()) return;
    final vibration = await NotificationSettings.generalVibrationEnabled();
    final flash = await NotificationSettings.generalFlashEnabled();
    _rememberEntry(notificationId, entryId);
    return _plugin.show(
      id: notificationId,
      title: title.trim().isEmpty
          ? 'Captured announcement ($confidencePercent% confidence)'
          : title,
      body: message,
      payload: '$entryId|$route',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId('captured_announcements'),
          'Captured public announcements',
          channelDescription:
              'Public-address announcements captured from the environment',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: vibration,
          enableLights: flash,
          actions: [_markReadAction],
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
    );
  }

  Future<void> showImportantSound({
    required String title,
    required String details,
  }) async {
    final entryId = 'sound-${DateTime.now().microsecondsSinceEpoch}';
    final notificationId = DateTime.now().millisecondsSinceEpoch.remainder(
      0x7fffffff,
    );
    await _recordHistory(
      entryId: entryId,
      notificationId: notificationId,
      kind: 'sound',
      title: title,
      body: details,
      route: null,
    );
    if (!await NotificationSettings.alertPushEnabled()) return;
    final vibration = await NotificationSettings.alertVibrationEnabled();
    _rememberEntry(notificationId, entryId);
    return _plugin.show(
      id: notificationId,
      title: title,
      body: details,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId('important_sounds'),
          'Important sound alerts',
          channelDescription:
              'Visual and vibration alerts for important sounds',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: vibration,
          actions: [_markReadAction],
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
    );
  }
}

/// Handles the "Mark as read" action while the app is not active. Must be a
/// top-level function so the plugin can invoke it from a background isolate.
@pragma('vm:entry-point')
Future<void> notificationBackgroundHandler(
  NotificationResponse response,
) async {
  try {
    if (response.actionId != AppNotificationService._markReadActionId) return;
    final payload = response.payload;
    if (payload != null && payload.isNotEmpty) {
      final separator = payload.indexOf('|');
      if (separator > 0) {
        await NotificationHistoryStore.instance.markRead(
          payload.substring(0, separator),
        );
      }
    }
    // Dismiss the push from the tray — the action's own cancel flag is not
    // honoured on every OEM build.
    final id = response.id;
    if (id != null) {
      await FlutterLocalNotificationsPlugin().cancel(id: id);
    }
  } catch (_) {
    // Marking read from the background is best-effort.
  }
}
