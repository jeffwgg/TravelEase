import 'package:flutter/foundation.dart';
import '../models/entities/sign_language_entity.dart';
import '../services/asl_tflite_service.dart';
import '../services/bim_tflite_service.dart';
import '../services/travel_phrase_assembler.dart';
import '../services/sign_frame_data.dart';
import '../models/repositories/communication_repository.dart';
import '../core/hardware_services.dart';
import '../services/translation_service.dart';

/// ViewModel for Camera Sign Translation (Alphabet Fingerspelling & Words)
class SignTranslationCameraViewModel extends ChangeNotifier {
  final CommunicationRepository _repository;
  final HardwareServices _hardware;
  final AslTfliteService _aslTflite = AslTfliteService();
  final BimTfliteService _bimTflite = BimTfliteService();

  SignTranslationCameraViewModel({
    CommunicationRepository? repository,
    HardwareServices? hardware,
  })  : _repository = repository ?? CommunicationRepository(),
        _hardware = hardware ?? HardwareServices() {
    _initServices();
  }

  Future<void> _initServices() async {
    await _hardware.initialize();
    await _aslTflite.initialize();
    notifyListeners();
  }

  // State Properties - ASL First and English Output First by Default
  bool _isDetecting = true;
  bool _isHandDetected = false;
  SignLanguageType _selectedLanguage = SignLanguageType.asl;
  String _predictedText = ''; // Real recognized character/word
  double _confidenceScore = 0.0;
  bool _isConfirmed = false;
  bool _isPlayingAudio = false;

  /// Which landmark source is driving recognition:
  /// 'mediapipe' | 'pose-synth' | 'none' | '' (unknown yet).
  String _trackingSource = '';

  /// Latest 21-point hand skeleton (screen-normalized, mirror-compensated)
  /// and face/body anchors — rendered as a debug overlay on the camera.
  List<SGPoint> _handPoints = const [];
  SignAnchors? _handAnchors;
  bool _handFromMediaPipe = false;

  /// Target Output Text Language (Default: English 'en' matching ASL)
  String _targetOutputLang = 'en';

  /// Custom overrides per language if edited by the user
  final Map<String, String> _customTranslations = {};

  /// Auto-speak toggle
  bool _isAutoSpeakEnabled = false;

  bool _isLoading = false; // ignore: prefer_final_fields — kept mutable for future async flows
  String? _errorMessage;

  // Shared word→sentence pipeline (both dialects): recognized glosses
  // accumulate in [recognizedWords]; the assembler turns them into a
  // complete travel phrase shown in the sentence box and spoken by TTS.
  static const int _maxWords = 8;
  final TravelPhraseAssembler _phrases = TravelPhraseAssembler();
  List<String> _words = const [];
  AssembledPhrase _phrase = AssembledPhrase.empty;
  DateTime _lastPredictionTime = DateTime.now();

  // Getters
  bool get isDetecting => _isDetecting;
  bool get isHandDetected => _isHandDetected;
  SignLanguageType get selectedLanguage => _selectedLanguage;
  String get predictedText => _predictedText;
  double get confidenceScore => _confidenceScore;
  bool get isConfirmed => _isConfirmed;
  bool get isPlayingAudio => _isPlayingAudio;
  bool get isAutoSpeakEnabled => _isAutoSpeakEnabled;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String get targetOutputLang => _targetOutputLang;
  bool get hasContent => _predictedText.trim().isNotEmpty;
  bool get isAslModelLoaded => _aslTflite.isModelLoaded;
  bool get isBimRecognitionActive => _selectedLanguage == SignLanguageType.bim;

  /// Recognized gloss words accumulated for the current phrase (both
  /// dialects) — shown in the words box.
  List<String> get recognizedWords => List.unmodifiable(_words);
  String get wordsText => _words.join(' ');

  /// The assembled travel phrase — shown in the sentence box and spoken.
  AssembledPhrase get phrase => _phrase;
  bool get phraseMatched => _phrase.matched;
  String get trackingSource => _trackingSource;
  List<SGPoint> get handPoints => _handPoints;
  SignAnchors? get handAnchors => _handAnchors;
  bool get handFromMediaPipe => _handFromMediaPipe;

  bool get isHighConfidence => _confidenceScore >= 0.80;
  bool get isMediumConfidence =>
      _confidenceScore >= 0.50 && _confidenceScore < 0.80;
  bool get isLowConfidence => _confidenceScore < 0.50;

