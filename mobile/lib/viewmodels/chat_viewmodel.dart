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
  RealtimeChannel? _requestChannel;

  // Request details — populated on init and updated via realtime
  Map<String, dynamic>? requestDetails;

  // Staff name: prefers live request field, falls back to first staff message
  String? _staffNameFromRequest;

  ChatViewModel({required this.requestId});

  String? get assignedStaffName {
    // Priority 1: real-time assignment on the request row
    if (_staffNameFromRequest != null && _staffNameFromRequest!.isNotEmpty && _staffNameFromRequest != 'Unassigned') {
      return _staffNameFromRequest;
    }
    // Priority 2: derive from first staff message (existing fallback)
    try {
      final staffMsg = messages.firstWhere((m) => m['sender_type'] == 'staff');
      return staffMsg['sender_name'];
    } catch (e) {
      return null;
    }
  }

  Future<void> loadMessages() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();

    try {
      // Load request details to get the assigned staff name immediately
      await _loadRequestDetails();

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

  /// Fetch the assistance request row to pick up assigned_staff_name right away.
  Future<void> _loadRequestDetails() async {
    try {
      final details = await _repository.getRequestDetails(requestId);
      if (details != null) {
        requestDetails = details;
        _staffNameFromRequest = details['assigned_staff_name'] as String?;
      }
    } catch (e) {
      // Non-fatal — chat still works without staff name
      print('Failed to load request details: $e');
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

  // FR-M5-16 / FR-M5-26: Deaf traveler confirms resolution and submits rating
  Future<bool> submitResolutionFeedback({
    required String outcome,
    required int rating,
    String? comment,
  }) async {
    return await _repository.submitResolutionFeedback(
      requestId: requestId,
      outcome: outcome,
      rating: rating,
      comment: comment,
    );
  }

  void subscribeToLive() {
    // Subscribe to new chat messages
    _channel = _repository.subscribeToMessages(requestId, (newMessage) {
      if (!messages.any((m) => m['id'] == newMessage['id'])) {
        messages.add(newMessage);
        notifyListeners();
        _scrollToBottom();
      }
    });

    // Subscribe to request row updates so staff name appears the moment
    // a staff member is assigned (no need to wait for them to send a message).
    _requestChannel = _repository.subscribeToRequestChanges(requestId, (updatedRequest) {
      final newName = updatedRequest['assigned_staff_name'] as String?;
      if (newName != null && newName.isNotEmpty && newName != 'Unassigned') {
        _staffNameFromRequest = newName;
        requestDetails = updatedRequest;
        notifyListeners();
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
    _requestChannel?.unsubscribe();
    _requestChannel = null;
  }

  @override
  void dispose() {
    unsubscribe();
    messageController.dispose();
    scrollController.dispose();
    super.dispose();
  }
}
