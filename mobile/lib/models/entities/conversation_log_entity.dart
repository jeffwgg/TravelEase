/// Stored conversation log / transcript 
class ConversationLog {
  final String id;
  final String userId;
  final String? sessionId;
  final String logTitle;
  final String translationType; // 'two_way_dialogue', 'sign_to_text'
  final String? summary;
  final List<Map<String, dynamic>> fullTranscript;
  final int messageCount;
  final DateTime createdAt;

  const ConversationLog({
    required this.id,
    required this.userId,
    this.sessionId,
    required this.logTitle,
    this.translationType = 'two_way_dialogue',
    this.summary,
    this.fullTranscript = const [],
    this.messageCount = 0,
    required this.createdAt,
  });

  factory ConversationLog.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> transcript = [];
    if (json['full_transcript'] is List) {
      transcript = (json['full_transcript'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();
    }

    return ConversationLog(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      sessionId: json['session_id'] as String?,
      logTitle: json['log_title'] as String? ?? 'Conversation Log',
      translationType: json['translation_type'] as String? ?? 'two_way_dialogue',
      summary: json['summary'] as String?,
      fullTranscript: transcript,
      messageCount: (json['message_count'] as num?)?.toInt() ?? transcript.length,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'session_id': sessionId,
      'log_title': logTitle,
      'translation_type': translationType,
      'summary': summary,
      'full_transcript': fullTranscript,
      'message_count': messageCount,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
