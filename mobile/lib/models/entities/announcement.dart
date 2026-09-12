class Announcement {
  final String id;
  final String institutionId;
  final String? zoneId;
  final String title;
  final String messageEn;
  final String type;
  final String priority;
  final String status;
  final String? zoneName;
  final String? institutionName;
  final DateTime publishedAt;
  final Map<String, AnnouncementTranslation> translations;

  /// 'official' for institution-published rows, 'captured' for
  /// microphone-captured public announcements (FR-M2-09).
  final String source;

  /// Composite confidence of a captured announcement, 0..1. Null for official.
  final double? confidence;

  const Announcement({
    required this.id,
    required this.institutionId,
    required this.title,
    required this.messageEn,
    required this.type,
    required this.priority,
    required this.status,
    required this.publishedAt,
    this.zoneId,
    this.zoneName,
    this.institutionName,
    this.translations = const {},
    this.source = 'official',
    this.confidence,
  });

  bool get isCaptured => source == 'captured';

  factory Announcement.fromJson(Map<String, dynamic> json) {
    final zone = json['venue_zones'];
    final institution = json['institutions'];
    final rawTranslations = json['translations'];
    final translations = <String, AnnouncementTranslation>{};
    if (rawTranslations is Map<String, dynamic>) {
      for (final entry in rawTranslations.entries) {
        if (entry.value is Map<String, dynamic>) {
          translations[entry.key] = AnnouncementTranslation.fromJson(entry.value as Map<String, dynamic>);
        }
      }
    }

    return Announcement(
      id: json['id'] as String,
      institutionId: json['institution_id'] as String,
      zoneId: json['zone_id'] as String?,
      title: json['title'] as String,
      messageEn: json['message_en'] as String,
      type: json['announcement_type'] as String,
      priority: json['priority'] as String,
      status: json['status'] as String,
      zoneName: zone is Map<String, dynamic> ? zone['name'] as String? : null,
      institutionName: institution is Map<String, dynamic>
          ? institution['name'] as String?
          : null,
      publishedAt: DateTime.parse((json['published_at'] ?? json['created_at']) as String).toLocal(),
      translations: translations,
    );
  }

  bool get isUrgent => priority == 'urgent' || priority == 'high';
}

class AnnouncementTranslation {
  final String title;
  final String message;

  const AnnouncementTranslation({required this.title, required this.message});

  factory AnnouncementTranslation.fromJson(Map<String, dynamic> json) {
    return AnnouncementTranslation(
      title: json['title'] as String? ?? '',
      message: json['message'] as String? ?? '',
    );
  }
}
