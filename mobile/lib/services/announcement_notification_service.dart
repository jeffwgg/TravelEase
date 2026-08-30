import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/repositories/announcement_repository.dart';
import 'app_notification_service.dart';
import 'flash_alert_service.dart';
import 'venue_session_service.dart';

/// Listens for official announcements of the active venue session app-wide
/// (independent of which tab is open) and raises a local notification with
/// sound and a torch flash for each new announcement. Tapping the alert
/// deep-links into the announcement details page.
class AnnouncementNotificationService {
  AnnouncementNotificationService._();

  static final instance = AnnouncementNotificationService._();

  static const _seenKeyPrefix = 'notified_announcement_ids:';

  /// Announcements older than this at start-up are considered read history;
  /// only fresh ones (or realtime arrivals) alert.
  static const _freshWindow = Duration(minutes: 30);

  final AnnouncementRepository _repository = AnnouncementRepository();
  RealtimeChannel? _channel;
  String? _institutionId;

  void start() {
    VenueSessionService.instance.addListener(_onSessionChanged);
    _sync();
  }

  Future<void> _onSessionChanged() => _sync();

  Future<void> _sync() async {
    final session = VenueSessionService.instance.session;
    final institutionId = session?.institutionId;
    if (institutionId == _institutionId && _channel != null) return;
    final previous = _channel;
    _channel = null;
    _institutionId = institutionId;
    if (previous != null) await _repository.removeSubscription(previous);
    if (institutionId == null) return;
    _channel = _repository.subscribeToAnnouncements(
      _refresh,
      institutionId: institutionId,
    );
    await _refresh();
  }

  Future<void> _refresh() async {
    final institutionId = _institutionId;
    if (institutionId == null) return;
    try {
      final items = await _repository.getActiveAnnouncements(
        institutionId: institutionId,
      );
      final seen = await _loadSeen(institutionId);
      final cutoff = DateTime.now().subtract(_freshWindow);
      final fresh = items
          .where(
            (announcement) =>
                !seen.contains(announcement.id) &&
                announcement.publishedAt.isAfter(cutoff),
          )
          .toList();
      seen
        ..clear()
        ..addAll(items.map((announcement) => announcement.id));
      await _saveSeen(institutionId, seen);
      if (fresh.isEmpty) return;
      await FlashAlertService.instance.blinkTwice();
      for (final announcement in fresh) {
        await AppNotificationService.instance.showOfficialAnnouncement(
          id: announcement.id,
          title: announcement.title,
          message: announcement.messageEn,
        );
      }
    } catch (_) {
      // Announcement alerts are best-effort; the list views surface errors.
    }
  }

  Future<Set<String>> _loadSeen(String institutionId) async {
    final preferences = await SharedPreferences.getInstance();
    return (preferences.getStringList('$_seenKeyPrefix$institutionId') ??
            const [])
        .toSet();
  }

  Future<void> _saveSeen(String institutionId, Set<String> seen) async {
    final preferences = await SharedPreferences.getInstance();
    final all = seen.toList();
    final limited = all.length > 100 ? all.sublist(all.length - 100) : all;
    await preferences.setStringList(
      '$_seenKeyPrefix$institutionId',
      limited,
    );
  }
}
