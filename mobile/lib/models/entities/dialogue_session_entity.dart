/// Configuration for Speech-to-Speech / Text-to-Speech audio synthesis (FR-M3-10, FR-M3-11, FR-M3-12)
class SpeechSynthesisConfig {
  final double speed; // 0.5x to 2.0x
  final double volume; // 0.0 to 1.0
  final String voiceGender; // 'female', 'male', 'neutral'

  const SpeechSynthesisConfig({
    this.speed = 1.0,
    this.volume = 1.0,
    this.voiceGender = 'female',
  });

  factory SpeechSynthesisConfig.fromJson(Map<String, dynamic> json) {
    return SpeechSynthesisConfig(
      speed: (json['speed'] as num?)?.toDouble() ?? 1.0,
      volume: (json['volume'] as num?)?.toDouble() ?? 1.0,
      voiceGender: json['voice_gender'] as String? ?? 'female',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'speed': speed,
      'volume': volume,
      'voice_gender': voiceGender,
    };
  }

  SpeechSynthesisConfig copyWith({
    double? speed,
    double? volume,
    String? voiceGender,
  }) {
    return SpeechSynthesisConfig(
      speed: speed ?? this.speed,
      volume: volume ?? this.volume,
      voiceGender: voiceGender ?? this.voiceGender,
    );
  }
}

/// Two-Way Bidirectional Dialogue Session (UC303)
class DialogueSession {
  final String id;
  final String sessionCode;
  final String travelerId;
  final String travelerName;
  final String staffName;
  final String travelerSignLanguage; // 'BIM', 'ASL', 'CSL'
  final String sourceLanguage; // 'en', 'ms', 'zh'
  final String targetLanguage; // 'ms', 'en', 'zh'
  final SpeechSynthesisConfig speechConfig;
  final String status; // 'active', 'completed', 'cancelled'
  final DateTime createdAt;
  final DateTime? endedAt;

  const DialogueSession({
    required this.id,
    required this.sessionCode,
    required this.travelerId,
    this.travelerName = 'Deaf Traveler',
    this.staffName = 'Staff / Hearing Individual',
    this.travelerSignLanguage = 'BIM',
    this.sourceLanguage = 'en',
    this.targetLanguage = 'ms',
    this.speechConfig = const SpeechSynthesisConfig(),
    this.status = 'active',
    required this.createdAt,
    this.endedAt,
  });

  bool get isActive => status == 'active';

  factory DialogueSession.fromJson(Map<String, dynamic> json) {
    return DialogueSession(
      id: json['id'] as String? ?? '',
      sessionCode: json['session_code'] as String? ?? '',
      travelerId: json['traveler_id'] as String? ?? '',
      travelerName: json['traveler_name'] as String? ?? 'Deaf Traveler',
      staffName: json['staff_name'] as String? ?? 'Staff / Hearing Individual',
      travelerSignLanguage: json['traveler_sign_language'] as String? ?? 'BIM',
      sourceLanguage: json['source_language'] as String? ?? 'en',
      targetLanguage: json['target_language'] as String? ?? 'ms',
      speechConfig: SpeechSynthesisConfig(
        speed: (json['speech_playback_speed'] as num?)?.toDouble() ?? 1.0,
        volume: (json['speech_playback_volume'] as num?)?.toDouble() ?? 1.0,
        voiceGender: json['speech_voice_gender'] as String? ?? 'female',
      ),
      status: json['status'] as String? ?? 'active',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      endedAt: json['ended_at'] != null
          ? DateTime.tryParse(json['ended_at'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'session_code': sessionCode,
      'traveler_id': travelerId,
      'traveler_name': travelerName,
      'staff_name': staffName,
      'traveler_sign_language': travelerSignLanguage,
      'source_language': sourceLanguage,
      'target_language': targetLanguage,
      'speech_playback_speed': speechConfig.speed,
      'speech_playback_volume': speechConfig.volume,
      'speech_voice_gender': speechConfig.voiceGender,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
    };
  }

  DialogueSession copyWith({
    String? id,
    String? sessionCode,
    String? travelerId,
    String? travelerName,
    String? staffName,
    String? travelerSignLanguage,
    String? sourceLanguage,
    String? targetLanguage,
    SpeechSynthesisConfig? speechConfig,
    String? status,
    DateTime? createdAt,
    DateTime? endedAt,
  }) {
    return DialogueSession(
      id: id ?? this.id,
      sessionCode: sessionCode ?? this.sessionCode,
      travelerId: travelerId ?? this.travelerId,
      travelerName: travelerName ?? this.travelerName,
      staffName: staffName ?? this.staffName,
      travelerSignLanguage: travelerSignLanguage ?? this.travelerSignLanguage,
      sourceLanguage: sourceLanguage ?? this.sourceLanguage,
      targetLanguage: targetLanguage ?? this.targetLanguage,
      speechConfig: speechConfig ?? this.speechConfig,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      endedAt: endedAt ?? this.endedAt,
    );
  }
}
