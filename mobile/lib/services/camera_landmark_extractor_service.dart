import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Size;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'asl_tflite_service.dart';
import 'bim_tflite_service.dart';
import 'geometric_sign_recognizer.dart';
import 'sign_clip_recorder.dart';
import 'sign_frame_data.dart';

/// Top-level function required by compute() — must not be a closure or method.
/// Accepts Uint8List planes directly (avoids wasteful .toList() copies).
Map<String, dynamic> _buildNv21Params(List<dynamic> args) {
  final yBytes   = args[0] as Uint8List;
  final uBytes   = args[1] as Uint8List;
  final vBytes   = args[2] as Uint8List;
  final width    = args[3] as int;
  final height   = args[4] as int;
  final yStride  = args[5] as int;
  final uvStride = args[6] as int;
  final uvPixel  = args[7] as int;

  final nv21 = Uint8List(width * height + (width * height ~/ 2));
  int idx = 0;
  for (int row = 0; row < height; row++) {
    final start = row * yStride;
    for (int col = 0; col < width; col++) {
      nv21[idx++] = yBytes[start + col];
    }
  }
  final uvH = height ~/ 2;
  final uvW = width ~/ 2;
  for (int row = 0; row < uvH; row++) {
    for (int col = 0; col < uvW; col++) {
      final off = row * uvStride + col * uvPixel;
      nv21[idx++] = vBytes[off];
      nv21[idx++] = uBytes[off];
    }
  }
  return {'nv21': nv21, 'width': width, 'height': height};
}

/// Extracts body/hand landmarks from live camera frames using Google ML Kit
/// Pose Detection and MediaPipe Hand Landmarker, then recognises signs via:
///
///   1. TFLITE path (primary): landmark ring buffer + motion gating; when a
///      gesture window closes, its frames (543-landmark GISLR tensors) are
///      resampled and each run through the single-frame GISLR model, with
///      the per-frame class probabilities averaged.
///   2. GEOMETRIC path (fallback): rule-based shape+anchor matching.
///
/// Also hosts the accuracy-harness clip recorder.
class CameraLandmarkExtractorService {
  final AslTfliteService _aslTflite = AslTfliteService();
  final GeometricSignRecognizer _recognizer = GeometricSignRecognizer();
  final SignClipRecorder clipRecorder = SignClipRecorder();
  PoseDetector? _poseDetector;
  HandLandmarkerPlugin? _handLandmarker;
  List<Hand> _latestHands = [];
  StreamSubscription<List<Hand>>? _handStreamSub;

  // ─── Hand-frame auto-calibration ──────────────────────────────────────
  // The hand plugin's normalized output frame differs per camera (front
  // sensorOrientation 270 vs back 90): on this device the back camera lands
  // directly in portrait space while the front camera comes out rotated/
  // mirrored. Instead of hard-coding per-camera guesses, every frame tests
  // the 8 candidate frame transforms (4 rotations x mirror) of the hand
  // wrist against the POSE wrist — pose is known-correct (anchors land on
  // the face) — and locks onto the transform that puts the hand on the body.
  int _handTransform = 0;
  int _handTransformAlt = -1;
  int _handTransformAltStreak = 0;
  static const int _handTransformSwitchAfter = 10;

  // Pose decoupled from the hand loop: cached result + staleness handling.
  Pose? _lastPose;
  int _lastPoseTs = 0;
  bool _poseRunning = false;
  static const int _poseMaxAgeMs = 200;

  /// Rolling processed-frames-per-second trace (debug log only).
  int _perfCount = 0;
  int _perfWindowStartMs = 0;
  int _perfDropped = 0;
  double _perfComputeMs = 0;
  int _perfComputeN = 0;
  double _perfFrameMs = 0;
  double _perfFrameMaxMs = 0;

  /// Called by the camera screen when a frame arrives while the previous one
  /// is still being processed (busy guard). Dropped >> 0 means the camera
  /// stream outruns the pipeline; the skeleton then updates at the PROCESSED
  /// rate, and the compute/frame numbers say what eats the difference.
  void noteFrameDropped() => _perfDropped++;

  // EMA-smoothed pose points for stable synthetic face anchors between the
  // sparse pose runs (hands move fast; the head does not).
  List<SGPoint?> _smoothedPose = const [];
  static const double _poseEmaAlpha = 0.5;

  bool _isInitialized = false;

  /// Which word classifier the motion-gated windows feed: false runs the
  /// ASL GISLR model + geometric fallback, true runs the on-device BIM
  /// model and suppresses the geometric path.
  bool get bimMode => _bimMode;
  bool _bimMode = false;

  /// Fires with the raw frames of every VALID gesture window the motion
  /// gate closes. Batch clip capture attaches this to turn "sign the word
  /// 12 times" into 12 auto-segmented labeled clips without per-tap wiring.
  void Function(List<SignFrameData> window)? onGestureWindowClosed;
  set bimMode(bool value) {
    if (_bimMode == value) return;
    _bimMode = value;
    // A dialect switch must never carry a queued result across the
    // boundary: an ASL word finalized just before the tap would otherwise
    // be consumed on the next frame and look like "ASL still recognizes in
    // BIM mode". Drop the pending word and close any half-open window.
    _lastTfliteSign = null;
    _lastTfliteTs = 0;
    _inGesture = false;
    _fastStreak = 0;
    _slowStreak = 0;
  }
  final BimTfliteService _bimTflite = BimTfliteService();

  // ─── Hand-loss state hygiene (Phase 1.5) ──────────────────────────────
  int _noHandStreak = 0;
  static const int _noHandResetAfter = 10;

