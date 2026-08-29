import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase_client.dart';
import '../entities/announcement.dart';

class AnnouncementRepository {
  static const kliaTerminalOneId = '11111111-1111-4111-8111-111111111111';
  final SupabaseClient _client = SupabaseClientHelper.client;

  Future<List<Announcement>> getActiveAnnouncements({String institutionId = kliaTerminalOneId}) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final response = await _client
        .from('announcements')
        .select('*, venue_zones(name, code)')
        .eq('institution_id', institutionId)
        .eq('status', 'active')
        .lte('published_at', now)
        .or('expires_at.is.null,expires_at.gt.$now')
        .order('published_at', ascending: false);

    return (response as List<dynamic>)
        .map((row) => Announcement.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  RealtimeChannel subscribeToAnnouncements(
    void Function() onChanged, {
    String institutionId = kliaTerminalOneId,
  }) {
    return _client
        .channel('mobile-official-announcements:$institutionId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'announcements',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'institution_id',
            value: institutionId,
          ),
          callback: (_) => onChanged(),
        )
        .subscribe();
  }

  Future<void> removeSubscription(RealtimeChannel channel) => _client.removeChannel(channel);
}
