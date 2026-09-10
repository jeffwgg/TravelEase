enum EnvironmentSoundType {
  alarm,
  siren,
  vehicleHorn,
  doorbell,
  speechAnnouncement,
}

enum SoundSensitivity { high, balanced, low }

extension EnvironmentSoundTypeDetails on EnvironmentSoundType {
  String get title => switch (this) {
    EnvironmentSoundType.alarm => 'Alarm',
    EnvironmentSoundType.siren => 'Emergency Siren',
    EnvironmentSoundType.vehicleHorn => 'Vehicle Horn',
    EnvironmentSoundType.doorbell => 'Doorbell or Knock',
    EnvironmentSoundType.speechAnnouncement => 'Spoken Announcement',
  };

  String get description => switch (this) {
    EnvironmentSoundType.alarm => 'Smoke alarms, fire alarms and warning beeps',
    EnvironmentSoundType.siren => 'Emergency vehicle and public warning sirens',
    EnvironmentSoundType.vehicleHorn => 'Car, train, truck and air horns',
    EnvironmentSoundType.doorbell =>
      'Doorbells, entrance chimes and door knocks',
    EnvironmentSoundType.speechAnnouncement =>
      'Public-address speech and narrated announcements only',
  };
}

extension SoundSensitivityDetails on SoundSensitivity {
  String get title => switch (this) {
    SoundSensitivity.high => 'High',
    SoundSensitivity.balanced => 'Balanced',
    SoundSensitivity.low => 'Low',
  };

  double get threshold => switch (this) {
    SoundSensitivity.high => 0.14,
    SoundSensitivity.balanced => 0.24,
    SoundSensitivity.low => 0.38,
  };
}

class EnvironmentSoundDetection {
  final EnvironmentSoundType type;
  final String modelLabel;
  final double score;
  final DateTime detectedAt;

  const EnvironmentSoundDetection({
    required this.type,
    required this.modelLabel,
    required this.score,
    required this.detectedAt,
  });

  Map<String, dynamic> toJson() => {
    'type': type.name,
    'modelLabel': modelLabel,
    'score': score,
    'detectedAt': detectedAt.toIso8601String(),
  };

  factory EnvironmentSoundDetection.fromJson(Map<String, dynamic> json) {
    return EnvironmentSoundDetection(
      type: EnvironmentSoundType.values.firstWhere(
        (value) => value.name == json['type'],
        orElse: () => EnvironmentSoundType.alarm,
      ),
      modelLabel: json['modelLabel'] as String? ?? 'Environmental sound',
      score: (json['score'] as num?)?.toDouble() ?? 0,
      detectedAt:
          DateTime.tryParse(json['detectedAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class SoundDetectionSnapshot {
  final String label;
  final double score;
  final double inputLevel;

  const SoundDetectionSnapshot({
    required this.label,
    required this.score,
    required this.inputLevel,
  });

  static const idle = SoundDetectionSnapshot(
    label: 'Waiting for sound',
    score: 0,
    inputLevel: 0,
  );
}