  // ─── Temporal buffer + motion gating (Phase 2) ────────────────────────
  /// Ring capacity: ~5-7s of gesture history at 20-25fps.
  static const int _maxRingFrames = 150;  /// Continuous pre-roll ring buffer of landmark tensors (543 x 3), written
  /// every processed frame regardless of gate state. A gesture window is a
  /// SLICE of this buffer: [activation - preRoll, deactivation + postRoll],
  /// so the sign onset the speed trigger misses is always captured.
  /// Pre-roll as a TIME bound, not a frame count — at 6fps, 60 frames is
  /// 10 seconds of lookback, which blows past every window limit.
  static const int _preRollMs = 1200;
  final List<List<double>> _ring = [];
  final List<int> _ringTs = [];

  /// Parallel ring of raw frames (same add/evict schedule as [_ring]) so a
  /// closed window can be re-cut as [SignFrameData] for the BIM classifier,
  /// which runs its own 258-channel preprocessing.
  final List<SignFrameData> _frameRing = [];
  double? _lastWristX, _lastWristY;
  int _lastWristTs = 0;
  bool _inGesture = false;
  int _fastStreak = 0;
  int _slowStreak = 0;

  /// Window start as a TIMESTAMP, not a ring index — the ring evicts from
  /// the front, so an index drifts toward newer frames over time and the
  /// elapsed/span computation silently saturates (windows never hit the cap).
  int _gestureStartTs = 0;

  /// EMA-smoothed wrist for SPEED measurement only (raw landmarks jitter a
  /// few thousandths per frame at 15-20fps, which alone exceeds the
  /// stillness threshold and prevents windows from ever closing).
  double? _speedWristX, _speedWristY;
  static const double _speedEmaAlpha = 0.6;

  /// Wrist speed (portrait heights / second) that opens a gesture window:
  /// 2 consecutive fast frames. Low enough for calm signing.
  static const double _gestureStartSpeed = 0.35;
  static const int _gestureStartHold = 2;
  /// Wrist speed below which the gesture counts as finished. Above the raw
  /// landmark jitter once speed is EMA-smoothed, so genuine stillness closes
  /// windows again.
  static const double _gestureEndSpeed = 0.22;
  /// Consecutive slow processed frames that close a gesture window (~0.4s
  /// of genuine stillness at ~25fps).
  static const int _gestureEndHold = 10;
  /// Hard cap so one continuous motion cannot buffer forever. Short enough
  /// that even a stuck-open gate still isolates ~1-2 signs per window.
  static const int _maxGestureMs = 2500;
  /// A window shorter/cheaper than this cannot discriminate signs — skip
  /// inference, keep buffering (the next window may overlap the tail).
  static const int _minWindowFrames = 8;
  static const int _minWindowMs = 400;

  /// Margin-based acceptance: accept the temporal prediction when the
  /// top-1 softmax beats the runner-up by this margin OR top-1 alone is
  /// decisive. Sparse on-device input spreads softmax, so absolute
  /// confidence alone rejects correct answers (0.60 gate rejected all).
  static const double _minTopMargin = 0.06;
  static const double _minTopConfidence = 0.30;

  /// Upper bound on frames inferred per closed gesture window.
  static const int _maxInferenceFrames = 48;

  /// Sanity probe: if the model returns the same class at ~1.0 confidence
  /// for this many consecutive windows, the temporal path is PAUSED (not
  /// disabled): it auto-resumes after the pause or on any diverse result.
  static const int _suspectStreakLimit = 5;
  static const int _suspectPauseMs = 15000;
  int _suspectPauseUntilTs = 0;
  String _suspectClass = '';
  int _suspectStreak = 0;

  String? _lastTfliteSign;
  double _lastTfliteConf = 0.0;
  int _lastTfliteTs = 0;

  /// How long a temporal result suppresses the geometric fallback.
  static const int _temporalGraceMs = 1500;

  bool get isInitialized => _isInitialized;
  bool get isTemporalModelSuspect =>
      _suspectPauseUntilTs > DateTime.now().millisecondsSinceEpoch;

  Future<void> initialize() async {
    try {
      _poseDetector = PoseDetector(
        options: PoseDetectorOptions(
          mode: PoseDetectionMode.stream,
          model: PoseDetectionModel.base,
        ),
      );

      try {
        // Stickier detection: the default 0.5 drops the hand during fast
        // motion blur, which fragments gestures right where they matter.
        final plugin = HandLandmarkerPlugin.create(
          minHandDetectionConfidence: 0.3,
        );
        _handLandmarker = plugin;
        // 3.x runs MediaPipe LIVE_STREAM on a background thread: results
        // arrive here asynchronously, one frame after each processFrame().
        _handStreamSub = plugin.landmarkStream.listen((hands) {
          _latestHands = hands;
        });
      } catch (handErr) {
        debugPrint('[CameraLandmarkExtractor] HandLandmarker note: $handErr');
      }

      await _aslTflite.initialize();
      _isInitialized = true;
      debugPrint('[CameraLandmarkExtractor] Initialized. TFLite loaded='
          '${_aslTflite.isModelLoaded} (temporal path '
          '${_aslTflite.isModelLoaded ? "ENABLED" : "disabled"})');
    } catch (e) {
      debugPrint('[CameraLandmarkExtractor] Init error: $e');
    }
  }

  // =====================================================================
  //  PUBLIC  —  Process a single camera frame
  // =====================================================================

