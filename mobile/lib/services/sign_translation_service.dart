import '../models/entities/sign_language_entity.dart';

/// Result of a 3-way sign language translation pipeline
class SignTranslationPipelineResult {
  final SignLanguageType sourceSignLanguage;
  final String sourceRecognizedText;
  final double confidenceScore;
  final String sourceSpokenLanguage; // 'en', 'ms', 'zh'
  final String targetSpokenLanguage; // 'en', 'ms', 'zh'
  final String translatedText;
  final SignLanguageType targetSignLanguage;
  final String targetSignGloss;
  final List<String> targetSignTokens;
  final bool isFingerspelled;
  final String? videoUrl;
  final String? animationUrl;

  const SignTranslationPipelineResult({
    required this.sourceSignLanguage,
    required this.sourceRecognizedText,
    required this.confidenceScore,
    required this.sourceSpokenLanguage,
    required this.targetSpokenLanguage,
    required this.translatedText,
    required this.targetSignLanguage,
    required this.targetSignGloss,
    required this.targetSignTokens,
    this.isFingerspelled = false,
    this.videoUrl,
    this.animationUrl,
  });
}

/// Core Multimodal Sign Language Translation Service supporting ASL, BIM, and CSL
class SignTranslationService {
  static final SignTranslationService _instance = SignTranslationService._internal();
  factory SignTranslationService() => _instance;
  SignTranslationService._internal();

  /// Multilingual translation matrix for core travel phrases
  static final Map<String, Map<String, String>> _translationDictionary = {
    'where is the gate': {
      'en': 'Where is the gate?',
      'ms': 'Di manakah pintu masuk / perlepasan?',
      'zh': '登机口在哪里？',
    },
    'i need to check in': {
      'en': 'I need to check in for my flight.',
      'ms': 'Saya perlu daftar masuk untuk penerbangan saya.',
      'zh': '我需要办理航班值机。',
    },
    'my flight is delayed': {
      'en': 'My flight has been delayed.',
      'ms': 'Penerbangan saya telah tertangguh.',
      'zh': '我的航班延误了。',
    },
    'i have a reservation': {
      'en': 'I have a hotel room reservation.',
      'ms': 'Saya mempunyai tempahan bilik hotel.',
      'zh': '我有酒店房间预订。',
    },
    'can i get the menu': {
      'en': 'Can I see the food menu, please?',
      'ms': 'Bolehkah saya melihat menu makanan?',
      'zh': '请问我可以看一下菜单吗？',
    },
    'i need help': {
      'en': 'I need emergency assistance.',
      'ms': 'Saya memerlukan bantuan kecemasan.',
      'zh': '我需要紧急帮助。',
    },
    'thank you very much': {
      'en': 'Thank you very much.',
      'ms': 'Terima kasih banyak-banyak.',
      'zh': '非常感谢你。',
    },
    'hello': {
      'en': 'Hello, nice to meet you.',
      'ms': 'Halo, selamat berkenalan.',
      'zh': '你好，很高兴认识你。',
    },
    'which bus goes to the city center': {
      'en': 'Which bus goes to the city center?',
      'ms': 'Bas manakah yang pergi ke pusat bandar?',
      'zh': '请问哪趟巴士开往市中心？',
    },
    'i feel sick': {
      'en': 'I feel unwell and need a doctor.',
      'ms': 'Saya berasa tidak sihat dan memerlukan doktor.',
      'zh': '我感觉不舒服，需要看医生。',
    },
  };

