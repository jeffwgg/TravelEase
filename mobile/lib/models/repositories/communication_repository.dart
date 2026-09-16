import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase_client.dart';
import '../entities/dialogue_session_entity.dart';
import '../entities/dialogue_message_entity.dart';
import '../entities/conversation_log_entity.dart';

/// Repository for Module 3: Multimodal Accessible Communication Module (FR-M3-01 to FR-M3-18)
class CommunicationRepository {
  final _client = SupabaseClientHelper.client;

  // Local fallback storage for offline operation
  static final List<DialogueMessage> _inMemoryMessages = [];
  static final List<ConversationLog> _inMemoryLogs = [];

  // --------------------------------------------------------------------------
  // 1. Dialogue Sessions (UC303)
  // --------------------------------------------------------------------------
  Future<DialogueSession?> createDialogueSession({
    required String sessionCode,
    required String travelerId,
    String travelerName = 'Deaf Traveler',
    String staffName = 'Staff Member',
    String travelerSignLanguage = 'BIM',
    String sourceLanguage = 'en',
    String targetLanguage = 'ms',
    SpeechSynthesisConfig speechConfig = const SpeechSynthesisConfig(),
  }) async {
    try {
      final response = await _client
          .from('communication_dialogue_sessions')
          .insert({
            'session_code': sessionCode,
            'traveler_id': travelerId,
            'traveler_name': travelerName,
            'staff_name': staffName,
            'traveler_sign_language': travelerSignLanguage,
            'source_language': sourceLanguage,
            'target_language': targetLanguage,
            'speech_playback_speed': speechConfig.speed,
            'speech_playback_volume': speechConfig.volume,
            'speech_voice_gender': speechConfig.voiceGender,
            'status': 'active',
          })
          .select()
          .single();
      return DialogueSession.fromJson(response);
    } catch (e) {
      // Offline fallback
      return DialogueSession(
        id: 'offline_${DateTime.now().millisecondsSinceEpoch}',
        sessionCode: sessionCode,
        travelerId: travelerId,
        travelerName: travelerName,
        staffName: staffName,
        travelerSignLanguage: travelerSignLanguage,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
        speechConfig: speechConfig,
        createdAt: DateTime.now(),
      );
    }
  }

  Future<bool> endDialogueSession(String sessionId) async {
    try {
      await _client
          .from('communication_dialogue_sessions')
          .update({
            'status': 'completed',
            'ended_at': DateTime.now().toIso8601String(),
          })
          .eq('id', sessionId);
      return true;
    } catch (e) {
      return true;
    }
  }

  // --------------------------------------------------------------------------
  // 2. Dialogue Messages Stream (FR-M3-09, FR-M3-13, FR-M3-14)
  // --------------------------------------------------------------------------
  Future<List<DialogueMessage>> getDialogueMessages(String sessionId) async {
    try {
      final response = await _client
          .from('communication_dialogue_messages')
          .select()
          .eq('session_id', sessionId)
          .order('created_at', ascending: true);
      return (response as List).map((m) => DialogueMessage.fromJson(m)).toList();
    } catch (e) {
      return _inMemoryMessages.where((m) => m.sessionId == sessionId).toList();
    }
  }

  Future<DialogueMessage?> sendDialogueMessage({
    required String sessionId,
    required String senderRole, // 'traveler', 'staff'
    required String senderName,
    required String originalText,
    required String translatedText,
    required String sourceLanguage,
    required String targetLanguage,
    required String inputModality, // 'sign_to_text', 'speech_to_text', 'typed_text'
    double aiConfidenceScore = 0.95,
    String? audioUrl,
  }) async {
    final messageData = {
      'session_id': sessionId,
      'sender_role': senderRole,
      'sender_name': senderName,
      'original_text': originalText,
      'translated_text': translatedText,
      'source_language': sourceLanguage,
      'target_language': targetLanguage,
      'input_modality': inputModality,
      'ai_confidence_score': aiConfidenceScore,
      'is_corrected': false,
      'audio_url': audioUrl,
    };

    try {
      final response = await _client
          .from('communication_dialogue_messages')
          .insert(messageData)
          .select()
          .single();
      final msg = DialogueMessage.fromJson(response);
      _inMemoryMessages.add(msg);
      return msg;
    } catch (e) {
      final fallbackMsg = DialogueMessage(
        id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
        sessionId: sessionId,
        senderRole: senderRole,
        senderName: senderName,
        originalText: originalText,
        translatedText: translatedText,
        sourceLanguage: sourceLanguage,
        targetLanguage: targetLanguage,
        inputModality: inputModality,
        aiConfidenceScore: aiConfidenceScore,
        audioUrl: audioUrl,
        createdAt: DateTime.now(),
      );
      _inMemoryMessages.add(fallbackMsg);
      return fallbackMsg;
    }
  }

