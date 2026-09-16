import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../../core/theme.dart';
import '../../viewmodels/chat_viewmodel.dart';
import '../../services/webrtc_service.dart';
import 'resolution_feedback_sheet.dart';

class ChatView extends StatefulWidget {
  final String requestId;

  const ChatView({super.key, required this.requestId});

  @override
  State<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends State<ChatView> {
  late final ChatViewModel _viewModel;
  late final WebRTCService _webrtc;
  final ImagePicker _picker = ImagePicker();
  // Track VideoPlayerControllers keyed by message id
  final Map<String, VideoPlayerController> _videoControllers = {};

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

  WebRTCCallState _prevCallState = WebRTCCallState.idle;

  void _onChanged() {
    final now = _webrtc.callState;
    // When a call this device dialed ends after connecting, log it in the chat.
    if (now == WebRTCCallState.idle &&
        _prevCallState != WebRTCCallState.idle &&
        _webrtc.hasCallSummary) {
      _emitCallSummary();
    }
    _prevCallState = now;
    if (_webrtc.callError != null) {
      final message = _webrtc.callError!;
      _webrtc.callError = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(message),
              backgroundColor: AppColors.emergency,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      });
    }
    if (mounted) setState(() {});
  }

  Future<void> _emitCallSummary() async {
    final type = _webrtc.endedCallType == CallType.voice ? 'voice' : 'video';
    final seconds = _webrtc.endedCallSeconds;
    _webrtc.clearCallSummary();
    if (seconds > 0) {
      await _viewModel.sendCallSummary(callType: type, seconds: seconds);
    }
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onChanged);
    _viewModel.dispose();
    _webrtc.removeListener(_onChanged);
    // Dispose all video controllers
    for (final vc in _videoControllers.values) {
      vc.dispose();
    }
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
        titleSpacing: 0,
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
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _viewModel.assignedStaffName ?? 'Staff Chat',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: _viewModel.assignedStaffName != null ? AppColors.success : AppColors.textMuted,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _viewModel.assignedStaffName != null ? 'Online' : 'Waiting...',
                        style: TextStyle(
                          fontSize: 11,
                          color: _viewModel.assignedStaffName != null ? AppColors.success : AppColors.textMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // Voice call button
          IconButton(
            icon: Icon(Icons.call, color: _viewModel.isReadOnly ? AppColors.textMuted : AppColors.success),
            tooltip: _viewModel.isReadOnly ? 'Calls unavailable — request resolved' : 'Start Voice Call',
            onPressed: _viewModel.isReadOnly ? null : () => _startCall(CallType.voice),
          ),
          // Video call button
          IconButton(
            icon: Icon(Icons.videocam, color: _viewModel.isReadOnly ? AppColors.textMuted : AppColors.primary),
            tooltip: _viewModel.isReadOnly ? 'Calls unavailable — request resolved' : 'Start Video Call',
            onPressed: _viewModel.isReadOnly ? null : () => _startCall(CallType.video),
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
                    if (!_viewModel.isClosed)
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

              // Input bar — replaced by a read-only notice once resolved/closed
              if (_viewModel.isReadOnly)
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, -2))],
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lock_outline, size: 16, color: AppColors.textMuted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _viewModel.isClosed
                              ? 'This request is closed. The conversation is view-only.'
                              : 'Marked as resolved — chat is view-only. Confirm the resolution above to close the request.',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, -2))],
                  ),
                  child: Row(
                    children: [
                      // Attach media / pick files button
                      IconButton(
                        icon: _viewModel.isUploading
                            ? const SizedBox(
                                width: 22, height: 22,
                                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.textMuted),
                              )
                            : const Icon(Icons.add_circle_outline, color: AppColors.textMuted),
                        onPressed: _viewModel.isUploading ? null : () => _pickMedia(context),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _viewModel.messageController,
                          enabled: !_viewModel.isUploading,
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

        if ((msg['message_type'] ?? 'text') == 'call') {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: _buildCallLogMsg(content, time),
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildMsgBubble(msg, isUser, time, senderName),
        );
      },
    );
  }

  // Dispatch to text or media bubble
  Widget _buildMsgBubble(
    Map<String, dynamic> msg,
    bool isUser,
    String time,
    String senderName,
  ) {
    final msgType = msg['message_type'] ?? 'text';
    final content = msg['content'] ?? '';
    if (msgType == 'image') {
      return _buildMediaMsg(isUser: isUser, time: time, child: _buildImageBubble(content, isUser));
    } else if (msgType == 'video') {
      final msgId = msg['id'] as String? ?? content;
      return _buildMediaMsg(isUser: isUser, time: time, child: _buildVideoBubble(content, msgId));
    }
    return _buildMsg(content, isUser, time, senderName);
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

  // Container for media bubbles (image / video)
  Widget _buildMediaMsg({required bool isUser, required String time, required Widget child}) {
    return Row(
      mainAxisAlignment: isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Flexible(
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
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
            clipBehavior: Clip.hardEdge,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                child,
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
                  child: Text(
                    time,
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 10, color: isUser ? Colors.white60 : AppColors.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImageBubble(String url, bool isUser) {
    return GestureDetector(
      onTap: () => _showFullscreenImage(url),
      child: Stack(
        children: [
          Image.network(
            url,
            fit: BoxFit.cover,
            width: double.infinity,
            height: 200,
            errorBuilder: (_, e, __) => Container(
              height: 100,
              color: Colors.black12,
              child: const Center(child: Icon(Icons.broken_image_outlined, color: Colors.grey)),
            ),
          ),
          // Zoom hint overlay
          Positioned(
            bottom: 6, right: 6,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.black45,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.zoom_in, color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoBubble(String url, String msgId) {
    if (!_videoControllers.containsKey(msgId)) {
      final vc = VideoPlayerController.networkUrl(Uri.parse(url))
        ..initialize().then((_) {
          if (mounted) setState(() {});
        });
      _videoControllers[msgId] = vc;
    }
    final vc = _videoControllers[msgId]!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: vc.value.isInitialized ? vc.value.aspectRatio : 16 / 9,
          child: vc.value.isInitialized
              ? VideoPlayer(vc)
              : const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        // Controls row
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: Icon(
                vc.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                color: AppColors.primary,
                size: 36,
              ),
              onPressed: () => setState(() {
                vc.value.isPlaying ? vc.pause() : vc.play();
              }),
            ),
          ],
        ),
      ],
    );
  }

  void _showFullscreenImage(String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => GestureDetector(
        onTap: () => Navigator.pop(ctx),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            foregroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(ctx),
            ),
          ),
          body: Center(
            child: InteractiveViewer(
              child: Image.network(url),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _pickMedia(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(top: 12, bottom: 16),
              decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(2)),
            ),
            const Text('Send Media', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.camera_alt_outlined, color: AppColors.primary),
              ),
              title: const Text('Take Photo'),
              subtitle: const Text('Open camera to capture image'),
              onTap: () async {
                Navigator.pop(ctx);
                final picked = await _picker.pickImage(source: ImageSource.camera, imageQuality: 80);
                if (picked != null && mounted) {
                  await _viewModel.sendMediaMessage(filePath: picked.path, mimeType: 'image/jpeg');
                }
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.photo_library_outlined, color: AppColors.secondary),
              ),
              title: const Text('Photo from Gallery'),
              subtitle: const Text('Choose an existing photo'),
              onTap: () async {
                Navigator.pop(ctx);
                final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
                if (picked != null && mounted) {
                  await _viewModel.sendMediaMessage(filePath: picked.path, mimeType: 'image/jpeg');
                }
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.videocam_outlined, color: AppColors.success),
              ),
              title: const Text('Record or Pick Video'),
              subtitle: const Text('Capture or choose a video clip'),
              onTap: () async {
                Navigator.pop(ctx);
                final picked = await _picker.pickVideo(
                  source: ImageSource.gallery,
                  maxDuration: const Duration(minutes: 2),
                );
                if (picked != null && mounted) {
                  await _viewModel.sendMediaMessage(filePath: picked.path, mimeType: 'video/mp4');
                }
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
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

  // Centered system row for a finished voice/video call, e.g. "Video call · 1:23"
  Widget _buildCallLogMsg(String content, String time) {
    // content format: '<video|voice>|<seconds>'
    var isVideo = true;
    var seconds = 0;
    final parts = content.split('|');
    if (parts.length == 2) {
      isVideo = parts[0] == 'video';
      seconds = int.tryParse(parts[1]) ?? 0;
    }
    final label = '${isVideo ? 'Video call' : 'Voice call'} · '
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isVideo ? Icons.videocam : Icons.call,
              size: 14,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
            ),
            if (time.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                time,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontSize: 10,
                      color: AppColors.textMuted,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── UC503: Resolution Confirmation Modal for Traveler ────────────────────
  Future<void> _showResolutionDialog(BuildContext context) async {
    final feedback = await showResolutionFeedbackSheet(
      context,
      title: 'Confirm Resolution',
      subtitle: 'Provide feedback for your assistance session',
      question: 'Was your assistance request effectively resolved by the staff?',
      onSubmit: (fb) => _viewModel.submitResolutionFeedback(
        outcome: fb.outcome,
        rating: fb.rating,
        comment: fb.comment,
      ),
    );
    if (feedback == null || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(feedback.isFullyResolved
            ? 'Request closed. Thank you for your rating!'
            : 'Ticket re-opened for staff review.'),
        backgroundColor: feedback.isFullyResolved ? AppColors.success : AppColors.secondary,
        behavior: SnackBarBehavior.floating,
      ),
    );
    Navigator.pop(context);
  }
}
