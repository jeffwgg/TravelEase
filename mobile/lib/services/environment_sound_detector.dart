import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

import '../models/entities/environment_sound.dart';
import '../models/repositories/environment_sound_repository.dart';
import 'app_notification_service.dart';
import 'flash_alert_service.dart';

class EnvironmentSoundDetector {
  factory EnvironmentSoundDetector() => _instance;
  EnvironmentSoundDetector._();
  static final EnvironmentSoundDetector _instance =
      EnvironmentSoundDetector._();

  static const _sampleRate = 16000;
  static const _frameLength = 15600;
  static const _frameHop = 7800;
  static const _cooldown = Duration(seconds: 8);

  final AudioRecorder _recorder = AudioRecorder();
  final Queue<double> _samples = Queue<double>();
  final StreamController<SoundDetectionSnapshot> _snapshotController =
      StreamController.broadcast();
  final StreamController<EnvironmentSoundDetection> _alertController =
      StreamController.broadcast();
  final StreamController<String> _errorController =
      StreamController.broadcast();
  final EnvironmentSoundPreferences _preferences =
      EnvironmentSoundPreferences();

  Interpreter? _interpreter;
  StreamSubscription<Uint8List>? _audioSubscription;
  StreamSubscription<EnvironmentSoundDetection>? _monitoringSubscription;
  List<String> _labels = const [];
  Set<EnvironmentSoundType> _enabledTypes = EnvironmentSoundType.values.toSet();
  SoundSensitivity _sensitivity = SoundSensitivity.balanced;
  final Map<EnvironmentSoundType, DateTime> _lastAlerts = {};
  EnvironmentSoundType? _candidate;
  int _candidateHits = 0;
  int? _trailingByte;
  bool _processing = false;

  Stream<SoundDetectionSnapshot> get snapshots => _snapshotController.stream;
  Stream<EnvironmentSoundDetection> get alerts => _alertController.stream;
  Stream<String> get errors => _errorController.stream;
  bool get isMonitoring => _audioSubscription != null;

  /// Restores saved monitoring settings at app start and keeps the app-scoped
  /// alert delivery active while the detector is running in the background.
  Future<void> initializeMonitoring() async {
    _monitoringSubscription ??= alerts.listen(_handleMonitoringAlert);
    if (!await _preferences.loadEnabled()) return;
    final types = await _preferences.loadTypes();
    if (types.isEmpty) return;
    try {
      await start(
        enabledTypes: types,
        sensitivity: await _preferences.loadSensitivity(),
      );
    } catch (_) {
      // The settings page reports permission and microphone errors to the user.
    }
  }

  void _handleMonitoringAlert(EnvironmentSoundDetection detection) {
    // Spoken announcements continue through the dedicated speech-to-text
    // pipeline. The capture service sends the transcript notification.
    if (detection.type == EnvironmentSoundType.speechAnnouncement) return;
    unawaited(
      FlashAlertService.instance
          .blinkTwice(alert: true)
          .then(
            (_) => AppNotificationService.instance.showImportantSound(
              title: '${detection.type.title} detected',
              details:
                  'TravelEase heard ${detection.modelLabel.toLowerCase()} nearby.',
            ),
          ),
    );
  }

  Future<void> initialize() async {
    if (_interpreter != null) return;
    _interpreter = await Interpreter.fromAsset('assets/models/1.tflite');
    final csv = await rootBundle.loadString(
      'assets/models/yamnet_class_map.csv',
    );
    _labels = csv
        .split(RegExp(r'\r?\n'))
        .skip(1)
        .where((line) => line.trim().isNotEmpty)
        .map(_readDisplayName)
        .toList(growable: false);
  }

