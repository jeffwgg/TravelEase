import 'package:flutter/material.dart';
import '../../core/router.dart';
import '../../core/theme.dart';
import '../../services/webrtc_service.dart';

class IncomingCallOverlay extends StatefulWidget {
  final Widget child;

  const IncomingCallOverlay({super.key, required this.child});

  @override
  State<IncomingCallOverlay> createState() => _IncomingCallOverlayState();
}

class _IncomingCallOverlayState extends State<IncomingCallOverlay> {
  final WebRTCService _webrtc = WebRTCService.instance;

  @override
  void initState() {
    super.initState();
    _webrtc.addListener(_onCallStateChanged);
  }

  @override
  void dispose() {
    _webrtc.removeListener(_onCallStateChanged);
    super.dispose();
  }

  void _onCallStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIncoming = _webrtc.callState == WebRTCCallState.incoming;

    return Stack(
      children: [
        widget.child,
        if (isIncoming)
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            left: 16,
            right: 16,
            child: Material(
              elevation: 12,
              borderRadius: BorderRadius.circular(20),
              color: AppColors.surface,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 16,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _webrtc.callType == CallType.video
                            ? Icons.videocam_rounded
                            : Icons.phone_in_talk_rounded,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Incoming ${_webrtc.callType == CallType.video ? "Video" : "Voice"} Call',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _webrtc.incomingCallerName.isNotEmpty
                                ? _webrtc.incomingCallerName
                                : 'Staff Member',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Decline Button
                    IconButton(
                      onPressed: () async {
                        await _webrtc.rejectCall();
                      },
                      icon: const Icon(Icons.call_end_rounded, color: Colors.white, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.emergency,
                        padding: const EdgeInsets.all(10),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 8),

                    // Accept Button
                    IconButton(
                      onPressed: () async {
                        final reqId = _webrtc.incomingRequestId;
                        await _webrtc.acceptCall();
                        if (reqId != null && reqId.isNotEmpty) {
                          appRouter.push('/chat?requestId=$reqId');
                        }
                      },
                      icon: const Icon(Icons.call_rounded, color: Colors.white, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor: AppColors.success,
                        padding: const EdgeInsets.all(10),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
