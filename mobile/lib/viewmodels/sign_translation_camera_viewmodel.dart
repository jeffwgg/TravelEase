import 'package:flutter/foundation.dart';
import '../models/entities/sign_language_entity.dart';
import '../services/asl_tflite_service.dart';
import '../services/bim_sign_recognition_service.dart';
import '../services/bim_tflite_service.dart';
import '../services/sign_frame_data.dart';
import '../models/repositories/communication_repository.dart';
import '../core/hardware_services.dart';
import '../services/translation_service.dart';

/// ViewModel for Camera Sign Translation (Alphabet Fingerspelling & Words)
class SignTranslationCameraViewModel extends ChangeNotifier {
  final CommunicationRepository _repository;
  final HardwareServices _hardware;
  final AslTfliteService _aslTflite = AslTfliteService();
  final BimSignRecognitionService _bimRecognitionService;
  final BimTfliteService _bimTflite = BimTfliteService();

  SignTranslationCameraViewModel({
    CommunicationRepository? repository,
    HardwareServices? hardware,
    BimSignRecognitionService? bimRecognitionService,
  })  : _repository = repository ?? CommunicationRepository(),
        _hardware = hardware ?? HardwareServices(),
        _bimRecognitionService =
            bimRecognitionService ?? BimSignRecognitionService() {
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

  bool _isLoading = false;
  String? _errorMessage;
  BimSignRecognition? _lastBimRecognition;
  List<String> _bimGlosses = const [];
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
  List<String> get bimGlosses => List.unmodifiable(_bimGlosses);
  BimSignRecognition? get lastBimRecognition => _lastBimRecognition;
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

  /// Returns the active translated text or alphabet string.
  String get currentTranslatedText {
    if (_predictedText.trim().isEmpty) {
      return '';
    }

    if (_customTranslations.containsKey(_targetOutputLang)) {
      return _customTranslations[_targetOutputLang]!;
    }

    final bim = _lastBimRecognition;
    if (_selectedLanguage == SignLanguageType.bim && bim != null) {
      return switch (_targetOutputLang) {
        'zh' => bim.chinese,
        'en' => bim.english,
        _ => bim.malay,
      };
    }

    final word = _predictedText.trim();
    // Single letters (alphabet/fingerspelling) pass through directly.
    if (word.length == 1) {
      return word.toUpperCase();
    }
    if (_targetOutputLang == _sourceLang) {
      return word;
    }
    // Show the source word until the real translation lands.
    return _translationCache['$_sourceLang|$_targetOutputLang|${word.toLowerCase()}'] ?? word;
  }

  /// Language of the raw recognized word: the ASL model emits English
  /// glosses, the on-device BIM model Malay ones — translation direction
  /// follows the active dialect.
  String get _sourceLang =>
      _selectedLanguage == SignLanguageType.bim ? 'ms' : 'en';

  /// Kicks off a real translation of the recognized word into the current
  /// target language (no-op when the word is already in that language, and
  /// for single letters).
  void _requestTranslation(String word) {
    final w = word.trim();
    if (w.isEmpty || w.length == 1 || _targetOutputLang == _sourceLang) return;
    final lang = _targetOutputLang;
    final source = _sourceLang;
    final key = '$source|$lang|${w.toLowerCase()}';
    if (_translationCache.containsKey(key)) return;
    final seq = ++_translationSeq;
    _translation.translateText(text: w, fromLang: source, toLang: lang).then((translated) {
      _translationCache[key] = translated;
      // Only repaint while this exact word+language is still what's shown.
      if (seq == _translationSeq &&
          _targetOutputLang == lang &&
          _predictedText.trim().toLowerCase() == w.toLowerCase()) {
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
        // BIM words are Malay glosses from the on-device model; accumulate
        // them into the shared gloss list — the same word→phrase staging
        // the ASL flow will use once sentence assembly is unified.
        if (_selectedLanguage == SignLanguageType.bim && isNewSign) {
          final all = [..._bimGlosses, newText];
          _bimGlosses = List.unmodifiable(
              all.length > 8 ? all.sublist(all.length - 8) : all);
        }
        notifyListeners();
        if (isNewSign) _requestTranslation(newText);

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
    notifyListeners();
  }

  // Actions
  void switchDialect(SignLanguageType newDialect) {
    final wasBim = _selectedLanguage == SignLanguageType.bim;
    _selectedLanguage = newDialect;
    _customTranslations.clear();
    if (wasBim || newDialect == SignLanguageType.bim) {
      _lastBimRecognition = null;
      _bimGlosses = const [];
      _predictedText = '';
      _confidenceScore = 0;
      _isConfirmed = false;
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
    _requestTranslation(_predictedText);
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

  /// Recognise one recorded clip with the BIM-only model service.
  ///
  /// Legacy HTTP path kept for reference/debugging: live recognition now
  /// runs fully on-device (see CameraLandmarkExtractorService.bimMode), so
  /// nothing calls this unless wired back in.
  Future<void> recognizeBimVideo(String videoPath) async {
    if (_selectedLanguage != SignLanguageType.bim) return;

    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await _bimRecognitionService.recognizeVideo(
        videoPath: videoPath,
        previousGlosses: _bimGlosses,
      );
      _lastBimRecognition = result;
      _bimGlosses = result.glosses;
      _predictedText = result.malay;
      _confidenceScore = result.confidence;
      _customTranslations.clear();
      _isConfirmed = false;
      _isLoading = false;
      notifyListeners();

      if (_isAutoSpeakEnabled) {
        await speakAloud();
      }
    } on BimSignRecognitionException catch (e) {
      _errorMessage = e.message;
      _isLoading = false;
      notifyListeners();
    } catch (_) {
      _errorMessage = 'Unable to recognise this BIM sign. Please try again.';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Starts a new BIM phrase without changing ASL/CSL state or settings.
  void clearBimPhrase() {
    if (_selectedLanguage != SignLanguageType.bim) return;
    _lastBimRecognition = null;
    _bimGlosses = const [];
    _predictedText = '';
    _confidenceScore = 0;
    _customTranslations.clear();
    _isConfirmed = false;
    _errorMessage = null;
    notifyListeners();
  }
}
