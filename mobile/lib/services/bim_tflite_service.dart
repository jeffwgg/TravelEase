import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import 'bim_sign_recognition_service.dart';
import 'sign_frame_data.dart';

/// On-device BIM word recognition: the exported BIM-SIGN Pose BiLSTM
/// (slr/scripts/export_tflite.py) run over live gesture windows.
///
/// This is a frame-accurate port of `predict_sign` in `slr/scripts/demo.py` —
/// guards, idle trimming, the mirror-flip x multi-temporal-scale ensemble, and
/// shoulder-center standardization must all stay in lockstep with the desktop
/// inference, because the model's real-webcam accuracy was tuned against that
/// exact pipeline (see the README ablation notes).
///
/// STATE HYGIENE: the converter exports the LSTM with arena-backed state
/// tensors that leak between invokes — each classification MUST start from
/// zeroed state. tflite_flutter 0.12.1's `resetVariableTensors()` cannot be
/// used: its deleted-flag guard is inverted upstream and it throws
/// `Bad state: Should not acces delegate after it has been closed.` on every
/// call against a healthy interpreter. This service instead builds a FRESH
/// Interpreter per clip (the asset bytes are cached; creation is single-digit
/// ms) and closes it afterwards — a new interpreter's state is zeroed by
/// definition. (The Python parity harness uses ai_edge_litert's working
/// `reset_all_variables()` instead.)
///
/// It recognises ONE word per clip. Phrase assembly stays in the shared
/// word→phrase step (the viewmodel's gloss list), identical in spirit to how
/// ASL accumulates words — no BIM-only templates are applied here.
class BimTfliteService {
  static final BimTfliteService _instance = BimTfliteService._internal();
  factory BimTfliteService() => _instance;
  BimTfliteService._internal();

  static const int _fixedFrames = 64;
  static const double _poseVisFloor = 0.15;
  static const double _handMotionFloor = 0.01;
  static const int _maxGlosses = 8;
  static const String _modelAsset = 'assets/models/bim_model.tflite';

  Map<int, String> _indexToGloss = {};
  List<double> _mean = const [], _std = const [];
  bool _isInitialized = false;
  String? _lastError;
  Future<void>? _initFuture;

  bool get isModelLoaded => _isInitialized;
  String? get lastError => _lastError;
  int get glossCount => _indexToGloss.length;

  /// Top-1 minus runner-up probability from the last recognizeClip.
  double lastMargin = 0;

  /// Load model, label map and normalization stats. Concurrent callers share
  /// ONE load: without the in-flight guard two paths (dialect warm-up +
  /// first window) could each build an Interpreter and the loser's native
  /// arena would leak — the extra memory pressure visibly slows the camera
  /// loop in every mode, ASL included.
  Future<void> initialize() {
    if (_isInitialized) return Future.value();
    final pending = _initFuture;
    if (pending != null) return pending;
    late final Future<void> future;
    future = _doInitialize().whenComplete(() {
      // Clear the slot only after a failure (retry allowed); keep it on
      // success so every later call short-circuits via _isInitialized.
      if (!_isInitialized && identical(_initFuture, future)) {
        _initFuture = null;
      }
    });
    _initFuture = future;
    return future;
  }

  Future<void> _doInitialize() async {
    try {
      final labelJson = await rootBundle
          .loadString('assets/models/bim_sign_to_prediction_index_map.json');
      final Map<String, dynamic> raw = json.decode(labelJson);
      _indexToGloss = <int, String>{
        for (final e in raw.entries) (e.value as num).toInt(): e.key,
      };

      final statsJson =
          await rootBundle.loadString('assets/models/bim_norm_stats.json');
      final stats = json.decode(statsJson) as Map<String, dynamic>;
      _mean = (stats['mean'] as List).cast<num>().map((v) => v.toDouble()).toList();
      _std = (stats['std'] as List).cast<num>().map((v) => v.toDouble()).toList();
      if (_mean.length != kBimChannels || _std.length != kBimChannels) {
        throw StateError('bim_norm_stats.json must hold 258-value arrays');
      }

      final probe = await Interpreter.fromAsset(_modelAsset);
      final inShape = probe.getInputTensor(0).shape;
      final outShape = probe.getOutputTensor(0).shape;
      probe.close();
      if (outShape.last != _indexToGloss.length) {
        throw StateError('model has ${outShape.last} classes but the label '
            'map holds ${_indexToGloss.length} — re-run export_tflite.py');
      }
      _isInitialized = true;
      _lastError = null;
      debugPrint('[BimTfliteService] Model loaded – ${_indexToGloss.length} '
          'glosses, input: $inShape, output: $outShape '
          '(fresh interpreter per clip)');
    } catch (e) {
      _lastError = e.toString();
      _initFuture = null; // allow a retry after a failed load
      debugPrint('[BimTfliteService] Initialization failed: $e');
    }
  }