  Future<void> start({
    required Set<EnvironmentSoundType> enabledTypes,
    required SoundSensitivity sensitivity,
  }) async {
    if (isMonitoring) return;
    await initialize();
    if (!await _recorder.hasPermission()) {
      throw const EnvironmentSoundException(
        'Microphone permission is required to detect environmental sounds.',
      );
    }
    _enabledTypes = {...enabledTypes};
    _sensitivity = sensitivity;
    _samples.clear();
    _candidate = null;
    _candidateHits = 0;
    _trailingByte = null;

    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
        autoGain: false,
        echoCancel: false,
        noiseSuppress: false,
        streamBufferSize: 4096,
      ),
    );
    _audioSubscription = stream.listen(
      _acceptAudio,
      onError: (Object error) =>
          _emitError('Microphone stream stopped: $error'),
      onDone: () => _audioSubscription = null,
    );
  }

  void updateConfiguration({
    required Set<EnvironmentSoundType> enabledTypes,
    required SoundSensitivity sensitivity,
  }) {
    _enabledTypes = {...enabledTypes};
    _sensitivity = sensitivity;
    if (_candidate != null && !_enabledTypes.contains(_candidate)) {
      _candidate = null;
      _candidateHits = 0;
    }
  }

  Future<void> stop() async {
    final subscription = _audioSubscription;
    _audioSubscription = null;
    await subscription?.cancel();
    if (await _recorder.isRecording()) await _recorder.stop();
    _samples.clear();
    _snapshotController.add(SoundDetectionSnapshot.idle);
  }

  void _acceptAudio(Uint8List bytes) {
    var index = 0;
    if (_trailingByte case final previous?) {
      if (bytes.isNotEmpty) {
        final sample = previous | (bytes[0] << 8);
        _samples.add(_normalizeInt16(sample));
        index = 1;
        _trailingByte = null;
      }
    }
    while (index + 1 < bytes.length) {
      final sample = bytes[index] | (bytes[index + 1] << 8);
      _samples.add(_normalizeInt16(sample));
      index += 2;
    }
    if (index < bytes.length) _trailingByte = bytes[index];
    _processFrames();
  }

  double _normalizeInt16(int value) {
    final signed = value >= 0x8000 ? value - 0x10000 : value;
    return signed / 32768.0;
  }

  Future<void> _processFrames() async {
    if (_processing || _samples.length < _frameLength || _interpreter == null) {
      return;
    }
    _processing = true;
    try {
      while (_samples.length >= _frameLength && isMonitoring) {
        final frame = Float32List(_frameLength);
        var sumSquares = 0.0;
        var index = 0;
        for (final sample in _samples.take(_frameLength)) {
          frame[index++] = sample;
          sumSquares += sample * sample;
        }
        for (var removed = 0; removed < _frameHop; removed++) {
          _samples.removeFirst();
        }
        final inputLevel = math.min(
          1.0,
          math.sqrt(sumSquares / _frameLength) * 6,
        );
        _classify(frame, inputLevel);
        await Future<void>.delayed(Duration.zero);
      }
    } catch (error) {
      _emitError('Sound classification stopped: $error');
      await stop();
    } finally {
      _processing = false;
    }
  }

  void _classify(Float32List frame, double inputLevel) {
    final interpreter = _interpreter!;
    final outputSize = interpreter.getOutputTensor(0).shape.last;
    final output = [List<double>.filled(outputSize, 0)];
    final inputShape = interpreter.getInputTensor(0).shape;
    interpreter.run(inputShape.length == 1 ? frame : [frame], output);
    final scores = output.first;

    var topIndex = 0;
    var topScore = -1.0;
    for (var index = 0; index < scores.length; index++) {
      if (scores[index] > topScore) {
        topScore = scores[index];
        topIndex = index;
      }
    }
    final topLabel = topIndex < _labels.length
        ? _labels[topIndex]
        : 'Environmental sound';
    _snapshotController.add(
      SoundDetectionSnapshot(
        label: topLabel,
        score: topScore,
        inputLevel: inputLevel,
      ),
    );

    EnvironmentSoundType? bestType;
    var bestTargetScore = 0.0;
    var bestTargetLabel = '';
    for (
      var index = 0;
      index < scores.length && index < _labels.length;
      index++
    ) {
      final type = _mapLabel(_labels[index]);
      if (type != null &&
          _enabledTypes.contains(type) &&
          scores[index] > bestTargetScore) {
        bestType = type;
        bestTargetScore = scores[index];
        bestTargetLabel = _labels[index];
      }
    }

    if (bestType == null || bestTargetScore < _sensitivity.threshold) {
      _candidate = null;
      _candidateHits = 0;
      return;
    }
    if (_candidate == bestType) {
      _candidateHits++;
    } else {
      _candidate = bestType;
      _candidateHits = 1;
    }
    // Spoken announcements need an immediate handoff to speech recognition.
    // Waiting for a second YAMNet window loses too much of short PA clips.
    final isSpokenAnnouncement =
        bestType == EnvironmentSoundType.speechAnnouncement;
    if (!isSpokenAnnouncement && _candidateHits < 2 && bestTargetScore < 0.65) {
      return;
    }

    final now = DateTime.now();
    final lastAlert = _lastAlerts[bestType];
    if (lastAlert != null && now.difference(lastAlert) < _cooldown) return;
    _lastAlerts[bestType] = now;
    _candidateHits = 0;
    _alertController.add(
      EnvironmentSoundDetection(
        type: bestType,
        modelLabel: bestTargetLabel,
        score: bestTargetScore,
        detectedAt: now,
      ),
    );
  }

  EnvironmentSoundType? _mapLabel(String label) {
    final value = label.toLowerCase();
    if (value == 'speech' ||
        value.contains('public speaking') ||
        value.contains('narration, monologue') ||
        value.contains('speech synthesizer')) {
      return EnvironmentSoundType.speechAnnouncement;
    }
    if (value.contains('siren')) return EnvironmentSoundType.siren;
    if (value.contains('vehicle horn') ||
        value.contains('car horn') ||
        value.contains('train horn') ||
        value.contains('air horn') ||
        value.contains('truck horn') ||
        value.contains('foghorn') ||
        value == 'honking') {
      return EnvironmentSoundType.vehicleHorn;
    }
    // Exact matches only: labels like "Bellow" and "Belly laugh" also
    // contain "bell" as a substring and must not map here.
    if (value.contains('doorbell') ||
        value.contains('ding-dong') ||
        value.contains('door knock') ||
        value == 'knock' ||
        value == 'bell' ||
        value == 'chime' ||
        value == 'ding' ||
        value == 'tubular bells' ||
        value == 'church bell' ||
        value == 'jingle bell' ||
        value == 'telephone bell ringing') {
      return EnvironmentSoundType.doorbell;
    }
    if (value.contains('alarm') ||
        value.contains('smoke detector') ||
        value == 'buzzer' ||
        value == 'beep, bleep') {
      return EnvironmentSoundType.alarm;
    }
    return null;
  }

  String _readDisplayName(String line) {
    final firstComma = line.indexOf(',');
    final secondComma = line.indexOf(',', firstComma + 1);
    if (secondComma == -1) return line.trim();
    var value = line.substring(secondComma + 1).trim();
    if (value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1).replaceAll('""', '"');
    }
    return value;
  }

  void _emitError(String message) {
    _errorController.add(message);
  }

  Future<void> dispose() async {
    // App-scoped singleton: monitoring may continue after the settings page closes.
  }
}

class EnvironmentSoundException implements Exception {
  final String message;
  const EnvironmentSoundException(this.message);
  @override
  String toString() => message;
}
