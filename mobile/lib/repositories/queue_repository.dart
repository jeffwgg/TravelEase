import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';
import '../models/queue_tracking.dart';

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
        .order('name');
    return (response as List<dynamic>)
        .map((row) => QueueLineInfo.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<QueueTrackingData?> trackNumber({
    required String number,
    String? queueLineId,
    String institutionId = kliaTerminalOneId,
  }) async {
    var query = _client
        .from('queue_numbers')
        .select('*, queue_lines!inner(*)')
        .eq('institution_id', institutionId)
        .eq('number', number.trim().toUpperCase());
    if (queueLineId != null && queueLineId.isNotEmpty) {
      query = query.eq('queue_line_id', queueLineId);
    }
    final response = await query.limit(1).maybeSingle();
    if (response == null) return null;
    return QueueTrackingData.fromJson(Map<String, dynamic>.from(response));
  }

  RealtimeChannel subscribeToTracking(
    String queueLineId,
    void Function() onChanged,
  ) {
    return _client
        .channel('mobile-queue-tracking:$queueLineId')
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
        .subscribe();
  }

  Future<void> removeSubscription(RealtimeChannel channel) =>
      _client.removeChannel(channel);
}
