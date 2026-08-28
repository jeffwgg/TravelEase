import 'dart:math' as math;

/// Lightweight immutable 3D point used across the sign recognition pipeline.
class SGPoint {
  final double x, y, z;
  const SGPoint(this.x, this.y, [this.z = 0.0]);

  SGPoint operator -(SGPoint o) => SGPoint(x - o.x, y - o.y, z - o.z);
  SGPoint operator +(SGPoint o) => SGPoint(x + o.x, y + o.y, z + o.z);

  double dist(SGPoint o) => math.sqrt(
        (x - o.x) * (x - o.x) + (y - o.y) * (y - o.y) + (z - o.z) * (z - o.z),
      );

  double dist2D(SGPoint o) => math.sqrt((x - o.x) * (x - o.x) + (y - o.y) * (y - o.y));

  Map<String, num> toJson() => {'x': x, 'y': y, 'z': z};

  static SGPoint fromJson(Map<String, dynamic> j) => SGPoint(
        (j['x'] as num).toDouble(),
        (j['y'] as num).toDouble(),
        (j['z'] as num?)?.toDouble() ?? 0.0,
      );
}

/// Body/face anchor set for one frame, in screen-normalized coordinates
/// (0..1, mirror-compensated for the front camera).
class SignAnchors {
  final SGPoint? nose;
  final SGPoint? leftEar;
  final SGPoint? rightEar;
  final SGPoint? mouthCenter;
  final SGPoint? eyeCenter;
  final SGPoint? chestCenter;
  final SGPoint? leftShoulder;
  final SGPoint? rightShoulder;

  /// Horizontal body center (midpoint of shoulders), null if unknown.
  final double? bodyCenterX;

  const SignAnchors({
    this.nose,
    this.leftEar,
    this.rightEar,
    this.mouthCenter,
    this.eyeCenter,
    this.chestCenter,
    this.leftShoulder,
    this.rightShoulder,
    this.bodyCenterX,
  });

  Map<String, dynamic> toJson() => {
        'nose': nose?.toJson(),
        'leftEar': leftEar?.toJson(),
        'rightEar': rightEar?.toJson(),
        'mouthCenter': mouthCenter?.toJson(),
        'eyeCenter': eyeCenter?.toJson(),
        'chestCenter': chestCenter?.toJson(),
        'leftShoulder': leftShoulder?.toJson(),
        'rightShoulder': rightShoulder?.toJson(),
        'bodyCenterX': bodyCenterX,
      };

  static SignAnchors fromJson(Map<String, dynamic> j) => SignAnchors(
        nose: _pt(j['nose']),
        leftEar: _pt(j['leftEar']),
        rightEar: _pt(j['rightEar']),
        mouthCenter: _pt(j['mouthCenter']),
        eyeCenter: _pt(j['eyeCenter']),
        chestCenter: _pt(j['chestCenter']),
        leftShoulder: _pt(j['leftShoulder']),
        rightShoulder: _pt(j['rightShoulder']),
        bodyCenterX: (j['bodyCenterX'] as num?)?.toDouble(),
      );

  static SGPoint? _pt(dynamic v) =>
      v == null ? null : SGPoint.fromJson((v as Map).cast<String, dynamic>());
}

/// One processed camera frame ready for recognition or recording.
///
/// [hand] always contains 21 points in MediaPipe layout
/// (0=wrist, 1-4=thumb, 5-8=index, 9-12=middle, 13-16=ring, 17-20=pinky),
/// in screen-normalized coordinates (0..1), already mirror-compensated.
/// When [hasMediaPipeHand] is false the hand was synthesized from pose
/// landmarks and finger angles are unreliable.
///
/// [pose] holds up to 33 ML Kit pose landmarks (same order as
/// [PoseLandmarkType] values is NOT guaranteed — the extractor fills the
/// holistic pose indices it needs; null where undetected).
class SignFrameData {
  final List<SGPoint> hand;
  final SignAnchors anchors;
  final List<SGPoint?> pose;
  final bool hasMediaPipeHand;
  final bool isFrontCamera;
  final int timestampMs;

  const SignFrameData({
    required this.hand,
    required this.anchors,
    this.pose = const [],
    required this.hasMediaPipeHand,
    required this.isFrontCamera,
    required this.timestampMs,
  });

  Map<String, dynamic> toJson() => {
        'hand': hand.map((p) => p.toJson()).toList(),
        'anchors': anchors.toJson(),
        'pose': pose.map((p) => p?.toJson()).toList(),
        'hasMediaPipeHand': hasMediaPipeHand,
        'isFrontCamera': isFrontCamera,
        'timestampMs': timestampMs,
      };

  static SignFrameData fromJson(Map<String, dynamic> j) => SignFrameData(
        hand: (j['hand'] as List)
            .map((p) => SGPoint.fromJson((p as Map).cast<String, dynamic>()))
            .toList(),
        anchors: SignAnchors.fromJson((j['anchors'] as Map).cast<String, dynamic>()),
        pose: ((j['pose'] as List?) ?? const [])
            .map((p) => p == null ? null : SGPoint.fromJson((p as Map).cast<String, dynamic>()))
            .toList(),
        hasMediaPipeHand: j['hasMediaPipeHand'] as bool? ?? false,
        isFrontCamera: j['isFrontCamera'] as bool? ?? true,
        timestampMs: j['timestampMs'] as int? ?? 0,
      );
}
