import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

/// Features whose first use is tracked independently for each traveller.
enum TrackedFeature {
  signTranslate,
  speechToSign,
  twoWayDialogue,
  signDictionary,
  requestHelp,
  queueTracking,
  announcements,
  gpsLocation,
  sos,
}

extension TrackedFeatureKey on TrackedFeature {
  String get key => switch (this) {
    TrackedFeature.signTranslate => 'sign_translate',
    TrackedFeature.speechToSign => 'speech_to_sign',
    TrackedFeature.twoWayDialogue => 'two_way_dialogue',
    TrackedFeature.signDictionary => 'sign_dictionary',
    TrackedFeature.requestHelp => 'request_help',
    TrackedFeature.queueTracking => 'queue_tracking',
    TrackedFeature.announcements => 'announcements',
    TrackedFeature.gpsLocation => 'gps_location',
    TrackedFeature.sos => 'sos',
  };
}

enum FeatureUsageEvent { opened, completed }

extension FeatureUsageEventKey on FeatureUsageEvent {
  String get key => switch (this) {
    FeatureUsageEvent.opened => 'opened',
    FeatureUsageEvent.completed => 'completed',
  };
}

class FeatureUsageStatus {
  const FeatureUsageStatus({
    required this.feature,
    this.firstOpenedAt,
    this.firstCompletedAt,
  });

  final TrackedFeature feature;
  final DateTime? firstOpenedAt;
  final DateTime? firstCompletedAt;

  bool get hasOpened => firstOpenedAt != null;
  bool get hasCompleted => firstCompletedAt != null;

  factory FeatureUsageStatus.fromMap(
    TrackedFeature feature,
    Map<String, dynamic> data,
  ) => FeatureUsageStatus(
    feature: feature,
    firstOpenedAt: DateTime.tryParse(data['first_opened_at'] as String? ?? ''),
    firstCompletedAt: DateTime.tryParse(
      data['first_completed_at'] as String? ?? '',
    ),
  );
}

/// Persists first-use events to the authenticated traveller's account.
///
/// The database RPC is idempotent: a screen may call it repeatedly, but the
/// original first-opened and first-completed timestamps are never overwritten.
class FeatureUsageRepository {
  FeatureUsageRepository({SupabaseClient? client})
    : _client = client ?? SupabaseClientHelper.client;

  final SupabaseClient _client;
  static const _outboxKeyPrefix = 'travelease.feature_usage_outbox';

  Future<FeatureUsageStatus?> getStatus(TrackedFeature feature) async {
    final user = _client.auth.currentUser;
    if (user == null) return null;
    final data = await _client
        .from('user_feature_guidance')
        .select()
        .eq('user_id', user.id)
        .eq('feature_key', feature.key)
        .maybeSingle();
    return data == null
        ? null
        : FeatureUsageStatus.fromMap(feature, Map<String, dynamic>.from(data));
  }

  Future<void> record(TrackedFeature feature, FeatureUsageEvent event) async {
    final user = _client.auth.currentUser;
    if (user == null) return;
    try {
      await _flushOutbox(user.id);
      await _recordRemote(feature.key, event.key);
    } catch (_) {
      await _enqueue(user.id, feature.key, event.key);
    }
  }

  Future<void> _recordRemote(String featureKey, String eventKey) {
    return _client.rpc(
      'record_feature_usage',
      params: {'p_feature_key': featureKey, 'p_event': eventKey},
    );
  }

  String _outboxKeyFor(String userId) => '${_outboxKeyPrefix}_$userId';

  Future<void> _enqueue(
    String userId,
    String featureKey,
    String eventKey,
  ) async {
    final preferences = await SharedPreferences.getInstance();
    final pending = _readOutbox(preferences, userId);
    pending.add({'feature_key': featureKey, 'event': eventKey});
    await preferences.setString(_outboxKeyFor(userId), jsonEncode(pending));
  }

  Future<void> _flushOutbox(String userId) async {
    final preferences = await SharedPreferences.getInstance();
    final pending = _readOutbox(preferences, userId);
    if (pending.isEmpty) return;

    for (var index = 0; index < pending.length; index++) {
      final entry = pending[index];
      try {
        await _recordRemote(
          entry['feature_key'] as String,
          entry['event'] as String,
        );
      } catch (_) {
        await preferences.setString(
          _outboxKeyFor(userId),
          jsonEncode(pending.sublist(index)),
        );
        rethrow;
      }
    }
    await preferences.remove(_outboxKeyFor(userId));
  }

  List<Map<String, Object>> _readOutbox(
    SharedPreferences preferences,
    String userId,
  ) {
    final encoded = preferences.getString(_outboxKeyFor(userId));
    if (encoded == null) return [];
    try {
      final decoded = jsonDecode(encoded) as List<dynamic>;
      return decoded
          .whereType<Map>()
          .map(
            (entry) => {
              'feature_key': entry['feature_key'] as String,
              'event': entry['event'] as String,
            },
          )
          // Discard retired guide events from an older offline queue. Only
          // first-use events are persisted now.
          .where(
            (entry) =>
                entry['event'] == FeatureUsageEvent.opened.key ||
                entry['event'] == FeatureUsageEvent.completed.key,
          )
          .toList();
    } catch (_) {
      // A corrupt local outbox must not interfere with a traveller's feature.
      unawaited(preferences.remove(_outboxKeyFor(userId)));
      return [];
    }
  }
}

/// Fire-and-forget facade for screen and action handlers. Usage collection
/// must never block a traveller from accessing an accessibility feature.
class FeatureUsageTracker {
  FeatureUsageTracker._();

  static final instance = FeatureUsageTracker._();

  final FeatureUsageRepository _repository = FeatureUsageRepository();

  void opened(TrackedFeature feature) =>
      _record(feature, FeatureUsageEvent.opened);

  void completed(TrackedFeature feature) =>
      _record(feature, FeatureUsageEvent.completed);

  void _record(TrackedFeature feature, FeatureUsageEvent event) {
    unawaited(_repository.record(feature, event).catchError((_) {}));
  }
}
