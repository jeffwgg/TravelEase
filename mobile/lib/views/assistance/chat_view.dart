import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../core/theme.dart';
import '../../viewmodels/chat_viewmodel.dart';
import '../../services/webrtc_service.dart';

class ChatView extends StatefulWidget {
  final String requestId;

  const ChatView({super.key, required this.requestId});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  late final ChatViewModel _viewModel;
  late final WebRTCService _webrtc;

  @override
  void initState() {
    super.initState();
    _viewModel = ChatViewModel(requestId: widget.requestId);
    _viewModel.addListener(_onChanged);
    _viewModel.loadMessages();
    _viewModel.subscribeToLive();

    _webrtc = WebRTCService.instance;
    _webrtc.addListener(_onChanged);
    _webrtc.init().then((_) {
      _webrtc.subscribeToSignaling(widget.requestId);
    });
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onChanged);
    _viewModel.dispose();
    _webrtc.removeListener(_onChanged);
    super.dispose();
  }

  // ── Start a call (Mobile initiates) ────────────────────────────────────────
  Future<void> _startCall(CallType type) async {
    await _webrtc.startCall(widget.requestId, type);
  }

  @override
  Widget build(BuildContext context) {
    final isInCall = _webrtc.callState == WebRTCCallState.connected ||
        _webrtc.callState == WebRTCCallState.calling;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.support_agent, size: 18, color: AppColors.primary),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_viewModel.assignedStaffName ?? 'Staff Chat', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                Row(
                  children: [
                    Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(color: _viewModel.assignedStaffName != null ? AppColors.success : AppColors.textMuted, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 4),
                    Text(_viewModel.assignedStaffName != null ? 'Online' : 'Waiting...', style: TextStyle(fontSize: 11, color: _viewModel.assignedStaffName != null ? AppColors.success : AppColors.textMuted)),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          // Confirm Resolution button for traveler
          IconButton(
            icon: const Icon(Icons.check_circle_outline, color: AppColors.success),
            tooltip: 'Confirm Resolution & Rate',
            onPressed: () => _showResolutionDialog(context),
          ),
          // Voice call button
          IconButton(
            icon: const Icon(Icons.call, color: AppColors.success),
            tooltip: 'Start Voice Call',
            onPressed: () => _startCall(CallType.voice),
          ),
          // Video call button
          IconButton(
            icon: const Icon(Icons.videocam, color: AppColors.primary),
            tooltip: 'Start Video Call',
            onPressed: () => _startCall(CallType.video),
          ),
          IconButton(icon: const Icon(Icons.more_vert), onPressed: () {}),
        ],
      ),
      body: Stack(
        children: [
          // ── Main chat body ────────────────────────────────────────────────
          Column(
            children: [
              // Request context banner
              Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: AppColors.textMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Request #${widget.requestId.length > 8 ? widget.requestId.substring(0, 8) : widget.requestId}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
                      ),
                    ),
                    InkWell(
                      onTap: () => _showResolutionDialog(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.success.withValues(alpha: 0.5)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle, size: 14, color: AppColors.success),
                            SizedBox(width: 4),
                            Text('Resolve & Rate', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.success)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Messages
              Expanded(child: _buildMessageList()),

              // Input bar
              Container(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, -2))],
                ),
                child: Row(
                  children: [
                    IconButton(icon: const Icon(Icons.add_circle_outline, color: AppColors.textMuted), onPressed: () {}),
                    Expanded(
                      child: TextField(
                        controller: _viewModel.messageController,
                        decoration: InputDecoration(
                          hintText: 'Type a message...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                          filled: true,
                          fillColor: AppColors.surfaceVariant,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                        onSubmitted: (_) => _viewModel.sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(color: AppColors.primary, borderRadius: BorderRadius.circular(12)),
                      child: IconButton(
                        icon: const Icon(Icons.send, color: Colors.white, size: 20),
                        onPressed: () => _viewModel.sendMessage(),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── Incoming Call Overlay (Web → Mobile) ──────────────────────────
          if (_webrtc.callState == WebRTCCallState.incoming)
            _buildIncomingCallOverlay(context),

          // ── Active Call Overlay ───────────────────────────────────────────
          if (isInCall)
            _buildActiveCallOverlay(context),
        ],
      ),
    );
  }

  // ── Incoming Call Dialog (Web staff calls traveler) ────────────────────────
  Widget _buildIncomingCallOverlay(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.75),
      child: Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: const Color(0xFF1e293b),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 40)],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Animated avatar
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withValues(alpha: 0.2),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.5), width: 2),
                ),
                child: Icon(
                  _webrtc.callType == CallType.video ? Icons.videocam : Icons.call,
                  size: 36, color: const Color(0xFF60a5fa),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Incoming ${_webrtc.callType == CallType.video ? "Video" : "Voice"} Call',
                style: const TextStyle(color: Color(0xFF94a3b8), fontSize: 13, letterSpacing: 1),
              ),
              const SizedBox(height: 8),
              Text(
                _webrtc.incomingCallerName,
                style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 32),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Reject
                  GestureDetector(
                    onTap: () => _webrtc.rejectCall(),
                    child: Container(
                      width: 60, height: 60,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFef4444)),
                      child: const Icon(Icons.call_end, color: Colors.white, size: 26),
                    ),
                  ),
                  const SizedBox(width: 24),
                  // Accept
                  GestureDetector(
                    onTap: () => _webrtc.acceptCall(),
                    child: Container(
                      width: 60, height: 60,
                      decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF22c55e)),
                      child: const Icon(Icons.call, color: Colors.white, size: 26),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Active Call (video/voice) full-screen overlay ─────────────────────────
  Widget _buildActiveCallOverlay(BuildContext context) {
    final isCalling = _webrtc.callState == WebRTCCallState.calling;

    return Container(
      color: const Color(0xFF0f172a),
      child: Stack(
        children: [
          // Remote video (full screen)
          if (_webrtc.callType == CallType.video)
            Positioned.fill(
              child: RTCVideoView(
                _webrtc.remoteRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
            ),

          // Calling state message
          if (isCalling)
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.phone_in_talk, size: 64, color: const Color(0xFF60a5fa)),
                  const SizedBox(height: 16),
                  const Text(
                    'Calling Staff...',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Waiting for staff to accept',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 14),
                  ),
                ],
              ),
            ),

          // Local video (PIP — bottom right)
          if (_webrtc.callType == CallType.video)
            Positioned(
              bottom: 120, right: 16,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 120, height: 90,
                  child: RTCVideoView(
                    _webrtc.localRenderer,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),
            ),

          // Controls bar
          Positioned(
            bottom: 32, left: 0, right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Mute
                _callControlBtn(
                  icon: _webrtc.isMicMuted ? Icons.mic_off : Icons.mic,
                  active: _webrtc.isMicMuted,
                  onTap: () => _webrtc.toggleMic(),
                  size: 48,
                ),
                const SizedBox(width: 16),
                // Camera (video calls only)
                if (_webrtc.callType == CallType.video) ...[
                  _callControlBtn(
                    icon: _webrtc.isCameraOff ? Icons.videocam_off : Icons.videocam,
                    active: _webrtc.isCameraOff,
                    onTap: () => _webrtc.toggleCamera(),
                    size: 48,
                  ),
                  const SizedBox(width: 16),
                ],
                // End call
                GestureDetector(
                  onTap: () => _webrtc.hangup(),
                  child: Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFef4444),
                      boxShadow: [BoxShadow(color: const Color(0xFFef4444).withValues(alpha: 0.5), blurRadius: 16)],
                    ),
                    child: const Icon(Icons.call_end, color: Colors.white, size: 28),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _callControlBtn({
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
    double size = 48,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size, height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? const Color(0xFFef4444) : Colors.white.withValues(alpha: 0.15),
        ),
        child: Icon(icon, color: Colors.white, size: size * 0.4),
      ),
    );
  }

  // ── Message list ───────────────────────────────────────────────────────────
  Widget _buildMessageList() {
    if (_viewModel.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_viewModel.messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: AppColors.textMuted.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text('No messages yet', style: TextStyle(color: AppColors.textMuted, fontSize: 15)),
            const SizedBox(height: 4),
            const Text('Send a message to start the conversation', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _viewModel.scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _viewModel.messages.length,
      itemBuilder: (context, index) {
        final msg = _viewModel.messages[index];
        final senderType = msg['sender_type'] ?? '';
        final isUser = senderType == 'traveler';
        final content = msg['content'] ?? '';
        final createdAt = msg['created_at'] as String?;
        final senderName = msg['sender_name'] ?? '';

        String time = '';
        if (createdAt != null) {
          try {
            final date = DateTime.parse(createdAt).toLocal();
            final hour = date.hour > 12 ? date.hour - 12 : date.hour;
            final amPm = date.hour >= 12 ? 'PM' : 'AM';
            time = '${hour == 0 ? 12 : hour}:${date.minute.toString().padLeft(2, '0')} $amPm';
          } catch (_) {}
        }

        if (senderType == 'system') {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: _buildSystemMsg(context, content),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildMsg(content, isUser, time, senderName),
        );
      },
    );
  }

  Widget _buildMsg(String text, bool isUser, String time, String senderName) {
    return Row(
      mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Flexible(
          child: Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.85,
            ),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isUser ? AppColors.primary : AppColors.surface,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isUser ? 16 : 4),
                bottomRight: Radius.circular(isUser ? 4 : 16),
              ),
              border: isUser ? null : Border.all(color: AppColors.cardBorder),
            ),
            child: IntrinsicWidth(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(text, style: TextStyle(color: isUser ? Colors.white : AppColors.textPrimary, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(time, textAlign: TextAlign.right, style: TextStyle(fontSize: 10, color: isUser ? Colors.white54 : AppColors.textMuted)),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSystemMsg(BuildContext context, String text) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(12)),
        child: Text(text, style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }

  // ── UC503: Resolution Confirmation Modal for Traveler ────────────────────
  void _showResolutionDialog(BuildContext context) {
    String selectedOutcome = '';
    int selectedRating = 0;
    final commentCtrl = TextEditingController();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          return Container(
            padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(ctx).viewInsets.bottom + 24),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.check_circle_outline, color: AppColors.success, size: 24),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Confirm Resolution', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                          Text('Provide feedback for your assistance session', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Was your assistance request effectively resolved by the staff?',
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
                ),
                const SizedBox(height: 20),
                const Text('Outcome', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildOutcomeChip('fully_resolved', '✅ Resolved', AppColors.success, selectedOutcome, (v) => setSheetState(() => selectedOutcome = v)),
                    const SizedBox(width: 8),
                    _buildOutcomeChip('partially_resolved', '⚠️ Partial', AppColors.secondary, selectedOutcome, (v) => setSheetState(() => selectedOutcome = v)),
                    const SizedBox(width: 8),
                    _buildOutcomeChip('unresolved', '❌ Unresolved', AppColors.emergency, selectedOutcome, (v) => setSheetState(() => selectedOutcome = v)),
                  ],
                ),
                const SizedBox(height: 20),
                const Text('Satisfaction Rating', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (i) {
                    final star = i + 1;
                    return GestureDetector(
                      onTap: () => setSheetState(() => selectedRating = star),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(
                          star <= selectedRating ? Icons.star_rounded : Icons.star_outline_rounded,
                          size: 42,
                          color: star <= selectedRating ? const Color(0xFFF59E0B) : AppColors.textMuted,
                        ),
                      ),
                    );
                  }),
                ),
                if (selectedRating > 0) ...[
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      ['', 'Poor', 'Fair', 'Good', 'Very Good', 'Excellent'][selectedRating],
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontStyle: FontStyle.italic),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                TextField(
                  controller: commentCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    hintText: 'Any feedback comments? (optional)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (selectedOutcome.isEmpty || selectedRating == 0 || isSubmitting)
                        ? null
                        : () async {
                            setSheetState(() => isSubmitting = true);
                            final success = await _viewModel.submitResolutionFeedback(
                              outcome: selectedOutcome,
                              rating: selectedRating,
                              comment: commentCtrl.text.trim().isEmpty ? null : commentCtrl.text.trim(),
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            if (success && mounted) {
                              final isFullyResolved = selectedOutcome == 'fully_resolved';
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(isFullyResolved
                                      ? '✅ Request closed. Thank you for your rating!'
                                      : '⚠️ Ticket re-opened for staff review.'),
                                  backgroundColor: isFullyResolved ? AppColors.success : AppColors.secondary,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                              Navigator.pop(context);
                            }
                          },
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                    child: isSubmitting
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Submit Feedback'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildOutcomeChip(String value, String label, Color color, String selected, ValueChanged<String> onTap) {
    final isSelected = selected == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onTap(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.12) : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? color : AppColors.cardBorder, width: isSelected ? 2 : 1),
          ),
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isSelected ? color : AppColors.textMuted)),
        ),
      ),
    );
  }
}