  // FR-M3-15: Manually correct misidentified text in the dialogue stream
  Future<bool> correctDialogueMessage({
    required String messageId,
    required String correctedText,
    String? correctedTranslation,
  }) async {
    try {
      await _client
          .from('communication_dialogue_messages')
          .update({
            'is_corrected': true,
            'corrected_text': correctedText,
            'translated_text': ?correctedTranslation,
          })
          .eq('id', messageId);
      return true;
    } catch (e) {
      final index = _inMemoryMessages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        _inMemoryMessages[index] = _inMemoryMessages[index].copyWith(
          isCorrected: true,
          correctedText: correctedText,
          translatedText: correctedTranslation,
        );
      }
      return true;
    }
  }

  // Subscribe to live split-screen dialogue updates
  RealtimeChannel subscribeToDialogueMessages(
    String sessionId,
    void Function(DialogueMessage message) onNewMessage,
  ) {
    return _client
        .channel('dialogue_session_$sessionId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'communication_dialogue_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'session_id',
            value: sessionId,
          ),
          callback: (payload) {
            onNewMessage(DialogueMessage.fromJson(payload.newRecord));
          },
        )
        .subscribe();
  }

  // --------------------------------------------------------------------------
  // 3. Conversation Logs
  // --------------------------------------------------------------------------
  Future<ConversationLog?> saveConversationLog({
    required String userId,
    String? sessionId,
    required String logTitle,
    required String translationType, // 'two_way_dialogue', 'sign_to_text'
    String? summary,
    required List<Map<String, dynamic>> fullTranscript,
  }) async {
    final logData = {
      'user_id': userId,
      'session_id': sessionId,
      'log_title': logTitle,
      'translation_type': translationType,
      'summary': summary,
      'full_transcript': fullTranscript,
      'message_count': fullTranscript.length,
    };

    try {
      final response = await _client
          .from('communication_saved_logs')
          .insert(logData)
          .select()
          .single();
      final log = ConversationLog.fromJson(response);
      _inMemoryLogs.add(log);
      return log;
    } catch (e) {
      final fallbackLog = ConversationLog(
        id: 'log_${DateTime.now().millisecondsSinceEpoch}',
        userId: userId,
        sessionId: sessionId,
        logTitle: logTitle,
        translationType: translationType,
        summary: summary,
        fullTranscript: fullTranscript,
        messageCount: fullTranscript.length,
        createdAt: DateTime.now(),
      );
      _inMemoryLogs.insert(0, fallbackLog);
      return fallbackLog;
    }
  }

  Future<List<ConversationLog>> getSavedLogs({
    required String userId,
    String? filterType,
  }) async {
    try {
      var query = _client.from('communication_saved_logs').select().eq('user_id', userId);
      if (filterType != null && filterType.isNotEmpty && filterType != 'all') {
        query = query.eq('translation_type', filterType);
      }
      final response = await query.order('created_at', ascending: false);
      return (response as List).map((l) => ConversationLog.fromJson(l)).toList();
    } catch (e) {
      final localLogs = await getLocalConversationLogs(userId: userId);
      if (filterType != null && filterType.isNotEmpty && filterType != 'all') {
        return localLogs.where((l) => l.translationType == filterType).toList();
      }
      return localLogs;
    }
  }

  Future<bool> deleteConversationLog(String logId) async {
    try {
      await _client.from('communication_saved_logs').delete().eq('id', logId);
    } catch (_) {}
    _inMemoryLogs.removeWhere((l) => l.id == logId);
    await _deleteLocalConversationLog(logId);
    return true;
  }

  // --------------------------------------------------------------------------
  // Local Device Storage for Conversation Text Logs
  // Persists full transcripts locally via shared_preferences so logs survive
  // app restarts even when offline.
  // --------------------------------------------------------------------------
  static const String _localLogsKey = 'travelease_local_conversation_logs';

  Future<ConversationLog> saveConversationLogLocally({
    required String userId,
    String? sessionId,
    required String logTitle,
    required String translationType,
    String? summary,
    required List<Map<String, dynamic>> fullTranscript,
  }) async {
    final log = ConversationLog(
      id: 'local_${DateTime.now().millisecondsSinceEpoch}',
      userId: userId,
      sessionId: sessionId,
      logTitle: logTitle,
      translationType: translationType,
      summary: summary,
      fullTranscript: fullTranscript,
      messageCount: fullTranscript.length,
      createdAt: DateTime.now(),
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(_localLogsKey);
      final logs = existing != null
          ? List<Map<String, dynamic>>.from(jsonDecode(existing) as List)
          : <Map<String, dynamic>>[];
      logs.insert(0, log.toJson());
      await prefs.setString(_localLogsKey, jsonEncode(logs));
    } catch (e) {
      debugPrint('Local conversation log save failed: $e');
    }
    return log;
  }

  Future<List<ConversationLog>> getLocalConversationLogs({required String userId}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_localLogsKey);
      if (raw == null) return [];
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map((j) => ConversationLog.fromJson(Map<String, dynamic>.from(j)))
          .where((l) => l.userId == userId)
          .toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> _deleteLocalConversationLog(String logId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_localLogsKey);
      if (raw == null) return;
      final logs = List<Map<String, dynamic>>.from(jsonDecode(raw) as List);
      logs.removeWhere((l) => l['id'] == logId);
      await prefs.setString(_localLogsKey, jsonEncode(logs));
    } catch (_) {}
  }

  // --------------------------------------------------------------------------
  // 5. Sign Translation Prediction Logger (UC301)
  // --------------------------------------------------------------------------
  Future<bool> recordSignTranslationPrediction({
    required String userId,
    required String signLanguageId,
    required String predictedText,
    required String confirmedText,
    required double confidenceScore,
    bool isEdited = false,
    bool audioPlayed = false,
  }) async {
    try {
      await _client.from('sign_translations_history').insert({
        'user_id': userId,
        'sign_language_id': signLanguageId,
        'predicted_text': predictedText,
        'confirmed_text': confirmedText,
        'confidence_score': confidenceScore,
        'is_edited': isEdited,
        'audio_played': audioPlayed,
      });
      return true;
    } catch (e) {
      return true;
    }
  }
}
