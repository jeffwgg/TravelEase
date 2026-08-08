/// Sign Asset Moderation Feedback Entity (UC402 Alt A3)
class AssetFeedbackReport {
  final String id;
  final String userId;
  final String? phraseId;
  final String? signLanguageId;
  final String issueType; // 'unclear_gesture', 'broken_video', 'incorrect_gloss', 'incorrect_translation', 'other'
  final String description;
  final String status; // 'pending', 'reviewed', 'resolved'
  final DateTime createdAt;

  const AssetFeedbackReport({
    required this.id,
    required this.userId,
    this.phraseId,
    this.signLanguageId,
    required this.issueType,
    required this.description,
    this.status = 'pending',
    required this.createdAt,
  });

  factory AssetFeedbackReport.fromJson(Map<String, dynamic> json) {
    return AssetFeedbackReport(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      phraseId: json['phrase_id'] as String?,
      signLanguageId: json['sign_language_id'] as String?,
      issueType: json['issue_type'] as String? ?? 'unclear_gesture',
      description: json['description'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'phrase_id': phraseId,
      'sign_language_id': signLanguageId,
      'issue_type': issueType,
      'description': description,
      'status': status,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
