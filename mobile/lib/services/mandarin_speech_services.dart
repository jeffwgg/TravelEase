import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:huawei_ml_language/huawei_ml_language.dart';
import 'package:permission_handler/permission_handler.dart';

/// Mandarin speech built on Huawei ML Kit (HMS Core) — used because the
/// WGR-W09's system engines expose no Chinese (verified by the diagnostics
/// screen: HiAI TTS lists 13 languages, none Chinese; the Google recognizer
/// only offers en_MY).
///
/// Authentication uses a programmatic API key (HMS_API_KEY in .env) so no
/// agconnect-services.json / AGCP plugin is required. If the key is missing
/// or HMS Core is unavailable, callers get [MandarinSpeechException] and can
/// fall back to the system engines.
///
///   await MandarinTts.instance.speak('你好，欢迎使用我们的应用');
///   final text = await MandarinAsr.instance.listen();
class MandarinSpeechException implements Exception {
  final MandarinSpeechError error;
  final String message;
  final int? nativeCode;

  MandarinSpeechException(this.error, this.message, {this.nativeCode});

  @override
  String toString() =>
      'MandarinSpeechException(${error.name}${nativeCode != null ? '/$nativeCode' : ''}): $message';
}

enum MandarinSpeechError {
  hmsUnavailable,
  apiKeyMissing,
  mandarinUnavailable,
  microphonePermissionDenied,
  networkUnavailable,
  serviceUnavailable,
  noSpeechRecognized,
  ttsFailed,
  timeout,
}

/// Shared init: sets the AGC API key (from .env) once before any cloud call.
class MandarinSpeech {
  static bool _authApplied = false;
  static String? lastInitProblem;

  /// True when an HMS Core-powered backend can be attempted.
  static Future<bool> ensureInitialized() async {
    if (_authApplied) return lastInitProblem == null;
    _authApplied = true;
    final apiKey = _apiKey();
    if (apiKey == null || apiKey.isEmpty) {
      lastInitProblem = 'HMS_API_KEY is empty — add the AppGallery Connect '
          'API key to .env to enable Huawei ML Kit speech.';
      debugPrint('[MandarinSpeech] $lastInitProblem');
      return false;
    }
    try {
      await MLLanguageApp().setApiKey(apiKey);
      return true;
    } catch (e) {
      lastInitProblem = 'HMS Core unavailable: $e';
      debugPrint('[MandarinSpeech] $lastInitProblem');
      return false;
    }
  }

  static String? _apiKey() {
    try {
      return dotenv.maybeGet('HMS_API_KEY');
    } catch (_) {
      return null;
    }
  }
}

/// Mandarin text-to-speech through ML Kit.
///
///   await MandarinTts.instance.speak('你好，欢迎使用我们的应用');
class MandarinTts {
  static final MandarinTts instance = MandarinTts._();
  MandarinTts._();

  static const String language = MLTtsConstants.TTS_ZH_HANS;

  MLTtsEngine? _engine;
  Completer<void>? _speakCompleter;
  bool _speakerConfigured = false;

  /// True when ML Kit can synthesize Mandarin on this device.
  Future<bool> isAvailable() async {
    if (!await MandarinSpeech.ensureInitialized()) return false;
    try {
      final result = await _engineOrThrow().isLanguageAvailable(language);
      return result == MLTtsConstants.LANGUAGE_AVAILABLE ||
          result == MLTtsConstants.LANGUAGE_UPDATING;
    } catch (e) {
      debugPrint('[MandarinTts] availability check failed: $e');
      return false;
    }
  }

  MLTtsEngine _engineOrThrow() {
    if (_engine == null) {
      _engine = MLTtsEngine();
      _engine!.setTtsCallback(MLTtsCallback(
        onError: _onError,
        onEvent: _onEvent,
        onWarn: (taskId, warn) =>
            debugPrint('[MandarinTts] warn: ${warn.warnMsg ?? warn}'),
      ));
    }
    return _engine!;
  }