  /// Recognise one BIM word from a gesture window. Runs the 12 ensemble
  /// views on a fresh Interpreter, yielding to the event loop between
  /// forwards so the camera stream keeps feeding the skeleton overlay while
  /// a word is being classified.
  ///
  /// Returns the shared [BimSignRecognition] shape so the viewmodel path is
  /// identical to the HTTP API's: word, confidence, and the accumulated
  /// gloss list with the new word appended (last 8 kept, like the server did).
  /// [malay]/[chinese]/[english] currently carry the accumulated gloss words
  /// verbatim — sentence templates are deferred until ASL and BIM share one
  /// word→phrase step.
  Future<BimSignRecognition> recognizeClip(
    List<SignFrameData> frames, {
    required List<String> previousGlosses,
  }) async {
    final p = _prepareViews(frames);
    final it = await Interpreter.fromAsset(_modelAsset);
    try {
      final origProbs = <List<double>>[];
      for (final s in p.seqsOrig) {
        origProbs.add(_runForProbs(it, s));
        await Future<void>.delayed(Duration.zero);
      }
      final flipProbs = <List<double>>[];
      for (final s in p.seqsFlip) {
        flipProbs.add(_runForProbs(it, s));
        await Future<void>.delayed(Duration.zero);
      }
      return _aggregate(p, origProbs, flipProbs, previousGlosses);
    } finally {
      it.close();
    }
  }

  /// Guards + trimming + the 2-orientation × 2-candidate × 3-time-scale
  /// view construction (mirrors predict_sign's setup in demo.py).
  _PreparedBimViews _prepareViews(List<SignFrameData> frames) {
    if (!isModelLoaded) {
      throw const BimSignRecognitionException(
        'The on-device BIM model is not loaded yet. '
        'Check that assets/models/bim_model.tflite is present.',
      );
    }
    if (frames.length < 5) {
      throw const BimSignRecognitionException(
        'Recording too short — sign one word for about 0.8–4 seconds.',
      );
    }

    final arr = frames.map(buildBimTensor).toList(growable: false);

    // Detection-quality guard: garbage input must not become a confident
    // guess (mirrors predict_sign's pose_vis / hand_motion checks).
    double visSum = 0;
    for (final frame in arr) {
      for (int i = 0; i < 33; i++) {
        visSum += frame[i * 4 + 3];
      }
    }
    final poseVis = visSum / (arr.length * 33);
    if (poseVis < _poseVisFloor) {
      throw const BimSignRecognitionException(
        'I could not see you clearly — move closer, keep your face and hands '
        'in frame with good light, then try again.',
      );
    }
    final handMotion =
        math.max(_stdOfBlocks(arr, 132, 3), _stdOfBlocks(arr, 195, 3));
    if (handMotion < _handMotionFloor) {
      throw const BimSignRecognitionException(
        'No hand movement detected — raise your hands into view and sign '
        'the word once.',
      );
    }

    final trimmed = _trimIdle(arr);
    // Orientation views: the dataset is unmirrored webcam footage while the
    // selfie stream may arrive mirrored; classify both orientations and keep
    // whichever is more confident (the same fix that recovered 16% -> 97%
    // in the desktop demo).
    List<List<List<double>>> buildSeqs(List<List<double>> base) {
      final seqs = <List<List<double>>>[];
      for (final candidate in [base, arr]) {
        for (final scale in [1.0, 0.55, 1.6]) {
          final l = (candidate.length * scale).toInt();
          final sub = l == candidate.length
              ? candidate
              : _resample(candidate, math.max(10, l));
          final seq = _resample(sub, _fixedFrames);
          seqs.add(_standardize(_normalizeInPlace(seq)));
        }
      }
      return seqs;
    }

    return _PreparedBimViews(
      buildSeqs(trimmed),
      buildSeqs(_flipKeypoints(trimmed)),
      poseVis,
      handMotion,
    );
  }

