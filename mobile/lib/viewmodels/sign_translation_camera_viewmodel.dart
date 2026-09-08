import 'package:flutter/foundation.dart';
import '../models/entities/sign_language_entity.dart';
import '../services/bim_sign_recognition_service.dart';
import '../services/sign_translation_service.dart';
import '../models/repositories/communication_repository.dart';
import '../core/hardware_services.dart';

/// ViewModel for Camera Sign Translation (FR-M3-01 to FR-M3-06, UC301)
class SignTranslationCameraViewModel extends ChangeNotifier {
  final SignTranslationService _service;
  final BimSignRecognitionService _bimRecognitionService;
  final CommunicationRepository _repository;
  final HardwareServices _hardware;

  SignTranslationCameraViewModel({
    SignTranslationService? service,
    BimSignRecognitionService? bimRecognitionService,
    CommunicationRepository? repository,
    HardwareServices? hardware,
  }) : _service = service ?? SignTranslationService(),
       _bimRecognitionService =
           bimRecognitionService ?? BimSignRecognitionService(),
       _repository = repository ?? CommunicationRepository(),
       _hardware = hardware ?? HardwareServices() {
    _hardware.initialize();
  }

  // State Properties: No hardcoded dummy text; clean state awaiting real gesture/voice input
  bool _isDetecting = true;
  SignLanguageType _selectedLanguage = SignLanguageType.bim;
  String _predictedText = '';
  double _confidenceScore = 0.0;
  bool _isConfirmed = false;
  bool _isPlayingAudio = false;

  /// Target Output Text Language (Default: Bahasa Melayu)
  String _targetOutputLang = 'ms';

  /// Custom overrides per language if edited by the user
  final Map<String, String> _customTranslations = {};

  /// Auto-speak toggle: When enabled, automatically speaks aloud any predicted/confirmed text.
  bool _isAutoSpeakEnabled = false;

  bool _isLoading = false;
  String? _errorMessage;
  BimSignRecognition? _lastBimRecognition;
  List<String> _bimGlosses = const [];

  // Getters
  bool get isDetecting => _isDetecting;
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
  bool get isBimRecognitionActive => _selectedLanguage == SignLanguageType.bim;
  List<String> get bimGlosses => List.unmodifiable(_bimGlosses);

  bool get isHighConfidence => _confidenceScore >= 0.80;
  bool get isMediumConfidence =>
      _confidenceScore >= 0.50 && _confidenceScore < 0.80;
  bool get isLowConfidence => _confidenceScore < 0.50;

  /// Returns the current active translated text for the single unified text box
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

    if (_targetOutputLang == 'ms') {
      if (_predictedText.toLowerCase().contains('gate')) {
        return 'Di manakah pintu masuk / perlepasan?';
      } else if (_predictedText.toLowerCase().contains('toilet') ||
          _predictedText.toLowerCase().contains('washroom')) {
        return 'Di manakah tandas terdekat?';
      } else if (_predictedText.toLowerCase().contains('help')) {
        return 'Bolehkah anda tolong saya?';
      }
      return 'Di manakah pintu pelepasan dan kaunter?';
    } else if (_targetOutputLang == 'zh') {
      if (_predictedText.toLowerCase().contains('gate')) {
        return '登机口在哪里？';
      } else if (_predictedText.toLowerCase().contains('toilet') ||
          _predictedText.toLowerCase().contains('washroom')) {
        return '最近的洗手间在哪里？';
      } else if (_predictedText.toLowerCase().contains('help')) {
        return '请问能帮帮我吗？';
      }
      return '请问登机口在哪里？';
    }
    return _predictedText;
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
    notifyListeners();
  }

  /// Switch target output text language (e.g. 'ms', 'zh', 'en')
  void switchTargetOutputLang(String langCode) {
    _targetOutputLang = langCode;
    notifyListeners();

    if (_isAutoSpeakEnabled && hasContent) {
      speakAloud();
    }
  }

  void toggleDetection() {
    _isDetecting = !_isDetecting;
    notifyListeners();
  }

  /// Toggle Auto-Speak mode: once enabled, automatically speaks aloud any predicted/confirmed text.
  void toggleAutoSpeak() {
    _isAutoSpeakEnabled = !_isAutoSpeakEnabled;
    notifyListeners();

    if (_isAutoSpeakEnabled && hasContent) {
      speakAloud();
    }
  }

  /// Directly update translated text in the single unified editable area
  void updateActiveTranslatedText(String newText) {
    if (newText.trim().isEmpty) return;
    _customTranslations[_targetOutputLang] = newText.trim();
    if (_targetOutputLang == 'en' || _predictedText.isEmpty) {
      _predictedText = newText.trim();
    }
    _confidenceScore = 1.0; // Manual correction has 100% confidence
    _isConfirmed = false;
    notifyListeners();

    if (_isAutoSpeakEnabled) {
      speakAloud();
    }
  }

  /// Confirm predicted text (FR-M3-05) & save prediction history
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

  /// Synthesize spoken audio output via real device speaker
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

  /// Simulate live gesture neural tracking (FR-M3-01, FR-M3-02)
  Future<void> simulateGestureRecognition({String? keyPhrase}) async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _service.translateSignToText(
        sourceDialect: _selectedLanguage,
        recognizedPhraseKey: keyPhrase ?? 'Where is the departure gate?',
      );

      _predictedText = result['text'] as String;
      _confidenceScore = (result['confidence'] as num).toDouble();
      _customTranslations.clear();
      _isConfirmed = false;
      _isLoading = false;
      notifyListeners();

      if (_isAutoSpeakEnabled) {
        speakAloud();
      }
    } catch (e) {
      _errorMessage = 'Error detecting gesture: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Recognise one recorded clip with the BIM-only model service.
  ///
  /// This method intentionally does nothing for ASL/CSL, so their existing
  /// recognition and translation paths remain isolated from BIM networking.
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