  void _onError(String taskId, MLTtsError err) {
    debugPrint('[MandarinTts] error ${err.errorId}: ${err.errorMsg}');
    final completer = _speakCompleter;
    _speakCompleter = null;
    if (completer?.isCompleted == false) {
      completer!.completeError(MandarinSpeechException(
        MandarinSpeechError.ttsFailed,
        err.errorMsg ?? 'ML Kit TTS error',
        nativeCode: err.errorId,
      ));
    }
  }

  void _onEvent(String taskId, int eventId) {
    // EVENT_SYNTHESIS_COMPLETE fires when every queued segment finished.
    if (eventId == MLTtsConstants.EVENT_SYNTHESIS_COMPLETE) {
      final completer = _speakCompleter;
      _speakCompleter = null;
      if (completer?.isCompleted == false) completer!.complete();
    }
  }

  /// Speaks [text] in Mandarin and completes when playback finishes.
  ///
  /// [speed]/[volume] are ML Kit multipliers (1.0 = normal). Throws
  /// [MandarinSpeechException] on failure — catch it to fall back to the
  /// system TTS engine.
  Future<void> speak(
    String text, {
    double speed = 1.0,
    double volume = 1.0,
    String speaker = MLTtsConstants.TTS_SPEAKER_FEMALE_ZH,
  }) async {
    if (text.trim().isEmpty) return;
    if (!await MandarinSpeech.ensureInitialized()) {
      throw MandarinSpeechException(
        MandarinSpeechError.apiKeyMissing,
        MandarinSpeech.lastInitProblem ?? 'HMS API key not configured',
      );
    }
    await stop();
    final engine = _engineOrThrow();
    if (!_speakerConfigured) {
      try {
        engine.setPlayerVolume(100); // 0-100 scale for the internal player.
      } catch (_) {}
      _speakerConfigured = true;
    }

    final completer = Completer<void>();
    _speakCompleter = completer;

    try {
      await engine.speak(MLTtsConfig(
        text: text,
        language: language,
        person: speaker,
        speed: speed.clamp(0.5, 2.0),
        volume: volume.clamp(0.0, 2.0),
        queuingMode: MLTtsEngine.QUEUE_FLUSH,
        synthesizeMode: MLTtsConstants.TTS_ONLINE_MODE,
      ));
    } catch (e) {
      _speakCompleter = null;
      throw MandarinSpeechException(
        MandarinSpeechError.hmsUnavailable,
        'ML Kit TTS speak() failed: $e',
      );
    }

    // ~4 chars/second for Mandarin plus a network/startup buffer.
    final budget = Duration(
        seconds: (text.length / 4).ceil() + 12);
    try {
      await completer.future.timeout(budget, onTimeout: () {
        debugPrint('[MandarinTts] completion timeout — forcing stop');
        stop();
        throw MandarinSpeechException(
          MandarinSpeechError.timeout,
          'TTS playback did not finish within ${budget.inSeconds}s',
        );
      });
    } on MandarinSpeechException {
      rethrow;
    }
  }

  Future<void> stop() async {
    try {
      _engine?.stop();
    } catch (_) {}
    final completer = _speakCompleter;
    _speakCompleter = null;
    if (completer?.isCompleted == false) completer!.complete();
  }

  void dispose() {
    try {
      _engine?.shutdown();
    } catch (_) {}
    _engine = null;
  }
}

/// Mandarin speech-to-text through ML Kit (cloud ASR, ≤60 s per utterance).
///
///   final text = await MandarinAsr.instance.listen();
///   final text = await MandarinAsr.instance.listen(
///       onPartial: (p) => debugPrint(p));
class MandarinAsr {
  static final MandarinAsr instance = MandarinAsr._();
  MandarinAsr._();

