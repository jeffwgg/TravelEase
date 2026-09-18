import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/entities/announcement.dart';
import '../models/entities/spoken_announcement.dart';
import '../models/repositories/announcement_repository.dart';
import '../models/repositories/feature_usage_repository.dart';
import '../models/repositories/spoken_announcement_repository.dart';
import '../services/translation_service.dart';

/// State and use-cases for a Module 2 announcement detail screen.
class AnnouncementDetailsViewModel extends ChangeNotifier {
  static const _languageKey = 'announcement_language';
  AnnouncementDetailsViewModel({
    AnnouncementRepository? repository,
    TranslationService? translator,
  }) : _repository = repository ?? AnnouncementRepository(),
       _translator = translator ?? TranslationService();

  final AnnouncementRepository _repository;
  final TranslationService _translator;
  final Map<String, AnnouncementTranslation> deviceTranslations = {};
  Announcement? announcement;
  CapturedAnnouncement? capture;
  bool isLoading = true;
  String? error;
  String language = 'en';
  bool isTranslating = false;
  String? translationError;

  Future<void> load(String id) async {
    isLoading = true;
    error = null;
    notifyListeners();
    try {
      final preferences = await SharedPreferences.getInstance();
      final savedLanguage =
          preferences.getString(_languageKey) ??
          preferences.getString('official_announcement_list_language') ??
          preferences.getString('spoken_announcement_list_language');
      if (const {'en', 'ms', 'zh'}.contains(savedLanguage)) {
        language = savedLanguage!;
      }
      final localCapture = await CapturedAnnouncementStore.instance.byId(id);
      final resolved =
          localCapture?.toAnnouncement() ??
          await _repository.getAnnouncementById(id);
      announcement = resolved;
      capture = localCapture;
      isLoading = false;
      error = resolved == null
          ? 'This announcement is no longer available.'
          : null;
      if (resolved != null) {
        FeatureUsageTracker.instance.completed(TrackedFeature.announcements);
      }
    } catch (_) {
      isLoading = false;
      error = 'Announcement could not be loaded.';
    }
    notifyListeners();
    if (announcement != null && language != 'en') {
      await selectLanguage(language);
    }
  }

  Future<void> selectLanguage(String value) async {
    language = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_languageKey, value);
    translationError = null;
    final current = announcement;
    notifyListeners();
    if (current == null ||
        value == 'en' ||
        deviceTranslations.containsKey(value) ||
        (current.translations[value]?.title.isNotEmpty == true &&
            current.translations[value]?.message.isNotEmpty == true)) {
      return;
    }
    isTranslating = true;
    notifyListeners();
    try {
      // Captured titles are short English category labels while a caption can
      // be bilingual or Malay. Translate the title using its own language.
      final sourceTitle = current.title;
      final sourceMessage = capture?.transcript ?? current.messageEn;
      final sourceMessageLanguage = capture == null
          ? 'en'
          : await _translator.detectLanguage(sourceMessage);
      final sourceTitleLanguage = await _translator.detectLanguage(sourceTitle);
      final translated = await Future.wait([
        _translator.translateText(
          text: sourceTitle,
          fromLang: sourceTitleLanguage,
          toLang: value,
        ),
        _translator.translateText(
          text: sourceMessage,
          fromLang: sourceMessageLanguage,
          toLang: value,
        ),
      ]);
      deviceTranslations[value] = AnnouncementTranslation(
        title: translated[0],
        message: translated[1],
      );
    } catch (_) {
      translationError = 'Translation failed — showing recognised text.';
    } finally {
      isTranslating = false;
      notifyListeners();
    }
  }
}
