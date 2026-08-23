/// Sign Media Asset representing front/side videos and 3D animations
class SignMediaAsset {
  final String id;
  final String phraseId;
  final String signLanguageId;
  final String perspective; // 'front', 'side', 'top'
  final String videoUrl;
  final String? animationUrl;
  final String? thumbnailUrl;
  final double durationSeconds;
  final int frameCount;
  final int fps;

  const SignMediaAsset({
    required this.id,
    required this.phraseId,
    required this.signLanguageId,
    this.perspective = 'front',
    required this.videoUrl,
    this.animationUrl,
    this.thumbnailUrl,
    this.durationSeconds = 3.0,
    this.frameCount = 90,
    this.fps = 30,
  });

  bool get isFrontView => perspective.toLowerCase() == 'front';
  bool get isSideView => perspective.toLowerCase() == 'side';

  factory SignMediaAsset.fromJson(Map<String, dynamic> json) {
    return SignMediaAsset(
      id: json['id'] as String? ?? '',
      phraseId: json['phrase_id'] as String? ?? '',
      signLanguageId: json['sign_language_id'] as String? ?? 'BIM',
      perspective: json['perspective'] as String? ?? 'front',
      videoUrl: json['video_url'] as String? ?? '',
      animationUrl: json['animation_url'] as String?,
      thumbnailUrl: json['thumbnail_url'] as String?,
      durationSeconds: (json['duration_seconds'] as num?)?.toDouble() ?? 3.0,
      frameCount: (json['frame_count'] as num?)?.toInt() ?? 90,
      fps: (json['fps'] as num?)?.toInt() ?? 30,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'phrase_id': phraseId,
      'sign_language_id': signLanguageId,
      'perspective': perspective,
      'video_url': videoUrl,
      'animation_url': animationUrl,
      'thumbnail_url': thumbnailUrl,
      'duration_seconds': durationSeconds,
      'frame_count': frameCount,
      'fps': fps,
    };
  }
}
