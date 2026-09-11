import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

/// Service to load and run inference on the ASL TFLite model (250 signs).
///
/// This service is **sign-language-agnostic** in its landmark input format:
/// the same MediaPipe Holistic landmarks (hands, pose, face) are used regardless
/// of whether the model recognises ASL, BIM, or CSL. Only the `.tflite` model
/// file and label map need to change per language.
class AslTfliteService {
  static final AslTfliteService _instance = AslTfliteService._internal();
  factory AslTfliteService() => _instance;
  AslTfliteService._internal();

  Interpreter? _interpreter;
  Map<int, String> _indexToSign = {};
  Map<String, int> _signToIndex = {};

  bool _isInitialized = false;
  String? _lastError;

  bool get isModelLoaded => _isInitialized && _interpreter != null;
  String? get lastError => _lastError;
  int get signCount => _indexToSign.length;
  Map<int, String> get indexToSign => Map.unmodifiable(_indexToSign);
  Map<String, int> get signToIndex => Map.unmodifiable(_signToIndex);

  /// Initialize model and label map from Flutter assets.
  ///
  /// Call once at app startup or before first inference.
  /// Safe to call multiple times — subsequent calls are no-ops.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 1. Load label map
      await _loadLabelMap();

      // 2. Load TFLite model
      await _loadModel();

