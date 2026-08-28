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

  /// Run inference on a temporal window of landmark frames.
  ///
  /// [frames] is a list of flat 543x3 tensors (one per frame), already
  /// resampled and preprocessed by the caller to match the model's expected
  /// frame count.
  Map<String, dynamic> predictWindow(List<List<double>> frames) {
    final flat = <double>[];
    for (final f in frames) {
      flat.addAll(f);
    }
    return predictGesture(flat);
  }

  /// Run inference on a flat list of landmark values.
  ///
  /// [landmarks] should match the model's expected input shape.
  /// For the GISLR model this is typically 543 landmark points × 3 coords.
  ///
  /// Returns `{'character': String, 'confidence': double, 'index': int}`.
  Map<String, dynamic> predictGesture(List<double> landmarks) {
    if (!isModelLoaded) {
      return {'character': '', 'confidence': 0.0, 'index': -1};
    }

    try {
      final inputTensor  = _interpreter!.getInputTensor(0);
      final outputTensor = _interpreter!.getOutputTensor(0);
      final inputShape   = inputTensor.shape;
      final outputShape  = outputTensor.shape;

      // Reshape input to match model expectations
      final input = _reshapeInput(landmarks, inputShape);

      // Prepare output buffer — handle both [250] and [1, 250] output shapes
      final List<double> scores;
      if (outputShape.length == 1) {
        // Flat output: [numClasses]
        final flatOutput = List<double>.filled(outputShape[0], 0.0);
        _interpreter!.run(input, flatOutput);
        scores = flatOutput;
      } else {
        // Batched output: [1, numClasses]
        final batchOutput = List<List<double>>.generate(
          1, (_) => List<double>.filled(outputShape.last, 0.0),
        );
        _interpreter!.run(input, batchOutput);
        scores = batchOutput[0];
      }

      // Find top prediction
      int bestIndex = 0;
      double bestScore = scores[0];
      for (int i = 1; i < scores.length; i++) {
        if (scores[i] > bestScore) {
          bestScore = scores[i];
          bestIndex = i;
        }
      }

      // Sort indices by score to find top 5
      final indexedScores = List.generate(scores.length, (i) => MapEntry(i, scores[i]))
        ..sort((a, b) => b.value.compareTo(a.value));

      final top5 = indexedScores.take(5).map((e) {
        final sign = _indexToSign[e.key] ?? '#${e.key}';
        return '$sign (${e.value.toStringAsFixed(2)})';
      }).join(', ');

      debugPrint('[AslTfliteService] Top 5 candidates: $top5');

      // Apply softmax if scores don't look like probabilities
      double confidence = bestScore;
      if (bestScore > 1.0 || bestScore < 0.0) {
        confidence = _softmaxMax(scores);
      }

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

  /// Decode a prediction index to the sign word label.
  String decodeIndex(int index) {
    return _indexToSign[index] ?? 'unknown';
  }

  /// Look up the prediction index for a sign word.
  int? encodeSign(String signWord) {
    return _signToIndex[signWord.toLowerCase()];
  }

  /// Reshape a flat landmark list into the tensor shape the model expects.
  dynamic _reshapeInput(List<double> flat, List<int> shape) {
    // Pad or truncate to match expected flat size
    int totalElements = shape.fold(1, (a, b) => a * b);
    List<double> padded = List<double>.filled(totalElements, 0.0);
    for (int i = 0; i < flat.length && i < totalElements; i++) {
      padded[i] = flat[i];
    }

    // Reshape based on number of dimensions
    if (shape.length == 3) {
      // [1, landmarks, 3] or [batch, seq, features]
      return _reshape3D(padded, shape);
    } else if (shape.length == 4) {
      // [1, frames, landmarks, 3]
      return _reshape4D(padded, shape);
    } else if (shape.length == 2) {
      // [1, features]
      return [padded.sublist(0, shape[1])];
    }

    return [padded];
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

  /// Compute softmax and return the maximum probability.
  double _softmaxMax(List<double> logits) {
    final maxLogit = logits.reduce((a, b) => a > b ? a : b);
    final exps = logits.map((l) => math.exp((l - maxLogit).clamp(-80.0, 80.0))).toList();
    final sum = exps.reduce((a, b) => a + b);
    final probs = exps.map((e) => e / sum).toList();
    return probs.reduce((a, b) => a > b ? a : b);
  }

  void dispose() {
    _interpreter?.close();
    _interpreter = null;
    _isInitialized = false;
  }
}