  /// Gloss translation per sign language
  static final Map<String, Map<SignLanguageType, String>> _glossDictionary = {
    'where is the gate': {
      SignLanguageType.asl: 'GATE WHERE ?',
      SignLanguageType.bim: 'PINTU MASUK MANA ?',
      SignLanguageType.csl: '登机口 在哪 ?',
    },
    'i need to check in': {
      SignLanguageType.asl: 'I NEED CHECK-IN TICKET',
      SignLanguageType.bim: 'SAYA PERLU DAFTAR MASUK',
      SignLanguageType.csl: '我 需要 办理 值机',
    },
    'my flight is delayed': {
      SignLanguageType.asl: 'MY FLIGHT DELAY LATE',
      SignLanguageType.bim: 'PENERBANGAN SAYA TANGGUH',
      SignLanguageType.csl: '我 航班 延误',
    },
    'i have a reservation': {
      SignLanguageType.asl: 'I HAVE ROOM BOOKING',
      SignLanguageType.bim: 'SAYA ADA TEMPAHAN BILIK',
      SignLanguageType.csl: '我 有 预订 房间',
    },
    'can i get the menu': {
      SignLanguageType.asl: 'PLEASE I SEE MENU FOOD',
      SignLanguageType.bim: 'BOLEH SAYA LIHAT MENU MAKANAN',
      SignLanguageType.csl: '可以 给我 菜单 吗',
    },
    'i need help': {
      SignLanguageType.asl: 'I NEED HELP SOS URGENT',
      SignLanguageType.bim: 'SAYA PERLU BANTUAN KECEMASAN',
      SignLanguageType.csl: '我 需要 紧急 帮助',
    },
    'thank you very much': {
      SignLanguageType.asl: 'THANK YOU VERY MUCH',
      SignLanguageType.bim: 'TERIMA KASIH BANYAK',
      SignLanguageType.csl: '非常 感谢 你',
    },
    'hello': {
      SignLanguageType.asl: 'HELLO NICE MEET YOU',
      SignLanguageType.bim: 'HALO SELAMAT JUMPA',
      SignLanguageType.csl: '你好 认识 高兴',
    },
  };

  /// Step 1: Convert captured sign gesture into Source Text with AI confidence score
  Future<Map<String, dynamic>> translateSignToText({
    required SignLanguageType sourceDialect,
    String? recognizedPhraseKey,
  }) async {
    // Simulate real-time neural vision gesture recognition
    await Future.delayed(const Duration(milliseconds: 300));

    final key = recognizedPhraseKey?.toLowerCase().trim() ?? 'where is the gate';
    final spokenCode = sourceDialect.spokenLangCode;

    String text = 'Where is the gate?';
    if (_translationDictionary.containsKey(key)) {
      text = _translationDictionary[key]![spokenCode] ?? _translationDictionary[key]!['en']!;
    } else {
      text = recognizedPhraseKey ?? 'Where is the gate?';
    }

    return {
      'text': text,
      'confidence': 0.94,
      'dialect': sourceDialect.code,
      'is_confident': true,
    };
  }

  /// Step 2: Translate text between English ('en'), Bahasa Melayu ('ms'), and Chinese ('zh')
  String translateText({
    required String text,
    required String fromLang,
    required String toLang,
  }) {
    if (fromLang.toLowerCase() == toLang.toLowerCase()) {
      return text;
    }

    final lower = text.toLowerCase().trim();
    for (var entry in _translationDictionary.entries) {
      final translations = entry.value;
      if (translations.values.any((val) => lower.contains(val.toLowerCase()) || val.toLowerCase().contains(lower))) {
        return translations[toLang] ?? translations['en'] ?? text;
      }
    }

    // Default matching fallback
    if (lower.contains('gate') || lower.contains('pintu') || lower.contains('登机口')) {
      return _translationDictionary['where is the gate']![toLang] ?? text;
    }
    if (lower.contains('check') || lower.contains('daftar') || lower.contains('值机')) {
      return _translationDictionary['i need to check in']![toLang] ?? text;
    }
    if (lower.contains('delay') || lower.contains('tangguh') || lower.contains('延误')) {
      return _translationDictionary['my flight is delayed']![toLang] ?? text;
    }
    if (lower.contains('hotel') || lower.contains('bilik') || lower.contains('房间') || lower.contains('预订')) {
      return _translationDictionary['i have a reservation']![toLang] ?? text;
    }
    if (lower.contains('menu') || lower.contains('makan') || lower.contains('菜单')) {
      return _translationDictionary['can i get the menu']![toLang] ?? text;
    }
    if (lower.contains('help') || lower.contains('bantuan') || lower.contains('sos') || lower.contains('帮助')) {
      return _translationDictionary['i need help']![toLang] ?? text;
    }
    if (lower.contains('thank') || lower.contains('terima kasih') || lower.contains('谢谢') || lower.contains('感谢')) {
      return _translationDictionary['thank you very much']![toLang] ?? text;
    }

    return text;
  }