  /// Process a single camera frame and return sign recognition results:
  /// `{hasHand, character, confidence, trackingSource}` or null on failure.
  Future<Map<String, dynamic>?> processCameraFrame(
    CameraImage image,
    CameraDescription camera,
  ) async {
    if (!_isInitialized || _poseDetector == null) return null;

    final frameSw = Stopwatch()..start();
    try {
      // ── Pose cadence decision FIRST ────────────────────────────────────
      // The NV21 conversion (plane copies + compute round-trip, 8-17 ms)
      // is ONLY needed for the ML Kit pose input. Pose now runs ~5 Hz off
      // the critical path, so do the pixel work only on frames that
      // actually launch a pose run — previously every frame paid it and
      // ~80% of the conversions were thrown away, capping the loop at ~20
      // fps and letting the pose cache age 200-350 ms.
      final now0 = DateTime.now().millisecondsSinceEpoch;
      final runPose = (now0 - _lastPoseTs > _poseMaxAgeMs ||
              _lastPose == null) &&
          !_poseRunning;
      final w = image.width;
      final h = image.height;

      InputImage? inputImage;
      if (runPose) {
        final computeSw = Stopwatch()..start();
        final params = await compute(_buildNv21Params, <dynamic>[
          image.planes[0].bytes,
          image.planes[1].bytes,
          image.planes[2].bytes,
          image.width,
          image.height,
          image.planes[0].bytesPerRow,
          image.planes[1].bytesPerRow,
          image.planes[1].bytesPerPixel ?? 1,
        ]);
        computeSw.stop();
        _perfComputeMs += computeSw.elapsedMicroseconds / 1000.0;
        _perfComputeN++;

        inputImage = InputImage.fromBytes(
          bytes: params['nv21'] as Uint8List,
          metadata: InputImageMetadata(
            size: Size(w.toDouble(), h.toDouble()),
            rotation: _rotationFromCamera(camera),
            format: InputImageFormat.nv21,
            bytesPerRow: w,
          ),
        );
      }

      // ── Hand landmark detection (native MediaPipe, async stream) ───────
      // 3.x direct YUV→ARGB conversion, no JPEG round-trip; the result for
      // this frame lands on _latestHands via landmarkStream.
      try {
        _handLandmarker?.processFrame(image, camera.sensorOrientation);
      } catch (e) {
        debugPrint('[CameraLandmarkExtractor] HandLandmarker error: $e');
      }

      // ── Pose detection (decoupled cadence, fire-and-forget) ────────────
      // The CPU pose run is the largest single cost on low-end devices
      // (60-150 ms); awaiting it inside this serialized callback would stall
      // the whole hand loop, so the fresh result lands whenever it's ready
      // while every frame keeps flowing on the cached pose.
      if (runPose && inputImage != null) {
        _poseRunning = true;
        _poseDetector!.processImage(inputImage).then((poses) {
          if (poses.isNotEmpty) {
            _lastPose = poses.first;
            _lastPoseTs = DateTime.now().millisecondsSinceEpoch;
          }
        }, onError: (e) {
          debugPrint('[CameraLandmarkExtractor] pose error: $e');
        }).whenComplete(() => _poseRunning = false);
      }
      final pose = _lastPose;
      if (pose == null) {
        _handleNoHand();
        return _result(false, '', 0, 'none');
      }
      final isFront = camera.lensDirection == CameraLensDirection.front;
      final now = DateTime.now().millisecondsSinceEpoch;
      // ML Kit returns landmarks in the rotated frame; 90°/270° sensors swap
      // the effective width/height used for normalization.
      _poseFrameSwapped = camera.sensorOrientation == 90 ||
          camera.sensorOrientation == 270;

      // ── Build the normalized frame (hand + anchors) ────────────────────
      final frameData = _buildFrameData(pose, w, h, isFront, now);
      if (frameData == null) {
        _handleNoHand();
        return _result(false, '', 0, 'none');
      }

      // Accuracy-harness recording hook.
      if (clipRecorder.isRecording) {
        clipRecorder.addFrame(frameData);
      }

      // [Perf] trace: how fast the serialized camera loop actually runs.
      // If this sits far below the camera stream rate, whatever blocks the
      // loop is the thing making the skeleton lag.
      _perfCount++;
      if (_perfWindowStartMs == 0) _perfWindowStartMs = now0;
      if (now0 - _perfWindowStartMs >= 2000) {
        final secs = (now0 - _perfWindowStartMs) / 1000.0;
        final denom = _perfCount == 0 ? 1 : _perfCount;
        debugPrint('[Perf] processed ${(_perfCount / secs).toStringAsFixed(1)} fps '
            '| dropped $_perfDropped '
            '| pose-hop ${(_perfComputeMs / math.max(1, _perfComputeN)).toStringAsFixed(1)}ms $_perfComputeN '
            '| frame avg ${(_perfFrameMs / denom).toStringAsFixed(1)}ms '
            'max ${_perfFrameMaxMs.toStringAsFixed(0)}ms '
            '| pose ${_lastPose == null ? 'none' : '${now0 - _lastPoseTs}ms'}');
        _perfCount = 0;
        _perfDropped = 0;
        _perfComputeMs = 0;
        _perfComputeN = 0;
        _perfFrameMs = 0;
        _perfFrameMaxMs = 0;
        _perfWindowStartMs = now0;
      }

      // ── TEMPORAL TFLITE path (motion-gated window) ─────────────────────
      _updateMotionGate(frameData);
      String character = '';
      double confidence = 0.0;
      if (_lastTfliteSign != null) {
        character = _lastTfliteSign!;
        confidence = _lastTfliteConf;
        _lastTfliteSign = null; // consume one-shot window result
      }

      // ── GEOMETRIC path (fallback / cross-check) ────────────────────────
      // After a temporal result, let it own the screen for a grace period —
      // the static-pose fallback otherwise shouts over the model between
      // windows. BIM mode: never — these are ASL-trained rules and would
      // shout ASL words over the BIM model's output.
      final outcome = _recognizer.processFrame(frameData);
      final temporalGrace = DateTime.now().millisecondsSinceEpoch - _lastTfliteTs <
          _temporalGraceMs;
      if (!bimMode &&
          character.isEmpty &&
          !temporalGrace &&
          outcome.committedSign.isNotEmpty) {
        character = outcome.committedSign;
        confidence = outcome.committedConfidence;
      }

      frameSw.stop();
      _perfFrameMs += frameSw.elapsedMicroseconds / 1000.0;
      _perfFrameMaxMs =
          math.max(_perfFrameMaxMs, frameSw.elapsedMicroseconds / 1000.0);

      return _result(
        true,
        character,
        confidence,
        // trackingSource stays the skeleton source (mediapipe/pose-synth) —
        // the model choice is conveyed by the dialect itself.
        outcome.trackingSource,
        hand: frameData.hand,
        anchors: frameData.anchors,
        hasMediaPipeHand: frameData.hasMediaPipeHand,
      );
    } catch (e, st) {
      debugPrint('[CameraLandmarkExtractor] Frame error: $e\n$st');
      return null;
    }
  }

