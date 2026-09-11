import 'dart:math' as math;
import 'sign_frame_data.dart';

/// Outcome of running the recognizer on a single frame.
class GeometricFrameOutcome {
  /// Best rule match for THIS frame ('' when no rule fired).
  final String candidate;

  /// Debounced sign committed for display ('' until stable for N frames).
  final String committedSign;
  final double committedConfidence;
  final bool handPresent;
  final String trackingSource; // 'mediapipe' | 'pose-synth' | 'none'

  const GeometricFrameOutcome({
    required this.candidate,
    required this.committedSign,
    required this.committedConfidence,
    required this.handPresent,
    required this.trackingSource,
  });
}

/// Rule-based geometric sign recognizer.
///
/// Pure and replayable: operates only on [SignFrameData], so the accuracy
/// harness can replay recorded clips through the exact same logic used live.
///
/// Stateful across frames (EMA smoothing + debounce). Call [reset] when hand
/// tracking is lost for a prolonged period.
///
/// Phase-1 fixes embedded:
///  * Zone thresholds scale with FACE SIZE (ear-to-ear), not absolute screen
///    fractions — works near and far.
///  * Pinch threshold tightened to 0.30 palm units.
///  * Palm orientation conditioned on inferred handedness (screen side).
///  * Catch-all free-space rules removed (they caused idle false positives).
///  * Real confidence: base weight x zone quality x shape quality.
///  * Vocabulary restricted to signs that exist in the 250-class label map
///    and the translation dictionary.
class GeometricSignRecognizer {
  // ─── Tuning constants ─────────────────────────────────────────────────
  static const double _emaAlpha = 0.70;
  static const int _debounceFrames = 3;
  static const int _smoothingGapResetMs = 400;

  /// Palm-facing calibration. MediaPipe plugin gives no handedness, so we
  /// infer hand side from screen position. If `happy`/`please`/`book` are
  /// systematically wrong on device, flip this to -1.
  static const double _palmCrossSignRightHand = 1.0;

  /// Fingers with PIP angle above this are candidates for "extended".
  static const double _extThresh = 120.0;
  static const double _curlThresh = 80.0;

  // ─── State ────────────────────────────────────────────────────────────
  List<List<double>>? _smoothed; // 21 x 3, wrist-centred palm units
  String _prevSign = '';
  int _streak = 0;
  String _committedSign = '';
  double _committedConf = 0.0;
  int _lastFrameTs = 0;
  int _noRuleStreak = 0;
  static const int _commitClearAfter = 15; // ~2.5 s at 6 fps

  String get committedSign => _committedSign;

  void reset() {
    _smoothed = null;
    _prevSign = '';
    _streak = 0;
    _committedSign = '';
    _committedConf = 0.0;
    _noRuleStreak = 0;
  }