  /// Real machine translation (same Google web endpoint as the dialogue
  /// flow); results are cached per word+language so re-recognizing a word
  /// never re-hits the network.
  final TranslationService _translation = TranslationService();
  final Map<String, String> _translationCache = {};
  int _translationSeq = 0;

  /// The sentence-box text, in the active output language. Matched phrases
  /// carry their own MS/EN/ZH translations (template table — no network);
  /// an unmatched word list falls back to machine translation, cached as
  /// before. Single fingerspelled letters pass through directly.
  String get currentTranslatedText {
    if (_predictedText.trim().isEmpty) {
      return '';
    }

    if (_customTranslations.containsKey(_targetOutputLang)) {
      return _customTranslations[_targetOutputLang]!;
    }

    if (_words.isEmpty && _predictedText.trim().length == 1) {
      return _predictedText.trim().toUpperCase();
    }

    final phrase = _phrase;
    if (phrase.matched) {
      return phrase.forLang(_targetOutputLang);
    }
    final sourceText = phrase.words.join(' ');
    if (_targetOutputLang == phrase.sourceLang) {
      return sourceText;
    }
    // Show the source words until the real translation lands.
    return _translationCache[
            '${phrase.sourceLang}|$_targetOutputLang|$sourceText'] ??
        sourceText;
  }

  /// Translate the accumulated word list when no template matched
  /// (matched templates already include every language).
  void _requestPhraseTranslation() {
    if (_phrase.matched) return;
    final source = _phrase.sourceLang;
    final lang = _targetOutputLang;
    if (lang == source) return;
    final text = _phrase.words.join(' ');
    if (text.isEmpty) return;
    final key = '$source|$lang|$text';
    if (_translationCache.containsKey(key)) return;
    final seq = ++_translationSeq;
    _translation
        .translateText(text: text, fromLang: source, toLang: lang)
        .then((translated) {
      _translationCache[key] = translated;
      if (seq == _translationSeq &&
          _targetOutputLang == lang &&
          _phrase.words.join(' ') == text) {
        notifyListeners();
      }
    });
  }

  /// Live vision frame callback from camera stream (Real-time sign recognition)
  void onLiveFrameRecognized({
    required bool hasHand,
    required String gestureText,
    required double confidence,
    String trackingSource = '',
    List<SGPoint>? handPoints,
    SignAnchors? anchors,
    bool handFromMediaPipe = false,
  }) {
    final now = DateTime.now();
    _isHandDetected = hasHand;
    if (trackingSource.isNotEmpty) _trackingSource = trackingSource;
    _handPoints = handPoints ?? const [];
    _handAnchors = anchors;
    _handFromMediaPipe = handFromMediaPipe;

    if (hasHand && gestureText.trim().isNotEmpty) {
      final newText = gestureText.trim();
      // New sign replaces immediately; identical repeats are rate-limited.
      final isNewSign = newText != _predictedText;
      if (isNewSign || now.difference(_lastPredictionTime).inMilliseconds > 800) {
        _lastPredictionTime = now;
        _predictedText = newText;
        _confidenceScore = confidence;
        _customTranslations.clear();
        _isConfirmed = false;
        // Both dialects accumulate words; the shared assembler turns the
        // set into the sentence shown below the words box.
        if (isNewSign) {
          final all = [..._words, newText.toLowerCase()];
          _words = all.length > _maxWords
              ? List.unmodifiable(all.sublist(all.length - _maxWords))
              : List.unmodifiable(all);
          _phrase = _phrases.assemble(
              _selectedLanguage == SignLanguageType.bim ? 'bim' : 'asl',
              _words);
        }
        notifyListeners();
        if (isNewSign) _requestPhraseTranslation();

        if (_isAutoSpeakEnabled && hasContent) {
          speakAloud();
        }
      }
    }
    // Recognition went quiet: the last recognized word STAYS displayed until
    // the next recognized word replaces it or the user clears it manually.
  }

  /// Debug-only: directly set a known letter/word (accuracy harness tray).
  /// This does NOT touch the TFLite model — the previous implementation fed a
  /// zero-filled tensor into a temporal model and always produced a garbage
  /// class regardless of the camera image.
  void debugCaptureLetter(String letterKey) {
    _isHandDetected = true;
    _predictedText = letterKey.trim().toUpperCase();
    _confidenceScore = 1.0;
    _customTranslations.clear();
    _isConfirmed = false;
    notifyListeners();

    if (_isAutoSpeakEnabled && hasContent) {
      speakAloud();
    }
  }