  Map<String, dynamic> _result(
    bool hasHand,
    String ch,
    double conf,
    String src, {
    List<SGPoint>? hand,
    SignAnchors? anchors,
    bool hasMediaPipeHand = false,
  }) =>
      {
        'hasHand': hasHand,
        'character': ch,
        'confidence': conf,
        'trackingSource': src,
        'hand': hand,
        'anchors': anchors,
        'hasMediaPipeHand': hasMediaPipeHand,
      };

  void _handleNoHand() {
    _noHandStreak++;
    // A single missed hand frame (motion blur, detector hiccup) must not kill
    // an open gesture — fast signing is exactly when the detector blinks.
    // Sustained loss CLOSES the window (the gesture was likely complete and
    // the hand simply left frame); validation inside discards junk.
    if (_inGesture && _noHandStreak >= 2) {
      debugPrint('[Gate] close (hand tracking lost mid-gesture)');
      _closeGestureWindow();
    }
    _slowStreak = 0;
    if (_noHandStreak >= _noHandResetAfter) {
      // FIX 1.5: full state reset after sustained hand loss — no stale signs,
      // no EMA blending across tracking gaps.
      _recognizer.reset();
      _ring.clear();
      _ringTs.clear();
      _frameRing.clear();
      _inGesture = false;
      _lastWristX = _lastWristY = null;
      _lastPose = null;
      _smoothedPose = const [];
    }
  }

  // =====================================================================
  //  FRAME DATA BUILDER
  // =====================================================================

  /// Build a [SignFrameData] from MediaPipe hands (preferred) or a hand
  /// synthesized from ML Kit pose landmarks. Returns null when no hand is
  /// present at all.
  SignFrameData? _buildFrameData(Pose pose, int w, int h, bool isFront, int ts) {
    final posePts = <SGPoint?>[
      for (final t in PoseLandmarkType.values) _normPoseLandmark(pose, t, w, h, isFront),
    ];
    // BIM's 258-channel tensor carries a visibility per pose landmark; the
    // training data stored MediaPipe's CONTINUOUS visibility, so pass ML Kit's
    // likelihood through instead of the binary present/absent the GISLR tensor
    // (ASL) uses.
    final poseLikelihood = <double>[
      for (final t in PoseLandmarkType.values)
        pose.landmarks[t]?.likelihood ?? 0.0,
    ];
    _updateSmoothedPose(posePts);
    final anchors = _anchorsFromSmoothed();

    final leftWrist  = pose.landmarks[PoseLandmarkType.leftWrist];
    final rightWrist = pose.landmarks[PoseLandmarkType.rightWrist];
    final hasPoseHand = (leftWrist != null && leftWrist.likelihood > 0.3) ||
        (rightWrist != null && rightWrist.likelihood > 0.3);

    // Dual-hand: MediaPipe can return up to 2 hands. Assign anatomical slots
    // by wrist proximity to the pose wrists; the closer hand is primary.
    List<SGPoint>? hand;
    List<SGPoint>? hand2;
    bool fromMediaPipe = false;

    final mpHands = _latestHands
        .where((h) => h.landmarks.length >= 21)
        .map((h) => List<SGPoint>.generate(21, (i) {
              // Raw plugin coords — the frame transform is auto-calibrated
              // against the pose wrist below (rotations + mirror cover all
              // per-camera sensor conventions).
              return SGPoint(h.landmarks[i].x, h.landmarks[i].y,
                  h.landmarks[i].z);
            }))
        .toList();

    if (mpHands.isNotEmpty) {
      _calibrateHandFrame(mpHands.first, posePts);
      final t = _handTransform;
      for (var i = 0; i < mpHands.length; i++) {
        mpHands[i] = [for (final p in mpHands[i]) _applyHandTransform(p, t)];
      }
    }

    if (mpHands.isNotEmpty) {
      fromMediaPipe = true;
      if (mpHands.length == 1) {
        hand = mpHands.first;
      } else {
        // Two hands: primary = the one nearer a pose wrist (or screen center
        // for the dominant side when pose wrists are missing).
        final lw = posePts.length > kPoseRightWristIndex
            ? posePts[kPoseLeftWristIndex]
            : null;
        final rw = posePts.length > kPoseRightWristIndex
            ? posePts[kPoseRightWristIndex]
            : null;
        double dist0 = _wristAnchorDist(mpHands[0], lw, rw);
        double dist1 = _wristAnchorDist(mpHands[1], lw, rw);
        if (dist0 <= dist1) {
          hand = mpHands[0];
          hand2 = mpHands[1];
        } else {
          hand = mpHands[1];
          hand2 = mpHands[0];
        }
      }
    } else if (hasPoseHand) {
      hand = _synthesiseHandFromPose(pose, w, h, isFront);
    }

    if (hand == null) return null;
    _noHandStreak = 0;
    return SignFrameData(
      hand: hand,
      hand2: hand2,
      anchors: anchors,
      pose: posePts,
      poseLikelihood: poseLikelihood,
      hasMediaPipeHand: fromMediaPipe,
      isFrontCamera: isFront,
      timestampMs: ts,
    );
  }

