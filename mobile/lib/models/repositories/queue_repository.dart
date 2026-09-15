import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase_client.dart';
import '../entities/queue_tracking.dart';

class QueueRepository {
  static const kliaTerminalOneId = '11111111-1111-4111-8111-111111111111';
  final SupabaseClient _client = SupabaseClientHelper.client;

  Future<List<QueueLineInfo>> getActiveQueueLines({
    String institutionId = kliaTerminalOneId,
  }) async {
    final response = await _client
        .from('queue_lines')
        .select()
        .eq('institution_id', institutionId)
        .neq('status', 'closed')
        .neq('status', 'reset')
        .order('name');
    return (response as List<dynamic>)
        .map((row) => QueueLineInfo.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<QueueTrackingData?> trackNumber({
    required String number,
    String? queueLineId,
    String? queuePrefix,
    String institutionId = kliaTerminalOneId,
  }) async {
    var query = _client
        .from('queue_numbers')
        .select('*, queue_lines!inner(*)')
        .eq('institution_id', institutionId)
        .inFilter('number', numberCandidates(number, queuePrefix));
    if (queueLineId != null && queueLineId.isNotEmpty) {
      query = query.eq('queue_line_id', queueLineId);
    }
    final response = await query.limit(1).maybeSingle();
    if (response == null) {
      return _virtualWaitingNumber(
        number: number,
        queueLineId: queueLineId,
        queuePrefix: queuePrefix,
        institutionId: institutionId,
      );
    }
    final tracking = QueueTrackingData.fromJson(
      Map<String, dynamic>.from(response),
    );
    enforceMaximumQueueNumber(tracking);
    return tracking;
  }

  /// Waiting numbers are not pre-created in the database. When a number is
  /// inside a live line's configured maximum, expose it as a local Waiting
  /// record so travellers can look it up without filling Supabase with future
  /// queue rows. A real row replaces it when staff calls the number.
  Future<QueueTrackingData?> _virtualWaitingNumber({
    required String number,
    required String institutionId,
    String? queueLineId,
    String? queuePrefix,
  }) async {
    final match = RegExp(r'^(?:([A-Z]+)[-\\s]?)?(\\d+)$')
        .firstMatch(number.trim().toUpperCase());
    if (match == null) return null;
    final value = int.tryParse(match.group(2)!);
    if (value == null || value < 1) return null;
    final requestedPrefix = (queuePrefix ?? match.group(1) ?? '')
        .replaceAll(RegExp(r'[\\s-]'), '')
        .toUpperCase();
    var lines = _client
        .from('queue_lines')
        .select()
        .eq('institution_id', institutionId)
        .neq('status', 'reset');
    if (queueLineId != null && queueLineId.isNotEmpty) {
      lines = lines.eq('id', queueLineId);
    }
    final response = await lines.limit(20);
    final lineJson = (response as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .where((row) {
          final linePrefix = (row['prefix'] as String? ?? '')
              .replaceAll(RegExp(r'[\\s-]'), '')
              .toUpperCase();
          return row['status'] != 'reset' &&
              linePrefix == requestedPrefix &&
              value <= (row['max_tracking_number'] as int? ??
                  QueueLineInfo.defaultMaxTrackingNumber);
        })
        .cast<Map<String, dynamic>>()
        .firstOrNull;
    if (lineJson == null) return null;
    final line = QueueLineInfo.fromJson(lineJson);
    final digits = value.toString().padLeft(3, '0');
    final formatted = line.prefix.trim().isEmpty ? digits : '${line.prefix}-$digits';
    return QueueTrackingData(
      id: 'virtual-${line.id}-$value',
      number: formatted,
      status: 'waiting',
      line: line,
    );
  }

  /// The maximum queue number configured on the web portal is a hard cap:
  /// waiting numbers beyond it will never be called, so they cannot be
  /// tracked. Legacy numbers that were already called before the cap keep
  /// their status visible. Returns a specific error message when [number]
  /// is beyond [line]'s cap, or null when the number is trackable.
  static String? maximumQueueNumberViolation(
    String number,
    QueueLineInfo line,
  ) {
    final match = RegExp(r'\d+$').firstMatch(number);
    final value = int.tryParse(match?.group(0) ?? '');
    if (value == null || value <= line.maxTrackingNumber) return null;
    final prefix = line.prefix.trim().toUpperCase();
    final capLabel = prefix.isEmpty
        ? '${line.maxTrackingNumber}'
        : '$prefix-${'${line.maxTrackingNumber}'.padLeft(3, '0')}';
    return 'Queue number ${number.trim().toUpperCase()} is beyond the '
        'maximum queue number ($capLabel) for this queue line and will not '
        'be called.';
  }

  static void enforceMaximumQueueNumber(QueueTrackingData tracking) {
    if (tracking.status != 'waiting') return;
    final message = maximumQueueNumberViolation(tracking.number, tracking.line);
    if (message != null) {
      throw QueueNumberBeyondMaximumException(message);
    }
  }

  /// Formatting variants for a queue number so lookups tolerate prefixes,
  /// dashes and zero padding ("A-047", "A047", "a 47"...).
  static List<String> numberCandidates(String number, String? prefix) {
    final raw = number.trim().toUpperCase();
    final compact = raw.replaceAll(RegExp(r'[\s-]'), '');
    final cleanPrefix = (prefix ?? '').trim().toUpperCase().replaceAll(
      RegExp(r'[\s-]'),
      '',
    );
    final candidates = <String>{raw, compact};
    var resolvedPrefix = cleanPrefix;
    var numberPart = compact;
    if (cleanPrefix.isNotEmpty && compact.startsWith(cleanPrefix)) {
      numberPart = compact.substring(cleanPrefix.length);
    } else if (cleanPrefix.isEmpty) {
      final match = RegExp(r'^([A-Z]+)(\d+)$').firstMatch(compact);
      if (match != null) {
        resolvedPrefix = match.group(1)!;
        numberPart = match.group(2)!;
      }
    }
    if (resolvedPrefix.isNotEmpty && RegExp(r'^\d+$').hasMatch(numberPart)) {
      final padded = numberPart.padLeft(3, '0');
      candidates
        ..add('$resolvedPrefix-$padded')
        ..add('$resolvedPrefix$padded')
        ..add('$resolvedPrefix-$numberPart');
    }
    return candidates.where((value) => value.isNotEmpty).toList();
  }

  /// [channelTag] keeps concurrent subscribers (tracking view, notification
  /// service) on distinct realtime topics — Supabase dedupes duplicate
  /// channel names, which silently stopped one of the callbacks firing.
  /// Marks the tracked queue number as held by this traveller (traveler_id)
  /// so the staff console can show how many real people are waiting instead
  /// of counting pre-registered future numbers. Best-effort and idempotent:
  /// once claimed, the update matches no rows and raises no realtime event.
  Future<void> claimNumber({
    required String number,
    required String queueLineId,
    String? queuePrefix,
  }) async {
    try {
      final user = _client.auth.currentUser;
      if (user == null) return;
      await _client
          .from('queue_numbers')
          .update({'traveler_id': user.id})
          .eq('queue_line_id', queueLineId)
          .inFilter('number', numberCandidates(number, queuePrefix))
          .filter('traveler_id', 'is', null);
    } catch (_) {
      // Claiming is best-effort; tracking must keep working without it.
    }
  }

  RealtimeChannel subscribeToTracking(
    String queueLineId,
    void Function() onChanged, {
    String channelTag = 'view',
    void Function(Map<String, dynamic> event)? onNotification,
  }) {
    return _client
        .channel('mobile-queue-tracking:$channelTag:$queueLineId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'queue_lines',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: queueLineId,
          ),
          callback: (_) => onChanged(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'queue_numbers',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'queue_line_id',
            value: queueLineId,
          ),
          callback: (_) => onChanged(),
        )
        // A staff member can notify a number again without changing its
        // status. Keep that event separate from queue-number updates so a
        // repeated call still reaches the traveller after the number is
        // already marked as called.
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'queue_events',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'queue_line_id',
            value: queueLineId,
          ),
          callback: (payload) {
            onChanged();
            final event = payload.newRecord;
            if (event['event_type'] == 'notified') onNotification?.call(event);
          },
        )
        .subscribe();
  }

  Future<void> removeSubscription(RealtimeChannel channel) =>
      _client.removeChannel(channel);
}

/// The tracked queue number is beyond its queue line's maximum queue number.
class QueueNumberBeyondMaximumException implements Exception {
  final String message;

  const QueueNumberBeyondMaximumException(this.message);

  @override
  String toString() => message;
}
