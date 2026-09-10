import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase_client.dart';
import '../entities/announcement.dart';

class AnnouncementRepository {
  final SupabaseClient _client = SupabaseClientHelper.client;

  /// Official announcements published by the given institution. Official
  /// announcements are institution-scoped, so without an active venue session
  /// there are none to show.
  Future<List<Announcement>> getActiveAnnouncements({String? institutionId}) async {
    if (institutionId == null) return const [];
    final now = DateTime.now().toUtc().toIso8601String();
    final response = await _client
        .from('announcements')
        .select('*, venue_zones(name, code), institutions(name)')
        .eq('institution_id', institutionId)
        .eq('status', 'active')
        .lte('published_at', now)
        .or('expires_at.is.null,expires_at.gt.$now')
        .order('published_at', ascending: false);

    return (response as List<dynamic>)
        .map((row) => Announcement.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// A single announcement for the details page, including its institution
  /// name. Returns null when the announcement no longer exists.
  Future<Announcement?> getAnnouncementById(String id) async {
    final response = await _client
        .from('announcements')
        .select('*, venue_zones(name, code), institutions(name)')
        .eq('id', id)
        .maybeSingle();
    if (response == null) return null;
    return Announcement.fromJson(response);
  }

  RealtimeChannel subscribeToAnnouncements(
    void Function() onChanged, {
    required String institutionId,
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
