import 'announcement.dart';

/// A public-address announcement captured through the microphone (FR-M2-08,
/// FR-M2-09). The device hears an announcement, transcribes it and validates
/// it with the keyword/repetition scorer. Captured announcements are stored
/// device-locally and rendered in the separate spoken-announcement feed.
class CapturedAnnouncement {
  final String id;

  /// Kept only to read captures created by older app versions. New captures
  /// are device-wide and do not require an active venue session.
  final String? institutionId;
  final String title;
  final String transcript;
  final String originalTranscript;
  final bool isAiRefined;
  final String language;
  final double confidence;
  final double detectionScore;
  final int keywordHits;
  final int repetitionCount;
  final DateTime firstCapturedAt;
  final DateTime lastCapturedAt;

  const CapturedAnnouncement({
    required this.id,
    this.institutionId,
    required this.title,
    required this.transcript,
    required this.originalTranscript,
    required this.isAiRefined,
    required this.language,
    required this.confidence,
    required this.detectionScore,
    required this.keywordHits,
    required this.repetitionCount,
    required this.firstCapturedAt,
    required this.lastCapturedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'institutionId': institutionId,
    'title': title,
    'transcript': transcript,
    'originalTranscript': originalTranscript,
    'isAiRefined': isAiRefined,
    'language': language,
    'confidence': confidence,
    'detectionScore': detectionScore,
    'keywordHits': keywordHits,
    'repetitionCount': repetitionCount,
    'firstCapturedAt': firstCapturedAt.toIso8601String(),
    'lastCapturedAt': lastCapturedAt.toIso8601String(),
  };

  factory CapturedAnnouncement.fromJson(Map<String, dynamic> json) =>
      CapturedAnnouncement(
        id: json['id'] as String,
        institutionId: json['institutionId'] as String?,
        title:
            json['title'] as String? ??
            deriveTitle(json['transcript'] as String? ?? ''),
        transcript: json['transcript'] as String,
        originalTranscript:
            json['originalTranscript'] as String? ??
            json['transcript'] as String,
        isAiRefined: json['isAiRefined'] as bool? ?? false,
        language: json['language'] as String? ?? 'en',
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
        detectionScore: (json['detectionScore'] as num?)?.toDouble() ?? 0,
        keywordHits: json['keywordHits'] as int? ?? 0,
        repetitionCount: json['repetitionCount'] as int? ?? 1,
        firstCapturedAt:
            DateTime.tryParse(json['firstCapturedAt'] as String? ?? '') ??
            DateTime.now(),
        lastCapturedAt:
            DateTime.tryParse(json['lastCapturedAt'] as String? ?? '') ??
            DateTime.now(),
      );

  /// Renders the capture through the shared [Announcement] entity so the home
  /// preview, the announcement list and the details page can treat official
  /// and captured announcements uniformly.
  Announcement toAnnouncement() => Announcement(
    id: id,
    institutionId: institutionId ?? '',
    title: title,
    messageEn: transcript,
    type: 'captured',
    priority: 'normal',
    status: 'active',
    publishedAt: lastCapturedAt,
    source: 'captured',
    confidence: confidence,
  );

  static String deriveTitle(String transcript) {
    final cleaned = transcript.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) return 'Captured announcement';
    final firstChunk = cleaned
        .split(RegExp(r'[.,!?,;]'))
        .map((part) => part.trim())
        .firstWhere((part) => part.isNotEmpty, orElse: () => cleaned);
    var title = firstChunk.isEmpty ? cleaned : firstChunk;
    if (title.length > 60) {
      final cut = title.substring(0, 60);
      final lastSpace = cut.lastIndexOf(' ');
      title = '${lastSpace > 30 ? cut.substring(0, lastSpace) : cut}…';
    }
    return title;
  }
}