  /// Clear current recognized text
  void clearText() {
    _predictedText = '';
    _confidenceScore = 0.0;
    _customTranslations.clear();
    _words = const [];
    _phrase = AssembledPhrase.empty;
    _errorMessage = null;
    notifyListeners();
  }

  // Actions
  void switchDialect(SignLanguageType newDialect) {
    final changed = newDialect != _selectedLanguage;
    _selectedLanguage = newDialect;
    _customTranslations.clear();
    if (changed) {
      // Words/sentence are per-dialect: BIM glosses are Malay, ASL words
      // English — never carry a half-built phrase across the switch.
      _predictedText = '';
      _confidenceScore = 0;
      _isConfirmed = false;
      _words = const [];
      _phrase = AssembledPhrase.empty;
    }
    if (newDialect == SignLanguageType.bim) {
      // Warm the on-device model while the user hasn't tapped yet;
      // initialize() is idempotent and cheap on subsequent calls.
      _bimTflite.initialize();
    }
    notifyListeners();
  }

  /// Switch target output text language (e.g. 'en', 'ms', 'zh')
  void switchTargetOutputLang(String langCode) {
    _targetOutputLang = langCode;
    _requestPhraseTranslation();
    notifyListeners();

    if (_isAutoSpeakEnabled && hasContent) {
      speakAloud();
    }
  }

  void toggleDetection() {
    _isDetecting = !_isDetecting;
    if (!_isDetecting) {
      _isHandDetected = false;
    }
    notifyListeners();
  }

  void toggleAutoSpeak() {
    _isAutoSpeakEnabled = !_isAutoSpeakEnabled;
    notifyListeners();

    if (_isAutoSpeakEnabled && hasContent) {
      speakAloud();
    }
  }

  void updateActiveTranslatedText(String newText) {
    if (newText.trim().isEmpty) return;
    _customTranslations[_targetOutputLang] = newText.trim();
    if (_targetOutputLang == 'en' || _predictedText.isEmpty) {
      _predictedText = newText.trim();
    }
    _confidenceScore = 1.0;
    _isConfirmed = false;
    notifyListeners();

    if (_isAutoSpeakEnabled) {
      speakAloud();
    }
  }

  Future<void> confirmPrediction() async {
    if (!hasContent) return;
    _isConfirmed = true;
    notifyListeners();

    await _repository.recordSignTranslationPrediction(
      userId: 'demo_user',
      signLanguageId: _selectedLanguage.code,
      predictedText: _predictedText,
      confirmedText: currentTranslatedText,
      confidenceScore: _confidenceScore,
      isEdited: _confidenceScore == 1.0,
      audioPlayed: _isAutoSpeakEnabled || _isPlayingAudio,
    );

    if (_isAutoSpeakEnabled) {
      speakAloud();
    }
  }

  Future<void> speakAloud() async {
    if (!hasContent) return;
    _isPlayingAudio = true;
    notifyListeners();

    try {
      final textToSpeak = currentTranslatedText;
      if (textToSpeak.trim().isNotEmpty) {
        await _hardware.speak(
          text: textToSpeak,
          language: _targetOutputLang,
          speed: 1.0,
          volume: 1.0,
        );
      }
    } catch (e) {
      debugPrint('TTS Error: $e');
    } finally {
      _isPlayingAudio = false;
      notifyListeners();
    }
  }

  /// Optional simulation method for testing/fallback gesture triggering
  Future<void> simulateGestureRecognition({String? keyPhrase}) async {
    _isHandDetected = true;
    _predictedText = keyPhrase ?? 'HELLO';
    _confidenceScore = 0.95;
    _customTranslations.clear();
    _isConfirmed = false;
    notifyListeners();

    if (_isAutoSpeakEnabled && hasContent) {
      await speakAloud();
    }
  }

  @override
  void dispose() {
    _aslTflite.dispose();
    _bimTflite.dispose();
    super.dispose();
  }

  // The legacy HTTP BIM path (recognizeBimVideo) and the BIM-only
  // clearBimPhrase are retired: recognition is live and on-device for both
  // dialects, and clearText() resets the shared words + sentence state.
}