  /// Recognized Chinese text, or throws [MandarinSpeechException].
  Future<String> listen({
    void Function(String partialText)? onPartial,
    Duration maxDuration = const Duration(seconds: 30),
  }) async {
    if (!await MandarinSpeech.ensureInitialized()) {
      throw MandarinSpeechException(
        MandarinSpeechError.apiKeyMissing,
        MandarinSpeech.lastInitProblem ?? 'HMS API key not configured',
      );
    }

    final micStatus = await Permission.microphone.request();
    if (micStatus.isDenied || micStatus.isPermanentlyDenied) {
      throw MandarinSpeechException(
        MandarinSpeechError.microphonePermissionDenied,
        'Microphone permission was not granted',
      );
    }

    final completer = Completer<String>();
    var bestPartial = '';
    final recognizer = MLAsrRecognizer();

    void finish(String text) {
      if (completer.isCompleted) return;
      completer.complete(text);
    }

    void fail(MandarinSpeechException exception) {
      if (completer.isCompleted) return;
      completer.completeError(exception);
    }

    recognizer.setAsrListener(MLAsrListener(
      onRecognizingResults: (partial) {
        bestPartial = partial;
        onPartial?.call(partial);
      },
      onResults: (result) {
        debugPrint('[MandarinAsr] final: $result');
        result.trim().isEmpty
            ? fail(MandarinSpeechException(
                MandarinSpeechError.noSpeechRecognized,
                'Recognizer returned an empty result'))
            : finish(result);
      },
      onError: (code, message) {
        debugPrint('[MandarinAsr] error $code: $message');
        fail(_mapAsrError(code, message));
      },
      onState: (state) {
        if (state == MLAsrConstants.STATE_NO_NETWORK) {
          fail(MandarinSpeechException(
            MandarinSpeechError.networkUnavailable,
            'No network — ML Kit ASR is cloud-based',
            nativeCode: state,
          ));
        }
      },
    ));

    final watchdog = Timer(maxDuration, () {
      if (completer.isCompleted) return;
      bestPartial.trim().isEmpty
          ? fail(MandarinSpeechException(
              MandarinSpeechError.timeout,
              'No speech recognized within ${maxDuration.inSeconds}s'))
          : finish(bestPartial);
    });

    try {
      recognizer.startRecognizing(MLAsrSetting(
        language: MLAsrConstants.LAN_ZH_CN,
        feature: MLAsrConstants.FEATURE_WORDFLUX,
      ));
    } catch (e) {
      watchdog.cancel();
      recognizer.destroy();
      throw MandarinSpeechException(
        MandarinSpeechError.hmsUnavailable,
        'Could not start ML Kit ASR: $e',
      );
    }

    try {
      return await completer.future;
    } finally {
      watchdog.cancel();
      recognizer.destroy();
    }
  }

  MandarinSpeechException _mapAsrError(int code, String message) {
    switch (code) {
      case MLAsrConstants.ERR_NO_NETWORK:
        return MandarinSpeechException(MandarinSpeechError.networkUnavailable,
            'No network connection',
            nativeCode: code);
      case MLAsrConstants.ERR_SERVICE_UNAVAILABLE:
        return MandarinSpeechException(MandarinSpeechError.serviceUnavailable,
            'Huawei speech service is unavailable — try again later',
            nativeCode: code);
      case MLAsrConstants.ERR_NO_UNDERSTAND:
        return MandarinSpeechException(MandarinSpeechError.noSpeechRecognized,
            'Speech could not be recognized',
            nativeCode: code);
      case MLAsrConstants.ERR_INVALIDATE_TOKEN:
        return MandarinSpeechException(MandarinSpeechError.apiKeyMissing,
            'AGC authentication failed — check HMS_API_KEY / AGC app config',
            nativeCode: code);
      default:
        return MandarinSpeechException(
          MandarinSpeechError.serviceUnavailable,
          message,
          nativeCode: code,
        );
    }
  }
}