  /// Score all 8 frame-transform candidates of [hand]'s wrist against the
  /// pose wrists (nearest wins) and vote. The current winner only flips when
  /// another candidate leads consistently for [_handTransformSwitchAfter]
  /// frames — hysteresis prevents flapping when both hands hover mid-frame.
  void _calibrateHandFrame(List<SGPoint> hand, List<SGPoint?> posePts) {
    SGPoint? leftWrist;
    SGPoint? rightWrist;
    if (posePts.length > kPoseRightWristIndex) {
      leftWrist = posePts[kPoseLeftWristIndex];
      rightWrist = posePts[kPoseRightWristIndex];
    }
    if (leftWrist == null && rightWrist == null) return;
    final wrist = hand[0];

    int best = 0;
    double bestDist = double.infinity;
    for (var t = 0; t < 8; t++) {
      final w = _applyHandTransform(wrist, t);
      final dl = leftWrist == null ? 9.0 : w.dist2D(leftWrist);
      final dr = rightWrist == null ? 9.0 : w.dist2D(rightWrist);
      final d = math.min(dl, dr);
      if (d < bestDist) {
        bestDist = d;
        best = t;
      }
    }

    if (best == _handTransform) {
      _handTransformAltStreak = 0;
      return;
    }
    if (best == _handTransformAlt) {
      _handTransformAltStreak++;
    } else {
      _handTransformAlt = best;
      _handTransformAltStreak = 1;
    }
    if (_handTransformAltStreak >= _handTransformSwitchAfter) {
      debugPrint('[Calib] hand frame -> candidate $_handTransform '
          '(was $_handTransform)');
      _handTransform = best;
      _handTransformAlt = -1;
      _handTransformAltStreak = 0;
    }
  }

  /// Apply candidate transform [t] (0..7: bits0-2 = rotation 0/90/180/270,
  /// bit0 of the count = mirror-x first). Maps raw hand-plugin coordinates
  /// into the pose coordinate space.
  SGPoint _applyHandTransform(SGPoint p, int t) {
    double x = (t & 1) != 0 ? 1.0 - p.x : p.x;
    double y = p.y;
    switch ((t >> 1) & 3) {
      case 1: // 90° cw: (x,y) -> (1-y, x)
        final nx = 1.0 - y;
        y = x;
        x = nx;
        break;
      case 2: // 180°
        x = 1.0 - x;
        y = 1.0 - y;
        break;
      case 3: // 270° cw: (x,y) -> (y, 1-x)
        final nx = y;
        y = 1.0 - x;
        x = nx;
        break;
    }
    return SGPoint(x, y, p.z);
  }

  /// Distance from a hand's wrist to the nearest pose wrist anchor (large
  /// sentinel when the pose wrists are unknown).
  double _wristAnchorDist(List<SGPoint> hand, SGPoint? lw, SGPoint? rw) {
    if (lw == null && rw == null) return 0.0;
    final w0 = hand[0];
    final dl = lw == null ? 9.0 : w0.dist2D(lw);
    final dr = rw == null ? 9.0 : w0.dist2D(rw);
    return math.min(dl, dr);
  }

  /// EMA-smooth the pose point vector so the sparse pose cadence (4-8 runs/s)
  /// does not make the synthetic face anchors jitter against the fast hands.
  void _updateSmoothedPose(List<SGPoint?> fresh) {
    if (_smoothedPose.length != fresh.length) {
      _smoothedPose = List<SGPoint?>.from(fresh);
      return;
    }
    final a = _poseEmaAlpha;
    _smoothedPose = List<SGPoint?>.generate(fresh.length, (i) {
      final f = fresh[i];
      final s = _smoothedPose[i];
      if (f == null) return s; // keep last known value for missing points
      if (s == null) return f;
      return SGPoint(
        a * f.x + (1 - a) * s.x,
        a * f.y + (1 - a) * s.y,
        a * f.z + (1 - a) * s.z,
      );
    });
  }

  /// Anchors built from the smoothed pose vector (same indices as
  /// [PoseLandmarkType.values]).
  SignAnchors _anchorsFromSmoothed() {
    SGPoint? at(int i) => i < _smoothedPose.length ? _smoothedPose[i] : null;

    final nose = at(_poseIndexOf(PoseLandmarkType.nose));
    final leftMouth = at(_poseIndexOf(PoseLandmarkType.leftMouth));
    final rightMouth = at(_poseIndexOf(PoseLandmarkType.rightMouth));
    final leftEye = at(_poseIndexOf(PoseLandmarkType.leftEye));
    final rightEye = at(_poseIndexOf(PoseLandmarkType.rightEye));
    final leftShoulder = at(_poseIndexOf(PoseLandmarkType.leftShoulder));
    final rightShoulder = at(_poseIndexOf(PoseLandmarkType.rightShoulder));

    final mouthCenter = (leftMouth != null && rightMouth != null)
        ? SGPoint((leftMouth.x + rightMouth.x) / 2, (leftMouth.y + rightMouth.y) / 2)
        : (nose != null ? SGPoint(nose.x, nose.y + 0.04) : null);
    final eyeCenter = (leftEye != null && rightEye != null)
        ? SGPoint((leftEye.x + rightEye.x) / 2, (leftEye.y + rightEye.y) / 2)
        : null;
    final chestCenter = (leftShoulder != null && rightShoulder != null)
        ? SGPoint((leftShoulder.x + rightShoulder.x) / 2,
            (leftShoulder.y + rightShoulder.y) / 2 + 0.08)
        : null;
    final bodyCenterX = (leftShoulder != null && rightShoulder != null)
        ? (leftShoulder.x + rightShoulder.x) / 2
        : null;

    return SignAnchors(
      nose: nose,
      leftEar: at(_poseIndexOf(PoseLandmarkType.leftEar)),
      rightEar: at(_poseIndexOf(PoseLandmarkType.rightEar)),
      mouthCenter: mouthCenter,
      eyeCenter: eyeCenter,
      chestCenter: chestCenter,
      leftShoulder: leftShoulder,
      rightShoulder: rightShoulder,
      bodyCenterX: bodyCenterX,
    );
  }

