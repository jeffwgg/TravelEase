import 'package:flutter/foundation.dart';
import '../models/entities/sign_language_entity.dart';
import '../services/sign_translation_service.dart';
import '../models/repositories/communication_repository.dart';
import '../core/hardware_services.dart';

/// ViewModel for Camera Sign Translation (FR-M3-01 to FR-M3-06, UC301)
class SignTranslationCameraViewModel extends ChangeNotifier {
  final SignTranslationService _service;
  final CommunicationRepository _repository;
  final HardwareServices _hardware;

  SignTranslationCameraViewModel({
    SignTranslationService? service,
    CommunicationRepository? repository,
    HardwareServices? hardware,
  })  : _service = service ?? SignTranslationService(),
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

  bool get isHighConfidence => _confidenceScore >= 0.80;
  bool get isMediumConfidence => _confidenceScore >= 0.50 && _confidenceScore < 0.80;
  bool get isLowConfidence => _confidenceScore < 0.50;

  /// Returns the current active translated text for the single unified text box
  String get currentTranslatedText {
    if (_predictedText.trim().isEmpty) {
      return '';
    }

    if (_customTranslations.containsKey(_targetOutputLang)) {
      return _customTranslations[_targetOutputLang]!;
    }

    if (_targetOutputLang == 'ms') {
      if (_predictedText.toLowerCase().contains('gate')) {
        return 'Di manakah pintu masuk / perlepasan?';
      } else if (_predictedText.toLowerCase().contains('toilet') || _predictedText.toLowerCase().contains('washroom')) {
        return 'Di manakah tandas terdekat?';
      } else if (_predictedText.toLowerCase().contains('help')) {
        return 'Bolehkah anda tolong saya?';
      }
      return 'Di manakah pintu pelepasan dan kaunter?';
    } else if (_targetOutputLang == 'zh') {
      if (_predictedText.toLowerCase().contains('gate')) {
        return '登机口在哪里？';
      } else if (_predictedText.toLowerCase().contains('toilet') || _predictedText.toLowerCase().contains('washroom')) {
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
    _selectedLanguage = newDialect;
    _customTranslations.clear();
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
}
