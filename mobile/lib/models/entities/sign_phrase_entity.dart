import 'sign_language_entity.dart';

/// Step-by-step physical hand and body movement instruction
class SignMovementStep {
  final int step;
  final String title;
  final String description;

  const SignMovementStep({
    required this.step,
    required this.title,
    required this.description,
  });

  factory SignMovementStep.fromJson(Map<String, dynamic> json) {
    return SignMovementStep(
      step: (json['step'] as num?)?.toInt() ?? 1,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'step': step,
      'title': title,
      'description': description,
    };
  }
}

/// Sign Dictionary Phrase Entity with multilingual translations and gloss codes
class SignPhrase {
  final String id;
  final String categoryId;
  final String phraseEn;
  final String phraseMs;
  final String phraseZh;
  final String? glossAsl;
  final String? glossBim;
  final String? glossCsl;
  final String? scenario;
  final List<SignMovementStep> stepInstructions;
  final List<String> relatedPhraseIds;
  final bool isVerified;
  final int viewCount;

  const SignPhrase({
    required this.id,
    required this.categoryId,
    required this.phraseEn,
    required this.phraseMs,
    required this.phraseZh,
    this.glossAsl,
    this.glossBim,
    this.glossCsl,
    this.scenario,
    this.stepInstructions = const [],
    this.relatedPhraseIds = const [],
    this.isVerified = true,
    this.viewCount = 0,
  });

  /// Get text based on target spoken language code ('en', 'ms', 'zh')
  String getTextByLanguage(String langCode) {
    switch (langCode.toLowerCase()) {
      case 'ms':
      case 'my':
        return phraseMs;
      case 'zh':
      case 'cn':
        return phraseZh;
      default:
        return phraseEn;
    }
  }

  /// Primary spoken-language text for the selected SignLanguageType
  /// (BIM -> Bahasa Malaysia, ASL/CSL -> English).
  String getPrimaryText(SignLanguageType type) =>
      type == SignLanguageType.bim ? phraseMs : phraseEn;

  /// Multilingual (text, TTS language code) pairs ordered so the selected
  /// dialect's language is first.
  List<(String, String)> orderedTextsWithLanguage(SignLanguageType type) {
    final primary = getPrimaryText(type);
    final all = [(phraseEn, 'en'), (phraseMs, 'ms'), (phraseZh, 'zh')];
    return [
      all.firstWhere((p) => p.$1 == primary),
      ...all.where((p) => p.$1 != primary),
    ];
  }

  /// Get sign gloss notation based on selected SignLanguageType
  String getGloss(SignLanguageType type) {
    switch (type) {
      case SignLanguageType.asl:
        return glossAsl ?? phraseEn.toUpperCase();
      case SignLanguageType.csl:
        return glossCsl ?? phraseZh;
      case SignLanguageType.bim:
        return glossBim ?? phraseMs.toUpperCase();
    }
  }

  factory SignPhrase.fromJson(Map<String, dynamic> json) {
    var rawSteps = json['step_instructions'];
    List<SignMovementStep> steps = [];
    if (rawSteps is List) {
      steps = rawSteps
          .map((s) => SignMovementStep.fromJson(Map<String, dynamic>.from(s as Map)))
          .toList();
    }

    List<String> related = [];
    if (json['related_phrase_ids'] is List) {
      related = (json['related_phrase_ids'] as List).map((e) => e.toString()).toList();
    }

    return SignPhrase(
      id: json['id'] as String? ?? '',
      categoryId: json['category_id'] as String? ?? 'general',
      phraseEn: json['phrase_en'] as String? ?? '',
      phraseMs: json['phrase_ms'] as String? ?? '',
      phraseZh: json['phrase_zh'] as String? ?? '',
      glossAsl: json['gloss_asl'] as String?,
      glossBim: json['gloss_bim'] as String?,
      glossCsl: json['gloss_csl'] as String?,
      scenario: json['scenario'] as String?,
      stepInstructions: steps,
      relatedPhraseIds: related,
      isVerified: json['is_verified'] as bool? ?? true,
      viewCount: (json['view_count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'category_id': categoryId,
      'phrase_en': phraseEn,
      'phrase_ms': phraseMs,
      'phrase_zh': phraseZh,
      'gloss_asl': glossAsl,
      'gloss_bim': glossBim,
      'gloss_csl': glossCsl,
      'scenario': scenario,
      'step_instructions': stepInstructions.map((s) => s.toJson()).toList(),
      'related_phrase_ids': relatedPhraseIds,
      'is_verified': isVerified,
      'view_count': viewCount,
    };
  }

  SignPhrase copyWith({
    String? id,
    String? categoryId,
    String? phraseEn,
    String? phraseMs,
    String? phraseZh,
    String? glossAsl,
    String? glossBim,
    String? glossCsl,
    String? scenario,
    List<SignMovementStep>? stepInstructions,
    List<String>? relatedPhraseIds,
    bool? isVerified,
    int? viewCount,
  }) {
    return SignPhrase(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      phraseEn: phraseEn ?? this.phraseEn,
      phraseMs: phraseMs ?? this.phraseMs,
      phraseZh: phraseZh ?? this.phraseZh,
      glossAsl: glossAsl ?? this.glossAsl,
      glossBim: glossBim ?? this.glossBim,
      glossCsl: glossCsl ?? this.glossCsl,
      scenario: scenario ?? this.scenario,
      stepInstructions: stepInstructions ?? this.stepInstructions,
      relatedPhraseIds: relatedPhraseIds ?? this.relatedPhraseIds,
      isVerified: isVerified ?? this.isVerified,
      viewCount: viewCount ?? this.viewCount,
    );
  }
}
