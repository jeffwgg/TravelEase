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
        // Scheduled rows remain hidden until their publish time, but are
        // included here so a mobile client can show them immediately after
        // that time even before the server's status-refresh job runs.
        .inFilter('status', const ['active', 'scheduled'])
        .lte('published_at', now);
    query = query.or('expires_at.is.null,expires_at.gt.$now');
    query = serviceAreaId == null
        ? query.isFilter('service_area_id', null)
        : query.or('service_area_id.is.null,service_area_id.eq.$serviceAreaId');
    final response = await query.order('published_at', ascending: false);

    final announcements = (response as List<dynamic>)
        .map((row) => Announcement.fromJson(row as Map<String, dynamic>))
        .toList();
    announcements.sort((first, second) {
      final priority = _priorityRank(first.priority)
          .compareTo(_priorityRank(second.priority));
      if (priority != 0) return priority;
      return second.publishedAt.compareTo(first.publishedAt);
    });
    return announcements;
  }

  static int _priorityRank(String priority) => switch (priority) {
    'urgent' => 0,
    'high' => 1,
    'normal' => 2,
    'low' => 3,
    _ => 4,
  };

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
