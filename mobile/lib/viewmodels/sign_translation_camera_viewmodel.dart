import 'package:flutter/foundation.dart';
import '../models/entities/sign_language_entity.dart';
import '../services/sign_translation_service.dart';
import '../models/repositories/communication_repository.dart';
import '../core/hardware_services.dart';

/// ViewModel for Camera Sign Translation (Alphabet Fingerspelling & Words)
class SignTranslationCameraViewModel extends ChangeNotifier {
  final SignTranslationService _service;
  final CommunicationRepository _repository;
  final HardwareServices _hardware;
  final AslTfliteService _aslTflite = AslTfliteService();

  SignTranslationCameraViewModel({
    SignTranslationService? service,
    CommunicationRepository? repository,
    HardwareServices? hardware,
  })  : _service = service ?? SignTranslationService(),
        _repository = repository ?? CommunicationRepository(),
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

  /// Last time a recognized sign arrived; the display clears after a grace
  /// period of continuous non-recognition (idle hands show nothing).
  DateTime _lastSignAt = DateTime.now();

  /// Target Output Text Language (Default: English 'en' matching ASL)
  String _targetOutputLang = 'en';

  /// Custom overrides per language if edited by the user
  final Map<String, String> _customTranslations = {};

  /// Auto-speak toggle
  bool _isAutoSpeakEnabled = false;

  final bool _isLoading = false;
  String? _errorMessage;
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
  String get trackingSource => _trackingSource;
  List<SGPoint> get handPoints => _handPoints;
  SignAnchors? get handAnchors => _handAnchors;
  bool get handFromMediaPipe => _handFromMediaPipe;

  bool get isHighConfidence => _confidenceScore >= 0.80;
  bool get isMediumConfidence => _confidenceScore >= 0.50 && _confidenceScore < 0.80;
  bool get isLowConfidence => _confidenceScore < 0.50;

  /// Returns the active translated text or alphabet string
  String get currentTranslatedText {
    if (_predictedText.trim().isEmpty) {
      return '';
    }

    if (_customTranslations.containsKey(_targetOutputLang)) {
      return _customTranslations[_targetOutputLang]!;
    }

    // Single letters (alphabet/fingerspelling) pass through directly;
    // everything else — including 2-letter words like "no" — translates.
    if (_predictedText.trim().length == 1) {
      return _predictedText.toUpperCase();
    }

    return _service.translateText(
      text: _predictedText,
      fromLang: 'en',
      toLang: _targetOutputLang,
    );
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
        _lastSignAt = now;
        notifyListeners();

        if (_isAutoSpeakEnabled && hasContent) {
          speakAloud();
        }
      } else {
        _lastSignAt = now;
      }
    } else {
      // Recognition went quiet: keep the last sign briefly (the temporal
      // path commits one frame per window), then clear so idle shows nothing.
      if (hasContent && now.difference(_lastSignAt).inMilliseconds > 1500) {
        _predictedText = '';
        _confidenceScore = 0.0;
        _customTranslations.clear();
        _isConfirmed = false;
      }
      notifyListeners();
    }
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
    _selectedLanguage = newDialect;
    _customTranslations.clear();
    notifyListeners();
  }

  /// Switch target output text language (e.g. 'en', 'ms', 'zh')
  void switchTargetOutputLang(String langCode) {
    _targetOutputLang = langCode;
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

  @override
  void dispose() {
    _aslTflite.dispose();
    super.dispose();
  }
}
