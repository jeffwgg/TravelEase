import 'dart:math' as math;
import 'dart:ui' show Size;
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:hand_landmarker/hand_landmarker.dart';
import 'asl_tflite_service.dart';
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
  bool _isInitialized = false;

  // ─── Hand-loss state hygiene (Phase 1.5) ──────────────────────────────
  int _noHandStreak = 0;
  static const int _noHandResetAfter = 10;

  // ─── Temporal buffer + motion gating (Phase 2) ────────────────────────
  /// Buffered landmark tensors (543 x 3) for the current gesture window.
  final List<List<double>> _windowTensor = [];
  final List<int> _windowTimestamps = [];
  double? _lastWristX, _lastWristY;
  int _lastWristTs = 0;
  bool _inGesture = false;
  int _slowStreak = 0;

  /// Wrist speed (screen units / second) that opens a gesture window.
  static const double _gestureStartSpeed = 0.70;
  /// Wrist speed below which a gesture is considered finished.
  static const double _gestureEndSpeed = 0.30;
  /// Consecutive slow processed frames that close a gesture window.
  static const int _gestureEndHold = 3;
  static const int _minWindowFrames = 4;
  static const int _maxWindowFrames = 120;

  /// Minimum TFLite softmax confidence to prefer the neural result.
  static const double _tfliteMinConfidence = 0.60;

  /// Upper bound on frames inferred per closed gesture window (the model is
  /// single-frame, so cost scales with window length).
  static const int _maxInferenceFrames = 32;

  /// Sanity probe: if the model returns the same class at ~1.0 confidence for
  /// this many consecutive windows, it is judged degenerate (bad preprocessing
  /// or single-frame-trained) and the path is disabled.
  static const int _suspectStreakLimit = 5;
  String _suspectClass = '';
  int _suspectStreak = 0;
  bool _modelSuspect = false;

  String? _lastTfliteSign;
  double _lastTfliteConf = 0.0;

  bool get isInitialized => _isInitialized;
  bool get isTemporalModelSuspect => _modelSuspect;

  Future<void> initialize() async {
    try {
      _poseDetector = PoseDetector(
        options: PoseDetectorOptions(
          mode: PoseDetectionMode.stream,
          model: PoseDetectionModel.base,
        ),
      );

      try {
        _handLandmarker = HandLandmarkerPlugin.create();
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

    try {
      // ── Offload pixel-copy to background isolate ───────────────────────
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

      final nv21 = params['nv21'] as Uint8List;
      final w    = params['width']  as int;
      final h    = params['height'] as int;

      final inputImage = InputImage.fromBytes(
        bytes: nv21,
        metadata: InputImageMetadata(
          size: Size(w.toDouble(), h.toDouble()),
          rotation: _rotationFromCamera(camera),
          format: InputImageFormat.nv21,
          bytesPerRow: w,
        ),
      );

      // ── Hand landmark detection (native MediaPipe) ─────────────────────
      try {
        final hands = _handLandmarker?.detect(image, camera.sensorOrientation);
        if (hands != null && hands.isNotEmpty) {
          _latestHands = hands;
        } else {
          _latestHands = [];
        }
      } catch (e) {
        _latestHands = [];
        debugPrint('[CameraLandmarkExtractor] HandLandmarker error: $e');
      }

      // ── Pose detection ─────────────────────────────────────────────────
      final poses = await _poseDetector!.processImage(inputImage);
      if (poses.isEmpty) {
        _handleNoHand();
        return _result(false, '', 0, 'none');
      }

      final pose = poses.first;
      final isFront = camera.lensDirection == CameraLensDirection.front;
      final now = DateTime.now().millisecondsSinceEpoch;

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
      final outcome = _recognizer.processFrame(frameData);
      if (character.isEmpty && outcome.committedSign.isNotEmpty) {
        character = outcome.committedSign;
        confidence = outcome.committedConfidence;
      }

      return _result(
        true,
        character,
        confidence,
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
    _inGesture = false;
    _slowStreak = 0;
    if (_noHandStreak >= _noHandResetAfter) {
      // FIX 1.5: full state reset after sustained hand loss — no stale signs,
      // no EMA blending across tracking gaps.
      _recognizer.reset();
      _windowTensor.clear();
      _windowTimestamps.clear();
      _lastWristX = _lastWristY = null;
    }
  }

  // =====================================================================
  //  FRAME DATA BUILDER
  // =====================================================================

  /// Build a [SignFrameData] from MediaPipe hands (preferred) or a hand
  /// synthesized from ML Kit pose landmarks. Returns null when no hand is
  /// present at all.
  SignFrameData? _buildFrameData(Pose pose, int w, int h, bool isFront, int ts) {
    final anchors = _extractAnchors(pose, w, h, isFront);
    final posePts = <SGPoint?>[
      for (final t in PoseLandmarkType.values) _normPoseLandmark(pose, t, w, h, isFront),
    ];

    final leftWrist  = pose.landmarks[PoseLandmarkType.leftWrist];
    final rightWrist = pose.landmarks[PoseLandmarkType.rightWrist];
    final hasPoseHand = (leftWrist != null && leftWrist.likelihood > 0.3) ||
        (rightWrist != null && rightWrist.likelihood > 0.3);

    List<SGPoint>? hand;
    bool fromMediaPipe = false;

    if (_latestHands.isNotEmpty && _latestHands.first.landmarks.length >= 21) {
      // Path A: precise MediaPipe 21-point hand (already normalized 0..1).
      final lm = _latestHands.first.landmarks;
      hand = List<SGPoint>.generate(21, (i) {
        double x = lm[i].x;
        if (isFront) x = 1.0 - x; // mirror-compensate selfie view
        return SGPoint(x, lm[i].y, lm[i].z);
      });
      fromMediaPipe = true;
    } else if (hasPoseHand) {
      // Path B: synthesize from pose wrist/thumb/index/pinky.
      hand = _synthesiseHandFromPose(pose, w, h, isFront);
    }

    if (hand == null) return null;
    _noHandStreak = 0;
    return SignFrameData(
      hand: hand,
      anchors: anchors,
      pose: posePts,
      hasMediaPipeHand: fromMediaPipe,
      isFrontCamera: isFront,
      timestampMs: ts,
    );
  }

  SGPoint? _normPoseLandmark(Pose pose, PoseLandmarkType t, int w, int h, bool isFront) {
    final lm = pose.landmarks[t];
    if (lm == null) return null;
    double x = lm.x / w;
    if (isFront) x = 1.0 - x;
    return SGPoint(x, lm.y / h, lm.z / w);
  }

  SignAnchors _extractAnchors(Pose pose, int w, int h, bool isFront) {
    SGPoint? anchor(PoseLandmarkType t) {
      final lm = pose.landmarks[t];
      if (lm == null) return null;
      double x = lm.x / w;
      if (isFront) x = 1.0 - x;
      return SGPoint(x, lm.y / h, lm.z / w);
    }

    final nose = anchor(PoseLandmarkType.nose);
    final leftMouth = anchor(PoseLandmarkType.leftMouth);
    final rightMouth = anchor(PoseLandmarkType.rightMouth);
    final leftEye = anchor(PoseLandmarkType.leftEye);
    final rightEye = anchor(PoseLandmarkType.rightEye);
    final leftShoulder = anchor(PoseLandmarkType.leftShoulder);
    final rightShoulder = anchor(PoseLandmarkType.rightShoulder);

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
      leftEar: anchor(PoseLandmarkType.leftEar),
      rightEar: anchor(PoseLandmarkType.rightEar),
      mouthCenter: mouthCenter,
      eyeCenter: eyeCenter,
      chestCenter: chestCenter,
      leftShoulder: leftShoulder,
      rightShoulder: rightShoulder,
      bodyCenterX: bodyCenterX,
    );
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
      double x = lm.x / w;
      if (isFront) x = 1.0 - x;
      return SGPoint(x, lm.y / h, lm.z / w);
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
  //  TEMPORAL TFLITE PATH — ring buffer, motion gating, window inference
  // =====================================================================

  void _updateMotionGate(SignFrameData frame) {
    final wx = frame.hand[0].x;
    final wy = frame.hand[0].y;
    final ts = frame.timestampMs;

    if (_lastWristX != null && _lastWristTs != 0) {
      final dt = (ts - _lastWristTs) / 1000.0;
      if (dt > 0.001 && dt < 2.0) {
        final speed = math.sqrt((wx - _lastWristX!) * (wx - _lastWristX!) +
            (wy - _lastWristY!) * (wy - _lastWristY!)) / dt;

        if (!_inGesture && speed > _gestureStartSpeed) {
          _inGesture = true;
          _slowStreak = 0;
          _windowTensor.clear();
          _windowTimestamps.clear();
        }
        if (_inGesture) {
          if (speed < _gestureEndSpeed) {
            _slowStreak++;
          } else {
            _slowStreak = 0;
          }
        }
      }
    }
    _lastWristX = wx;
    _lastWristY = wy;
    _lastWristTs = ts;

    if (_inGesture) {
      _windowTensor.add(buildGislrTensor(frame));
      _windowTimestamps.add(ts);
      if (_windowTensor.length > _maxWindowFrames) {
        _windowTensor.removeAt(0);
        _windowTimestamps.removeAt(0);
      }

      if (_slowStreak >= _gestureEndHold &&
          _windowTensor.length >= _minWindowFrames) {
        _inGesture = false;
        _slowStreak = 0;
        _runTemporalInference();
      } else if (_slowStreak >= _gestureEndHold) {
        _inGesture = false;
        _slowStreak = 0;
        _windowTensor.clear();
      }
    }
  }

  /// Run the single-frame GISLR model over the closed gesture window:
  /// resample to at most [_maxInferenceFrames] frames, infer on each frame,
  /// and average the class probabilities (see [AslTfliteService.predictFrames]).
  void _runTemporalInference() {
    if (!isTemporalPathEnabled) return;
    if (_aslTflite.lastError != null && !_aslTflite.isModelLoaded) return;

    try {
      final prepared = _preprocessWindow(_windowTensor, _maxInferenceFrames);
      if (prepared == null) return;

      final sw = Stopwatch()..start();
      final prediction = _aslTflite.predictFrames(prepared);
      sw.stop();

      final sign = prediction['character'] as String? ?? '';
      final conf = (prediction['confidence'] as num?)?.toDouble() ?? 0.0;
      debugPrint('[Temporal] window=${_windowTensor.length}f -> "$sign" '
          'conf=${conf.toStringAsFixed(3)} (${sw.elapsedMilliseconds}ms)');

      // Sanity probe: detect a degenerate model (same class at ~1.0 forever).
      if (conf > 0.985) {
        if (sign == _suspectClass) {
          _suspectStreak++;
        } else {
          _suspectClass = sign;
          _suspectStreak = 1;
        }
        if (_suspectStreak >= _suspectStreakLimit) {
          _modelSuspect = true;
          debugPrint('[Temporal] MODEL SUSPECT: "$sign" at ~1.0 confidence '
              'for $_suspectStreak consecutive windows — temporal path '
              'DISABLED. Preprocessing mismatch or single-frame model. '
              'Falling back to geometric engine.');
        }
      } else {
        _suspectStreak = 0;
        _suspectClass = '';
      }

      if (sign.isNotEmpty && conf >= _tfliteMinConfidence) {
        _lastTfliteSign = sign;
        _lastTfliteConf = conf;
      }
    } catch (e) {
      debugPrint('[Temporal] inference error: $e');
    } finally {
      _windowTensor.clear();
      _windowTimestamps.clear();
    }
  }

  bool get isTemporalPathEnabled => _aslTflite.isModelLoaded && !_modelSuspect;

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
    _handLandmarker?.dispose();
    _poseDetector?.close();
    _poseDetector = null;
    _isInitialized = false;
  }
}
