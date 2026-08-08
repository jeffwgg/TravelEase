import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/repositories/assistance_repository.dart';

class ChatViewModel extends ChangeNotifier {
  final AssistanceRepository _repository = AssistanceRepository();
  final String requestId;

  List<Map<String, dynamic>> messages = [];
  bool isLoading = false;
  String? errorMessage;
  final TextEditingController messageController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  RealtimeChannel? _channel;

  // Request details
  Map<String, dynamic>? requestDetails;

  ChatViewModel({required this.requestId});

  Future<void> loadMessages() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      final result = await _repository.getChatMessages(requestId);
      messages = result;
      isLoading = false;
      notifyListeners();
      _scrollToBottom();
    } catch (e) {
      isLoading = false;
      errorMessage = 'Failed to load messages: $e';
      notifyListeners();
    }
  }

  Future<void> sendMessage() async {
    final content = messageController.text.trim();
    if (content.isEmpty) return;

    messageController.clear();

    try {
      final result = await _repository.sendChatMessage(
        requestId: requestId,
        content: content,
      );

      if (result != null) {
        // Add locally for instant feedback (realtime will also push it)
        if (!messages.any((m) => m['id'] == result['id'])) {
          messages.add(result);
          notifyListeners();
          _scrollToBottom();
        }
      }
    } catch (e) {
      errorMessage = 'Failed to send message';
      notifyListeners();
    }
  }

  void subscribeToLive() {
    _channel = _repository.subscribeToMessages(requestId, (newMessage) {
      // Avoid duplicates
      if (!messages.any((m) => m['id'] == newMessage['id'])) {
        messages.add(newMessage);
        notifyListeners();
        _scrollToBottom();
      }
    });
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (scrollController.hasClients) {
        scrollController.animateTo(
          scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void unsubscribe() {
    _channel?.unsubscribe();
    _channel = null;
  }

  @override
  void dispose() {
    unsubscribe();
    messageController.dispose();
    scrollController.dispose();
    super.dispose();
  }
}
