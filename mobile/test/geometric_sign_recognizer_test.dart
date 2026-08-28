import 'package:flutter_test/flutter_test.dart';
import 'package:travelease/models/services/sign_frame_data.dart';
import 'package:travelease/models/services/sign_clip_recorder.dart';
import 'package:travelease/models/services/geometric_sign_recognizer.dart';
import 'package:travelease/models/services/sign_accuracy_evaluator.dart';

/// Synthetic hand/anchor geometry used to verify the geometric recognizer
/// end-to-end (Phase 0.2 harness validation).
///
/// Coordinate space: screen-normalized 0..1, y grows downward, front camera
/// (mirrored) semantics. Fingers extend upward (decreasing y) from the
/// finger-base row at [baseY]; wrist sits below at [wristY].

const _ts = 1000;

SignFrameData _frame({
  required List<SGPoint> hand,
  bool front = true,
  int ts = _ts,
}) {
  return SignFrameData(
    hand: hand,
    anchors: const SignAnchors(
      nose: SGPoint(0.48, 0.35),
      leftEar: SGPoint(0.38, 0.32),
      rightEar: SGPoint(0.58, 0.32),
      mouthCenter: SGPoint(0.48, 0.42),
      eyeCenter: SGPoint(0.48, 0.28),
      chestCenter: SGPoint(0.48, 0.62),
      leftShoulder: SGPoint(0.33, 0.55),
      rightShoulder: SGPoint(0.63, 0.55),
      bodyCenterX: 0.48,
    ),
    hasMediaPipeHand: true,
    isFrontCamera: front,
    timestampMs: ts,
  );
}

/// Curled finger: MCP at (dx, baseY), folds back toward the palm.
List<SGPoint> _curled(double dx, double baseY) => [
      SGPoint(dx + 0.005, baseY), // MCP
      SGPoint(dx + 0.015, baseY - 0.03), // PIP (bent sharply)
      SGPoint(dx + 0.025, baseY), // DIP (hooked)
      SGPoint(dx + 0.030, baseY + 0.03), // TIP
    ];

/// Straight extended finger from (dx, baseY) up to tipY.
List<SGPoint> _extended(double dx, double baseY, double tipY) => [
      SGPoint(dx, baseY),
      SGPoint(dx - 0.002, baseY - (baseY - tipY) * 0.38),
      SGPoint(dx - 0.004, baseY - (baseY - tipY) * 0.72),
      SGPoint(dx - 0.006, tipY),
    ];

/// Builds a 21-point hand. [baseY] is the finger-base row; [wrist] the wrist.
/// Per-finger overrides: null = curled default; `_extended` for straight.
List<SGPoint> _hand({
  SGPoint wrist = const SGPoint(0.5, 0.70),
  double baseY = 0.58,
  List<SGPoint>? thumb,
  List<SGPoint>? index,
  List<SGPoint>? middle,
  List<SGPoint>? ring,
  List<SGPoint>? pinky,
}) {
  List<SGPoint> chain(List<SGPoint>? pts, double dx) => pts ?? _curled(dx, baseY);

  final t = chain(thumb, 0.44);
  final i = chain(index, 0.47);
  final m = chain(middle, 0.50);
  final r = chain(ring, 0.53);
  final p = chain(pinky, 0.56);

  return [
    wrist,
    t[0], t[1], t[2], t[3],
    i[0], i[1], i[2], i[3],
    m[0], m[1], m[2], m[3],
    r[0], r[1], r[2], r[3],
    p[0], p[1], p[2], p[3],
  ];
}

/// Runs [frames] through a fresh recognizer and returns the final outcome.
GeometricFrameOutcome _settle(List<SignFrameData> frames) {
  final rec = GeometricSignRecognizer();
  GeometricFrameOutcome o = const GeometricFrameOutcome(
    candidate: '', committedSign: '', committedConfidence: 0,
    handPresent: false, trackingSource: '',
  );
  for (final f in frames) {
    o = rec.processFrame(f);
  }
  return o;
}

List<SignFrameData> _repeat(List<SGPoint> hand, {int n = 5}) => [
      for (int i = 0; i < n; i++) _frame(hand: hand, ts: _ts + i * 100),
    ];

/// Index fingertip touching the nose anchor (0.48, 0.35).
List<SGPoint> _pointAtNose() => _hand(index: _extended(0.47, 0.58, 0.36));

