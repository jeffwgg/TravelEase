import 'sign_clip_recorder.dart';
import 'geometric_sign_recognizer.dart';

/// Per-clip result of the accuracy evaluation.
class ClipEvaluation {
  final String label;
  final String predictedSign; // majority vote of committed signs
  final bool correct;
  final int framesWithCommittedSign;
  final int totalFrames;

  const ClipEvaluation({
    required this.label,
    required this.predictedSign,
    required this.correct,
    required this.framesWithCommittedSign,
    required this.totalFrames,
  });
}

/// Aggregate accuracy report.
class AccuracyReport {
  final List<ClipEvaluation> clips;

  /// "label -> wrongSign" : occurrence count
  final Map<String, int> confusions;

  AccuracyReport({required this.clips, required this.confusions});

  int get totalClips => clips.length;
  int get correctClips => clips.where((c) => c.correct).length;
  double get top1Accuracy => totalClips == 0 ? 0 : correctClips / totalClips;

  /// Top-1 accuracy grouped per sign label.
  Map<String, double> accuracyPerLabel() {
    final totals = <String, int>{};
    final corrects = <String, int>{};
    for (final c in clips) {
      totals[c.label] = (totals[c.label] ?? 0) + 1;
      if (c.correct) corrects[c.label] = (corrects[c.label] ?? 0) + 1;
    }
    return totals.map((k, v) => MapEntry(k, (corrects[k] ?? 0) / v));
  }

  String toText() {
    final sb = StringBuffer();
    sb.writeln('=== Sign Recognition Accuracy Report ===');
    sb.writeln('Clips: $totalClips  Correct: $correctClips  '
        'Top-1: ${(top1Accuracy * 100).toStringAsFixed(1)}%');
    sb.writeln();
    sb.writeln('Per-label accuracy:');
    accuracyPerLabel().forEach((label, acc) {
      sb.writeln('  $label: ${(acc * 100).toStringAsFixed(0)}%');
    });
    if (confusions.isNotEmpty) {
      sb.writeln();
      sb.writeln('Confusions:');
      confusions.forEach((k, v) => sb.writeln('  $k (x$v)'));
    }
    sb.writeln();
    sb.writeln('Per-clip detail:');
    for (final c in clips) {
      sb.writeln('  [${c.correct ? 'OK' : 'MISS'}] label=${c.label} '
          'predicted="${c.predictedSign}" '
          '(${c.framesWithCommittedSign}/${c.totalFrames} frames committed)');
    }
    return sb.toString();
  }
}

/// Replays recorded clips through the live geometric recognizer and reports
/// top-1 accuracy + confusions (Phase 0.2 harness).
class SignAccuracyEvaluator {
  const SignAccuracyEvaluator();

  AccuracyReport evaluate(List<SignClip> clips) {
    final evals = <ClipEvaluation>[];
    final confusions = <String, int>{};

    for (final clip in clips) {
      // Fresh recognizer per clip so debounce/smoothing state does not leak
      // across clips — same as a fresh live session.
      final recognizer = GeometricSignRecognizer();
      final committedCounts = <String, int>{};
      int framesWithSign = 0;

      for (final frame in clip.frames) {
        final outcome = recognizer.processFrame(frame);
        if (outcome.committedSign.isNotEmpty) {
          framesWithSign++;
          committedCounts[outcome.committedSign] =
              (committedCounts[outcome.committedSign] ?? 0) + 1;
        }
      }

      // Majority vote across the clip.
      String best = '';
      int bestN = 0;
      committedCounts.forEach((sign, n) {
        if (n > bestN) {
          best = sign;
          bestN = n;
        }
      });

      final correct = best == clip.label;
      if (!correct && best.isNotEmpty) {
        final key = '${clip.label} -> $best';
        confusions[key] = (confusions[key] ?? 0) + 1;
      }

      evals.add(ClipEvaluation(
        label: clip.label,
        predictedSign: best,
        correct: correct,
        framesWithCommittedSign: framesWithSign,
        totalFrames: clip.frames.length,
      ));
    }

    return AccuracyReport(clips: evals, confusions: confusions);
  }
}
