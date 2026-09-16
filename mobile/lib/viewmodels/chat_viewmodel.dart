import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/repositories/assistance_repository.dart';

class ChatViewModel extends ChangeNotifier {
  final AssistanceRepository _repository = AssistanceRepository();
  final String requestId;

  /// Tracks which request IDs the user currently has open in ChatView.
  /// Used by ChatNotificationService to suppress redundant notifications.
  static final Set<String> activeRequestIds = {};

  List<Map<String, dynamic>> messages = [];
  bool isLoading = false;
  bool isUploading = false;
  String? errorMessage;
  final TextEditingController messageController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  RealtimeChannel? _channel;
  RealtimeChannel? _requestChannel;

  // Request details — populated on init and updated via realtime
  Map<String, dynamic>? requestDetails;

  // Staff name: prefers live request field, falls back to first staff message
  String? _staffNameFromRequest;

  ChatViewModel({required this.requestId}) {
    activeRequestIds.add(requestId);
  }

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
    if (content.isEmpty || isReadOnly) return;

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

  Future<void> sendMediaMessage({
    required String filePath,
    required String mimeType,
  }) async {
    if (isReadOnly) return;
    isUploading = true;
    notifyListeners();

    try {
      final result = await _repository.sendMediaMessage(
        requestId: requestId,
        filePath: filePath,
        mimeType: mimeType,
      );

      if (result != null) {
        if (!messages.any((m) => m['id'] == result['id'])) {
          messages.add(result);
          _scrollToBottom();
        }
      } else {
        errorMessage = 'Failed to upload media';
      }
    } catch (e) {
      errorMessage = 'Failed to upload media: $e';
    } finally {
      isUploading = false;
      notifyListeners();
    }
  }

  String? get requestStatus => (requestDetails?['status'] ?? '').toString().toLowerCase();

  /// Traveler has confirmed (fully) — request closed, conversation archived.
  bool get isClosed => requestStatus == 'closed';

  /// Staff marked resolved, or the request is closed: chat becomes view-only.
  bool get isReadOnly => requestStatus == 'resolved' || isClosed;

  // FR-M5-16 / FR-M5-26: Deaf traveler confirms resolution and submits rating
  Future<bool> submitResolutionFeedback({
    required String outcome,
    required int rating,
    String? comment,
  }) async {
    final success = await _repository.submitResolutionFeedback(
      requestId: requestId,
      outcome: outcome,
      rating: rating,
      comment: comment,
    );
    if (success) {
      // Optimistically flip local status so the UI locks immediately,
      // without waiting for the realtime echo of our own update.
      final newStatus = outcome == 'fully_resolved' ? 'closed' : 'in_progress';
      requestDetails = {...?requestDetails, 'status': newStatus};
      notifyListeners();
    }
    return success;
  }

  /// Chat log row after a finished voice/video call: "Video call · 1:23".
  /// Stored as message_type `call` with content `video|45` (type, seconds).
  Future<void> sendCallSummary({
    required String callType,
    required int seconds,
  }) async {
    try {
      final result = await _repository.sendChatMessage(
        requestId: requestId,
        content: '$callType|$seconds',
        messageType: 'call',
      );
      if (result != null && !messages.any((m) => m['id'] == result['id'])) {
        messages.add(result);
        notifyListeners();
        _scrollToBottom();
      }
    } catch (e) {
      debugPrint('Failed to log call summary: $e');
    }
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
    // a staff member is assigned, and status changes (resolved/closed)
    // lock the conversation in real time.
    _requestChannel = _repository.subscribeToRequestChanges(requestId, (updatedRequest) {
      final newName = updatedRequest['assigned_staff_name'] as String?;
      if (newName != null && newName.isNotEmpty && newName != 'Unassigned') {
        _staffNameFromRequest = newName;
      }
      requestDetails = updatedRequest;
      notifyListeners();
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
    activeRequestIds.remove(requestId);
    unsubscribe();
    messageController.dispose();
    scrollController.dispose();
    super.dispose();
  }
}
