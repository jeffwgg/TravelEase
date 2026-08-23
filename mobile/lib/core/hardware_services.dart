import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
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

  bool _isTtsInitialized = false;
  bool _isSpeechInitialized = false;
  bool _speechSupported = false;
  List<stt.LocaleName> _availableLocales = [];
  List<CameraDescription> _availableCameras = [];

  List<CameraDescription> get cameras => _availableCameras;

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
          onError: (SpeechRecognitionError val) => debugPrint('STT Error handler: ${val.errorMsg}'),
          onStatus: (String val) => debugPrint('STT Status handler: $val'),
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

      // Map language code to TTS locale
      String langLocale = 'en-US';
      if (language == 'ms' || language.toLowerCase().contains('my')) {
        langLocale = 'ms-MY';
      } else if (language == 'zh' || language.toLowerCase().contains('cn')) {
        langLocale = 'zh-CN';
      }

      await _tts.setLanguage(langLocale);
      final rate = (speed * 0.5).clamp(0.1, 1.0);
      await _tts.setSpeechRate(rate);
      await _tts.setVolume(volume.clamp(0.0, 1.0));

      await _tts.speak(text);
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

  /// Start live microphone audio transcription (STT) in the requested language
  Future<bool> startListening({
    required Function(String text, double confidence) onResult,
    String languageLocale = 'en_US',
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

      if (_speechSupported && _speech.isAvailable) {
        // Resolve best matching locale on the device
        String targetLocale = languageLocale;
        if (_availableLocales.isNotEmpty) {
          final prefix = languageLocale.split('_').first.toLowerCase();
          final match = _availableLocales.firstWhere(
            (loc) => loc.localeId.toLowerCase().startsWith(prefix) || loc.localeId.toLowerCase().contains(prefix),
            orElse: () => _availableLocales.first,
          );
          targetLocale = match.localeId;
        }

        await _speech.listen(
          onResult: (result) {
            onResult(result.recognizedWords, result.confidence);
          },
          listenOptions: stt.SpeechListenOptions(
            listenMode: stt.ListenMode.confirmation,
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

  /// Request runtime permissions for Camera and Microphone
  Future<bool> requestCameraAndMicPermissions() async {
    final statuses = await [
      Permission.camera,
      Permission.microphone,
    ].request();

    return statuses[Permission.camera]?.isGranted == true;
  }
}