  /// Step 3: Convert text to Target Sign Language Visualizations / Gloss / Fingerspelling
  SignTranslationPipelineResult translateTextToSign({
    required String text,
    required SignLanguageType targetSignLanguage,
    String sourceLang = 'en',
    String targetLang = 'en',
  }) {
    final lower = text.toLowerCase().trim();
    String? matchedKey;

    for (var entry in _translationDictionary.entries) {
      if (entry.value.values.any((val) => lower.contains(val.toLowerCase()) || val.toLowerCase().contains(lower))) {
        matchedKey = entry.key;
        break;
      }
    }

    if (matchedKey != null && _glossDictionary.containsKey(matchedKey)) {
      final gloss = _glossDictionary[matchedKey]![targetSignLanguage] ?? text.toUpperCase();
      final tokens = gloss.split(' ').where((s) => s.isNotEmpty).toList();

      return SignTranslationPipelineResult(
        sourceSignLanguage: SignLanguageType.bim,
        sourceRecognizedText: text,
        confidenceScore: 0.96,
        sourceSpokenLanguage: sourceLang,
        targetSpokenLanguage: targetLang,
        translatedText: text,
        targetSignLanguage: targetSignLanguage,
        targetSignGloss: gloss,
        targetSignTokens: tokens,
        isFingerspelled: false,
        videoUrl: 'https://assets.travelease.app/signs/${targetSignLanguage.code.toLowerCase()}/gesture_front.mp4',
        animationUrl: 'https://assets.travelease.app/signs/${targetSignLanguage.code.toLowerCase()}/gesture_front.glb',
      );
    }

    // Fallback: Fingerspelling (UC302 Alt A3)
    final fingerspellTokens = text
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9 ]'), '')
        .split('')
        .where((ch) => ch != ' ')
        .toList();

    return SignTranslationPipelineResult(
      sourceSignLanguage: SignLanguageType.bim,
      sourceRecognizedText: text,
      confidenceScore: 0.88,
      sourceSpokenLanguage: sourceLang,
      targetSpokenLanguage: targetLang,
      translatedText: text,
      targetSignLanguage: targetSignLanguage,
      targetSignGloss: 'FS: ${fingerspellTokens.join('-')}',
      targetSignTokens: fingerspellTokens,
      isFingerspelled: true,
    );
  }

  /// Full 3-Way End-to-End Pipeline:
  /// Sign A (e.g. ASL/BIM/CSL) -> Source Text -> Target Language Text (e.g. EN/MS/ZH) -> Sign B (e.g. CSL/BIM/ASL)
  Future<SignTranslationPipelineResult> executeFullTranslationPipeline({
    required SignLanguageType sourceSign,
    required SignLanguageType targetSign,
    required String targetSpokenLang,
    String? customInputText,
  }) async {
    // 1. Gesture Recognition
    final recognition = await translateSignToText(sourceDialect: sourceSign);
    final recognizedText = customInputText ?? (recognition['text'] as String);
    final confidence = (recognition['confidence'] as num).toDouble();

    // 2. Multilingual Text Translation
    final translatedText = translateText(
      text: recognizedText,
      fromLang: sourceSign.spokenLangCode,
      toLang: targetSpokenLang,
    );

    // 3. Target Sign Language Visual Translation
    final signResult = translateTextToSign(
      text: translatedText,
      targetSignLanguage: targetSign,
      sourceLang: sourceSign.spokenLangCode,
      targetLang: targetSpokenLang,
    );

    return SignTranslationPipelineResult(
      sourceSignLanguage: sourceSign,
      sourceRecognizedText: recognizedText,
      confidenceScore: confidence,
      sourceSpokenLanguage: sourceSign.spokenLangCode,
      targetSpokenLanguage: targetSpokenLang,
      translatedText: translatedText,
      targetSignLanguage: targetSign,
      targetSignGloss: signResult.targetSignGloss,
      targetSignTokens: signResult.targetSignTokens,
      isFingerspelled: signResult.isFingerspelled,
      videoUrl: signResult.videoUrl,
      animationUrl: signResult.animationUrl,
    );
  }
}
