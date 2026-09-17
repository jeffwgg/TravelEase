import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/entities/announcement.dart';
import '../models/repositories/announcement_repository.dart';
import '../models/repositories/spoken_announcement_repository.dart';
import '../services/venue_session_service.dart';

/// State and workflow for the Module 2 announcement feeds.
class AnnouncementViewModel extends ChangeNotifier {
  AnnouncementViewModel({AnnouncementRepository? repository})
    : _repository = repository ?? AnnouncementRepository();

  final AnnouncementRepository _repository;

  List<Announcement> announcements = [];
  RealtimeChannel? channel;
  bool loading = true;
  String language = 'en';
  String? error;
  String? institutionId;
  String? institutionName;
  String? serviceAreaId;
  String? serviceAreaName;

  bool _isSpokenFeed = false;
  bool _disposed = false;

  /// Starts the appropriate feed and owns its change listener for the life of
  /// this view model.
  Future<void> initialize({required bool isSpokenFeed}) async {
    _isSpokenFeed = isSpokenFeed;
    if (isSpokenFeed) {
      CapturedAnnouncementStore.instance.version.addListener(
        _onCapturedAnnouncementsChanged,
      );
      await loadSpokenAnnouncements();
      return;
    }
    VenueSessionService.instance.addListener(_onSessionChanged);
    await syncSession(reload: true);
  }

  void selectLanguage(String value) {
    if (language == value) return;
    language = value;
    _notify();
  }

  void _onSessionChanged() {
    if (_disposed) return;
    unawaited(syncSession(reload: true));
  }

  void _onCapturedAnnouncementsChanged() {
    if (_disposed) return;
    unawaited(loadSpokenAnnouncements());
  }

  /// Official announcements are institution-scoped, so this feed follows the
  /// active venue session and resubscribes whenever that session changes.
  Future<void> syncSession({required bool reload}) async {
    final session = VenueSessionService.instance.session;
    final nextInstitutionId = session?.institutionId;
    final nextServiceAreaId = session?.serviceAreaId;
    final changed =
        nextInstitutionId != institutionId ||
        nextServiceAreaId != serviceAreaId;
    institutionId = nextInstitutionId;
    institutionName = session?.institutionName;
    serviceAreaId = nextServiceAreaId;
    serviceAreaName = session?.serviceAreaName;
    _notify();

    final previous = channel;
    channel = null;
    if (previous != null) await _repository.removeSubscription(previous);
    if (_disposed) return;

    if (nextInstitutionId == null) {
      announcements = const [];
      loading = false;
      error = null;
      _notify();
      return;
    }

    channel = _repository.subscribeToAnnouncements(
      loadOfficialAnnouncements,
      institutionId: nextInstitutionId,
    );
    if (reload || changed) await loadOfficialAnnouncements();
  }

  Future<void> loadOfficialAnnouncements() async {
    final activeInstitutionId = institutionId;
    if (activeInstitutionId == null) return;
    try {
      final official = await _repository.getActiveAnnouncements(
        institutionId: activeInstitutionId,
        serviceAreaId: serviceAreaId,
      );
      if (_disposed || activeInstitutionId != institutionId) return;
      announcements = official;
      error = null;
      loading = false;
    } catch (exception) {
      if (_disposed) return;
      error = exception.toString();
      loading = false;
    }
    _notify();
  }

  Future<void> loadSpokenAnnouncements() async {
    try {
      final spoken = await CapturedAnnouncementStore.instance.announcements();
      if (_disposed) return;
      announcements = spoken;
      error = null;
      loading = false;
    } catch (exception) {
      if (_disposed) return;
      error = exception.toString();
      loading = false;
    }
    _notify();
  }

  Future<void> reload() =>
      _isSpokenFeed ? loadSpokenAnnouncements() : loadOfficialAnnouncements();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    VenueSessionService.instance.removeListener(_onSessionChanged);
    CapturedAnnouncementStore.instance.version.removeListener(
      _onCapturedAnnouncementsChanged,
    );
    final activeChannel = channel;
    channel = null;
    if (activeChannel != null) {
      unawaited(_repository.removeSubscription(activeChannel));
    }
    super.dispose();
  }
}
