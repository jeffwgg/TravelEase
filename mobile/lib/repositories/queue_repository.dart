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
    String? queuePrefix,
    String institutionId = kliaTerminalOneId,
  }) async {
    var query = _client
        .from('queue_numbers')
        .select('*, queue_lines!inner(*)')
        .eq('institution_id', institutionId)
        .inFilter('number', _numberCandidates(number, queuePrefix));
    if (queueLineId != null && queueLineId.isNotEmpty) {
      query = query.eq('queue_line_id', queueLineId);
    }
    final response = await query.limit(1).maybeSingle();
    if (response == null) return null;
    return QueueTrackingData.fromJson(Map<String, dynamic>.from(response));
  }

  List<String> _numberCandidates(String number, String? prefix) {
    final raw = number.trim().toUpperCase();
    final compact = raw.replaceAll(RegExp(r'[\s-]'), '');
    final cleanPrefix = (prefix ?? '').trim().toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
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
