/// Real-time sign gesture translation prediction record (UC301)
class SignTranslationPrediction {
  final String id;
  final String userId;
  final String signLanguageId; // 'BIM', 'ASL', 'CSL'
  final String predictedText;
  final String confirmedText;
  final double confidenceScore;
  final bool isEdited;
  final bool audioPlayed;
  final DateTime createdAt;

  const SignTranslationPrediction({
    required this.id,
    required this.userId,
    required this.signLanguageId,
    required this.predictedText,
    required this.confirmedText,
    required this.confidenceScore,
    this.isEdited = false,
    this.audioPlayed = false,
    required this.createdAt,
  });

  bool get isHighConfidence => confidenceScore >= 0.80;
  bool get isMediumConfidence => confidenceScore >= 0.50 && confidenceScore < 0.80;
  bool get isLowConfidence => confidenceScore < 0.50;

  factory SignTranslationPrediction.fromJson(Map<String, dynamic> json) {
    return SignTranslationPrediction(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      signLanguageId: json['sign_language_id'] as String? ?? 'BIM',
      predictedText: json['predicted_text'] as String? ?? '',
      confirmedText: json['confirmed_text'] as String? ?? '',
      confidenceScore: (json['confidence_score'] as num?)?.toDouble() ?? 0.9,
      isEdited: json['is_edited'] as bool? ?? false,
      audioPlayed: json['audio_played'] as bool? ?? false,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'sign_language_id': signLanguageId,
      'predicted_text': predictedText,
      'confirmed_text': confirmedText,
      'confidence_score': confidenceScore,
      'is_edited': isEdited,
      'audio_played': audioPlayed,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
