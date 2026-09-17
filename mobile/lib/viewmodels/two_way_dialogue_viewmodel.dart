import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/entities/dialogue_session_entity.dart';
import '../models/entities/dialogue_message_entity.dart';
import '../models/entities/conversation_log_entity.dart';
import '../models/entities/favorite_phrase_entity.dart';
import '../models/repositories/communication_repository.dart';
import '../models/repositories/sign_reference_repository.dart';
import '../core/hardware_services.dart';
import '../core/supabase_client.dart';
import '../services/translation_service.dart';

/// ViewModel for Two-Way Split-Screen Bidirectional Dialogue (FR-M3-09 to FR-M3-18, UC303, UC304)
class TwoWayDialogueViewModel extends ChangeNotifier {
  final CommunicationRepository _repository;
  final TranslationService _translator;
  final HardwareServices _hardware;

  TwoWayDialogueViewModel({
    CommunicationRepository? repository,
    TranslationService? translator,
    HardwareServices? hardware,
  })  : _repository = repository ?? CommunicationRepository(),
        _translator = translator ?? TranslationService(),
        _hardware = hardware ?? HardwareServices() {
    _hardware.initialize();
  }

  // Supported languages selectable by the user (FR-M3-14)
  static const Map<String, String> supportedLanguages = {
    'en': 'English',
    'ms': 'Bahasa Melayu',
    'zh': '中文',
  };

  // State Properties
  DialogueSession? _currentSession;
  List<DialogueMessage> _messages = [];

  String _sourceLang = 'en'; // Traveler side language
  String _targetLang = 'ms'; // Staff side language

  SpeechSynthesisConfig _speechConfig = const SpeechSynthesisConfig(
    speed: 1.0,
    volume: 1.0,
    voiceGender: 'female',
  );

  final SignReferenceRepository _signRepository = SignReferenceRepository();
  List<FavoritePhrase> _favoritePhrases = [];
  bool _isLoadingFavorites = false;

  /// Continuous Auto-Speak / Auto-TTS mode:
  /// Once enabled by the user, newly converted or incoming messages are automatically
  /// spoken aloud through the phone speaker without needing to click the speak button every time.
  bool _isAutoTtsEnabled = true;

  /// Turn control: when ON the mic hands over to the other party's language
  /// automatically after every window; when OFF the turn only changes when
  /// the user taps the flip button (manual mode).
  bool _isAutoTurnEnabled = true;

  bool _isConversationMicActive = false;
  bool _isProcessingSpeech = false;
  bool _isRestartScheduled = false;
  // True once the engine reported 'listening' for the current window. A
  // 'done' may only hand the turn over when a window actually listened —
  // the 'done' fired right after a failed start (error_busy) belongs to a
  // window that never existed and must NOT flip the language.
  bool _windowActive = false;
  // Mic input is discarded while our TTS plays AND briefly after it ends —
  // recognizer endpointing lags behind the speaker, so results synthesized
  // from our own voice can arrive after speak() has already returned.
  DateTime _ttsGuardUntil = DateTime.fromMillisecondsSinceEpoch(0);
  int _startFailures = 0;
  String _liveTranscript = '';
  String _activeListenLang = 'en';
  String? _processingTurnLang;

  /// True while TTS playback (or its post-speech cooldown) is active.
  bool get _ttsGuarded => DateTime.now().isBefore(_ttsGuardUntil);

  // Speech-recognition health tracking (FR-M3-14): languages the recognizer
  // actively rejects at runtime are benched so the mic stops wasting turns
  // on them. Plain silence is NOT a failure — it just means nobody spoke.
  final Set<String> _unsupportedSttLangs = {};
  final Set<String> _substituteNoticeShown = {};
  final Map<String, int> _hardFailures = {};
  DateTime _lastResultCueAt = DateTime.fromMillisecondsSinceEpoch(0);

  bool _isLoading = false;
  bool _isSaving = false;
  bool _isTranslating = false;
  List<ConversationLog> _savedLogs = [];
  bool _isLoadingLogs = false;
  String? _statusMessage;