      _isInitialized = true;
      _lastError = null;
      debugPrint('[AslTfliteService] Model loaded – ${_indexToSign.length} signs, '
          'input: ${_interpreter!.getInputTensors().map((t) => t.shape)}, '
          'output: ${_interpreter!.getOutputTensors().map((t) => t.shape)}');
    } catch (e) {
      _lastError = e.toString();
      debugPrint('[AslTfliteService] Initialization failed: $e');
    }
  }

  Future<void> _loadLabelMap() async {
    final jsonStr = await rootBundle.loadString('assets/models/sign_to_prediction_index_map.json');
    final Map<String, dynamic> raw = json.decode(jsonStr);

    _signToIndex = raw.map((k, v) => MapEntry(k, (v as num).toInt()));
    _indexToSign = _signToIndex.map((k, v) => MapEntry(v, k));
  }

  Future<void> _loadModel() async {
    _interpreter = await Interpreter.fromAsset('assets/models/model.tflite');
  }

  /// Get the input tensor shape the model expects.
  ///
  /// Typical GISLR models expect `[1, num_frames, num_landmarks, 3]` or
  /// `[1, num_landmarks, 3]` for single-frame models.
  List<int> get inputShape {
    if (_interpreter == null) return [];
    return _interpreter!.getInputTensor(0).shape;
  }

  /// Get the output tensor shape (e.g. `[1, 250]` for 250 sign classes).
  List<int> get outputShape {
    if (_interpreter == null) return [];
    return _interpreter!.getOutputTensor(0).shape;
  }

  /// Number of temporal frames the model expects, when the input is a 4D
  /// sequence `[1, frames, landmarks, 3]`. Null for single-frame models.
  int? get expectedFrameCount {
    final shape = inputShape;
    if (shape.length == 4 && shape[1] > 1) return shape[1];
    return null;
  }

  /// Run inference on a single frame of 543x3 landmark values.
  ///
  /// [landmarks] must contain exactly the model's input element count
  /// (543*3 = 1629 for the GISLR model) in dataset column order — build it
  /// with [buildGislrTensor]. Mismatched sizes are rejected instead of
  /// silently truncated.
  ///
  /// Returns `{'character': String, 'confidence': double, 'index': int}`.
  Map<String, dynamic> predictGesture(List<double> landmarks) {
    if (!isModelLoaded) {
      return {'character': '', 'confidence': 0.0, 'index': -1};
    }

    try {
      final probs = _predictProbs(landmarks);

      final indexedScores = List.generate(probs.length, (i) => MapEntry(i, probs[i]))
        ..sort((a, b) => b.value.compareTo(a.value));

      final top5 = indexedScores.take(5).map((e) {
        final sign = _indexToSign[e.key] ?? '#${e.key}';
        return '$sign (${e.value.toStringAsFixed(2)})';
      }).join(', ');

      debugPrint('[AslTfliteService] Top 5 candidates: $top5');

      final bestIndex = indexedScores.first.key;
      final confidence = indexedScores.first.value;

      final signWord = _indexToSign[bestIndex] ?? 'unknown';
      debugPrint('[AslTfliteService] Top sign: "$signWord" (index=$bestIndex, confidence=${confidence.toStringAsFixed(3)})');

      return {
        'character': signWord,
        'confidence': confidence,
        'index': bestIndex,
      };
    } catch (e) {
      debugPrint('[AslTfliteService] Prediction error: $e');
      return {'character': '', 'confidence': 0.0, 'index': -1};
    }
  }

  /// Run per-frame inference over a closed gesture window.
  ///
  /// The GISLR model is a single-frame classifier (`[1, 543, 3]`): each
  /// entry of [frames] is inferred on its own and the per-frame class
  /// probabilities are averaged, approximating a temporal vote without a
  /// temporal model. Frames must all be flat 543x3 tensors (see
  /// [buildGislrTensor]); confidence is the winning class's mean
  /// probability across frames.
  Map<String, dynamic> predictFrames(List<List<double>> frames) {
    if (!isModelLoaded || frames.isEmpty) {
      return {'character': '', 'confidence': 0.0, 'index': -1};
    }

    try {
      final numClasses = _interpreter!.getOutputTensor(0).shape.last;
      final meanProbs = List<double>.filled(numClasses, 0.0);
      int usedFrames = 0;

      for (final frame in frames) {
        try {
          final probs = _predictProbs(frame);
          for (int i = 0; i < numClasses; i++) {
            meanProbs[i] += probs[i];
          }
          usedFrames++;
        } catch (e) {
          debugPrint('[AslTfliteService] Skipping malformed frame: $e');
        }
      }
      if (usedFrames == 0) {
        return {'character': '', 'confidence': 0.0, 'index': -1};
      }
      for (int i = 0; i < numClasses; i++) {
        meanProbs[i] /= usedFrames;
      }

      int bestIndex = 0;
      for (int i = 1; i < meanProbs.length; i++) {
        if (meanProbs[i] > meanProbs[bestIndex]) bestIndex = i;
      }

      final signWord = _indexToSign[bestIndex] ?? 'unknown';
      debugPrint('[AslTfliteService] Window of ${frames.length} frames '
          '($usedFrames used) -> "$signWord" '
          '(confidence=${meanProbs[bestIndex].toStringAsFixed(3)})');

      return {
        'character': signWord,
        'confidence': meanProbs[bestIndex],
        'index': bestIndex,
      };
    } catch (e) {
      debugPrint('[AslTfliteService] Window prediction error: $e');
      return {'character': '', 'confidence': 0.0, 'index': -1};
    }
  }

  /// Run the temporal model over a closed gesture window in ONE inference.
  ///
  /// The exported GISLR model has a dynamic frame dimension: its placeholder
  /// input shape [1, 543, 3] actually means [frames, 543 landmarks, 3 coords]
  /// — TFLite reports the dynamic dim as 1 until it is resized. This resizes
  /// the frame dim to the window length, feeds the whole sequence once, and
  /// reads out a single class distribution. Each entry of [frames] must be a
  /// flat 543x3 tensor built with [buildGislrTensor]; the model embeds its
  /// own preprocessing, so frames are passed through unchanged.
  Map<String, dynamic> predictSequence(List<List<double>> frames) {
    if (!isModelLoaded || frames.isEmpty) {
      return {'character': '', 'confidence': 0.0, 'index': -1};
    }

    try {
      final inputShape = _interpreter!.getInputTensor(0).shape;
      final landmarkCount = inputShape[inputShape.length - 2];
      final coordCount = inputShape.last;
      final frameElements = landmarkCount * coordCount;

      final sequence = <List<List<double>>>[];
      for (final frame in frames) {
        if (frame.length != frameElements) {
          throw ArgumentError(
            'Each frame must contain $frameElements values '
            '($landmarkCount landmarks x $coordCount coords), got '
            '${frame.length}. Build frames with buildGislrTensor().',
          );
        }
        sequence.add(_unflattenFrame(frame, landmarkCount, coordCount));
      }

      _resizeInput(frames.length);
      final outputShape = _interpreter!.getOutputTensor(0).shape;
      final probs = _toProbabilities(_run(sequence, outputShape));

      final indexedScores = List.generate(probs.length, (i) => MapEntry(i, probs[i]))
        ..sort((a, b) => b.value.compareTo(a.value));

      final top5 = indexedScores.take(5).map((e) {
        final sign = _indexToSign[e.key] ?? '#${e.key}';
        return '$sign (${e.value.toStringAsFixed(2)})';
      }).join(', ');
      debugPrint('[AslTfliteService] Sequence(${frames.length}f) top 5: $top5');

      final bestIndex = indexedScores.first.key;
      final runnerUp = indexedScores.length > 1 ? indexedScores[1].value : 0.0;
      debugPrint('[AslTfliteService] Top sign: "${_indexToSign[bestIndex] ?? 'unknown'}" '
          '(index=$bestIndex, confidence=${probs[bestIndex].toStringAsFixed(3)})');

      return {
        'character': _indexToSign[bestIndex] ?? 'unknown',
        'confidence': probs[bestIndex],
        'margin': probs[bestIndex] - runnerUp,
        'index': bestIndex,
      };
    } catch (e) {
      debugPrint('[AslTfliteService] Sequence prediction error: $e');
      return {'character': '', 'confidence': 0.0, 'index': -1};
    }
  }

  /// Resize the model's dynamic frame dimension to [frames] and reallocate.
  void _resizeInput(int frames) {
    final shape = [..._interpreter!.getInputTensor(0).shape];
    shape[0] = frames;
    _interpreter!.resizeInputTensor(0, shape);
    _interpreter!.allocateTensors();
  }

  /// Split a flat 543x3 frame into per-landmark coordinate rows.
  List<List<double>> _unflattenFrame(List<double> flat, int landmarks, int coords) {
    return List.generate(
      landmarks,
      (i) => flat.sublist(i * coords, (i + 1) * coords),
    );
  }

  /// Run the model on one frame and return class probabilities.
  ///
  /// The frame dimension is resized back to a single frame first, so this
  /// stays correct even after [predictSequence] resized it to a window.
  ///
  /// Throws [ArgumentError] on input-size mismatch so callers never infer
  /// on silently truncated data.
  List<double> _predictProbs(List<double> landmarks) {
    _resizeInput(1);
    final inputShape = _interpreter!.getInputTensor(0).shape;
    final outputShape = _interpreter!.getOutputTensor(0).shape;
    final totalElements = inputShape.fold<int>(1, (a, b) => a * b);
    if (landmarks.length != totalElements) {
      throw ArgumentError(
        'Expected $totalElements landmark values ($inputShape), got '
        '${landmarks.length}. Build one frame with buildGislrTensor() — '
        'this model is single-frame, not temporal.',
      );
    }

    final input = _reshapeInput(landmarks, inputShape);
    final scores = _run(input, outputShape);
    return _toProbabilities(scores);
  }

  List<double> _run(dynamic input, List<int> outputShape) {
    if (outputShape.length == 1) {
      final flatOutput = List<double>.filled(outputShape[0], 0.0);
      _interpreter!.run(input, flatOutput);
      return flatOutput;
    }
    final batchOutput = List<List<double>>.generate(
      1, (_) => List<double>.filled(outputShape.last, 0.0),
    );
    _interpreter!.run(input, batchOutput);
    return batchOutput[0];
  }

  /// Decode a prediction index to the sign word label.
  String decodeIndex(int index) {
    return _indexToSign[index] ?? 'unknown';
  }

  /// Look up the prediction index for a sign word.
  int? encodeSign(String signWord) {
    return _signToIndex[signWord.toLowerCase()];
  }

  /// Reshape a size-validated flat landmark list into the tensor shape the
  /// model expects. [_predictProbs] guarantees flat.length matches the
  /// shape, so no padding or truncation happens here.
  dynamic _reshapeInput(List<double> flat, List<int> shape) {
    if (shape.length == 3) {
      // [1, landmarks, 3]
      return _reshape3D(flat, shape);
    } else if (shape.length == 4) {
      // [1, frames, landmarks, 3]
      return _reshape4D(flat, shape);
    }
    // [1, features] and any other rank: single flat batch entry.
    return [flat];
  }

  List<List<List<double>>> _reshape3D(List<double> flat, List<int> shape) {
    final d1 = shape[0], d2 = shape[1], d3 = shape[2];
    return List.generate(d1, (i) {
      return List.generate(d2, (j) {
        return List.generate(d3, (k) {
          final idx = i * d2 * d3 + j * d3 + k;
          return idx < flat.length ? flat[idx] : 0.0;
        });
      });
    });
  }

  List<List<List<List<double>>>> _reshape4D(List<double> flat, List<int> shape) {
    final d1 = shape[0], d2 = shape[1], d3 = shape[2], d4 = shape[3];
    return List.generate(d1, (i) {
      return List.generate(d2, (j) {
        return List.generate(d3, (k) {
          return List.generate(d4, (l) {
            final idx = i * d2 * d3 * d4 + j * d3 * d4 + k * d4 + l;
            return idx < flat.length ? flat[idx] : 0.0;
          });
        });
      });
    });
  }

  /// Convert raw model output to class probabilities. The GISLR model ends
  /// in softmax (output already sums to ~1); anything else is treated as
  /// logits and softmaxed here.
  List<double> _toProbabilities(List<double> scores) {
    double sum = 0;
    for (final s in scores) {
      if (s < 0.0 || s > 1.0) return _softmax(scores);
      sum += s;
    }
    if (sum > 0.98 && sum < 1.02) return scores;
    return _softmax(scores);
  }

  List<double> _softmax(List<double> logits) {
    final maxLogit = logits.reduce((a, b) => a > b ? a : b);
    final exps = logits.map((l) => math.exp((l - maxLogit).clamp(-80.0, 80.0))).toList();
    final sum = exps.reduce((a, b) => a + b);
    return exps.map((e) => e / sum).toList();
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }
}
