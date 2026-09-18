import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/entities/announcement.dart';
import '../models/repositories/announcement_repository.dart';
import '../models/repositories/spoken_announcement_repository.dart';
import '../services/translation_service.dart';
import '../services/venue_session_service.dart';

/// State and workflow for the Module 2 announcement feeds.
class AnnouncementViewModel extends ChangeNotifier {
  AnnouncementViewModel({
    AnnouncementRepository? repository,
    TranslationService? translator,
  }) : _repository = repository ?? AnnouncementRepository(),
       _translator = translator ?? TranslationService();

  final AnnouncementRepository _repository;
  final TranslationService _translator;
  final Map<String, AnnouncementTranslation> _deviceTranslations = {};

  static const _officialLanguageKey = 'official_announcement_list_language';
  static const _spokenLanguageKey = 'spoken_announcement_list_language';

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
    final preferences = await SharedPreferences.getInstance();
    final savedLanguage = preferences.getString(
      isSpokenFeed ? _spokenLanguageKey : _officialLanguageKey,
    );
    if (const {'en', 'ms', 'zh'}.contains(savedLanguage)) {
      language = savedLanguage!;
    }
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

  Future<void> selectLanguage(String value) async {
    if (language == value) return;
    language = value;
    _notify();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _isSpokenFeed ? _spokenLanguageKey : _officialLanguageKey,
      value,
    );
    await _translateListAnnouncements();
  }

  AnnouncementTranslation? translationFor(Announcement announcement) {
    if (language == 'en') return null;
    return announcement.translations[language] ??
        _deviceTranslations['$language:${announcement.id}'];
  }

  Future<void> _translateListAnnouncements() async {
    if (language == 'en' || announcements.isEmpty || _disposed) return;
    final targetLanguage = language;
    for (final announcement in announcements) {
      if (_disposed || announcement.translations[targetLanguage] != null) {
        continue;
      }
      final cacheKey = '$targetLanguage:${announcement.id}';
      if (_deviceTranslations.containsKey(cacheKey)) continue;
      try {
        final messageLanguage = announcement.isCaptured
            ? await _translator.detectLanguage(announcement.messageEn)
            : 'en';
        final titleLanguage = announcement.isCaptured
            ? await _translator.detectLanguage(announcement.title)
            : 'en';
        final translated = await Future.wait([
          _translator.translateText(
            text: announcement.title,
            fromLang: titleLanguage,
            toLang: targetLanguage,
          ),
          _translator.translateText(
            text: announcement.messageEn,
            fromLang: messageLanguage,
            toLang: targetLanguage,
          ),
        ]);
        if (_disposed || language != targetLanguage) return;
        _deviceTranslations[cacheKey] = AnnouncementTranslation(
          title: translated[0],
          message: translated[1],
        );
        _notify();
      } catch (_) {
        // Original text remains visible if translation is unavailable.
      }
    }
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
    unawaited(_translateListAnnouncements());
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
    unawaited(_translateListAnnouncements());
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