  /// Index of [t] in PoseLandmarkType.values (cached order lookup).
  static final Map<PoseLandmarkType, int> _poseIndexCache = {
    for (var i = 0; i < PoseLandmarkType.values.length; i++)
      PoseLandmarkType.values[i]: i,
  };

  int _poseIndexOf(PoseLandmarkType t) => _poseIndexCache[t] ?? 0;

  /// Whether the ML Kit processing rotation swaps the sensor frame (90/270).
  /// Set per frame before any pose normalization runs.
  bool _poseFrameSwapped = false;

  /// Portrait-normalized pose coordinates.
  ///
  /// ML Kit processes the rotated (portrait) image, so its landmarks span
  /// the rotated frame of dims (h_s, w_s) for a 90°/270° sensor. Dividing by
  /// the sensor dims instead squashes x by w/h and stretches y by h/w — the
  /// audit's coordinate bug. The hand plugin returns portrait-normalized
  /// values already; dividing pose by the ROTATED dims puts both hands and
  /// body in that same [0,1] portrait space.
  SGPoint? _normPoseLandmark(Pose pose, PoseLandmarkType t, int w, int h, bool isFront) {
    final lm = pose.landmarks[t];
    if (lm == null) return null;
    final dw = _poseFrameSwapped ? h : w;
    final dh = _poseFrameSwapped ? w : h;
    // NO mirror compensation — same third-person convention as the hands and
    // the training data (mirroring flips signs into their mirror images:
    // hands unmirrored + pose mirrored is worse than either alone).
    return SGPoint(lm.x / dw, lm.y / dh, lm.z / dw);
  }

  /// Approximate 21-point hand from ML Kit pose (wrist/thumb/index/pinky).
  /// Finger angles from this path are unreliable (collinear interpolation) —
  /// the recognizer downweights shape confidence accordingly.
  List<SGPoint>? _synthesiseHandFromPose(Pose pose, int w, int h, bool isFront) {
    final leftWrist  = pose.landmarks[PoseLandmarkType.leftWrist];
    final rightWrist = pose.landmarks[PoseLandmarkType.rightWrist];

    PoseLandmark? wrist, thumb, index, pinky;
    final leftConf  = leftWrist?.likelihood  ?? 0.0;
    final rightConf = rightWrist?.likelihood ?? 0.0;

    if (leftConf < 0.3 && rightConf < 0.3) return null;
    if (leftConf >= rightConf) {
      wrist = leftWrist;
      thumb = pose.landmarks[PoseLandmarkType.leftThumb];
      index = pose.landmarks[PoseLandmarkType.leftIndex];
      pinky = pose.landmarks[PoseLandmarkType.leftPinky];
    } else {
      wrist = rightWrist;
      thumb = pose.landmarks[PoseLandmarkType.rightThumb];
      index = pose.landmarks[PoseLandmarkType.rightIndex];
      pinky = pose.landmarks[PoseLandmarkType.rightPinky];
    }
    if (wrist == null) return null;

    SGPoint? norm(PoseLandmark? lm) {
      if (lm == null || lm.likelihood < 0.2) return null;
      final dw = _poseFrameSwapped ? h : w;
      final dh = _poseFrameSwapped ? w : h;
      // NO mirror compensation — third-person training convention.
      return SGPoint(lm.x / dw, lm.y / dh, lm.z / dw);
    }

    final wPt = norm(wrist)!;
    final tPt = norm(thumb);
    final iPt = norm(index);
    final pPt = norm(pinky);
    if (tPt == null && iPt == null && pPt == null) return null;

    final midRef = (iPt != null && pPt != null)
        ? SGPoint((iPt.x + pPt.x) / 2, (iPt.y + pPt.y) / 2, (iPt.z + pPt.z) / 2)
        : (iPt ?? pPt ?? wPt);

    SGPoint lerp(SGPoint a, SGPoint b, double t) => SGPoint(
        a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, a.z + (b.z - a.z) * t);

    final pts = List<SGPoint>.filled(21, wPt);
    if (tPt != null) {
      pts[4] = tPt;
      pts[1] = lerp(wPt, tPt, 0.25);
      pts[2] = lerp(wPt, tPt, 0.50);
      pts[3] = lerp(wPt, tPt, 0.75);
    }
    if (iPt != null) {
      pts[8] = iPt;
      pts[5] = lerp(wPt, iPt, 0.25);
      pts[6] = lerp(wPt, iPt, 0.50);
      pts[7] = lerp(wPt, iPt, 0.75);
    }
    pts[12] = midRef;
    pts[9]  = lerp(wPt, midRef, 0.25);
    pts[10] = lerp(wPt, midRef, 0.50);
    pts[11] = lerp(wPt, midRef, 0.75);
    final ringRef = (pPt != null)
        ? SGPoint((midRef.x + pPt.x) / 2, (midRef.y + pPt.y) / 2, (midRef.z + pPt.z) / 2)
        : midRef;
    pts[16] = ringRef;
    pts[13] = lerp(wPt, ringRef, 0.25);
    pts[14] = lerp(wPt, ringRef, 0.50);
    pts[15] = lerp(wPt, ringRef, 0.75);
    if (pPt != null) {
      pts[20] = pPt;
      pts[17] = lerp(wPt, pPt, 0.25);
      pts[18] = lerp(wPt, pPt, 0.50);
      pts[19] = lerp(wPt, pPt, 0.75);
    }
    return pts;
  }

  // =====================================================================
  //  TEMPORAL TFLITE PATH — pre-roll ring buffer, motion gating, window
  //  inference
  // =====================================================================

