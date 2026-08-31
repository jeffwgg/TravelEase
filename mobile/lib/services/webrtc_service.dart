import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/supabase_client.dart';

/// Call types
enum CallType { video, voice }

/// States the call can be in
enum WebRTCCallState { idle, calling, incoming, connected, ended }

/// WebRTCService — Mobile (Traveler) side
///
/// Signaling channel: Supabase Realtime Broadcast
/// Channel name:      call_room_{requestId}
///
/// Broadcast events:
///   call_offer    — { sdp, callType, callerName, callerSide }
///   call_answer   — { sdp }
///   ice_candidate — { candidate, sdpMid, sdpMLineIndex }
///   call_end      — { reason }
///   call_reject   — { reason }
class WebRTCService extends ChangeNotifier {
  // Singleton instance
  static final WebRTCService instance = WebRTCService._internal();
  factory WebRTCService() => instance;
  WebRTCService._internal();

  // ── ICE Servers (public STUN — no account needed) ─────────────────────────
  static const _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ]
  };

  // ── State ──────────────────────────────────────────────────────────────────
  WebRTCCallState callState = WebRTCCallState.idle;
  CallType callType = CallType.video;
  String incomingCallerName = '';
  String? incomingRequestId;
  bool isMicMuted = false;
  bool isCameraOff = false;

  // ── WebRTC internals ───────────────────────────────────────────────────────
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  Map<String, dynamic>? _pendingOffer; // held until user accepts
  final List<RTCIceCandidate> _iceCandidateQueue = [];
  bool _remoteDescriptionSet = false;

  // ── Video renderers (attach to RTCVideoView in your widget) ───────────────
  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  // ── Supabase signaling ─────────────────────────────────────────────────────
  final _client = SupabaseClientHelper.client;
  RealtimeChannel? _signalingChannel;
  RealtimeChannel? _globalChannel;
  String? _requestId;

  bool _renderersInitialized = false;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Call this once when app starts.
  Future<void> init() async {
    if (_renderersInitialized) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _renderersInitialized = true;
  }

  /// Global foreground listener for incoming calls from any room/request
  void subscribeToGlobalSignaling() {
    if (_globalChannel != null) return;
    _globalChannel = _client
        .channel('call_room_global')
        .onBroadcast(
          event: 'call_offer',
          callback: (payload) => _onCallOffer(payload),
        )
        .onBroadcast(
          event: 'call_answer',
          callback: (payload) => _onCallAnswer(payload),
        )
        .onBroadcast(
          event: 'ice_candidate',
          callback: (payload) => _onIceCandidate(payload),
        )
        .onBroadcast(
          event: 'call_end',
          callback: (_) => hangup(notifyRemote: false),
        )
        .onBroadcast(
          event: 'call_reject',
          callback: (_) {
            _cleanupPeer();
            callState = WebRTCCallState.idle;
            notifyListeners();
          },
        )
        .subscribe();
  }

  /// Subscribe to the signaling channel for [requestId].
  /// Call this when the user enters the chat screen.
  void subscribeToSignaling(String requestId) {
    if (_requestId == requestId) return; // already subscribed
    _unsubscribeSignaling();
    _requestId = requestId;

    _signalingChannel = _client
        .channel('call_room_$requestId')
        .onBroadcast(
          event: 'call_offer',
          callback: (payload) => _onCallOffer(payload),
        )
        .onBroadcast(
          event: 'call_answer',
          callback: (payload) => _onCallAnswer(payload),
        )
        .onBroadcast(
          event: 'ice_candidate',
          callback: (payload) => _onIceCandidate(payload),
        )
        .onBroadcast(
          event: 'call_end',
          callback: (_) => hangup(notifyRemote: false),
        )
        .onBroadcast(
          event: 'call_reject',
          callback: (_) {
            _cleanupPeer();
            callState = WebRTCCallState.idle;
            notifyListeners();
          },
        )
        .subscribe();
  }

  // ── Mobile initiates a call → sends offer to Web ──────────────────────────

  Future<void> startCall(String requestId, CallType type) async {
    callType = type;
    callState = WebRTCCallState.calling;
    _remoteDescriptionSet = false;
    _iceCandidateQueue.clear();
    notifyListeners();

    try {
      final constraints = _mediaConstraints(type);
      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      localRenderer.srcObject = _localStream;

      final pc = await _createPeer();
      _localStream!.getTracks().forEach((track) {
        pc.addTrack(track, _localStream!);
      });

      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);

      await _sendSignal('call_offer', {
        'sdp': offer.sdp,
        'callType': type == CallType.video ? 'video' : 'voice',
        'callerName': 'Jeff Wong (Traveler)',
        'callerSide': 'mobile',
        'requestId': requestId,
      });
    } catch (e) {
      debugPrint('WebRTCService.startCall error: $e');
      _cleanupPeer();
      callState = WebRTCCallState.idle;
      notifyListeners();
    }
  }

  // ── Accept incoming call (Web initiated) ──────────────────────────────────

  Future<void> acceptCall() async {
    if (_pendingOffer == null) return;
    callState = WebRTCCallState.connected;
    notifyListeners();

    try {
      final constraints = _mediaConstraints(callType);
      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      localRenderer.srcObject = _localStream;

      final pc = await _createPeer();
      _localStream!.getTracks().forEach((track) {
        pc.addTrack(track, _localStream!);
      });

      await pc.setRemoteDescription(
        RTCSessionDescription(_pendingOffer!['sdp'] as String, 'offer'),
      );
      _remoteDescriptionSet = true;

      // Process any early ICE candidates that arrived before user accepted
      await _flushIceCandidates();

      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);

      await _sendSignal('call_answer', {'sdp': answer.sdp});
      _pendingOffer = null;
    } catch (e) {
      debugPrint('WebRTCService.acceptCall error: $e');
      _cleanupPeer();
      callState = WebRTCCallState.idle;
      notifyListeners();
    }
  }

  // ── Reject incoming call ───────────────────────────────────────────────────

  Future<void> rejectCall() async {
    await _sendSignal('call_reject', {'reason': 'rejected'});
    _pendingOffer = null;
    _cleanupPeer();
    callState = WebRTCCallState.idle;
    notifyListeners();
  }

  // ── Hang up ───────────────────────────────────────────────────────────────

  Future<void> hangup({bool notifyRemote = true}) async {
    if (notifyRemote) {
      await _sendSignal('call_end', {'reason': 'hangup'});
    }
    _cleanupPeer();
    callState = WebRTCCallState.idle;
    notifyListeners();
  }

  // ── Mic / Camera toggles ──────────────────────────────────────────────────

  void toggleMic() {
    _localStream?.getAudioTracks().forEach((t) {
      t.enabled = !t.enabled;
    });
    isMicMuted = !isMicMuted;
    notifyListeners();
  }

  void toggleCamera() {
    _localStream?.getVideoTracks().forEach((t) {
      t.enabled = !t.enabled;
    });
    isCameraOff = !isCameraOff;
    notifyListeners();
  }

  // ── Private: signal event handlers ───────────────────────────────────────

  void _onCallOffer(Map<String, dynamic> payload) {
    final data = payload.containsKey('payload') ? payload['payload'] : payload;

    // If we sent this ourselves (mobile), ignore
    if (data['callerSide'] == 'mobile') return;

    _pendingOffer = data;
    callType = (data['callType'] as String?) == 'voice'
        ? CallType.voice
        : CallType.video;
    incomingCallerName = (data['callerName'] as String?) ?? 'Staff';
    incomingRequestId = (data['requestId'] as String?) ?? _requestId;

    if (incomingRequestId != null && _requestId != incomingRequestId) {
      subscribeToSignaling(incomingRequestId!);
    }

    callState = WebRTCCallState.incoming;
    notifyListeners();
  }

  Future<void> _onCallAnswer(Map<String, dynamic> payload) async {
    if (_pc == null) return;
    final data = payload.containsKey('payload') ? payload['payload'] : payload;
    final sdp = data['sdp'] as String?;
    if (sdp == null) return;
    await _pc!.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
    _remoteDescriptionSet = true;
    await _flushIceCandidates();
    callState = WebRTCCallState.connected;
    notifyListeners();
  }

  Future<void> _onIceCandidate(Map<String, dynamic> payload) async {
    final data = payload.containsKey('payload') ? payload['payload'] : payload;
    final candidateStr = data['candidate'] as String?;
    if (candidateStr == null) return;

    final candidate = RTCIceCandidate(
      candidateStr,
      data['sdpMid'] as String?,
      data['sdpMLineIndex'] as int?,
    );

    if (_pc != null && _remoteDescriptionSet) {
      try {
        await _pc!.addCandidate(candidate);
      } catch (e) {
        debugPrint('addIceCandidate error: $e');
      }
    } else {
      // Buffer early ICE candidates until setRemoteDescription finishes
      _iceCandidateQueue.add(candidate);
    }
  }

  Future<void> _flushIceCandidates() async {
    if (_pc == null || !_remoteDescriptionSet) return;
    for (final candidate in List.of(_iceCandidateQueue)) {
      try {
        await _pc!.addCandidate(candidate);
      } catch (e) {
        debugPrint('flush candidate error: $e');
      }
    }
    _iceCandidateQueue.clear();
  }

  // ── Private: peer connection ───────────────────────────────────────────────

  Future<RTCPeerConnection> _createPeer() async {
    final pc = await createPeerConnection(_iceServers);

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        _sendSignal('ice_candidate', {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        });
      }
    };

    pc.onTrack = (event) async {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams[0];
      } else {
        if (remoteRenderer.srcObject == null) {
          final stream = await createLocalMediaStream('remote_stream');
          stream.addTrack(event.track);
          remoteRenderer.srcObject = stream;
        } else {
          remoteRenderer.srcObject!.addTrack(event.track);
        }
      }
      notifyListeners();
    };

    _pc = pc;
    return pc;
  }

  Map<String, dynamic> _mediaConstraints(CallType type) {
    return {
      'audio': true,
      'video': type == CallType.video
          ? {'facingMode': 'user', 'width': 640, 'height': 480}
          : false,
    };
  }

  void _cleanupPeer() {
    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream = null;
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;
    _iceCandidateQueue.clear();
    _remoteDescriptionSet = false;
    _pc?.close();
    _pc = null;
  }

  // ── Private: signaling ─────────────────────────────────────────────────────

  Future<void> _sendSignal(String event, Map<String, dynamic> payload) async {
    final fullPayload = {
      ...payload,
      if (!payload.containsKey('requestId') && _requestId != null) 'requestId': _requestId,
      if (!payload.containsKey('requestId') && incomingRequestId != null) 'requestId': incomingRequestId,
    };
    if (_signalingChannel != null) {
      await _signalingChannel!.sendBroadcastMessage(
        event: event,
        payload: fullPayload,
      );
    }
    try {
      final globalChannel = _client.channel('call_room_global');
      await globalChannel.sendBroadcastMessage(
        event: event,
        payload: fullPayload,
      );
    } catch (e) {
      debugPrint('Global signal broadcast error: $e');
    }
  }

  void _unsubscribeSignaling() {
    if (_signalingChannel != null) {
      _client.removeChannel(_signalingChannel!);
      _signalingChannel = null;
    }
    _requestId = null;
  }

  // ── Dispose ────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _cleanupPeer();
    _unsubscribeSignaling();
    if (_renderersInitialized) {
      localRenderer.dispose();
      remoteRenderer.dispose();
    }
    super.dispose();
  }
}
