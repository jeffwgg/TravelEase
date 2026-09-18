import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/entities/queue_tracking.dart';
import '../models/repositories/queue_repository.dart';
import 'app_notification_service.dart';
import 'flash_alert_service.dart';
import 'venue_session_service.dart';

/// Tracks the traveller's queue number app-wide and raises one-time alerts:
/// once when the estimated wait drops under ten minutes, and once when the
/// number is called. A number that is already almost due or already being
/// called at the moment it is tracked stays silent — the traveller just
/// entered it and is looking at the screen; only later transitions alert.
/// Alert state is persisted so the background poller and the UI isolate
/// never alert twice for the same event.
class QueueNotificationService {
  QueueNotificationService._();

  static final instance = QueueNotificationService._();

  static const _lineKey = 'tracked_queue_line_id';
  static const _numberKey = 'tracked_queue_number';
  static const _calledNotifiedKey = 'queue_called_notified_for';
  static const _waitNotifiedKey = 'queue_wait_notified_for';
  static const _manualNotificationEventIdsKey =
      'queue_manual_notification_event_ids';

  /// Estimated wait under which the traveller gets a single heads-up alert.
  static const int almostUpThresholdMinutes = 10;

  final QueueRepository _repository = QueueRepository();
  RealtimeChannel? _channel;
  QueueTrackingData? _current;
  Timer? _refreshTimer;
  bool _refreshing = false;

  static const _refreshInterval = Duration(seconds: 15);

  QueueTrackingData? get current => _current;

  Future<void> initialize() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final lineId = preferences.getString(_lineKey);
      final number = preferences.getString(_numberKey);
      if (lineId == null || number == null) return;
      final result = await _repository.trackNumber(
        number: number,
        queueLineId: lineId,
      );
      if (result == null) {
        await clear();
        return;
      }
      _current = result;
      await _subscribe(result.line.id);
      _ensureRefreshTimer();
    } catch (_) {
      // A temporary network failure must not prevent the app from opening.
    }
  }

  Future<void> track(QueueTrackingData tracking) async {
    _current = tracking;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_lineKey, tracking.line.id);
    await preferences.setString(_numberKey, tracking.number);
    // Claim the number so the staff console counts a real waiting traveller.
    await _repository.claimNumber(
      number: tracking.number,
      queueLineId: tracking.line.id,
      queuePrefix: tracking.line.prefix,
    );
    // Pre-mark the alert state for whatever is already true at track time so
    // entering an almost-due or called number never fires the corresponding
    // alert; the background poller shares these keys.
    if (tracking.status == 'called') {
      await preferences.setString(_calledNotifiedKey, tracking.number);
    }
    final wait = tracking.estimatedWaitMinutes;
    if (tracking.status == 'waiting' &&
        wait > 0 &&
        wait < almostUpThresholdMinutes) {
      await preferences.setString(_waitNotifiedKey, tracking.number);
    }
    await AppNotificationService.instance.requestPermission();
    await _subscribe(tracking.line.id);
    _ensureRefreshTimer();
    await evaluateAlerts(tracking);
  }

  Future<void> _subscribe(String lineId) async {
    final previous = _channel;
    if (previous != null) await _repository.removeSubscription(previous);
    _channel = _repository.subscribeToTracking(
      lineId,
      _refresh,
      channelTag: 'service',
      onNotification: _handleManualNotification,
    );
  }

  Future<void> _handleManualNotification(Map<String, dynamic> event) async {
    final tracked = _current;
    final eventId = event['id']?.toString();
    final eventNumber = event['event_number']?.toString();
    if (tracked == null || eventId == null || eventNumber == null) return;
    final candidates = QueueRepository.numberCandidates(
      tracked.number,
      tracked.line.prefix,
    );
    if (!candidates.contains(eventNumber.trim().toUpperCase())) return;
    await deliverManualNotification(tracked, eventId);
  }

  /// Delivers a staff "call again" notification. This intentionally bypasses
  /// the status-transition dedupe used by [evaluateAlerts]: the event itself
  /// is the new information, while the queue number remains unchanged.
  Future<void> deliverManualNotification(
    QueueTrackingData tracking,
    String eventId,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    if (preferences.getString(
          VenueSessionService.preferenceKey('venue_session_institution_id'),
        ) ==
        null) {
      return;
    }
    final seen =
        (preferences.getStringList(_manualNotificationEventIdsKey) ??
                const <String>[])
            .toSet();
    if (seen.contains(eventId)) return;
    seen.add(eventId);
    final ids = seen.toList();
    await preferences.setStringList(
      _manualNotificationEventIdsKey,
      ids.length > 100 ? ids.sublist(ids.length - 100) : ids,
    );
    await FlashAlertService.instance.blinkTwice();
    await AppNotificationService.instance.showQueueCalled(
      number: tracking.number,
      counter: tracking.line.counterLabel,
      notificationEventId: eventId,
    );
  }

  Future<void> _refresh() async {
    final tracked = _current;
    if (tracked == null || _refreshing) return;
    _refreshing = true;
    try {
      final refreshed = await _repository.trackNumber(
        number: tracked.number,
        queueLineId: tracked.line.id,
        queuePrefix: tracked.line.prefix,
      );
      if (refreshed == null) return;
      _current = refreshed;
      await evaluateAlerts(refreshed);
    } catch (_) {
      // Keep the last known state during transient realtime refresh failures.
    } finally {
      _refreshing = false;
    }
  }

  /// Realtime updates are immediate when the socket is healthy. This small
  /// foreground fallback keeps tracking and alerts working after a temporary
  /// socket disconnect, without relying on the background isolate.
  void _ensureRefreshTimer() {
    _refreshTimer ??= Timer.periodic(_refreshInterval, (_) => _refresh());
  }

  /// Raises the one-time queue alerts for the given tracking state. Also used
  /// by the background poller so both paths share the same dedupe keys.
  Future<void> evaluateAlerts(QueueTrackingData tracking) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    if (preferences.getString(
          VenueSessionService.preferenceKey('venue_session_institution_id'),
        ) ==
        null) {
      return;
    }
    final number = tracking.number;

    final isCalled = tracking.status == 'called';
    if (isCalled) {
      final notifiedFor = preferences.getString(_calledNotifiedKey);
      if (notifiedFor != number) {
        await preferences.setString(_calledNotifiedKey, number);
        await FlashAlertService.instance.blinkTwice();
        await AppNotificationService.instance.showQueueCalled(
          number: tracking.number,
          counter: tracking.line.counterLabel,
        );
      }
      return;
    }

    if (tracking.status == 'waiting') {
      final wait = tracking.estimatedWaitMinutes;
      final notifiedFor = preferences.getString(_waitNotifiedKey);
      if (wait > 0 &&
          wait < almostUpThresholdMinutes &&
          notifiedFor != number) {
        await preferences.setString(_waitNotifiedKey, number);
        await FlashAlertService.instance.blinkTwice();
        await AppNotificationService.instance.showQueueAlmostUp(
          number: tracking.number,
          minutes: wait,
        );
      }
    }
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_lineKey);
    await preferences.remove(_numberKey);
    await preferences.remove(_calledNotifiedKey);
    await preferences.remove(_waitNotifiedKey);
    await preferences.remove(_manualNotificationEventIdsKey);
    final previous = _channel;
    _channel = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    _refreshing = false;
    if (previous != null) await _repository.removeSubscription(previous);
    _current = null;
  }
}
