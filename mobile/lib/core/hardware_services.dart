import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:camera/camera.dart';

/// Global Hardware & Device Sensors Helper
class HardwareServices {
  static final HardwareServices _instance = HardwareServices._internal();
  factory HardwareServices() => _instance;
  HardwareServices._internal();

  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final AudioPlayer _cuePlayer = AudioPlayer();
  static final Map<String, Uint8List> _toneCache = {};

  bool _isTtsInitialized = false;
  bool _isSpeechInitialized = false;
  bool _speechSupported = false;
  List<stt.LocaleName> _availableLocales = [];
  List<CameraDescription> _availableCameras = [];

  /// Per-session STT status listener (set on each startListening call)
  void Function(String status)? _speechStatusListener;

  /// Locale actually passed to the recognizer on the last startListening call
  String? _lastUsedLocaleId;
  bool _lastLocaleMatched = true;

  String? get lastUsedLocaleId => _lastUsedLocaleId;

  /// Whether the requested language was found among the device's installed
  /// recognizer locales (false means the OS may not support that language).
  bool get lastLocaleMatched => _lastLocaleMatched;

  /// Per-session STT error listener (set on each startListening call)
  void Function(String errorCode)? _speechErrorListener;

  List<CameraDescription> get cameras => _availableCameras;

  /// Whether the native speech recognizer is currently listening
  bool get isListening => _speech.isListening;

  /// Initialize real device TTS, STT, and camera list
  Future<void> initialize() async {
    await _initTts();
    await _initCameras();
    await _initSpeech();
  }

  Future<void> _initTts() async {
    try {
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
      await _tts.setSpeechRate(0.5); // Normal speed
      await _tts.awaitSpeakCompletion(true);
      _isTtsInitialized = true;
    } catch (e) {
      debugPrint('TTS init error: $e');
    }
  }

  Future<void> _initCameras() async {
    try {
      _availableCameras = await availableCameras();
    } catch (e) {
      debugPrint('No physical camera detected or web fallback: $e');
    }
  }

  Future<void> _initSpeech() async {
    try {
      final status = await Permission.microphone.request();
      if (status.isGranted) {
        _speechSupported = await _speech.initialize(
          onError: (SpeechRecognitionError val) {
            debugPrint('STT Error handler: ${val.errorMsg}');
            _speechErrorListener?.call(val.errorMsg);
          },
          onStatus: (String val) {
            debugPrint('STT Status handler: $val');
            _speechStatusListener?.call(val);
          },
          finalTimeout: const Duration(milliseconds: 3000),
        );
        if (_speechSupported) {
          _availableLocales = await _speech.locales();
        }
        _isSpeechInitialized = true;
      }
    } catch (e) {
      debugPrint('STT init error: $e');
      _speechSupported = false;
    }
  }

  /// Speak text aloud through the physical device speaker (TTS)
  Future<void> speak({
    required String text,
    String language = 'en', // 'en', 'ms', 'zh'
    double speed = 1.0,
    double volume = 1.0,
    String voiceGender = 'female',
  }) async {
    if (text.trim().isEmpty) return;

    try {
      if (!_isTtsInitialized) {
        await _initTts();
      }

      // Map language code to TTS locale candidates — some engines register
      // only the bare language ('ms', 'zh') while others want the region tag.
      List<String> localeCandidates = ['en-US'];
      if (language == 'ms' || language.toLowerCase().contains('my')) {
        localeCandidates = ['ms-MY', 'ms'];
      } else if (language == 'zh' || language.toLowerCase().contains('cn')) {
        localeCandidates = ['zh-CN', 'zh'];
      }

      var languageSet = false;
      for (final candidate in localeCandidates) {
        try {
          final result = await _tts.setLanguage(candidate);
          if ('$result' == '1') {
            languageSet = true;
            break;
          }
        } catch (e) {
          debugPrint('TTS voice $candidate failed: $e');
        }
      }
      if (!languageSet) {
        debugPrint(
            'No TTS voice installed for $language — install it via '
            'Settings > Accessibility > Text-to-speech output > voice data.');
      }
      final rate = (speed * 0.5).clamp(0.1, 1.0);
      await _tts.setSpeechRate(rate);
      await _tts.setVolume(volume.clamp(0.0, 1.0));

      // Some engines never fire the completion event for a missing voice
      // (e.g. no ms-MY TTS), which would hang the dialogue loop forever —
      // force a stop after 15s so the conversation always continues.
      await _tts.speak(text).timeout(
            const Duration(seconds: 15),
            onTimeout: () async {
              debugPrint('TTS completion timeout — forcing stop');
              await _tts.stop();
            },
          );
    } catch (e) {
      debugPrint('Error speaking via TTS: $e');
    }
  }

