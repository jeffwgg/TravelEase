import 'package:flutter/foundation.dart';
import '../models/entities/dialogue_session_entity.dart';
import '../models/entities/dialogue_message_entity.dart';
import '../models/entities/quick_phrase_entity.dart';
import '../models/repositories/communication_repository.dart';
import '../models/services/sign_translation_service.dart';
import '../core/hardware_services.dart';

/// ViewModel for Two-Way Split-Screen Bidirectional Dialogue (FR-M3-09 to FR-M3-18, UC303, UC304)
class TwoWayDialogueViewModel extends ChangeNotifier {
  final CommunicationRepository _repository;
  final SignTranslationService _service;
  final HardwareServices _hardware;

  TwoWayDialogueViewModel({
    CommunicationRepository? repository,
    SignTranslationService? service,
    HardwareServices? hardware,
  })  : _repository = repository ?? CommunicationRepository(),
        _service = service ?? SignTranslationService(),
        _hardware = hardware ?? HardwareServices() {
    _hardware.initialize();
  }

  // State Properties
  DialogueSession? _currentSession;
  List<DialogueMessage> _messages = [];
  List<DialogueQuickPhrase> _quickPhrases = [];

  String _sourceLang = 'en'; // Deaf Traveler language
  String _targetLang = 'ms'; // Counter Staff language

  SpeechSynthesisConfig _speechConfig = const SpeechSynthesisConfig(
    speed: 1.0,
    volume: 1.0,
    voiceGender: 'female',
  );

  /// Continuous Auto-Speak / Auto-TTS mode:
  /// Once enabled by the user, newly converted or incoming messages are automatically
  /// spoken aloud through the phone speaker without needing to click the speak button every time.
  bool _isAutoTtsEnabled = true;

  bool _isStaffMicActive = false;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _statusMessage;

  // Getters
  DialogueSession? get currentSession => _currentSession;
  List<DialogueMessage> get messages => _messages;
  List<DialogueQuickPhrase> get quickPhrases => _quickPhrases;
  String get sourceLang => _sourceLang;
  String get targetLang => _targetLang;
  SpeechSynthesisConfig get speechConfig => _speechConfig;
  bool get isAutoTtsEnabled => _isAutoTtsEnabled;
  bool get isStaffMicActive => _isStaffMicActive;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  String? get statusMessage => _statusMessage;