  /// Every processed frame appends to the ring. The gate state machine only
  /// decides which SLICE of the ring is the gesture window:
  ///
  ///   [activation − preRoll … deactivation + end-hold frames]
  ///
  /// so the sign onset before the speed trigger crosses is always included.
  void _updateMotionGate(SignFrameData frame) {
    final wx = frame.hand[0].x;
    final wy = frame.hand[0].y;
    final ts = frame.timestampMs;

    // Continuous pre-roll ring (oldest evicted at capacity).
    _ring.add(buildGislrTensor(frame));
    _ringTs.add(ts);
    _frameRing.add(frame);
    if (_ring.length > _maxRingFrames) {
      _ring.removeAt(0);
      _ringTs.removeAt(0);
      _frameRing.removeAt(0);
    }

    // Wrist speed from the EMA-smoothed wrist (jitter-free stillness read).
    if (_speedWristX != null && _lastWristTs != 0) {
      final a = _speedEmaAlpha;
      _speedWristX = a * wx + (1 - a) * _speedWristX!;
      _speedWristY = a * wy + (1 - a) * _speedWristY!;
    } else {
      _speedWristX = wx;
      _speedWristY = wy;
    }

    double speed = 0;
    // After a hand-loss reset the previous smoothed wrist is gone; the
    // current frame then seeds it again with no speed measurement.
    if (_speedWristX != null && _lastWristX != null && _lastWristTs != 0) {
      final dt = (ts - _lastWristTs) / 1000.0;
      if (dt > 0.001 && dt < 2.0) {
        speed = math.sqrt((_speedWristX! - _lastWristX!) *
                    (_speedWristX! - _lastWristX!) +
                (_speedWristY! - _lastWristY!) *
                    (_speedWristY! - _lastWristY!)) /
            dt;
      }
    }
    _lastWristX = _speedWristX;
    _lastWristY = _speedWristY;
    _lastWristTs = ts;

    if (!_inGesture) {
      // Activation: 2 consecutive fast frames open the window. The window
      // starts a fixed TIME before now (time, not frames — frame rate
      // varies 6-25fps and a frame-count lookback swings 3s-10s).
      _fastStreak = speed > _gestureStartSpeed ? _fastStreak + 1 : 0;
      if (_fastStreak >= _gestureStartHold) {
        _inGesture = true;
        _slowStreak = 0;
        _gestureStartTs = ts - _preRollMs;
        debugPrint('[Gate] open (speed ${speed.toStringAsFixed(2)}/s, '
            'pre-roll ${_preRollMs}ms)');
      }
      return;
    }

    // Open: track stillness toward closure. Elapsed is measured against the
    // window's start TIMESTAMP — ring eviction shifts indices, so an index
    // based span silently saturates and the hard cap never fires.
    _slowStreak = speed < _gestureEndSpeed ? _slowStreak + 1 : 0;
    final elapsed = ts - _gestureStartTs;
    if (_slowStreak >= _gestureEndHold || elapsed >= _maxGestureMs) {
      _closeGestureWindow();
    }
  }

  /// Close the open gesture window: validate, resample, infer once.
  void _closeGestureWindow() {
    _inGesture = false;
    _slowStreak = 0;

    // Slice the ring by timestamp (indices drift as the ring evicts).
    final startIdx = _ringTs.indexWhere((t) => t >= _gestureStartTs);
    if (startIdx < 0 || startIdx >= _ring.length) return;
    final frames = _ring.sublist(startIdx);
    final tsSpan = _ringTs.last - _ringTs[startIdx];

    if (frames.length < _minWindowFrames) {
      debugPrint('[Gate] discard ${frames.length}f (<$_minWindowFrames min)');
      return;
    }
    if (tsSpan < _minWindowMs) {
      debugPrint('[Gate] discard span ${tsSpan}ms (<$_minWindowMs ms)');
      return;
    }
    // Hand-coverage check: a window where both hand slots are NaN for most
    // frames is tracking failure, not a sign.
    int noHand = 0;
    for (final t in frames) {
      final lx = t[468 * 3];
      final rx = t[522 * 3];
      if (lx.isNaN && rx.isNaN) noHand++;
    }
    if (noHand / frames.length > 0.40) {
      debugPrint('[Gate] discard ${frames.length}f '
          '(hand missing in ${(noHand * 100 / frames.length).round()}%)');
      return;
    }

    debugPrint('[Gate] close ${frames.length}f (span ${tsSpan}ms)');
    // Batch clip capture hook: hand the RAW frames of this validated gesture
    // to the screen (same window the classifiers see). Errors here must
    // never break the frame loop.
    final hook = onGestureWindowClosed;
    if (hook != null && startIdx < _frameRing.length) {
      try {
        hook(_frameRing.sublist(startIdx));
      } catch (e) {
        debugPrint('[Gate] window hook error: $e');
      }
    }
    if (bimMode) {
      final bimStart = startIdx.clamp(0, _frameRing.length);
      _runBimInference(_frameRing.sublist(bimStart));
      return;
    }
    _runTemporalInference(frames);
  }

  /// Run the on-device BIM word classifier over a closed gesture window.
  /// Inference runs ASYNC (yielding between ensemble views) so the
  /// frame-processing loop keeps feeding the skeleton overlay while a word
  /// is being classified — a synchronous 12-view burst froze the overlay
  /// for hundreds of ms per word. Quality rejects (no person / no motion /
  /// too short) are logged only: live recognition never interrupts the user
  /// with popups; the display keeps the previous word until a valid sign
  /// lands.
  bool _bimRunning = false;