  // ─── Public entry ─────────────────────────────────────────────────────
  GeometricFrameOutcome processFrame(SignFrameData frame) {
    final src = frame.hasMediaPipeHand ? 'mediapipe' : 'pose-synth';

    // Reset EMA if tracking jumped (hand lost & re-found).
    if (_lastFrameTs != 0 &&
        frame.timestampMs - _lastFrameTs > _smoothingGapResetMs) {
      _smoothed = null;
    }
    _lastFrameTs = frame.timestampMs;

    final raw = frame.hand;
    if (raw.length < 21) {
      return const GeometricFrameOutcome(
        candidate: '', committedSign: '', committedConfidence: 0,
        handPresent: false, trackingSource: 'none',
      );
    }

    // ── Wrist-centric normalisation (scale-invariant) ───────────────────
    final wrist = raw[0];
    final palmScale = wrist.dist2D(raw[9]);
    if (palmScale < 1e-6) {
      return GeometricFrameOutcome(
        candidate: '', committedSign: _committedSign,
        committedConfidence: _committedConf, handPresent: true,
        trackingSource: src,
      );
    }

    final pts = List<List<double>>.generate(21, (i) {
      return [
        (raw[i].x - wrist.x) / palmScale,
        (raw[i].y - wrist.y) / palmScale,
        raw[i].z / palmScale,
      ];
    });

    // ── EMA smoothing (with gap reset) ──────────────────────────────────
    if (_smoothed == null || _smoothed!.length != 21) {
      _smoothed = pts;
    } else {
      _smoothed = List<List<double>>.generate(21, (i) {
        return [
          _emaAlpha * pts[i][0] + (1 - _emaAlpha) * _smoothed![i][0],
          _emaAlpha * pts[i][1] + (1 - _emaAlpha) * _smoothed![i][1],
          _emaAlpha * pts[i][2] + (1 - _emaAlpha) * _smoothed![i][2],
        ];
      });
    }
    final sp = _smoothed!;

    // ── Finger joint angles ─────────────────────────────────────────────
    final thumbAngle = _angle(sp[1], sp[2], sp[3]);
    final indexAngle = _angle(sp[5], sp[6], sp[7]);
    final middleAngle = _angle(sp[9], sp[10], sp[11]);
    final ringAngle = _angle(sp[13], sp[14], sp[15]);
    final pinkyAngle = _angle(sp[17], sp[18], sp[19]);
    final indexDIP = _angle(sp[6], sp[7], sp[8]);
    final middleDIP = _angle(sp[10], sp[11], sp[12]);
    final ringDIP = _angle(sp[14], sp[15], sp[16]);
    final pinkyDIP = _angle(sp[18], sp[19], sp[20]);

    // Hybrid extension: PIP angle OR tip-farther-than-MCP fallback.
    final isThumbExt = thumbAngle > _extThresh ||
        _d(sp[4], sp[5]) > 0.55 ||
        _len(sp[4]) > _len(sp[2]) * 1.3;
    final isIndexExt = _isExt(indexAngle, indexDIP, 8, 5, sp);
    final isMiddleExt = _isExt(middleAngle, middleDIP, 12, 9, sp);
    final isRingExt = _isExt(ringAngle, ringDIP, 16, 13, sp);
    final isPinkyExt = _isExt(pinkyAngle, pinkyDIP, 20, 17, sp);

    final extCount = (isIndexExt ? 1 : 0) + (isMiddleExt ? 1 : 0) +
        (isRingExt ? 1 : 0) + (isPinkyExt ? 1 : 0);

    // ── Composite shapes ────────────────────────────────────────────────
    final isFist = extCount == 0;
    final isPointing = isIndexExt && extCount == 1;
    final isPeace = isIndexExt && isMiddleExt && extCount == 2;
    final isWShape = isIndexExt && isMiddleExt && isRingExt && extCount == 3;
    final isOpenPalm = extCount == 4;
    final isYShape = isThumbExt && isPinkyExt && !isIndexExt && !isMiddleExt && !isRingExt;

    // FIX 1.3: real pinch is ~0.15-0.25 palm units; 0.6 was firing on any
    // half-open hand.
    final pinchDist = _d(sp[4], sp[8]);
    final isPinch = pinchDist < 0.30;

    final isCShape = isThumbExt && isIndexExt && !isMiddleExt &&
        pinchDist > 0.35 && pinchDist < 1.4;

    final fingerSpread = _d(sp[8], sp[20]);
    final isFlatHand = isOpenPalm && fingerSpread < 1.2;

    // ── Palm orientation, conditioned on inferred handedness (FIX 1.4) ──
    final crossZ = (sp[5][0] - sp[0][0]) * (sp[17][1] - sp[0][1]) -
        (sp[5][1] - sp[0][1]) * (sp[17][0] - sp[0][0]);
    final isRightHand = _inferRightHand(frame);
    final isPalmFacing =
        (isRightHand ? crossZ * _palmCrossSignRightHand : -crossZ * _palmCrossSignRightHand) > 0;

    // ── Face/body scale (FIX 1.2) ───────────────────────────────────────
    final a = frame.anchors;
    final faceScale = _faceScale(a);
    final shoulderScale = _shoulderScale(a);

    final mouthR = 0.9 * faceScale;
    final noseR = 0.8 * faceScale;
    // 0.45 keeps the ear zones from overlapping the nose/mouth/eye zones
    // (nose-to-ear is ~0.5-0.6 faceScale); at 1.1 the whole face counted as
    // "near ear" and the ear rules shadowed every anchored face sign.
    final earR = 0.45 * faceScale;
    final eyeR = 0.7 * faceScale;
    final chinR = 0.9 * faceScale;
    final cheekR = 1.2 * faceScale;
    final foreheadR = 1.0 * faceScale;
    final chestR = 0.45 * shoulderScale;

    // ── Zone checks with quality (0..1 closeness) ───────────────────────
    final wristS = raw[0];
    final indexTipS = raw[8];
    final middleTipS = raw[12];

    final zqMouthW = _zoneQ(a.mouthCenter, wristS, mouthR);
    final zqMouthI = _zoneQ(a.mouthCenter, indexTipS, mouthR);
    final zqMouthM = _zoneQ(a.mouthCenter, middleTipS, mouthR);
    final zqNoseW = _zoneQ(a.nose, wristS, noseR);
    final zqNoseI = _zoneQ(a.nose, indexTipS, noseR * 0.85);
    final zqEyeI = _zoneQ(a.eyeCenter, indexTipS, eyeR);
    final zqEarI = math.max(_zoneQ(a.rightEar, indexTipS, earR), _zoneQ(a.leftEar, indexTipS, earR));
    final zqEarW = math.max(_zoneQ(a.rightEar, wristS, earR), _zoneQ(a.leftEar, wristS, earR));
    final zqChestW = _zoneQ(a.chestCenter, wristS, chestR);
    final zqCheekW = _zoneQ(a.mouthCenter, wristS, cheekR);

    final isWristNearMouth = zqMouthW > 0;
    final isIndexNearMouth = zqMouthI > 0;
    final isMiddleNearMouth = zqMouthM > 0;
    final isWristNearNose = zqNoseW > 0;
    final isIndexNearNose = zqNoseI > 0;
    final isIndexNearEye = zqEyeI > 0;
    final isNearEar = zqEarI > 0;
    final isWristNearEar = zqEarW > 0;

    // Face-anchor zones overlap heavily (the nose sits within a generous ear
    // radius, etc.), so pointing-family rules additionally require their
    // anchor to be the CLOSEST face anchor to the fingertip. This is the
    // anatomical disambiguator between ear/eye/nose/mouth pointing.
    double nd(SGPoint? anchor) =>
        (anchor == null) ? 99.0 : indexTipS.dist2D(anchor) / faceScale;
    final ndNose = nd(a.nose);
    final ndEye = nd(a.eyeCenter);
    final ndMouth = nd(a.mouthCenter);
    final ndEar = math.min(nd(a.leftEar), nd(a.rightEar));
    final noseIsClosest = ndNose <= ndEye && ndNose <= ndEar && ndNose <= ndMouth;
    final eyeIsClosest = ndEye <= ndNose && ndEye <= ndEar;
    final earIsClosest = ndEar <= ndNose && ndEar <= ndEye && ndEar <= ndMouth;
    final mouthIsClosest = ndMouth <= ndNose && ndMouth <= ndEye && ndMouth <= ndEar;

    final eyeCenter = a.eyeCenter;
    final isAboveEyes = eyeCenter != null && wristS.y < eyeCenter.y - 0.25 * faceScale;
    final isNearForehead = _zoneQ(eyeCenter, wristS, foreheadR) > 0 && isAboveEyes;
    final isNearCheek = zqCheekW > 0 && !isWristNearMouth;
    final isNearChest = zqChestW > 0;
    final isNearChin = a.mouthCenter != null &&
        wristS.dist2D(a.mouthCenter!) < chinR &&
        wristS.y > a.mouthCenter!.y - 0.02;

    // Shape quality: how decisively fingers are extended/curled.
    final shapeQ = _shapeQuality(
      thumbAngle, indexAngle, middleAngle, ringAngle, pinkyAngle,
      isThumbExt, isIndexExt, isMiddleExt, isRingExt, isPinkyExt,
    ) * (frame.hasMediaPipeHand ? 1.0 : 0.45);

    String best = '';
    double bestBase = 0, bestZQ = 0;

    // Helper: keep the highest-scoring rule (first match at equal base wins).
    void rule(String sign, bool cond, double base, double zq) {
      if (!cond) return;
      final score = base + zq * 0.01;
      if (score > bestBase) {
        best = sign;
        bestBase = base;
        bestZQ = zq;
      }
    }

    // ═══ ANCHORED RULES (priority: high specificity first) ═══
    rule('callonphone', isYShape && isWristNearEar, 0.95, zqEarW);
    rule('hear', isCShape && isWristNearEar, 0.93, zqEarW);
    rule('ear', isPointing && isNearEar && earIsClosest, 0.95, zqEarI);
    rule('sleep', (isFlatHand || isOpenPalm) && isWristNearEar && !isAboveEyes, 0.92, zqEarW);

    rule('see', isPeace && isIndexNearEye && eyeIsClosest, 0.93, zqEyeI);
    rule('eye', isPointing && isIndexNearEye && eyeIsClosest, 0.94, zqEyeI);

    rule('nose', isPointing && isIndexNearNose && noseIsClosest, 0.94, zqNoseI);
    rule('pig', isFist && isWristNearNose, 0.90, zqNoseW);

    rule('bird', isPinch && !isMiddleExt && isIndexNearMouth, 0.92, zqMouthI);
    rule('water', isWShape && (isWristNearMouth || isNearChin), 0.95, math.max(zqMouthW, 0.3));
    rule('food', isPinch && isWristNearMouth, 0.93, zqMouthW);
    rule('drink', isCShape && isWristNearMouth, 0.93, zqMouthW);
    rule('taste', isMiddleExt && !isIndexExt && isMiddleNearMouth, 0.90, zqMouthM);
    rule('mouth', isPointing && isIndexNearMouth && mouthIsClosest, 0.91, zqMouthI);
    rule('chin', isPointing && isNearChin, 0.90, 0.4);
    rule('mom', isOpenPalm && isNearChin && isThumbExt, 0.91, 0.4);
    rule('dad', isOpenPalm && isNearForehead && isThumbExt, 0.91, 0.4);
    rule('milk', isFist && isWristNearMouth, 0.89, zqMouthW);

    rule('think', isPointing && isNearForehead, 0.92, 0.4);
    rule('head', isOpenPalm && isNearForehead && !isThumbExt, 0.89, 0.4);
    rule('hat', isFlatHand && isAboveEyes, 0.89, 0.4);

    rule('face', isPointing && isNearCheek, 0.89, zqCheekW);

    rule('please', isFlatHand && isNearChest && isPalmFacing, 0.92, zqChestW);
    rule('like', isPinch && isNearChest, 0.89, zqChestW);

    // NOTE: catch-all free-space rules (open / there / scissors / bye /
    // close / give / book / stop / help / sorry / sad) were intentionally
    // removed:
    //  * bare-shape rules fired on random gestures (idle false positives),
    //  * stop/help/sorry are absent from the 250-class label map,
    //  * sad/bye are motion-defined and unrecognizable from a static frame,
    //  * book IS in the label map but needs both hands hinged together —
    //    one flat palm is indistinguishable from 'please'/'hello', so the
    //    temporal model owns it.
    //
    // Second sweep (fake-guess removal) — every removed word is in the 250
    // map, so the temporal model owns it and the static geometric proxy only
    // added idle false positives:
    //  * hello — waving is motion-defined; an open palm held above the eyes
    //    is a near-constant idle pose.
    //  * yes / no — thumbs-up/down are conversational gestures, not the ASL
    //    signs (fist nodding / index-middle tapping the thumb).
    //  * airplane (ILY and Y) — location-free rules fired on the extremely
    //    common ILY/shaka handshapes anywhere in frame; the sign is a glide.
    //  * cow — horns anywhere means "rock on"; the sign needs the head.
    //  * happy — ASL happy circles at the CHEST; a palm resting at the
    //    cheek is the most common touch-face idle pose.

    if (best.isEmpty) {
      // No rule this frame — decay streak; after a sustained unrecognized
      // stretch clear the committed sign so idle hands show NOTHING instead
      // of a stale sign sticking on screen.
      _streak = 0;
      _prevSign = '';
      _noRuleStreak++;
      if (_noRuleStreak >= _commitClearAfter && _committedSign.isNotEmpty) {
        _committedSign = '';
        _committedConf = 0.0;
      }
      return GeometricFrameOutcome(
        candidate: '', committedSign: _committedSign,
        committedConfidence: _committedConf, handPresent: true,
        trackingSource: src,
      );
    }
    _noRuleStreak = 0;

    // ── Debounce: commit after N consecutive identical candidates ───────
    if (best == _prevSign) {
      _streak++;
    } else {
      _prevSign = best;
      _streak = 1;
    }
    if (_streak >= _debounceFrames) {
      _committedSign = best;
      _committedConf = (0.55 * bestBase + 0.30 * bestZQ + 0.15 * shapeQ)
          .clamp(0.05, 0.99);
    }

    return GeometricFrameOutcome(
      candidate: best,
      committedSign: _committedSign,
      committedConfidence: _committedConf,
      handPresent: true,
      trackingSource: src,
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────

  /// Face scale from ear separation; falls back to a fraction of shoulder
  /// width, then to a conservative absolute.
  double _faceScale(SignAnchors a) {
    if (a.leftEar != null && a.rightEar != null) {
      final d = a.leftEar!.dist2D(a.rightEar!);
      if (d > 0.01) return d;
    }
    final s = _shoulderScale(a);
    if (s > 0.02) return s * 0.35;
    return 0.10;
  }

  double _shoulderScale(SignAnchors a) {
    if (a.leftShoulder != null && a.rightShoulder != null) {
      final d = a.leftShoulder!.dist2D(a.rightShoulder!);
      if (d > 0.02) return d;
    }
    return 0.30;
  }

  /// Closeness of [point] to [anchor] inside [radius]: 1.0 = on the anchor,
  /// 0.0 = at the edge, negative-safe (null anchor → 0).
  double _zoneQ(SGPoint? anchor, SGPoint point, double radius) {
    if (anchor == null || radius <= 0) return 0;
    return (1.0 - point.dist2D(anchor) / radius).clamp(0.0, 1.0).toDouble();
  }

  bool _isExt(double pipAngle, double dipAngle, int tipIdx, int mcpIdx, List<List<double>> sp) {
    // PIP angle is the primary signal. DIP alone must NOT classify extension:
    // hook-curled fingers keep a straight DIP while the PIP is clearly bent.
    if (pipAngle > _extThresh) return true;
    final tip = _len(sp[tipIdx]);
    final mcp = _len(sp[mcpIdx]);
    return dipAngle > _extThresh && pipAngle > _curlThresh + 20 || tip > mcp * 1.3;
  }

  /// How decisively each finger is on the correct side of the extension
  /// decision boundary (0..1 mean).
  double _shapeQuality(
    double tA, double iA, double mA, double rA, double pA,
    bool tE, bool iE, bool mE, bool rE, bool pE,
  ) {
    double m(double angle, bool ext) => ext
        ? ((angle - _extThresh) / 40.0).clamp(0.0, 1.0)
        : ((_curlThresh - angle) / 40.0).clamp(0.0, 1.0);
    final vals = [m(tA, tE), m(iA, iE), m(mA, mE), m(rA, rE), m(pA, pE)];
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  /// Infer dominant-hand side. Coordinates are third-person (unmirrored) on
  /// BOTH cameras — the front camera's raw sensor frame already matches the
  /// training convention — so the signer's right hand is on image-left in
  /// either case (x < body center).
  bool _inferRightHand(SignFrameData f) {
    final bc = f.anchors.bodyCenterX;
    if (bc == null) return true; // assume right-handed dominant
    return f.hand[0].x < bc;
  }

  double _d(List<double> a, List<double> b) => math.sqrt(
      (a[0] - b[0]) * (a[0] - b[0]) + (a[1] - b[1]) * (a[1] - b[1]) + (a[2] - b[2]) * (a[2] - b[2]));
  double _len(List<double> a) => math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);

  double _angle(List<double> a, List<double> b, List<double> c) {
    final bax = a[0] - b[0], bay = a[1] - b[1], baz = a[2] - b[2];
    final bcx = c[0] - b[0], bcy = c[1] - b[1], bcz = c[2] - b[2];
    final dot = bax * bcx + bay * bcy + baz * bcz;
    final m1 = math.sqrt(bax * bax + bay * bay + baz * baz);
    final m2 = math.sqrt(bcx * bcx + bcy * bcy + bcz * bcz);
    if (m1 < 1e-9 || m2 < 1e-9) return 180.0;
    final cosA = (dot / (m1 * m2)).clamp(-1.0, 1.0);
    return math.acos(cosA) * 180.0 / math.pi;
  }
}
