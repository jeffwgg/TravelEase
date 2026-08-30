import 'dart:async';
import 'dart:convert';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/supabase_client.dart';
import '../models/entities/queue_tracking.dart';
import '../models/repositories/queue_repository.dart';
import 'app_notification_service.dart';
import 'flash_alert_service.dart';
import 'queue_notification_service.dart';

/// Channel used by the persistent-service status notification. The
/// flutter_background_service plugin does not create a custom channel itself,
/// so the app must create it before the service calls startForeground(),
/// otherwise posting the notification crashes the app.
const _backgroundChannelId = 'travelease_background';

/// Poll interval for the background alert poller.
const _pollInterval = Duration(seconds: 60);

/// Freshness window for announcement alerts, matching the foreground service.
const _freshWindow = Duration(minutes: 30);

bool _backgroundServiceStarted = false;

Future<void> _ensureBackgroundChannel() async {
  try {
    final plugin = FlutterLocalNotificationsPlugin()
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await plugin?.createNotificationChannel(
      const AndroidNotificationChannel(
        _backgroundChannelId,
        'TravelEase background alerts',
        description:
            'Keeps venue announcements and queue alerts running while the app '
            'is in the background.',
        importance: Importance.low,
      ),
    );
  } catch (error) {
    debugPrint('[BackgroundAlerts] channel creation failed: $error');
  }
}

/// Starts the persistent venue-alert foreground service. While it runs, the
/// app keeps receiving announcement and queue alerts when the app is
/// backgrounded or its task is swiped away. Enabled by default for now; a
/// settings section will control it later.
///
/// Some Android builds (MIUI in particular) reject an FGS start issued while
/// the app is not yet foreground (e.g. launch with the screen off), so
/// failures are retried until the system allows it.
Future<void> startBackgroundNotificationService({int attemptsRemaining = 5}) async {
  if (_backgroundServiceStarted) return;
  await _ensureBackgroundChannel();
  final service = FlutterBackgroundService();
  try {
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: backgroundNotificationEntryPoint,
        isForegroundMode: true,
        autoStart: true,
        notificationChannelId: 'travelease_background',
        initialNotificationTitle: 'TravelEase is active',
        initialNotificationContent:
            'Receiving announcements and queue alerts for your venue.',
        foregroundServiceNotificationId: 9001,
      ),
      iosConfiguration: IosConfiguration(),
    );
    _backgroundServiceStarted = true;
  } catch (error) {
    debugPrint('[BackgroundAlerts] foreground service start failed: $error');
    if (attemptsRemaining > 0) {
      Timer(
        const Duration(seconds: 30),
        () => startBackgroundNotificationService(
          attemptsRemaining: attemptsRemaining - 1,
        ),
      );
    }
  }
}

/// Background-isolate entry point: polls Supabase for fresh official
/// announcements and tracked-queue changes, sharing its one-time-alert state
/// with the UI isolate through SharedPreferences so no alert ever double-fires.
@pragma('vm:entry-point')
Future<void> backgroundNotificationEntryPoint(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  await AppNotificationService.instance.initialize();
  Timer.periodic(_pollInterval, (_) => _poll());
  await _poll();
}

Future<void> _poll() async {
  try {
    await _pollAnnouncements();
  } catch (error) {
    debugPrint('[BackgroundAlerts] announcement poll failed: $error');
  }
  try {
    await _pollQueue();
  } catch (error) {
    debugPrint('[BackgroundAlerts] queue poll failed: $error');
  }
}

Future<Map<String, dynamic>?> _trackedSession() async {
  final preferences = await SharedPreferences.getInstance();
  final institutionId = preferences.getString('venue_session_institution_id');
  if (institutionId == null) return null;
  return {
    'institutionId': institutionId,
    'preferences': preferences,
  };
}

Future<List<dynamic>> _restGet(String path, Map<String, String> query) async {
  final uri = Uri.parse('${SupabaseClientHelper.supabaseUrl}/rest/v1/$path')
      .replace(queryParameters: query);
  final response = await http.get(
    uri,
    headers: {
      'apikey': SupabaseClientHelper.supabaseAnonKey,
      'Authorization': 'Bearer ${SupabaseClientHelper.supabaseAnonKey}',
      'Accept': 'application/json',
    },
  );
  if (response.statusCode != 200) {
    throw Exception('REST ${response.statusCode}: ${response.body}');
  }
  return jsonDecode(response.body) as List<dynamic>;
}

Future<void> _pollAnnouncements() async {
  final session = await _trackedSession();
  if (session == null) return;
  final institutionId = session['institutionId'] as String;
  final preferences = session['preferences'] as SharedPreferences;
  final seenKey = 'notified_announcement_ids:$institutionId';
  final seen = (preferences.getStringList(seenKey) ?? const <String>[]).toSet();

  final rows = await _restGet('announcements', {
    'select': 'id,title,message_en,published_at,expires_at',
    'institution_id': 'eq.$institutionId',
    'status': 'eq.active',
    'order': 'published_at.desc',
    'limit': '15',
  });

  final now = DateTime.now().toUtc();
  final cutoff = now.subtract(_freshWindow);
  var alerted = false;
  final fresh = <Map<String, dynamic>>[];
  for (final row in rows) {
    final data = row as Map<String, dynamic>;
    final id = data['id'] as String?;
    if (id == null) continue;
    final publishedAt = DateTime.tryParse(data['published_at'] as String? ?? '');
    final expiresAt = data['expires_at'] == null
        ? null
        : DateTime.tryParse(data['expires_at'] as String);
    if (publishedAt == null || publishedAt.isAfter(now)) continue;
    if (expiresAt != null && expiresAt.isBefore(now)) continue;
    if (seen.contains(id)) continue;
    if (publishedAt.isBefore(cutoff)) continue;
    fresh.add(data);
  }

  for (final data in fresh) {
    final id = data['id'] as String;
    if (!alerted) {
      await FlashAlertService.instance.blinkTwice();
      alerted = true;
    }
    await AppNotificationService.instance.showOfficialAnnouncement(
      id: id,
      title: data['title'] as String? ?? 'Announcement',
      message: data['message_en'] as String? ?? '',
    );
  }

  // Keep the seen set in sync with every active announcement observed.
  for (final row in rows) {
    final id = (row as Map<String, dynamic>)['id'];
    if (id is String) seen.add(id);
  }
  final all = seen.toList();
  await preferences.setStringList(
    seenKey,
    all.length > 100 ? all.sublist(all.length - 100) : all,
  );
}

Future<void> _pollQueue() async {
  final preferences = await SharedPreferences.getInstance();
  final lineId = preferences.getString('tracked_queue_line_id');
  final number = preferences.getString('tracked_queue_number');
  if (lineId == null || number == null) return;

  final candidates = QueueRepository.numberCandidates(number, null);
  final filter = candidates.map((candidate) => '"$candidate"').join(',');
  final rows = await _restGet('queue_numbers', {
    'select': '*,queue_lines!inner(*)',
    'queue_line_id': 'eq.$lineId',
    'number': 'in.($filter)',
    'limit': '1',
  });
  if (rows.isEmpty) return;

  final tracking = QueueTrackingData.fromJson(
    rows.first as Map<String, dynamic>,
  );
  await QueueNotificationService.instance.evaluateAlerts(tracking);
}