  BimSignRecognition _aggregate(
    _PreparedBimViews p,
    List<List<double>> origProbs,
    List<List<double>> flipProbs,
    List<String> previousGlosses,
  ) {
    double viewMax(List<List<double>> views) =>
        views.map((p) => p.reduce(math.max)).fold(0.0, math.max);
    final views = viewMax(flipProbs) > viewMax(origProbs) ? flipProbs : origProbs;
    final probs = List<double>.filled(_indexToGloss.length, 0.0);
    for (final view in views) {
      for (int i = 0; i < probs.length; i++) {
        probs[i] += view[i];
      }
    }
    for (int i = 0; i < probs.length; i++) {
      probs[i] /= views.length;
    }

    final ranked = List.generate(probs.length, (i) => MapEntry(i, probs[i]))
      ..sort((a, b) => b.value.compareTo(a.value));
    final word = _indexToGloss[ranked.first.key] ?? '';
    final confidence = ranked.first.value;
    // Runner-up gap: the live pipeline uses (margin or confidence) to accept
    // a word, mirroring the ASL acceptance gate.
    lastMargin = ranked.length > 1
        ? confidence - ranked[1].value
        : confidence;
    debugPrint('[BimTfliteService] top3: '
        '${ranked.take(3).map((e) => '${_indexToGloss[e.key]} '
            '(${e.value.toStringAsFixed(2)})').join(', ')} '
        '(pose vis ${p.poseVis.toStringAsFixed(2)}, '
        'hand motion ${p.handMotion.toStringAsFixed(3)})');

    final allGlosses = [...previousGlosses, word];
    final glossPhrase = allGlosses.length > _maxGlosses
        ? allGlosses.sublist(allGlosses.length - _maxGlosses)
        : allGlosses;
    final joined = glossPhrase.join(' ');
    return BimSignRecognition(
      word: word,
      confidence: confidence,
      glosses: List.unmodifiable(glossPhrase),
      malay: joined,
      chinese: joined,
      english: joined,
      matched: false,
    );
  }

  // ─── model forward ──────────────────────────────────────────────────────

  List<double> _runForProbs(Interpreter it, List<List<double>> seq) {
    final numClasses = it.getOutputTensor(0).shape.last;
    final input = <List<List<double>>>[seq];
    final output = <List<double>>[List<double>.filled(numClasses, 0.0)];
    it.run(input, output);
    final logits = output[0];
    final maxLogit = logits.reduce(math.max);
    final exps = logits.map((v) => math.exp(v - maxLogit)).toList();
    final sum = exps.reduce((a, b) => a + b);
    return exps.map((v) => v / sum).toList(growable: false);
  }

  // ─── preprocessing port of dataset.py / demo.py helpers ─────────────────

  /// Population standard deviation of one strided channel block, pooled over
  /// all frames — np.std over arr[:, start:end:stride].
  static double _stdOfBlocks(List<List<double>> seq, int start, int stride) {
    final values = <double>[];
    for (final frame in seq) {
      for (int c = start; c < start + 63; c += stride) {
        values.add(frame[c]);
      }
    }
    if (values.isEmpty) return 0.0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final variance =
        values.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
            values.length;
    return math.sqrt(variance);
  }

  /// Cut leading/trailing stillness using cumulative keypoint motion
  /// (dataset.py trim_idle, low=0.05 high=0.95 pad=5).
  static List<List<double>> _trimIdle(List<List<double>> seq) {
    if (seq.length < 12) return seq;
    final motion = <double>[];
    double total = 0;
    for (int t = 1; t < seq.length; t++) {
      double m = 0;
      for (int c = 0; c < kBimChannels; c++) {
        m += (seq[t][c] - seq[t - 1][c]).abs();
      }
      motion.add(m);
      total += m;
    }
    if (total < 1e-6) return seq;
    final cum = <double>[];
    double acc = 0;
    for (final m in motion) {
      acc += m;
      cum.add(acc / total);
    }
    // np.searchsorted(cum, x) is side='left': first index where cum[idx] >= x.
    int searchLeft(double x) {
      int lo = 0, hi = cum.length;
      while (lo < hi) {
        final mid = (lo + hi) ~/ 2;
        if (cum[mid] < x) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      return lo;
    }

    final i0 = math.max(0, searchLeft(0.05) - 5);
    final i1 = math.min(seq.length, searchLeft(0.95) + 1 + 5);
    return i1 - i0 >= 10 ? seq.sublist(i0, i1) : seq;
  }

  /// Linear time resample (T, 258) -> (target, 258), np.interp semantics.
  static List<List<double>> _resample(List<List<double>> seq, int target) {
    final t = seq.length;
    if (t == target) {
      return List.generate(target, (i) => List.of(seq[i]), growable: false);
    }
    return List.generate(target, (out) {
      final pos = out * (t - 1) / (target - 1);
      final lo = pos.floor(), hi = pos.ceil();
      final frac = pos - lo;
      return List.generate(
        kBimChannels,
        (c) => seq[lo][c] + (seq[hi][c] - seq[lo][c]) * frac,
        growable: false,
      );
    }, growable: false);
  }

  /// Mirror horizontally: x -> 1 - x on pose and both hand blocks, then swap
  /// the hand blocks (dataset.py flip_keypoints).
  static List<List<double>> _flipKeypoints(List<List<double>> seq) {
    return List.generate(seq.length, (t) {
      final out = List<double>.of(seq[t]);
      for (int i = 0; i < 33; i++) {
        out[i * 4] = 1.0 - out[i * 4];
      }
      for (int block = 132; block < 258; block += 63) {
        for (int i = 0; i < 21; i++) {
          out[block + i * 3] = 1.0 - out[block + i * 3];
        }
      }
      final tmp = out.sublist(132, 195);
      out.setRange(132, 195, out.sublist(195, 258));
      out.setRange(195, 258, tmp);
      return out;
    }, growable: false);
  }

  /// Standardize all channels with the training mean/std (norm_stats.npz),
  /// exactly like demo.py: (normalize_keypoints(seq) - MEAN) / STD.
  List<List<double>> _standardize(List<List<double>> seq) {
    for (final frame in seq) {
      for (int c = 0; c < kBimChannels; c++) {
        frame[c] = (frame[c] - _mean[c]) / _std[c];
      }
    }
    return seq;
  }

  /// Center pose x/y at the mid-shoulders, scale by shoulder width
  /// (dataset.py normalize_keypoints: pose landmarks 11/12, x/y only).
  static List<List<double>> _normalizeInPlace(List<List<double>> seq) {
    for (final frame in seq) {
      final lx = frame[11 * 4], ly = frame[11 * 4 + 1];
      final rx = frame[12 * 4], ry = frame[12 * 4 + 1];
      final cx = (lx + rx) / 2, cy = (ly + ry) / 2;
      final scale = math.max(math.sqrt((lx - rx) * (lx - rx) + (ly - ry) * (ly - ry)), 1e-6);
      for (int i = 0; i < 33; i++) {
        frame[i * 4] = (frame[i * 4] - cx) / scale;
        frame[i * 4 + 1] = (frame[i * 4 + 1] - cy) / scale;
      }
    }
    return seq;
  }

  void dispose() {
    // Interpreters are per-clip and closed by recognizeClip; nothing to
    // release here beyond resetting init state.
    _isInitialized = false;
    _initFuture = null;
  }
}

/// Prepared ensemble inputs for one clip: 6 sequences from the original
/// orientation and 6 from the mirrored one (2 candidates × 3 time scales),
/// plus the detection-quality readings logged with the result.
class _PreparedBimViews {
  _PreparedBimViews(this.seqsOrig, this.seqsFlip, this.poseVis, this.handMotion);

  final List<List<List<double>>> seqsOrig;
  final List<List<List<double>>> seqsFlip;
  final double poseVis;
  final double handMotion;
}
