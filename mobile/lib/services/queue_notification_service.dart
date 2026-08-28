import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/entities/queue_tracking.dart';
import '../models/repositories/queue_repository.dart';
import 'app_notification_service.dart';

class QueueNotificationService {
  QueueNotificationService._();

  static final instance = QueueNotificationService._();
  static const _lineKey = 'tracked_queue_line_id';
  static const _numberKey = 'tracked_queue_number';

  final QueueRepository _repository = QueueRepository();
  RealtimeChannel? _channel;
  QueueTrackingData? _current;
  String? _lastStatus;

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
      _lastStatus = result.status;
      await _subscribe(result.line.id);
    } catch (_) {
      // A temporary network failure must not prevent the app from opening.
    }
  }

  Future<void> track(QueueTrackingData tracking) async {
    _current = tracking;
    _lastStatus = tracking.status;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_lineKey, tracking.line.id);
    await preferences.setString(_numberKey, tracking.number);
    await AppNotificationService.instance.requestPermission();
    await _subscribe(tracking.line.id);
  }

  Future<void> _subscribe(String lineId) async {
    final previous = _channel;
    if (previous != null) await _repository.removeSubscription(previous);
    _channel = _repository.subscribeToTracking(lineId, _refresh);
  }

  Future<void> _refresh() async {
    final tracked = _current;
    if (tracked == null) return;
    final refreshed = await _repository.trackNumber(
      number: tracked.number,
      queueLineId: tracked.line.id,
      queuePrefix: tracked.line.prefix,
    );
    if (refreshed == null) return;
    final wasCalled = _lastStatus == 'called' || _lastStatus == 'serving';
    final isCalled =
        refreshed.status == 'called' || refreshed.status == 'serving';
    _current = refreshed;
    _lastStatus = refreshed.status;
    if (isCalled && !wasCalled) {
      await AppNotificationService.instance.showQueueCalled(
        number: refreshed.number,
        counter: refreshed.line.counter,
      );
    }
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_lineKey);
    await preferences.remove(_numberKey);
    final previous = _channel;
    _channel = null;
    if (previous != null) await _repository.removeSubscription(previous);
    _current = null;
    _lastStatus = null;
  }
}
