import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/entities/queue_tracking.dart';
import '../models/repositories/queue_repository.dart';
import 'app_notification_service.dart';
import 'flash_alert_service.dart';

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

  /// Estimated wait under which the traveller gets a single heads-up alert.
  static const int almostUpThresholdMinutes = 10;

  final QueueRepository _repository = QueueRepository();
  RealtimeChannel? _channel;
  QueueTrackingData? _current;

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
    } catch (_) {
      // A temporary network failure must not prevent the app from opening.
    }
  }

  Future<void> track(QueueTrackingData tracking) async {
    _current = tracking;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_lineKey, tracking.line.id);
    await preferences.setString(_numberKey, tracking.number);
    // Pre-mark the alert state for whatever is already true at track time so
    // entering an almost-due or called number never fires the corresponding
    // alert; the background poller shares these keys.
    if (tracking.status == 'called' || tracking.status == 'serving') {
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
    await evaluateAlerts(tracking);
  }

  Future<void> _subscribe(String lineId) async {
    final previous = _channel;
    if (previous != null) await _repository.removeSubscription(previous);
    _channel = _repository.subscribeToTracking(lineId, _refresh);
  }

  Future<void> _refresh() async {
    final tracked = _current;
    if (tracked == null) return;
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
    }
  }

  /// Raises the one-time queue alerts for the given tracking state. Also used
  /// by the background poller so both paths share the same dedupe keys.
  Future<void> evaluateAlerts(QueueTrackingData tracking) async {
    final preferences = await SharedPreferences.getInstance();
    final number = tracking.number;

    final isCalled = tracking.status == 'called' || tracking.status == 'serving';
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
      if (wait > 0 && wait < almostUpThresholdMinutes && notifiedFor != number) {
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
    final previous = _channel;
    _channel = null;
    if (previous != null) await _repository.removeSubscription(previous);
    _current = null;
  }
}