void main() {
  group('GeometricSignRecognizer (synthetic frames)', () {
    test('pointing at nose -> "nose" after debounce', () {
      final o = _settle(_repeat(_pointAtNose()));

      expect(o.committedSign, 'nose');
      expect(o.committedConfidence, greaterThan(0.5));
      expect(o.committedConfidence, lessThan(1.0));
      expect(o.trackingSource, 'mediapipe');
    });

    test('fist at nose -> "pig"', () {
      // Fist held up at the face: finger bases near the nose, wrist below.
      final hand = _hand(
        wrist: const SGPoint(0.49, 0.47),
        baseY: 0.40,
      );
      final o = _settle(_repeat(hand));

      expect(o.committedSign, 'pig');
    });

    test('Y-hand near right ear -> "callonphone"', () {
      final hand = _hand(
        wrist: const SGPoint(0.60, 0.34),
        thumb: [
          const SGPoint(0.585, 0.30),
          const SGPoint(0.575, 0.26),
          const SGPoint(0.565, 0.22),
          const SGPoint(0.555, 0.18),
        ],
        pinky: _extended(0.615, 0.58, 0.22),
      );
      final o = _settle(_repeat(hand));

      expect(o.committedSign, 'callonphone');
    });

    test('thumbs up -> "yes" (fist verified by tucked fingertips)', () {
      final hand = _hand(
        thumb: [
          const SGPoint(0.44, 0.56),
          const SGPoint(0.435, 0.53),
          const SGPoint(0.43, 0.50),
          const SGPoint(0.425, 0.47),
        ],
      );
      final o = _settle(_repeat(hand));

      expect(o.committedSign, 'yes');
    });

    test('thumbs down -> "no"', () {
      final hand = _hand(
        thumb: [
          const SGPoint(0.44, 0.62),
          const SGPoint(0.435, 0.68),
          const SGPoint(0.43, 0.74),
          const SGPoint(0.425, 0.80),
        ],
      );
      final o = _settle(_repeat(hand));

      expect(o.committedSign, 'no');
    });

    test('committed sign clears after sustained unrecognized frames', () {
      final rec = GeometricSignRecognizer();
      for (int i = 0; i < 5; i++) {
        rec.processFrame(_frame(hand: _pointAtNose(), ts: _ts + i * 100));
      }
      expect(rec.committedSign, 'nose');

      final idle = _hand(
        wrist: const SGPoint(0.80, 0.75),
        index: _extended(0.47, 0.58, 0.40),
        middle: _extended(0.50, 0.58, 0.38),
        ring: _extended(0.53, 0.58, 0.40),
        pinky: _extended(0.56, 0.58, 0.43),
      );
      for (int i = 0; i < 20; i++) {
        rec.processFrame(_frame(hand: idle, ts: _ts + 1000 + i * 100));
      }
      expect(rec.committedSign, isEmpty,
          reason: 'idle hand must clear the stale committed sign');
    });

    test('open palm in true free space commits NOTHING (catch-alls removed)', () {
      // Wrist far from chest/face anchors — no anchored rule may fire.
      final hand = _hand(
        wrist: const SGPoint(0.80, 0.75),
        index: _extended(0.47, 0.58, 0.40),
        middle: _extended(0.50, 0.58, 0.38),
        ring: _extended(0.53, 0.58, 0.40),
        pinky: _extended(0.56, 0.58, 0.43),
      );

      for (int i = 0; i < 6; i++) {
        final o = GeometricSignRecognizer()
            .processFrame(_frame(hand: hand, ts: _ts + i * 100));
        expect(o.committedSign, isEmpty,
            reason: 'idle open palm away from anchors must not produce a sign');
      }
    });

    test('reset() clears committed sign after hand loss', () {
      final rec = GeometricSignRecognizer();
      for (int i = 0; i < 5; i++) {
        rec.processFrame(_frame(hand: _pointAtNose(), ts: _ts + i * 100));
      }
      expect(rec.committedSign, 'nose');

      rec.reset();
      expect(rec.committedSign, isEmpty);
    });

    test('tracking gap (>400ms) resets EMA without crashing', () {
      final rec = GeometricSignRecognizer();
      rec.processFrame(_frame(hand: _pointAtNose(), ts: _ts));
      final o = rec.processFrame(_frame(hand: _pointAtNose(), ts: _ts + 5000));
      expect(o.handPresent, isTrue);
    });
  });

  group('SignAccuracyEvaluator', () {
    test('majority vote scores clips and reports confusions', () {
      final clip = SignClip(label: 'nose', frames: [
        for (int i = 0; i < 5; i++) _frame(hand: _pointAtNose(), ts: _ts + i * 100),
      ]);

      final report = const SignAccuracyEvaluator().evaluate([clip]);
      expect(report.totalClips, 1);
      expect(report.top1Accuracy, 1.0);
      expect(report.clips.first.predictedSign, 'nose');
    });
  });

  group('SignFrameData JSON round-trip', () {
    test('survives encode/decode', () {
      final frame = _frame(hand: _hand(index: _extended(0.47, 0.58, 0.40)));
      final decoded = SignFrameData.fromJson(frame.toJson());

      expect(decoded.hand.length, 21);
      expect(decoded.hasMediaPipeHand, frame.hasMediaPipeHand);
      expect(decoded.anchors.nose!.x, frame.anchors.nose!.x);
      expect(decoded.timestampMs, frame.timestampMs);
    });
  });
}