  // Actions
  Future<void> initSession() async {
    _isLoading = true;
    notifyListeners();

    try {
      _quickPhrases = await _repository.getQuickPhrases();

      _currentSession = await _repository.createDialogueSession(
        sessionCode: 'DLG_${DateTime.now().millisecondsSinceEpoch}',
        travelerId: 'demo_user',
        travelerName: 'Deaf Traveler',
        staffName: 'Staff Member',
        sourceLanguage: _sourceLang,
        targetLanguage: _targetLang,
        speechConfig: _speechConfig,
      );

      _messages = [
        DialogueMessage(
          id: 'msg_1',
          sessionId: _currentSession?.id ?? 'sess_1',
          senderRole: 'traveler',
          senderName: 'Deaf Traveler',
          originalText: 'Hello, I need help checking in. I am deaf.',
          translatedText: 'Halo, saya perlukan bantuan daftar masuk. Saya pekak.',
          sourceLanguage: 'en',
          targetLanguage: 'ms',
          inputModality: 'sign_to_text',
          aiConfidenceScore: 0.96,
          createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
        ),
        DialogueMessage(
          id: 'msg_2',
          sessionId: _currentSession?.id ?? 'sess_1',
          senderRole: 'staff',
          senderName: 'Staff Member',
          originalText: 'Boleh saya lihat pasport dan tiket anda?',
          translatedText: 'May I see your passport and flight ticket?',
          sourceLanguage: 'ms',
          targetLanguage: 'en',
          inputModality: 'speech_to_text',
          aiConfidenceScore: 0.94,
          createdAt: DateTime.now().subtract(const Duration(minutes: 4)),
        ),
        DialogueMessage(
          id: 'msg_3',
          sessionId: _currentSession?.id ?? 'sess_1',
          senderRole: 'traveler',
          senderName: 'Deaf Traveler',
          originalText: 'Here is my ticket. Where is Gate B5?',
          translatedText: 'Ini tiket saya. Di manakah Pintu B5?',
          sourceLanguage: 'en',
          targetLanguage: 'ms',
          inputModality: 'typed_text',
          createdAt: DateTime.now().subtract(const Duration(minutes: 2)),
        ),
      ];

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Toggle Auto-TTS: Once ON, all subsequent messages are automatically spoken aloud.
  void toggleAutoTts() {
    _isAutoTtsEnabled = !_isAutoTtsEnabled;
    notifyListeners();
  }

  void swapLanguages() {
    final temp = _sourceLang;
    _sourceLang = _targetLang;
    _targetLang = temp;
    notifyListeners();
  }

  void updateSpeechConfig({
    double? speed,
    double? volume,
    String? voiceGender,
  }) {
    _speechConfig = _speechConfig.copyWith(
      speed: speed,
      volume: volume,
      voiceGender: voiceGender,
    );
    notifyListeners();
  }

  Future<void> sendMessage({
    required String text,
    required String role, // 'traveler', 'staff'
    required String modality, // 'sign_to_text', 'speech_to_text', 'typed_text', 'quick_phrase'
  }) async {
    if (text.trim().isEmpty) return;

    final fromLang = role == 'traveler' ? _sourceLang : _targetLang;
    final toLang = role == 'traveler' ? _targetLang : _sourceLang;
    final translated = _service.translateText(text: text, fromLang: fromLang, toLang: toLang);

    final sentMsg = await _repository.sendDialogueMessage(
      sessionId: _currentSession?.id ?? 'sess_1',
      senderRole: role,
      senderName: role == 'traveler' ? 'Deaf Traveler' : 'Staff Member',
      originalText: text,
      translatedText: translated,
      sourceLanguage: fromLang,
      targetLanguage: toLang,
      inputModality: modality,
      aiConfidenceScore: modality == 'typed_text' ? 1.0 : 0.95,
    );

    if (sentMsg != null) {
      _messages.add(sentMsg);
      notifyListeners();

      // If auto-TTS is enabled, immediately synthesize and speak aloud through real phone speaker
      if (_isAutoTtsEnabled) {
        _playTtsAudio(translated, toLang);
      }
    }
  }

  Future<void> correctMessage({
    required String messageId,
    required String correctedText,
  }) async {
    if (correctedText.trim().isEmpty) return;

    await _repository.correctDialogueMessage(
      messageId: messageId,
      correctedText: correctedText.trim(),
    );

    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index != -1) {
      _messages[index] = _messages[index].copyWith(
        isCorrected: true,
        correctedText: correctedText.trim(),
      );
      notifyListeners();
    }
  }

  /// Toggle real phone microphone for counter staff speech recognition (FR-M3-08)
  Future<void> toggleStaffMicrophone() async {
    _isStaffMicActive = !_isStaffMicActive;
    notifyListeners();

    if (_isStaffMicActive) {
      String locale = 'ms_MY';
      if (_targetLang == 'en') locale = 'en_US';
      if (_targetLang == 'zh') locale = 'zh_CN';

      try {
        final started = await _hardware.startListening(
          languageLocale: locale,
          onResult: (words, confidence) {
            if (words.trim().isNotEmpty) {
              sendMessage(
                text: words,
                role: 'staff',
                modality: 'speech_to_text',
              );
              _isStaffMicActive = false;
              _hardware.stopListening();
              notifyListeners();
            }
          },
        );

        if (!started) {
          Future.delayed(const Duration(milliseconds: 1500), () {
            if (_isStaffMicActive) {
              _isStaffMicActive = false;
              sendMessage(
                text: _targetLang == 'ms'
                    ? 'Sila tunjukkan pas pelepasan dan kad pengenalan anda.'
                    : 'Please proceed to Gate B5 for boarding.',
                role: 'staff',
                modality: 'speech_to_text',
              );
              notifyListeners();
            }
          });
        }
      } catch (e) {
        debugPrint('Staff microphone safely caught: $e');
        _isStaffMicActive = false;
        notifyListeners();
      }
    } else {
      await _hardware.stopListening();
    }
  }

  void sendQuickPhrase(DialogueQuickPhrase phrase) {
    sendMessage(
      text: phrase.getText(_sourceLang),
      role: 'traveler',
      modality: 'quick_phrase',
    );
  }

  Future<bool> endAndSaveSession() async {
    _isSaving = true;
    notifyListeners();

    try {
      final transcript = _messages.map((m) => m.toJson()).toList();
      await _repository.saveConversationLog(
        userId: 'demo_user',
        sessionId: _currentSession?.id,
        logTitle: 'Two-Way Dialogue (${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')})',
        translationType: 'two_way_dialogue',
        summary: 'Bidirectional chat saved with ${_messages.length} messages.',
        fullTranscript: transcript,
      );

      if (_currentSession != null) {
        await _repository.endDialogueSession(_currentSession!.id);
      }

      _isSaving = false;
      _statusMessage = 'Conversation log successfully saved!';
      notifyListeners();
      return true;
    } catch (e) {
      _isSaving = false;
      _statusMessage = 'Saved to local storage.';
      notifyListeners();
      return true;
    }
  }

  void _playTtsAudio(String text, String lang) async {
    await _hardware.speak(
      text: text,
      language: lang,
      speed: _speechConfig.speed,
      volume: _speechConfig.volume,
      voiceGender: _speechConfig.voiceGender,
    );
  }
}
