import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';

class AssistanceRepository {
  final _client = SupabaseClientHelper.client;

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

  // Module 5: Submit a New Assistance Request
  Future<Map<String, dynamic>?> createAssistanceRequest({
    required String requestCode,
    required String travelerName,
    required String preferredCommunication,
    required String category,
    required String venueName,
    required String locationZone,
    required String description,
    required String urgency,
  }) async {
    try {
      final response = await _client
          .from('assistance_requests')
          .insert({
            'request_code': requestCode,
            'traveler_name': travelerName,
            'preferred_communication': preferredCommunication,
            'category': category,
            'venue_name': venueName,
            'location_zone': locationZone,
            'description': description,
            'urgency': urgency,
            'status': 'pending',
            'share_location': true,
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
            'sender_name': 'Jeff Wong (Traveler)',
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

  // Module 5 & 7: Report Accessibility Issue
  Future<Map<String, dynamic>?> reportAccessibilityIssue({
    required String reportCode,
    required String issueType,
    required String venueName,
    required String locationZone,
    required String description,
    required String severity,
  }) async {
    try {
      final response = await _client
          .from('accessibility_issue_reports')
          .insert({
            'report_code': reportCode,
            'traveler_name': 'Jeff Wong',
            'issue_type': issueType,
            'venue_name': venueName,
            'location_zone': locationZone,
            'description': description,
            'severity': severity,
            'status': 'reported',
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
}
