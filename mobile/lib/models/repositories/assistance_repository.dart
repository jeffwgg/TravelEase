import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/supabase_client.dart';

class AssistanceRepository {
  final _client = SupabaseClientHelper.client;

  // Identity of the signed-in traveller for assistance records. Full name is
  // taken from user_profiles (source of truth after profile setup), falling
  // back to auth metadata, then the email handle.
  Future<String> _currentTravelerName() async {
    final user = _client.auth.currentUser;
    if (user == null) return 'Guest';
    try {
      final row = await _client
          .from('user_profiles')
          .select('full_name')
          .eq('id', user.id)
          .maybeSingle();
      final profileName = (row?['full_name'] as String?)?.trim();
      if (profileName != null && profileName.isNotEmpty) return profileName;
    } catch (_) {
      // fall through to metadata below
    }
    final metadataName = (user.userMetadata?['full_name'] as String?)?.trim();
    if (metadataName != null && metadataName.isNotEmpty) return metadataName;
    final emailHandle = user.email?.split('@').first ?? '';
    return emailHandle.isNotEmpty ? emailHandle : 'Traveller';
  }

  // Module 5: Get All Assistance Requests for traveler
  Future<List<Map<String, dynamic>>> getAssistanceRequests() async {
    try {
      final response = await _client
          .from('assistance_requests')
          .select()
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error loading assistance requests: $e');
      return [];
    }
  }

  // Module 5: Get a single request by ID (used to pre-populate assigned staff name in chat)
  Future<Map<String, dynamic>?> getRequestDetails(String requestId) async {
    try {
      final response = await _client
          .from('assistance_requests')
          .select()
          .eq('id', requestId)
          .single();
      return response;
    } catch (e) {
      print('Error loading request details: $e');
      return null;
    }
  }

  // Module 5: Submit a New Assistance Request
  Future<Map<String, dynamic>?> createAssistanceRequest({
    required String requestCode,
    required String preferredCommunication,
    required String category,
    required String venueName,
    required String locationZone,
    required String description,
    required String urgency,
    required bool shareLocation,
    required bool analyticsConsent,
  }) async {
    try {
      final response = await _client
          .from('assistance_requests')
          .insert({
            'request_code': requestCode,
            'user_id': _client.auth.currentUser?.id,
            'traveler_name': await _currentTravelerName(),
            'preferred_communication': preferredCommunication,
            'category': category,
            'venue_name': venueName,
            'location_zone': locationZone,
            'description': description,
            'urgency': urgency,
            'status': 'pending',
            'share_location': shareLocation,
            'analytics_consent': analyticsConsent,
          })
          .select()
          .single();
      return response;
    } catch (e) {
      print('Error creating assistance request: $e');
      return null;
    }
  }

  // Module 5: Get Chat Messages
  Future<List<Map<String, dynamic>>> getChatMessages(String requestId) async {
    try {
      final response = await _client
          .from('assistance_chat_messages')
          .select()
          .eq('request_id', requestId)
          .order('created_at', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error loading chat messages: $e');
      return [];
    }
  }

  // Module 5: Send Chat Message from Traveler
  Future<Map<String, dynamic>?> sendChatMessage({
    required String requestId,
    required String content,
    String messageType = 'text',
  }) async {
    try {
      final response = await _client
          .from('assistance_chat_messages')
          .insert({
            'request_id': requestId,
            'sender_type': 'traveler',
            'sender_name': '${await _currentTravelerName()} (Traveler)',
            'content': content,
            'message_type': messageType,
            'is_read': false,
          })
          .select()
          .single();
      return response;
    } catch (e) {
      print('Error sending message: $e');
      return null;
    }
  }

  // Module 5: Upload chat media (image or video) to Supabase Storage
  Future<String?> uploadChatMedia({
    required String requestId,
    required String filePath,
    required String mimeType,
  }) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      final fileName = filePath.split('/').last;
      final safeName = fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storagePath = '$requestId/${timestamp}_$safeName';

      await _client.storage.from('chat-media').uploadBinary(
        storagePath,
        bytes,
        fileOptions: FileOptions(contentType: mimeType, upsert: false),
      );

      final publicUrl = _client.storage
          .from('chat-media')
          .getPublicUrl(storagePath);
      return publicUrl;
    } catch (e) {
      print('Error uploading chat media: $e');
      return null;
    }
  }

  // Module 5: Send Chat Media Message from Traveler (image or video)
  Future<Map<String, dynamic>?> sendMediaMessage({
    required String requestId,
    required String filePath,
    required String mimeType,
  }) async {
    final url = await uploadChatMedia(
      requestId: requestId,
      filePath: filePath,
      mimeType: mimeType,
    );
    if (url == null) return null;

    final msgType = mimeType.startsWith('image/') ? 'image' : 'video';
    return sendChatMessage(
      requestId: requestId,
      content: url,
      messageType: msgType,
    );
  }

  // Module 5 & 7: Report Accessibility Issue
  Future<Map<String, dynamic>?> reportAccessibilityIssue({
    required String reportCode,
    required String issueType,
    required String venueName,
    required String locationZone,
    required String description,
    required String severity,
    required bool analyticsConsent,
  }) async {
    try {
      final response = await _client
          .from('accessibility_issue_reports')
          .insert({
            'report_code': reportCode,
            'user_id': _client.auth.currentUser?.id,
            'traveler_name': await _currentTravelerName(),
            'issue_type': issueType,
            'venue_name': venueName,
            'location_zone': locationZone,
            'description': description,
            'severity': severity,
            'status': 'reported',
            'analytics_consent': analyticsConsent,
          })
          .select()
          .single();
      return response;
    } catch (e) {
      print('Error reporting accessibility issue: $e');
      return null;
    }
  }

  // Subscribe to Live Chat Messages
  RealtimeChannel subscribeToMessages(
      String requestId, void Function(Map<String, dynamic>) onNewMessage) {
    return _client
        .channel('mobile_chat_$requestId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'assistance_chat_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'request_id',
            value: requestId,
          ),
          callback: (payload) {
            onNewMessage(payload.newRecord);
          },
        )
        .subscribe();
  }

  // FR-M5-29: Cancel an active assistance request
  Future<bool> cancelRequest(String requestId) async {
    try {
      await _client
          .from('assistance_requests')
          .update({'status': 'cancelled', 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', requestId);
      return true;
    } catch (e) {
      print('Error cancelling request: $e');
      return false;
    }
  }

  // FR-M5-16 / FR-M5-26: Submit resolution feedback and close/reopen ticket
  Future<bool> submitResolutionFeedback({
    required String requestId,
    required String outcome, // 'fully_resolved' | 'partially_resolved' | 'unresolved'
    required int rating,
    String? comment,
  }) async {
    try {
      final newStatus = outcome == 'fully_resolved' ? 'closed' : 'in_progress';
      await _client
          .from('assistance_requests')
          .update({
            'resolution_outcome': outcome,
            'user_rating': rating,
            'user_feedback_comment': comment,
            'status': newStatus,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', requestId);
      return true;
    } catch (e) {
      print('Error submitting feedback: $e');
      return false;
    }
  }

  // FR-M5-11: Subscribe to changes on a specific request (e.g., status → resolved)
  RealtimeChannel subscribeToRequestChanges(
      String requestId, void Function(Map<String, dynamic>) onChanged) {
    return _client
        .channel('request_status_$requestId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'assistance_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: requestId,
          ),
          callback: (payload) {
            onChanged(payload.newRecord);
          },
        )
        .subscribe();
  }
}

