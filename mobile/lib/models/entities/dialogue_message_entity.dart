/// Message entity for Two-Way Dialogue stream (FR-M3-09, FR-M3-13, FR-M3-14, FR-M3-15)
class DialogueMessage {
  final String id;
  final String sessionId;
  final String senderRole; // 'traveler', 'staff', 'system'
  final String senderName;
  final String originalText;
  final String translatedText;
  final String sourceLanguage; // 'en', 'ms', 'zh'
  final String targetLanguage; // 'ms', 'en', 'zh'
  final String inputModality; // 'sign_to_text', 'speech_to_text', 'typed_text', 'quick_phrase'
  final double aiConfidenceScore;
  final bool isCorrected;
  final String? correctedText;
  final String? audioUrl;
  final DateTime createdAt;

  const DialogueMessage({
    required this.id,
    required this.sessionId,
    required this.senderRole,
    required this.senderName,
    required this.originalText,
    required this.translatedText,
    required this.sourceLanguage,
    required this.targetLanguage,
    required this.inputModality,
    this.aiConfidenceScore = 0.95,
    this.isCorrected = false,
    this.correctedText,
    this.audioUrl,
    required this.createdAt,
  });

  bool get isFromTraveler => senderRole == 'traveler';
  bool get isFromStaff => senderRole == 'staff';
  bool get isSystem => senderRole == 'system';

  /// Display text showing corrected version if available
  String get displayText => (isCorrected && correctedText != null) ? correctedText! : originalText;

  factory DialogueMessage.fromJson(Map<String, dynamic> json) {
    return DialogueMessage(
      id: json['id'] as String? ?? '',
      sessionId: json['session_id'] as String? ?? '',
      senderRole: json['sender_role'] as String? ?? 'traveler',
      senderName: json['sender_name'] as String? ?? '',
      originalText: json['original_text'] as String? ?? '',
      translatedText: json['translated_text'] as String? ?? '',
      sourceLanguage: json['source_language'] as String? ?? 'en',
      targetLanguage: json['target_language'] as String? ?? 'ms',
      inputModality: json['input_modality'] as String? ?? 'typed_text',
      aiConfidenceScore: (json['ai_confidence_score'] as num?)?.toDouble() ?? 0.95,
      isCorrected: json['is_corrected'] as bool? ?? false,
      correctedText: json['corrected_text'] as String?,
      audioUrl: json['audio_url'] as String?,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'session_id': sessionId,
      'sender_role': senderRole,
      'sender_name': senderName,
      'original_text': originalText,
      'translated_text': translatedText,
      'source_language': sourceLanguage,
      'target_language': targetLanguage,
      'input_modality': inputModality,
      'ai_confidence_score': aiConfidenceScore,
      'is_corrected': isCorrected,
      'corrected_text': correctedText,
      'audio_url': audioUrl,
      'created_at': createdAt.toIso8601String(),
    };
  }

  DialogueMessage copyWith({
    String? id,
    String? sessionId,
    String? senderRole,
    String? senderName,
    String? originalText,
    String? translatedText,
    String? sourceLanguage,
    String? targetLanguage,
    String? inputModality,
    double? aiConfidenceScore,
    bool? isCorrected,
    String? correctedText,
    String? audioUrl,
    DateTime? createdAt,
  }) {
    return DialogueMessage(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      senderRole: senderRole ?? this.senderRole,
      senderName: senderName ?? this.senderName,
      originalText: originalText ?? this.originalText,
      translatedText: translatedText ?? this.translatedText,
      sourceLanguage: sourceLanguage ?? this.sourceLanguage,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      inputModality: inputModality ?? this.inputModality,
      aiConfidenceScore: aiConfidenceScore ?? this.aiConfidenceScore,
      isCorrected: isCorrected ?? this.isCorrected,
      correctedText: correctedText ?? this.correctedText,
      audioUrl: audioUrl ?? this.audioUrl,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