  // Getters
  DialogueSession? get currentSession => _currentSession;
  List<DialogueMessage> get messages => _messages;
  String get sourceLang => _sourceLang;
  String get targetLang => _targetLang;
  SpeechSynthesisConfig get speechConfig => _speechConfig;
  bool get isAutoTtsEnabled => _isAutoTtsEnabled;
  bool get isAutoTurnEnabled => _isAutoTurnEnabled;
  bool get isConversationMicActive => _isConversationMicActive;
  bool get isProcessingSpeech => _isProcessingSpeech;
  String get liveTranscript => _liveTranscript;
  String get activeListenLang => _activeListenLang;
  String? get processingTurnLang => _processingTurnLang;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isTranslating => _isTranslating;
  List<ConversationLog> get savedLogs => _savedLogs;
  bool get isLoadingLogs => _isLoadingLogs;
  String? get statusMessage => _statusMessage;

  List<FavoritePhrase> get favoritePhrases => _favoritePhrases;
  bool get isLoadingFavorites => _isLoadingFavorites;

  String get currentUserId =>
      SupabaseClientHelper.client.auth.currentUser?.id ?? 'local_user';

  // Actions
  Future<void> initSession() async {
    _isLoading = true;
    notifyListeners();

    try {
      _currentSession = await _repository.createDialogueSession(
        sessionCode: 'DLG_${DateTime.now().millisecondsSinceEpoch}',
        travelerId: currentUserId,
        travelerName: 'Deaf Traveler',
        staffName: 'Staff Member',
        sourceLanguage: _sourceLang,
        targetLanguage: _targetLang,
        speechConfig: _speechConfig,
      );

      _messages = await _repository.getDialogueMessages(
        _currentSession?.id ?? '',
      );

      _statusMessage = null;
      _isLoading = false;
      notifyListeners();
      loadFavorites();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadFavorites() async {
    _isLoadingFavorites = true;
    notifyListeners();
    try {
      _favoritePhrases = await _signRepository.getFavoritePhrases(currentUserId);
    } catch (e) {
      _favoritePhrases = [];
    }
    _isLoadingFavorites = false;
    notifyListeners();
  }

  Future<void> sendFavoritePhrase(FavoritePhrase fav) async {
    if (fav.phrase == null) return;
    final text = fav.phrase!.getTextByLanguage(_sourceLang);
    await sendMessage(
      text: text,
      role: 'traveler',
      modality: 'quick_phrase',
    );
  }

  /// Toggle Auto-TTS: Once ON, all subsequent messages are automatically spoken aloud.
  void toggleAutoTts() {
    _isAutoTtsEnabled = !_isAutoTtsEnabled;
    notifyListeners();
  }

  /// Toggle between automatic turn handover and manual flip control.
  void toggleAutoTurn() {
    _isAutoTurnEnabled = !_isAutoTurnEnabled;
    notifyListeners();
  }

  /// Manual turn-flip: immediately hand the mic to the other party's language.
  Future<void> flipTurn() async {
    if (!_isConversationMicActive || _isProcessingSpeech) return;
    _activeListenLang = _otherLang(_activeListenLang);
    notifyListeners();
    await _hardware.stopListening();
    await Future.delayed(const Duration(milliseconds: 250));
    await _startListenCycle(forceLang: _activeListenLang);
  }

  void swapLanguages() {
    final temp = _sourceLang;
    _sourceLang = _targetLang;
    _targetLang = temp;
    notifyListeners();
  }

  void setSourceLang(String lang) {
    if (!supportedLanguages.containsKey(lang) || lang == _sourceLang) return;
    _sourceLang = lang;
    if (_targetLang == lang) _targetLang = _sourceLang == 'en' ? 'ms' : 'en';
    notifyListeners();
  }

  void setTargetLang(String lang) {
    if (!supportedLanguages.containsKey(lang) || lang == _targetLang) return;
    _targetLang = lang;
    if (_sourceLang == lang) _sourceLang = _targetLang == 'en' ? 'ms' : 'en';
    notifyListeners();
  }

  void updateSpeechConfig({
    double? speed,
    double? volume,
    String? voiceGender,
  }) {
    _speechConfig = _speechConfig.copyWith(
      speed: speed,
      volume: volume,
      voiceGender: voiceGender,
    );
    notifyListeners();
  }

  Future<void> sendMessage({
    required String text,
    required String role, // 'traveler', 'staff'
    required String modality, // 'sign_to_text', 'speech_to_text', 'typed_text', 'quick_phrase'
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    final fromLang = role == 'traveler' ? _sourceLang : _targetLang;
    final toLang = role == 'traveler' ? _targetLang : _sourceLang;

    // FR-M3-14: translate into the other party's selected language.
    _isTranslating = true;
    notifyListeners();

    String translated;
    try {
      translated = await _translator.translateText(
        text: trimmed,
        fromLang: fromLang,
        toLang: toLang,
      );
    } finally {
      _isTranslating = false;
      notifyListeners();
    }

    final sentMsg = await _repository.sendDialogueMessage(
      sessionId: _currentSession?.id ?? '',
      senderRole: role,
      senderName: role == 'traveler' ? 'Deaf Traveler' : 'Staff Member',
      originalText: trimmed,
      translatedText: translated,
      sourceLanguage: fromLang,
      targetLanguage: toLang,
      inputModality: modality,
      aiConfidenceScore: modality == 'typed_text' ? 1.0 : 0.95,
    );

    if (sentMsg != null) {
      _messages.add(sentMsg);
      notifyListeners();

      // If auto-TTS is enabled, immediately synthesize and speak aloud through real phone speaker
      if (_isAutoTtsEnabled) {
        _playTtsAudio(translated, toLang);
      }
    } else {
      _statusMessage = 'Message could not be delivered.';
      notifyListeners();
    }
  }

  Future<void> correctMessage({
    required String messageId,
    required String correctedText,
  }) async {
    if (correctedText.trim().isEmpty) return;
    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;
    final msg = _messages[index];

    // Re-translate the corrected sentence so the translation always matches
    // the fixed text instead of keeping the stale original translation.
    var updated =
        msg.copyWith(isCorrected: true, correctedText: correctedText.trim());
    try {
      final retranslated = await _translator.translateText(
        text: correctedText.trim(),
        fromLang: msg.sourceLanguage,
        toLang: msg.targetLanguage,
      );
      updated = updated.copyWith(translatedText: retranslated);
    } catch (e) {
      debugPrint('Re-translate corrected text failed: $e');
    }

    await _repository.correctDialogueMessage(
      messageId: messageId,
      correctedText: correctedText.trim(),
      correctedTranslation: updated.translatedText,
    );

    _messages[index] = updated;
    notifyListeners();
  }

  // --------------------------------------------------------------------------
  // Continuous Conversation Mode (FR-M3-08, FR-M3-14)
  // Strict turn-based two-party dialogue: the mic listens in ONE selected
  // language per turn; when the speaker finishes (or the turn times out) it
  // hands over directly to the other party's language. No language guessing.
  // --------------------------------------------------------------------------

  /// Toggle the always-on conversation microphone.
  Future<void> toggleConversationMic() async {
    if (_isConversationMicActive) {
      _isConversationMicActive = false;
      _windowActive = false;
      _liveTranscript = '';
      notifyListeners();
      unawaited(_hardware.playListenStopCue());
      await _hardware.stopListening();
      return;
    }

    _isConversationMicActive = true;
    _liveTranscript = '';
    // The traveler's side always opens the conversation.
    _activeListenLang = _sourceLang;
    // Fresh session: give every language a fair chance again (device-level
    // unsupported languages stay benched — that capability does not change).
    _hardFailures.clear();
    debugPrint(
        'Device STT locales: ${_hardware.installedSttLocales.join(', ')}');
    notifyListeners();
    // One 'ding' for the whole listening session — not per internal restart —
    // so the cue signals 'mic on' without becoming repetitive.
    unawaited(_hardware.playListenStartCue());
    // The first turn follows the user's selected source language exactly.
    await _startListenCycle(forceLang: _sourceLang);
  }

  String _sttLocaleFor(String lang) {
    switch (lang) {
      case 'ms':
        return 'ms_MY';
      case 'zh':
        return 'zh_CN';
      default:
        return 'en_US';
    }
  }

  /// Strict two-party turns: after every completed window — a captured
  /// sentence OR plain silence — the mic hands over DIRECTLY to the other
  /// selected language. No language guessing anywhere: whatever is heard
  /// during a window belongs 100% to that window's language.
  /// In manual mode (auto-turn off) the mic stays on the current turn until
  /// the user flips it with the turn button.
  String _nextTurnLang() {
    final other = _otherLang(_activeListenLang);
    if (_isAutoTurnEnabled && _isLangUsable(other)) return other;
    if (_isLangUsable(_activeListenLang)) return _activeListenLang;
    return other;
  }

  bool _isLangUsable(String lang) => !_unsupportedSttLangs.contains(lang);

  String _langName(String code) => supportedLanguages[code] ?? code;

  String _otherLang(String lang) => lang == _sourceLang ? _targetLang : _sourceLang;

  void _announceSttIssue(String message) {
    _statusMessage = message;
    notifyListeners();
  }

  void _deactivateMic(String message) {
    _isConversationMicActive = false;
    _windowActive = false;
    _liveTranscript = '';
    _statusMessage = message;
    notifyListeners();
    unawaited(_hardware.playListenStopCue());
    _hardware.stopListening();
  }

  /// One recognition session. Restarted continuously after each sentence.
  /// [forceLang] pins the window to a specific language WITHOUT flipping:
  /// used for session start, manual flip, TTS resume, and error_busy retries
  /// (the busy retry must NOT flip — the flip already happened for that
  /// window — otherwise the turn lands back on the same language).
  Future<void> _startListenCycle({String? forceLang}) async {
    if (!_isConversationMicActive) return;

    // Recover from a recognizer still holding the microphone (e.g. it hit
    // error_speech_timeout without ever reporting 'done') instead of
    // silently returning, which would kill the continuous loop. The wait
    // also lets the engine fully release its previous session — starting
    // too early is what produces error_busy.
    if (_hardware.isListening) {
      await _hardware.stopListening();
      await Future.delayed(const Duration(milliseconds: 500));
    }

    // Strict turn-based: this window belongs entirely to whichever party's
    // turn it is — no mid-utterance language guessing.
    if (forceLang != null && _isLangUsable(forceLang)) {
      _activeListenLang = forceLang;
    } else {
      _activeListenLang = _nextTurnLang();
    }
    final listenLang = _activeListenLang;

    // Both selected languages have failed hard at runtime — stop the mic.
    if (_unsupportedSttLangs.containsAll([_sourceLang, _targetLang])) {
      _deactivateMic(
        'Speech recognition is failing for both selected languages. '
        'Please type instead.',
      );
      return;
    }

    // Prefer an installed variant (zh_CN -> zh_TW, ms_MY -> id_ID), but never
    // refuse to try: recognizers often accept languages that locales()
    // omits (freshly downloaded voice packs), so only runtime errors may
    // disqualify a language.
    final requestedLocale = _sttLocaleFor(listenLang);
    final resolvedLocale = _hardware.bestSttLocaleFor(requestedLocale);
    if (_substituteNoticeShown.add(listenLang) &&
        _localePrimary(resolvedLocale) != _localePrimary(requestedLocale)) {
      final standInName =
          supportedLanguages[_localePrimary(resolvedLocale)] ?? resolvedLocale;
      _announceSttIssue(
        '${_langName(listenLang)} is being recognized through $standInName '
        '(closest installed voice).',
      );
    }

    try {
      final started = await _hardware.startListening(
        languageLocale: resolvedLocale,
        onResult: (words, confidence) {
          // Ignore the mic while our own TTS plays (plus cooldown) so the
          // synthesized voice is never transcribed as the other party.
          if (_ttsGuarded) return;
          if (words != _liveTranscript) {
            _liveTranscript = words;
            notifyListeners();
          }
        },
        onFinalResult: (words, confidence) {
          if (_ttsGuarded) return;
          final text = words.trim();
          _liveTranscript = '';
          if (text.isNotEmpty) {
            // This language demonstrably works — clear its failure streak.
            _hardFailures.remove(_activeListenLang);
            _playResultCue();
            _processHeardSentence(text, _activeListenLang);
          } else {
            notifyListeners();
          }
        },
        onStatus: (status) {
          if (status == 'listening') {
            _windowActive = true;
            return;
          }
          if (status != 'done') return;

          // 'done' terminates a session — but only a window that actually
          // LISTENED may hand the turn over. The 'done' fired right after a
          // failed start (error_busy) belongs to a window that never existed;
          // the busy handler already scheduled the same-language retry, so
          // flipping here would produce two consecutive same-language windows.
          final hadWindow = _windowActive;
          _windowActive = false;
          if (hadWindow && _isConversationMicActive) {
            _scheduleRestart(delay: const Duration(milliseconds: 700));
          }
        },
        onError: (errorCode) {
          // error_client usually means the recognizer rejected the requested
          // locale; timeouts/no-match simply mean nobody spoke this window —
          // the turn handover covers the other language next.
          if (errorCode == 'error_client') {
            _registerHardFailure();
          }
          // error_busy: the engine is still releasing its previous session.
          // Retry the SAME language — the turn flip for this window already
          // happened; flipping again would skip the other party's turn.
          if (errorCode == 'error_busy') {
            if (_isConversationMicActive) {
              _scheduleRestart(
                delay: const Duration(milliseconds: 1200),
                language: _activeListenLang,
              );
            }
            return;
          }
          if (_isConversationMicActive) {
            _scheduleRestart();
          }
        },
      );

      if (!started) {
        _startFailures++;
        if (_startFailures >= 3) {
          _isConversationMicActive = false;
          _liveTranscript = '';
          _statusMessage =
              'Speech recognition unavailable on this device. Use the keyboard instead.';
          notifyListeners();
        } else {
          // Retry the SAME language — a failed start must not consume a turn.
          _scheduleRestart(
            delay: const Duration(milliseconds: 600),
            language: listenLang,
          );
        }
        return;
      }
      _startFailures = 0;
    } catch (e) {
      debugPrint('Conversation microphone safely caught: $e');
      _startFailures++;
      if (_startFailures >= 3) {
        _isConversationMicActive = false;
        _liveTranscript = '';
        _statusMessage = 'Microphone error. Please use the keyboard instead.';
        notifyListeners();
      } else {
        _scheduleRestart(
          delay: const Duration(milliseconds: 600),
          language: listenLang,
        );
      }
    }
  }

  void _scheduleRestart({
    Duration delay = const Duration(milliseconds: 200),
    String? language,
  }) {
    if (!_isConversationMicActive || _isRestartScheduled) return;
    _isRestartScheduled = true;
    Future.delayed(delay, () {
      _isRestartScheduled = false;
      _startListenCycle(forceLang: language);
    });
  }

  /// Capture 'ding', rate-limited so rapid successive finals (or a final
  /// followed by an instant restart) never machine-gun the sound.
  void _playResultCue() {
    final now = DateTime.now();
    if (now.difference(_lastResultCueAt) < const Duration(milliseconds: 400)) {
      return;
    }
    _lastResultCueAt = now;
    unawaited(_hardware.playListenResultCue());
  }

  static String _localePrimary(String id) =>
      id.toLowerCase().replaceAll('-', '_').split('_').first;

  /// The recognizer actively rejected this language's locale (error_client).
  /// Two rejections bench it at runtime and shift focus to the other party's
  /// language — typing remains available for the benched language.
  void _registerHardFailure() {
    final lang = _activeListenLang;
    if (_unsupportedSttLangs.contains(lang)) return;
    final count = (_hardFailures[lang] ?? 0) + 1;
    _hardFailures[lang] = count;
    if (count >= 2 && _unsupportedSttLangs.add(lang)) {
      _announceSttIssue(
        '${_langName(lang)} voice input keeps failing on this device — '
        'switching fully to ${_langName(_otherLang(lang))}. '
        'You can still type in ${_langName(lang)}.',
      );
    }
  }

  /// Processes one heard sentence as belonging to the CURRENT TURN's language
  /// (no guessing). Translation and TTS run in the background while the
  /// listening cycle restarts straight into the other party's language — the
  /// turn flip happens ONLY in the restart path, never here, so the language
  /// always changes exactly once per sentence.
  Future<void> _processHeardSentence(String text, String turnLang) async {
    if (_isProcessingSpeech) return;
    _isProcessingSpeech = true;
    _processingTurnLang = turnLang;
    _liveTranscript = '';
    notifyListeners();

    try {
      final fromLang = turnLang;
      final toLang = _otherLang(fromLang);
      final role = fromLang == _sourceLang ? 'traveler' : 'staff';

      final translated = await _translator.translateText(
        text: text,
        fromLang: fromLang,
        toLang: toLang,
      );

      final sentMsg = await _repository.sendDialogueMessage(
        sessionId: _currentSession?.id ?? '',
        senderRole: role,
        senderName: role == 'traveler' ? 'Deaf Traveler' : 'Staff Member',
        originalText: text,
        translatedText: translated,
        sourceLanguage: fromLang,
        targetLanguage: toLang,
        inputModality: 'speech_to_text',
        aiConfidenceScore: 0.9,
      );

      if (sentMsg != null) {
        _messages.add(sentMsg);
        notifyListeners();

        if (_isAutoTtsEnabled) {
          // Guard the mic during playback and for 800ms after — lagging
          // recognizer results from our own voice arrive post-speak().
          _ttsGuardUntil = DateTime.now().add(const Duration(seconds: 20));
          await _hardware.speak(
            text: translated,
            language: toLang,
            speed: _speechConfig.speed,
            volume: _speechConfig.volume,
            voiceGender: _speechConfig.voiceGender,
          );
          _ttsGuardUntil =
              DateTime.now().add(const Duration(milliseconds: 800));
        }
      }
    } catch (e) {
      debugPrint('Sentence processing error: $e');
    } finally {
      _isProcessingSpeech = false;
      _processingTurnLang = null;
      notifyListeners();
      // Make sure a listening window is open (the status handler usually
      // already restarted it during translation — don't double-start).
      if (_isConversationMicActive && !_hardware.isListening) {
        _scheduleRestart();
      }
    }
  }

  /// Sends typed text with the same auto language-detection used for speech:
  /// whatever language is typed, it is translated into the other side's language.
  Future<void> sendAutoDetectedText(
    String text, {
    String modality = 'typed_text',
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    _isTranslating = true;
    notifyListeners();

    try {
      final detected = await _translator.detectLanguage(trimmed);
      final toLang = detected == _sourceLang
          ? _targetLang
          : (detected == _targetLang ? _sourceLang : _targetLang);
      final role = detected == _sourceLang ? 'traveler' : 'staff';

      final translated = await _translator.translateText(
        text: trimmed,
        fromLang: detected,
        toLang: toLang,
      );

      final sentMsg = await _repository.sendDialogueMessage(
        sessionId: _currentSession?.id ?? '',
        senderRole: role,
        senderName: role == 'traveler' ? 'Deaf Traveler' : 'Staff Member',
        originalText: trimmed,
        translatedText: translated,
        sourceLanguage: detected,
        targetLanguage: toLang,
        inputModality: modality,
        aiConfidenceScore: modality == 'typed_text' ? 1.0 : 0.95,
      );

      if (sentMsg != null) {
        _messages.add(sentMsg);
        notifyListeners();
        if (_isAutoTtsEnabled) {
          await _playTtsAudio(translated, toLang);
        }
      } else {
        _statusMessage = 'Message could not be delivered.';
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Typed message failed: $e');
      _statusMessage = 'Could not translate the message. Please try again.';
      notifyListeners();
    } finally {
      _isTranslating = false;
      notifyListeners();
    }
  }

  /// Manually speak a single message translation aloud (FR-M3-09 spoken captions)
  void speakMessage(DialogueMessage msg) {
    _playTtsAudio(msg.translatedText, msg.targetLanguage);
  }

  /// FR-M3-17 / FR-M3-18 / UC304: save the active conversation text log to
  /// local device storage first, then best-effort sync to Supabase.
  Future<bool> endAndSaveSession() async {
    if (_messages.isEmpty) {
      _statusMessage = 'Nothing to save yet.';
      notifyListeners();
      return false;
    }

    _isSaving = true;
    notifyListeners();

    try {
      final transcript = _messages.map((m) => m.toJson()).toList();

      await _repository.saveConversationLogLocally(
        userId: currentUserId,
        sessionId: _currentSession?.id,
        logTitle:
            'Two-Way Dialogue (${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')})',
        translationType: 'two_way_dialogue',
        summary: 'Bidirectional chat saved with ${_messages.length} messages.',
        fullTranscript: transcript,
      );

      // Best-effort cloud sync; local copy is authoritative on failure.
      try {
        await _repository.saveConversationLog(
          userId: currentUserId,
          sessionId: _currentSession?.id,
          logTitle:
              'Two-Way Dialogue (${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')})',
          translationType: 'two_way_dialogue',
          summary:
              'Bidirectional chat saved with ${_messages.length} messages.',
          fullTranscript: transcript,
        );
      } catch (_) {}

      if (_currentSession != null) {
        await _repository.endDialogueSession(_currentSession!.id);
      }

      _isSaving = false;
      _statusMessage = 'Conversation log saved to this device!';
      notifyListeners();
      return true;
    } catch (e) {
      _isSaving = false;
      _statusMessage = 'Failed to save conversation log.';
      notifyListeners();
      return false;
    }
  }

  /// Load all saved conversation logs for the history view (FR-M3-17/18).
  /// Cloud first, local device storage as automatic fallback.
  Future<void> loadSavedLogs() async {
    _isLoadingLogs = true;
    notifyListeners();
    try {
      _savedLogs = await _repository.getSavedLogs(userId: currentUserId);
    } catch (_) {}
    _isLoadingLogs = false;
    notifyListeners();
  }

  Future<void> deleteSavedLog(String logId) async {
    await _repository.deleteConversationLog(logId);
    _savedLogs.removeWhere((l) => l.id == logId);
    notifyListeners();
  }

  void clearStatus() {
    _statusMessage = null;
  }

  /// Speaks text aloud; temporarily pauses continuous recognition so the
  /// microphone does not pick up the synthesized voice, then resumes it.
  Future<void> _playTtsAudio(String text, String lang) async {
    final resumeAfter = _isConversationMicActive && !_isProcessingSpeech;
    if (resumeAfter) await _hardware.stopListening();

    _ttsGuardUntil = DateTime.now().add(const Duration(seconds: 20));
    try {
      await _hardware.speak(
        text: text,
        language: lang,
        speed: _speechConfig.speed,
        volume: _speechConfig.volume,
        voiceGender: _speechConfig.voiceGender,
      );
    } finally {
      // Cooldown so lagging recognizer results from our TTS are dropped.
      _ttsGuardUntil = DateTime.now().add(const Duration(milliseconds: 800));
    }

    if (resumeAfter) await _startListenCycle(forceLang: _activeListenLang);
  }
}
