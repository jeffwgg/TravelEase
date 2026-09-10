import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';
import '../viewmodels/chat_viewmodel.dart';
import 'app_notification_service.dart';

/// Listens globally for new staff chat messages and fires local notifications
/// when the traveler is NOT currently viewing that specific chat screen.
class ChatNotificationService {
  ChatNotificationService._();
  static final instance = ChatNotificationService._();

  final _client = SupabaseClientHelper.client;
  RealtimeChannel? _channel;

  /// Start listening across ALL assistance_chat_messages inserts.
  void initialize() {
    _channel = _client
        .channel('global_chat_notifications')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'assistance_chat_messages',
          callback: (payload) => _handleNewMessage(payload.newRecord),
        )
        .subscribe();
  }

  void _handleNewMessage(Map<String, dynamic> record) {
    final senderType = record['sender_type'] as String?;
    final requestId = record['request_id'] as String?;
    final senderName = record['sender_name'] as String? ?? 'Staff';
    final content = record['content'] as String? ?? '';

    // Only notify for staff messages directed at the traveler
    if (senderType != 'staff') return;
    if (requestId == null) return;

    // Suppress if the traveler currently has this chat open
    if (ChatViewModel.activeRequestIds.contains(requestId)) return;

    AppNotificationService.instance.showChatMessage(
      requestId: requestId,
      senderName: senderName,
      message: content,
    );
  }

  void dispose() {
    _channel?.unsubscribe();
    _channel = null;
  }
}