  /// Stop any active speech output
  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (e) {
      debugPrint('TTS stop error: $e');
    }
  }

  /// Locale IDs actually installed on this device (for diagnostics).
  List<String> get installedSttLocales =>
      _availableLocales.map((l) => l.localeId).toList();

  /// Neighbour languages acceptable as stand-in recognizers: Bahasa
  /// Indonesia overlaps Malay heavily in vocabulary and grammar.
  static const Map<String, List<String>> _neighbourLanguages = {
    'ms': ['id'],
    'id': ['ms'],
  };

  /// Closest recognizer locale for [languageLocale] (e.g. 'ms_MY').
  /// Resolution order:
  /// 1. Exact match            — ms_MY
  /// 2. Same-language variants — any zh_* serves Mandarin (zh_CN/zh_TW/zh_SG/zh_HK)
  /// 3. Neighbour language     — Bahasa Indonesia for Bahasa Melayu
  /// 4. The requested id itself
  ///
  /// NEVER returns null: many recognizers accept languages that locales()
  /// omits (freshly downloaded voice packs are a common case), so the device
  /// list alone must not disqualify a language — runtime errors decide that.
  String bestSttLocaleFor(String languageLocale) {
    String norm(String id) => id.toLowerCase().replaceAll('-', '_');
    final requested = norm(languageLocale);
    if (_availableLocales.isEmpty) {
      debugPrint(
          'STT locale list unavailable; requesting $requested directly.');
      return languageLocale;
    }

    final normalizedIds =
        _availableLocales.map((l) => norm(l.localeId)).toList();

    // 1. Exact match
    for (var i = 0; i < normalizedIds.length; i++) {
      if (normalizedIds[i] == requested) return _availableLocales[i].localeId;
    }

    // 2. Any regional variant of the same language (e.g. zh_TW for zh_CN)
    final lang = requested.split('_').first;
    for (var i = 0; i < normalizedIds.length; i++) {
      if (normalizedIds[i].split('_').first == lang) {
        debugPrint(
            'STT locale fallback: $requested -> ${_availableLocales[i].localeId} (variant)');
        return _availableLocales[i].localeId;
      }
    }

    // 3. Neighbour-language stand-in (ms_MY -> id_ID)
    for (final neighbour in _neighbourLanguages[lang] ?? const <String>[]) {
      for (var i = 0; i < normalizedIds.length; i++) {
        if (normalizedIds[i].split('_').first == neighbour) {
          debugPrint(
              'STT locale fallback: $requested -> ${_availableLocales[i].localeId} (neighbour)');
          return _availableLocales[i].localeId;
        }
      }
    }

    // 4. Not listed — still try it; the engine may support it anyway.
    debugPrint(
        'STT locale $requested not in device list; requesting directly.');
    return languageLocale;
  }

  /// Resolve the locale to hand to the recognizer. An installed variant wins
  /// (zh_CN -> zh_TW, ms_MY -> id_ID); a language NOT in the device list is
  /// requested DIRECTLY — downloaded voice packs are often missing from
  /// locales() but still work. Never silently swapped for a random installed
  /// locale (that bug turned every Malay turn into English (Malaysia)).
  String _resolveSttLocale(String languageLocale) {
    final best = bestSttLocaleFor(languageLocale);
    if (_availableLocales.isEmpty) return best;
    final normalizedBest = best.toLowerCase().replaceAll('-', '_');
    for (final loc in _availableLocales) {
      if (loc.localeId.toLowerCase().replaceAll('-', '_') == normalizedBest) {
        return loc.localeId;
      }
    }
    return best;
  }

  /// Start live microphone audio transcription (STT) in the requested language
  Future<bool> startListening({
    required Function(String text, double confidence) onResult,
    String languageLocale = 'en_US',
    void Function(String text, double confidence)? onFinalResult,
    void Function(String status)? onStatus,
    void Function(String errorCode)? onError,
  }) async {
    try {
      final status = await Permission.microphone.request();
      if (status.isDenied || status.isPermanentlyDenied) {
        debugPrint('Microphone permission denied');
        return false;
      }

      if (!_isSpeechInitialized) {
        await _initSpeech();
      }
      _speechStatusListener = onStatus;
      _speechErrorListener = onError;

      if (_speechSupported && _speech.isAvailable) {
        final targetLocale = _resolveSttLocale(languageLocale);
        debugPrint('STT locale requested: $languageLocale -> resolved: $targetLocale');

        // Record whether the resolved locale really covers the requested
        // language so callers can detect silent OS substitution.
        String norm(String id) => id.toLowerCase().replaceAll('-', '_');
        _lastUsedLocaleId = targetLocale;
        _lastLocaleMatched =
            norm(targetLocale).split('_').first == norm(languageLocale).split('_').first;

        await _speech.listen(
          onResult: (result) {
            onResult(result.recognizedWords, result.confidence);
            if (result.finalResult) {
              onFinalResult?.call(result.recognizedWords, result.confidence);
            }
          },
          listenOptions: stt.SpeechListenOptions(
            // LANGUAGE_MODEL_WEB_SEARCH (search mode) instead of free-form:
            // Google's free-form model covers very few languages on most
            // devices — Bahasa Malaysia and Mandarin typically ONLY work
            // through the web-search model even when voice packs installed.
            listenMode: stt.ListenMode.search,
            partialResults: true,
            cancelOnError: false,
            localeId: targetLocale,
          ),
        );
        return true;
      } else {
        debugPrint('Native STT not available; using fallback recognition.');
        return false;
      }
    } catch (e) {
      debugPrint('Error starting STT: $e');
      return false;
    }
  }

  /// Stop live microphone transcription
  Future<void> stopListening() async {
    try {
      if (_speech.isListening) {
        await _speech.stop();
      }
    } catch (e) {
      debugPrint('Error stopping STT: $e');
    }
  }

  // --------------------------------------------------------------------------
  // Audible listening cues (Google Translate-style 'ding')
  // --------------------------------------------------------------------------

  /// Bright 'ding' when the microphone goes live.
  Future<void> playListenStartCue() => _playCueTone('start', 1046.50, 110);

  /// Slightly lower 'ding' when a sentence is captured.
  Future<void> playListenResultCue() => _playCueTone('result', 783.99, 160);

  /// Low tone when listening is switched off.
  Future<void> playListenStopCue() => _playCueTone('stop', 523.25, 180);

  Future<void> _playCueTone(String key, double frequencyHz, int durationMs) async {
    try {
      final wav = _toneCache.putIfAbsent(
        key,
        () => _generateToneWav(frequencyHz, durationMs),
      );
      await _cuePlayer.stop();
      await _cuePlayer.play(BytesSource(wav, mimeType: 'audio/wav'));
    } catch (e) {
      debugPrint('Listen cue failed: $e');
    }
  }

  /// Builds a 16-bit PCM mono WAV entirely in memory — a sine beep with short
  /// fade-in/out so no speaker clicks are audible. No asset files needed.
  Uint8List _generateToneWav(double frequencyHz, int durationMs) {
    const int sampleRate = 44100;
    final int totalSamples = (sampleRate * durationMs / 1000).round();
    final int fadeSamples =
        totalSamples < 200 ? totalSamples ~/ 2 : sampleRate ~/ 100;

    final ByteData wav = ByteData(44 + totalSamples * 2);
    void ascii(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        wav.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    wav.setUint32(4, 36 + totalSamples * 2, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    wav.setUint32(16, 16, Endian.little); // PCM chunk size
    wav.setUint16(20, 1, Endian.little); // PCM format
    wav.setUint16(22, 1, Endian.little); // mono
    wav.setUint32(24, sampleRate, Endian.little);
    wav.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    wav.setUint16(32, 2, Endian.little); // block align
    wav.setUint16(34, 16, Endian.little); // bits per sample
    ascii(36, 'data');
    wav.setUint32(40, totalSamples * 2, Endian.little);

    for (var i = 0; i < totalSamples; i++) {
      double envelope = 1.0;
      if (i < fadeSamples) envelope = i / fadeSamples;
      if (i >= totalSamples - fadeSamples) {
        envelope = (totalSamples - i) / fadeSamples;
      }
      final sample = math.sin(2 * math.pi * frequencyHz * i / sampleRate) *
          envelope *
          0.6;
      wav.setInt16(44 + i * 2, (sample * 32767).round(), Endian.little);
    }
    return wav.buffer.asUint8List();
  }

  /// Request runtime permissions for Camera and Microphone
  Future<bool> requestCameraAndMicPermissions() async {
    final statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    return statuses[Permission.camera]?.isGranted == true;
  }
}
