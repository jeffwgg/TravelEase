import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';
import '../entities/announcement.dart';

class AnnouncementRepository {
  final SupabaseClient _client = SupabaseClientHelper.client;

  /// Official announcements published for the active service area. A null
  /// service area represents an institution-level session and receives only
  /// institution-wide announcements.
  Future<List<Announcement>> getActiveAnnouncements({
    String? institutionId,
    String? serviceAreaId,
  }) async {
    if (institutionId == null) return const [];
    final now = DateTime.now().toUtc().toIso8601String();
    var query = _client
        .from('announcements')
        .select('*, service_areas(name), institutions(name)')
        .eq('institution_id', institutionId)
        .eq('status', 'active')
        .lte('published_at', now);
    query = serviceAreaId == null
        ? query.isFilter('service_area_id', null)
        : query.or('service_area_id.is.null,service_area_id.eq.$serviceAreaId');
    final response = await query.order('published_at', ascending: false);

    return (response as List<dynamic>)
        .map((row) => Announcement.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// A single announcement for the details page, including its institution
  /// name. Returns null when the announcement no longer exists.
  Future<Announcement?> getAnnouncementById(String id) async {
    final response = await _client
        .from('announcements')
        .select('*, service_areas(name), institutions(name)')
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

  Future<void> removeSubscription(RealtimeChannel channel) =>
      _client.removeChannel(channel);
}
