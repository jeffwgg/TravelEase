import 'package:flutter/foundation.dart';

import '../models/entities/announcement.dart';
import '../models/entities/spoken_announcement.dart';
import '../models/repositories/announcement_repository.dart';
import '../models/repositories/feature_usage_repository.dart';
import '../models/repositories/spoken_announcement_repository.dart';
import '../services/translation_service.dart';

/// State and use-cases for a Module 2 announcement detail screen.
class AnnouncementDetailsViewModel extends ChangeNotifier {
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
      if (resolved != null)
        FeatureUsageTracker.instance.completed(TrackedFeature.announcements);
    } catch (_) {
      isLoading = false;
      error = 'Announcement could not be loaded.';
    }
    notifyListeners();
  }

  Future<void> selectLanguage(String value) async {
    language = value;
    translationError = null;
    final current = announcement;
    notifyListeners();
    if (current == null ||
        value == 'en' ||
        deviceTranslations.containsKey(value) ||
        (current.translations[value]?.title.isNotEmpty == true &&
            current.translations[value]?.message.isNotEmpty == true))
      return;
    isTranslating = true;
    notifyListeners();
    try {
      final sourceTitle = capture == null
          ? current.title
          : CapturedAnnouncement.deriveTitle(capture!.transcript);
      final sourceMessage = capture?.transcript ?? current.messageEn;
      final sourceLanguage = capture == null
          ? 'en'
          : await _translator.detectLanguage(sourceMessage);
      final translated = await Future.wait([
        _translator.translateText(
          text: sourceTitle,
          fromLang: sourceLanguage,
          toLang: value,
        ),
        _translator.translateText(
          text: sourceMessage,
          fromLang: sourceLanguage,
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
