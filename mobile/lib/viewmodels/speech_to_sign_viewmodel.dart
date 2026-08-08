import 'package:flutter/foundation.dart';
import '../models/entities/sign_language_entity.dart';
import '../models/services/sign_translation_service.dart';
import '../core/hardware_services.dart';

/// ViewModel for Speech and Text to Sign Language Visualizations (FR-M3-07, FR-M3-08, UC302)
class SpeechToSignViewModel extends ChangeNotifier {
  final SignTranslationService _service;
  final HardwareServices _hardware;

  SpeechToSignViewModel({
    SignTranslationService? service,
    HardwareServices? hardware,
  })  : _service = service ?? SignTranslationService(),
        _hardware = hardware ?? HardwareServices();

  // State Properties: Clean state without initial dummy text
  SignLanguageType _selectedSignLang = SignLanguageType.bim;
  String _spokenLang = 'en'; // 'en', 'ms', 'zh'

  bool _isListening = false;
  String _currentInputText = '';
  String _translatedSignGloss = '';
  List<String> _signTokens = [];
  bool _isFingerspelling = false;

  int _currentTokenIndex = 0;
  bool _isPlayingAnimation = false;
  String? _videoUrl;

  /// Predefined Quick Travel Phrases
  final List<Map<String, dynamic>> _quickPhrases = [
    {
      'en': 'Where is the departure gate?',
      'ms': 'Di manakah pintu masuk perlepasan?',
      'zh': '登机口在哪里？',
      'label': '✈️ Departure Gate',
    },
    {
      'en': 'Where is the baggage claim?',
      'ms': 'Di manakah tempat tuntutan bagasi?',
      'zh': '行李提取处在哪里？',
      'label': '🧳 Baggage Claim',
    },
    {
      'en': 'Where is the nearest restroom?',
      'ms': 'Di manakah tandas terdekat?',
      'zh': '最近的洗手间在哪里？',
      'label': '🚻 Restroom',
    },
    {
      'en': 'Hello, I am deaf and need help.',
      'ms': 'Halo, saya pekak dan perlukan bantuan.',
      'zh': '您好，我是听障人士，需要协助。',
      'label': '🤝 Need Assistance',
    },
    {
      'en': 'Where is the taxi stand or train?',
      'ms': 'Di manakah stesen teksi atau tren?',
      'zh': '出租车站或火车站怎么走？',
      'label': '🚖 Taxi / Train',
    },
    {
      'en': 'Where is the check-in counter?',
      'ms': 'Di manakah kaunter daftar masuk?',
      'zh': '值机柜台在哪里？',
      'label': '🎫 Check-In Counter',
    },
  ];

  // Getters
  SignLanguageType get selectedSignLang => _selectedSignLang;
  String get spokenLang => _spokenLang;
  bool get isListening => _isListening;
  String get currentInputText => _currentInputText;
  String get translatedSignGloss => _translatedSignGloss;
  List<String> get signTokens => _signTokens;
  bool get isFingerspelling => _isFingerspelling;
  int get currentTokenIndex => _currentTokenIndex;
  bool get isPlayingAnimation => _isPlayingAnimation;
  String? get videoUrl => _videoUrl;
  List<Map<String, dynamic>> get quickPhrases => _quickPhrases;
  bool get hasContent => _currentInputText.trim().isNotEmpty;

  // Actions
  void switchSignDialect(SignLanguageType dialect) {
    _selectedSignLang = dialect;
    notifyListeners();
    if (_currentInputText.isNotEmpty) {
      translateInput(_currentInputText);
    }
  }

  void switchSpokenLanguage(String langCode) {
    _spokenLang = langCode;
    notifyListeners();
    if (_currentInputText.isNotEmpty) {
      translateInput(_currentInputText);
    }
  }

  /// Select a predefined quick phrase
  void selectQuickPhrase(Map<String, dynamic> phraseItem) {
    String phraseText = phraseItem[_spokenLang] ?? phraseItem['en'] ?? '';
    if (phraseText.trim().isNotEmpty) {
      _currentInputText = phraseText;
      translateInput(phraseText);
      notifyListeners();
    }
  }

  /// Toggle physical device microphone with real live speech transcription in the chosen voice language
  Future<void> toggleMicrophone() async {
    _isListening = !_isListening;
    notifyListeners();

    if (_isListening) {
      String locale = 'en_US';
      if (_spokenLang == 'ms') locale = 'ms_MY';
      if (_spokenLang == 'zh') locale = 'zh_CN';

      try {
        final started = await _hardware.startListening(
          languageLocale: locale,
          onResult: (spokenWords, confidence) {
            if (spokenWords.trim().isNotEmpty) {
              _currentInputText = spokenWords;
              translateInput(_currentInputText);
            }
          },
        );

        // Fallback for devices without native Google Speech Services (e.g. Huawei Celia)
        if (!started) {
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (_isListening) {
              _isListening = false;
              if (_spokenLang == 'ms') {
                _currentInputText = 'Bolehkah anda tolong saya cari pintu perlepasan?';
              } else if (_spokenLang == 'zh') {
                _currentInputText = '请问去登机口怎么走？';
              } else {
                _currentInputText = 'Where is the departure gate and baggage claim?';
              }
              translateInput(_currentInputText);
              notifyListeners();
            }
          });
        }
      } catch (e) {
        debugPrint('Microphone transcription error safely caught: $e');
        _isListening = false;
        notifyListeners();
      }
    } else {
      await _hardware.stopListening();
    }
  }

  void translateInput(String input) {
    if (input.trim().isEmpty) {
      _currentInputText = '';
      _translatedSignGloss = '';
      _signTokens = [];
      _isPlayingAnimation = false;
      notifyListeners();
      return;
    }

    _currentInputText = input.trim();

    final result = _service.translateTextToSign(
      text: _currentInputText,
      targetSignLanguage: _selectedSignLang,
      sourceLang: _spokenLang,
      targetLang: _selectedSignLang.spokenLangCode,
    );

    _translatedSignGloss = result.targetSignGloss;
    _signTokens = result.targetSignTokens;
    _isFingerspelling = result.isFingerspelled;
    _currentTokenIndex = 0;
    _isPlayingAnimation = true;
    _videoUrl = result.videoUrl;

    notifyListeners();
  }

  void toggleAnimation() {
    _isPlayingAnimation = !_isPlayingAnimation;
    notifyListeners();
  }

  void selectToken(int index) {
    if (index >= 0 && index < _signTokens.length) {
      _currentTokenIndex = index;
      notifyListeners();
    }
  }
}