  void _runBimInference(List<SignFrameData> window) {
    if (!_bimTflite.isModelLoaded) {
      debugPrint('[Bim] model not loaded — dropping window (${window.length}f)');
      _bimTflite.initialize(); // warm up for the next window
      return;
    }
    if (_bimRunning) {
      debugPrint('[Bim] previous window still classifying — skipping '
          '${window.length}f');
      return;
    }
    _bimRunning = true;
    final sw = Stopwatch()..start();
    unawaited(() async {
      try {
        final result = await _bimTflite.recognizeClip(
            window, previousGlosses: const []);
        sw.stop();
        // Same acceptance rule as the ASL path: display only when top-1
        // clearly beats the runner-up or is decisive alone. Prevents junk
        // low-confidence guesses from cycling words on screen between signs.
        final accepted = result.word.isNotEmpty &&
            (_bimTflite.lastMargin >= _minTopMargin ||
                result.confidence >= _minTopConfidence);
        debugPrint('[Bim] window=${window.length}f -> "${result.word}" '
            'conf=${result.confidence.toStringAsFixed(3)} '
            'margin=${_bimTflite.lastMargin.toStringAsFixed(3)} '
            '${accepted ? "" : "BELOW GATE (not shown)"} '
            '(${sw.elapsedMilliseconds}ms)');
        // The user may have switched back to ASL while classifying.
        if (accepted && bimMode) {
          _lastTfliteSign = result.word;
          _lastTfliteConf = result.confidence;
          _lastTfliteTs = DateTime.now().millisecondsSinceEpoch;
        }
      } on BimSignRecognitionException catch (e) {
        debugPrint('[Bim] window rejected: ${e.message}');
      } catch (e) {
        debugPrint('[Bim] inference error: $e');
      } finally {
        _bimRunning = false;
      }
    }());
  }

  /// Run the temporal GISLR model over the closed gesture window:
  /// resample to at most [_maxInferenceFrames] frames, then classify the
  /// whole sequence in one inference (see [AslTfliteService.predictSequence]).
  void _runTemporalInference(List<List<double>> frames) {
    if (!isTemporalPathEnabled) return;
    if (_aslTflite.lastError != null && !_aslTflite.isModelLoaded) return;

    try {
      final prepared = _preprocessWindow(frames, _maxInferenceFrames);
      if (prepared == null) return;

      final sw = Stopwatch()..start();
      final prediction = _aslTflite.predictSequence(prepared);
      sw.stop();

      final sign = prediction['character'] as String? ?? '';
      final conf = (prediction['confidence'] as num?)?.toDouble() ?? 0.0;
      final margin = (prediction['margin'] as num?)?.toDouble() ?? 0.0;
      debugPrint('[Temporal] window=${frames.length}f -> "$sign" '
          'conf=${conf.toStringAsFixed(3)} margin=${margin.toStringAsFixed(3)} '
          '(${sw.elapsedMilliseconds}ms)');

      // Circuit breaker with auto-recovery: detect a degenerate model
      // (same class at ~1.0 forever) and PAUSE the temporal path — it
      // resumes automatically after the pause; nothing is permanent.
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (conf > 0.985) {
        _suspectStreak = sign == _suspectClass ? _suspectStreak + 1 : 1;
        _suspectClass = sign;
        if (_suspectStreak >= _suspectStreakLimit &&
            nowMs >= _suspectPauseUntilTs) {
          _suspectPauseUntilTs = nowMs + _suspectPauseMs;
          debugPrint('[Temporal] suspect: "$sign" at ~1.0 for '
              '$_suspectStreak windows — temporal path PAUSED '
              '${_suspectPauseMs}ms (auto-resumes)');
        }
      } else {
        _suspectStreak = 0;
        _suspectClass = '';
      }

      // Margin-based acceptance: accept when top-1 beats the runner-up by
      // a clear margin, or is decisive on its own.
      if (sign.isNotEmpty && (margin >= _minTopMargin || conf >= _minTopConfidence)) {
        _lastTfliteSign = sign;
        _lastTfliteConf = conf;
        _lastTfliteTs = DateTime.now().millisecondsSinceEpoch;
      }
    } catch (e) {
      debugPrint('[Temporal] inference error: $e');
    }
  }

  bool get isTemporalPathEnabled {
    if (!_aslTflite.isModelLoaded) return false;
    final pausedUntil = _suspectPauseUntilTs;
    return pausedUntil == 0 ||
        DateTime.now().millisecondsSinceEpoch >= pausedUntil;
  }

  /// Resample the window to at most [target] frames (linear interpolation)
  /// so a long gesture costs a bounded number of per-frame inferences.
  ///
  /// No further normalization: the GISLR dataset stores raw MediaPipe
  /// coordinates (x,y in 0..1, z as reported, zeros for missing landmarks)
  /// and [buildGislrTensor] already produces exactly that.
  List<List<double>>? _preprocessWindow(List<List<double>> window, int target) {
    if (window.isEmpty) return null;
    if (window.length <= target) return window;

    return List<List<double>>.generate(target, (i) {
      final t = i * (window.length - 1) / (target - 1);
      final i0 = t.floor();
      final i1 = math.min(i0 + 1, window.length - 1);
      final frac = t - i0;
      final a = window[i0], b = window[i1];
      return List<double>.generate(a.length, (j) => a[j] + (b[j] - a[j]) * frac);
    });
  }

  // =====================================================================
  //  ACCURACY HARNESS — clip recording controls (debug UI)
  // =====================================================================

  void startClipRecording(String label) => clipRecorder.startClip(label);
  SignClip? stopClipRecording() => clipRecorder.endClip();
  Future<int> copyRecordingsToClipboard() => clipRecorder.copyToClipboard();
  Future<String> exportRecordingsToFile() => clipRecorder.exportToFile();

  // =====================================================================
  //  UTILITIES
  // =====================================================================

  InputImageRotation _rotationFromCamera(CameraDescription camera) {
    switch (camera.sensorOrientation) {
      case 0:   return InputImageRotation.rotation0deg;
      case 90:  return InputImageRotation.rotation90deg;
      case 180: return InputImageRotation.rotation180deg;
      case 270: return InputImageRotation.rotation270deg;
      default:  return InputImageRotation.rotation0deg;
    }
  }

  void dispose() {
    _handStreamSub?.cancel();
    _handStreamSub = null;
    _handLandmarker?.dispose();
    _poseDetector?.close();
    _poseDetector = null;
    _lastPose = null;
    _smoothedPose = const [];
    _isInitialized = false;
  }
}
