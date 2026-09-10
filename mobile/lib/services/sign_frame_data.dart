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
/// in portrait-normalized coordinates (0..1), already mirror-compensated.
/// When [hasMediaPipeHand] is false the hand was synthesized from pose
/// landmarks and finger angles are unreliable.
///
/// [hand2] carries the SECOND detected hand when both are visible (null
/// otherwise) — two-handed signs need both slots of the GISLR tensor.
///
/// [pose] holds up to 33 ML Kit pose landmarks in [PoseLandmarkType.values]
/// order — identical to BlazePose order, i.e. the GISLR dataset's pose
/// landmarks 0-32; null where undetected. All coordinates are in the same
/// portrait-normalized space as the hands.
class SignFrameData {
  final List<SGPoint> hand;
  final List<SGPoint>? hand2;
  final SignAnchors anchors;
  final List<SGPoint?> pose;
  final bool hasMediaPipeHand;
  final bool isFrontCamera;
  final int timestampMs;

  const SignFrameData({
    required this.hand,
    this.hand2,
    required this.anchors,
    this.pose = const [],
    required this.hasMediaPipeHand,
    required this.isFrontCamera,
    required this.timestampMs,
  });

  Map<String, dynamic> toJson() => {
        'hand': hand.map((p) => p.toJson()).toList(),
        'hand2': hand2?.map((p) => p.toJson()).toList(),
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
        hand2: j['hand2'] == null
            ? null
            : (j['hand2'] as List)
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

/// Indices into [SignFrameData.pose] for the wrist entries (BlazePose order).
const int kPoseLeftWristIndex = 15;
const int kPoseRightWristIndex = 16;

/// Face-mesh landmark groups the GISLR model's feature selection reads.
/// Filling them from pose anchors (see [buildGislrTensor]) recovered
/// face-anchored signs like cat/hot/no that were lost when the whole face
/// region was NaN (11/12 vs 8/12 on recorded test clips).
const List<int> kMeshNosePoints = [1, 2, 98, 327];
const List<int> kMeshLeftEyePoints = [
  263, 249, 390, 373, 374, 380, 381, 382, 362, 466, 388, 387, 386, 385, 384, 398,
];
const List<int> kMeshRightEyePoints = [
  33, 7, 163, 144, 145, 153, 154, 155, 133, 246, 161, 160, 159, 158, 157, 173,
];
const List<int> kMeshLipPoints = [
  0, 61, 185, 40, 39, 37, 267, 269, 270, 409, 291, 146, 91, 181, 84, 17, 314,
  405, 321, 375, 78, 191, 80, 81, 82, 13, 312, 311, 310, 415, 95, 88, 178, 87,
  14, 317, 402, 318, 324, 308,
];

/// BlazePose indices for the anchors used in face synthesis.
const int kPoseNoseIndex = 0;
const int kPoseLeftEyeIndex = 2;
const int kPoseRightEyeIndex = 5;
const int kPoseLeftMouthIndex = 9;
const int kPoseRightMouthIndex = 10;

/// Builds the flat 543x3 landmark tensor in the Kaggle GISLR dataset column
/// order the model was trained on:
///
///   face mesh 0-467, left hand 468-488 (21),
///   pose 489-521 (33 BlazePose), right hand 522-542 (21).
///
/// The app has no face mesh, but the face points the model actually reads
/// (nose, eyes, lips — its feature subset) are synthesized from the pose
/// anchors: nose/eyes map directly, the lip line interpolates between the
/// mouth corners. Remaining face points stay NaN — the model's preprocessing
/// treats NaN as missing and stays accurate. Filling them with 0.0 instead
/// reads as a real landmark at the origin and destroys accuracy.
///
/// Coordinates are the raw screen-normalized values already carried by
/// [SignFrameData] (x,y in 0..1, mirror-compensated, z as reported) — the
/// dataset itself stores raw MediaPipe coordinates with NaN for missing
/// landmarks, so no extra normalization is applied.
List<double> buildGislrTensor(SignFrameData frame) {
  final tensor = List<double>.filled(543 * 3, double.nan);

  void setPt(int landmarkIndex, SGPoint? p) {
    if (p == null) return;
    final idx = landmarkIndex * 3;
    if (idx + 2 < tensor.length) {
      tensor[idx] = p.x;
      tensor[idx + 1] = p.y;
      tensor[idx + 2] = p.z;
    }
  }

  SGPoint? poseAt(int i) => i < frame.pose.length ? frame.pose[i] : null;

  // Pose 33 points at slots 489-521 — ML Kit's PoseLandmarkType order
  // matches BlazePose order.
  for (int i = 0; i < frame.pose.length && i < 33; i++) {
    setPt(489 + i, frame.pose[i]);
  }

  // Both hands into the slots matching their anatomical sides. When only
  // one hand is tracked it takes its matched side; the other stays NaN.
  final sides = _assignHandSides(frame);
  void writeHand(List<SGPoint>? hand, bool left) {
    if (hand == null) return;
    final base = left ? 468 : 522;
    for (int i = 0; i < hand.length && i < 21; i++) {
      setPt(base + i, hand[i]);
    }
  }

  writeHand(frame.hand, sides.$1);
  writeHand(frame.hand2, sides.$2);

  // Synthesize the face points the model reads from pose anchors.
  final nose = poseAt(kPoseNoseIndex);
  if (nose != null) {
    for (final i in kMeshNosePoints) {
      setPt(i, nose);
    }
  }
  final leftEye = poseAt(kPoseLeftEyeIndex);
  if (leftEye != null) {
    for (final i in kMeshLeftEyePoints) {
      setPt(i, leftEye);
    }
  }
  final rightEye = poseAt(kPoseRightEyeIndex);
  if (rightEye != null) {
    for (final i in kMeshRightEyePoints) {
      setPt(i, rightEye);
    }
  }
  final mouthL = poseAt(kPoseLeftMouthIndex);
  final mouthR = poseAt(kPoseRightMouthIndex);
  if (mouthL != null && mouthR != null) {
    final n = kMeshLipPoints.length;
    for (int k = 0; k < n; k++) {
      final t = n > 1 ? k / (n - 1) : 0.0;
      setPt(
        kMeshLipPoints[k],
        SGPoint(
          mouthL.x + (mouthR.x - mouthL.x) * t,
          mouthL.y + (mouthR.y - mouthL.y) * t,
          mouthL.z + (mouthR.z - mouthL.z) * t,
        ),
      );
    }
  }

  return tensor;
}

/// Assigns anatomical sides to the tracked hands.
///
/// Returns `(primaryIsLeft, secondaryIsLeft)`. Hand and pose landmarks share
/// the same mirror compensation, so nearest-wrist matching is orientation-
/// safe; the fallback is screen side (after mirror compensation the signer's
/// left side maps to x > 0.5). With both hands visible, each matches its
/// nearest pose wrist; ties are broken in favor of the primary hand and the
/// secondary takes the opposite side so the two never collide.
(bool, bool) _assignHandSides(SignFrameData frame) {
  SGPoint? leftWrist;
  SGPoint? rightWrist;
  if (frame.pose.length > kPoseRightWristIndex) {
    leftWrist = frame.pose[kPoseLeftWristIndex];
    rightWrist = frame.pose[kPoseRightWristIndex];
  }

  bool isLeft(SGPoint wrist) {
    if (leftWrist != null && rightWrist != null) {
      return wrist.dist2D(leftWrist) <= wrist.dist2D(rightWrist);
    }
    return wrist.x > 0.5;
  }

  final primaryLeft = isLeft(frame.hand[0]);
  if (frame.hand2 == null || frame.hand2!.isEmpty) {
    return (primaryLeft, !primaryLeft);
  }

  var secondaryLeft = isLeft(frame.hand2![0]);
  if (secondaryLeft == primaryLeft) secondaryLeft = !primaryLeft;
  return (primaryLeft, secondaryLeft);
}
