import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/entities/announcement.dart';
import '../models/entities/environment_sound.dart';
import '../models/repositories/announcement_repository.dart';
import '../models/repositories/environment_sound_repository.dart';
import '../models/repositories/spoken_announcement_repository.dart';
import '../services/environment_sound_detector.dart';
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
  bool translating = false;
  int translatedCount = 0;
  int translationTotal = 0;
  String language = 'en';
  String? error;
  String? institutionId;
  String? institutionName;
  String? serviceAreaId;
  String? serviceAreaName;
  bool isSoundMonitoring = false;
  bool isSpokenAnnouncementEnabled = false;

  bool _isSpokenFeed = false;
  bool _disposed = false;
  int _translationRunId = 0;

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
      await _loadSpokenMonitoringStatus();
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
    // Invalidate an in-flight run before changing the visible language. This
    // prevents a previous language's progress banner from remaining on screen
    // while its request finishes or times out.
    _translationRunId++;
    translating = false;
    translatedCount = 0;
    translationTotal = 0;
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
    final pending = announcements.where((announcement) {
      return announcement.translations[targetLanguage] == null &&
          !_deviceTranslations.containsKey(
            '$targetLanguage:${announcement.id}',
          );
    }).toList();
    if (pending.isEmpty) return;

    final runId = ++_translationRunId;
    translating = true;
    translatedCount = 0;
    translationTotal = pending.length;
    _notify();

    try {
      for (final announcement in pending) {
        if (_disposed ||
            language != targetLanguage ||
            runId != _translationRunId) {
          return;
        }
        final cacheKey = '$targetLanguage:${announcement.id}';
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
          if (_disposed ||
              language != targetLanguage ||
              runId != _translationRunId) {
            return;
          }
          _deviceTranslations[cacheKey] = AnnouncementTranslation(
            title: translated[0],
            message: translated[1],
          );
          translatedCount++;
          _notify();
        } catch (_) {
          // Original text remains visible if translation is unavailable.
          translatedCount++;
          _notify();
        }
      }
    } finally {
      if (!_disposed && runId == _translationRunId) {
        translating = false;
        _notify();
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
    await _translateListAnnouncements();
  }

  Future<void> loadSpokenAnnouncements() async {
    await _loadSpokenMonitoringStatus();
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
    await _translateListAnnouncements();
  }

  /// The capture pipeline requires both an active microphone monitor and the
  /// dedicated Spoken Announcement sound type. Keep these separate so the
  /// list can explain exactly why captures may not arrive.
  Future<void> _loadSpokenMonitoringStatus() async {
    final preferences = EnvironmentSoundPreferences();
    final values = await Future.wait([
      preferences.loadEnabled(),
      preferences.loadTypes(),
    ]);
    if (_disposed) return;
    final monitoringEnabled = values[0] as bool;
    final enabledTypes = values[1] as Set<EnvironmentSoundType>;
    isSoundMonitoring =
        monitoringEnabled && EnvironmentSoundDetector().isMonitoring;
    isSpokenAnnouncementEnabled = enabledTypes.contains(
      EnvironmentSoundType.speechAnnouncement,
    );
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
