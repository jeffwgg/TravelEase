import { useRef, useState, useCallback, useEffect } from 'react'
import { supabase } from '../lib/supabase'

// Public STUN servers — no account needed
const ICE_SERVERS = [
  { urls: 'stun:stun.l.google.com:19302' },
  { urls: 'stun:stun1.l.google.com:19302' },
]

/**
 * useWebRTC — Web (Staff) side
 *
 * Signaling channel: Supabase Realtime Broadcast
 * Channel name:      call_room_{requestId}
 *
 * Broadcast events sent/received:
 *   call_offer    — { sdp, callType, callerName, callerSide }
 *   call_answer   — { sdp }
 *   ice_candidate — { candidate, sdpMid, sdpMLineIndex }
 *   call_end      — { reason }
 *   call_reject   — { reason }
 */
export function useWebRTC(requestId, onIncomingCall) {
  const [callState, setCallState] = useState('idle') // idle | calling | incoming | connected | ended
  const [callType, setCallType] = useState('video')  // 'video' | 'voice'
  const [incomingOffer, setIncomingOffer] = useState(null)
  const [incomingCallerName, setIncomingCallerName] = useState('')
  const [isMicMuted, setIsMicMuted] = useState(false)
  const [isCameraOff, setIsCameraOff] = useState(false)

  const pcRef = useRef(null)          // RTCPeerConnection
  const localStreamRef = useRef(null) // local MediaStream
  const channelRef = useRef(null)     // Supabase Broadcast channel
  const globalChannelRef = useRef(null) // Global Broadcast channel

  const localVideoRef = useRef(null)  // attach to <video> element
  const remoteVideoRef = useRef(null) // attach to <video> element

  // ─── Signaling helpers ─────────────────────────────────────────────────────

  function getChannel(id = requestId) {
    if (!id) return channelRef.current
    if (channelRef.current && channelRef.current.topic === `realtime:call_room_${id}`) {
      return channelRef.current
    }
    if (channelRef.current) {
      supabase.removeChannel(channelRef.current)
    }
    const ch = supabase.channel(`call_room_${id}`)
    channelRef.current = ch
    return ch
  }

  async function sendSignal(event, payload) {
    const targetId = payload.requestId || requestId
    if (targetId) {
      const ch = getChannel(targetId)
      if (ch) await ch.send({ type: 'broadcast', event, payload })
    }
    if (globalChannelRef.current) {
      await globalChannelRef.current.send({ type: 'broadcast', event, payload })
    }
  }

  // ─── Subscribe to incoming signals ─────────────────────────────────────────

  const subscribeToSignaling = useCallback(() => {
    let channel = null
    if (requestId) {
      channel = getChannel(requestId)
      channel
        .on('broadcast', { event: 'call_offer' }, ({ payload }) => handleCallOffer(payload))
        .on('broadcast', { event: 'call_answer' }, ({ payload }) => handleCallAnswer(payload))
        .on('broadcast', { event: 'ice_candidate' }, ({ payload }) => handleIceCandidate(payload))
        .on('broadcast', { event: 'call_end' }, () => hangup(false))
        .on('broadcast', { event: 'call_reject' }, () => {
          cleanupPeer()
          setCallState('idle')
        })
        .subscribe()
    }

    if (!globalChannelRef.current) {
      const gCh = supabase.channel('call_room_global')
      gCh
        .on('broadcast', { event: 'call_offer' }, ({ payload }) => handleCallOffer(payload))
        .on('broadcast', { event: 'call_answer' }, ({ payload }) => handleCallAnswer(payload))
        .on('broadcast', { event: 'ice_candidate' }, ({ payload }) => handleIceCandidate(payload))
        .on('broadcast', { event: 'call_end' }, () => hangup(false))
        .on('broadcast', { event: 'call_reject' }, () => {
          cleanupPeer()
          setCallState('idle')
        })
        .subscribe()
      globalChannelRef.current = gCh
    }

    function handleCallOffer(payload) {
      if (payload.callerSide === 'web') return
      setIncomingOffer(payload)
      setCallType(payload.callType || 'video')
      setIncomingCallerName(payload.callerName || 'Traveler')
      setCallState('incoming')
      if (onIncomingCall && payload.requestId) {
        onIncomingCall(payload.requestId)
      }
    }

    function handleCallAnswer(payload) {
      if (pcRef.current && payload.sdp) {
        pcRef.current
          .setRemoteDescription(new RTCSessionDescription({ type: 'answer', sdp: payload.sdp }))
          .then(() => setCallState('connected'))
          .catch(console.error)
      }
    }

    function handleIceCandidate(payload) {
      if (pcRef.current && payload.candidate) {
        pcRef.current
          .addIceCandidate(new RTCIceCandidate(payload))
          .catch(console.error)
      }
    }

    return () => {
      if (channel) {
        supabase.removeChannel(channel)
        channelRef.current = null
      }
    }
  }, [requestId, onIncomingCall])

  // ─── Create RTCPeerConnection ───────────────────────────────────────────────

  function createPeer() {
    const pc = new RTCPeerConnection({ iceServers: ICE_SERVERS })

    pc.onicecandidate = (e) => {
      if (e.candidate) {
        sendSignal('ice_candidate', {
          candidate: e.candidate.candidate,
          sdpMid: e.candidate.sdpMid,
          sdpMLineIndex: e.candidate.sdpMLineIndex,
        })
      }
    }

    pc.ontrack = (e) => {
      if (remoteVideoRef.current && e.streams[0]) {
        remoteVideoRef.current.srcObject = e.streams[0]
      }
    }

    pcRef.current = pc
    return pc
  }

  // ─── Start call (Web initiates) ────────────────────────────────────────────

  const startCall = useCallback(async (type = 'video') => {
    setCallType(type)
    setCallState('calling')

    try {
      const constraints = type === 'video'
        ? { audio: true, video: true }
        : { audio: true, video: false }

      const stream = await navigator.mediaDevices.getUserMedia(constraints)
      localStreamRef.current = stream

      if (localVideoRef.current) {
        localVideoRef.current.srcObject = stream
      }

      const pc = createPeer()
      stream.getTracks().forEach((track) => pc.addTrack(track, stream))

      const offer = await pc.createOffer()
      await pc.setLocalDescription(offer)

      await sendSignal('call_offer', {
        sdp: offer.sdp,
        callType: type,
        callerName: 'Staff',
        callerSide: 'web',
      })
    } catch (err) {
      console.error('startCall error:', err)
      cleanupPeer()
      setCallState('idle')
    }
  }, [requestId])

  // ─── Accept incoming call (Web answers Mobile) ─────────────────────────────

  const acceptCall = useCallback(async () => {
    if (!incomingOffer) return
    setCallState('connected')

    try {
      const constraints = callType === 'video'
        ? { audio: true, video: true }
        : { audio: true, video: false }

      const stream = await navigator.mediaDevices.getUserMedia(constraints)
      localStreamRef.current = stream

      if (localVideoRef.current) {
        localVideoRef.current.srcObject = stream
      }

      const pc = createPeer()
      stream.getTracks().forEach((track) => pc.addTrack(track, stream))

      await pc.setRemoteDescription(
        new RTCSessionDescription({ type: 'offer', sdp: incomingOffer.sdp })
      )

      const answer = await pc.createAnswer()
      await pc.setLocalDescription(answer)

      await sendSignal('call_answer', { sdp: answer.sdp })
      setIncomingOffer(null)
    } catch (err) {
      console.error('acceptCall error:', err)
      cleanupPeer()
      setCallState('idle')
    }
  }, [incomingOffer, callType])

  // ─── Reject incoming call ──────────────────────────────────────────────────

  const rejectCall = useCallback(async () => {
    await sendSignal('call_reject', { reason: 'rejected' })
    setIncomingOffer(null)
    setCallState('idle')
  }, [])

  // ─── Hangup ─────────────────────────────────────────────────────────────────

  const hangup = useCallback(async (notifyRemote = true) => {
    if (notifyRemote) {
      await sendSignal('call_end', { reason: 'hangup' })
    }
    cleanupPeer()
    setCallState('idle')
  }, [])

  function cleanupPeer() {
    if (localStreamRef.current) {
      localStreamRef.current.getTracks().forEach((t) => t.stop())
      localStreamRef.current = null
    }
    if (pcRef.current) {
      pcRef.current.close()
      pcRef.current = null
    }
    if (localVideoRef.current) localVideoRef.current.srcObject = null
    if (remoteVideoRef.current) remoteVideoRef.current.srcObject = null
  }

  // ─── Media controls ───────────────────────────────────────────────────────

  const toggleMic = useCallback(() => {
    if (localStreamRef.current) {
      localStreamRef.current.getAudioTracks().forEach((t) => {
        t.enabled = !t.enabled
      })
      setIsMicMuted((prev) => !prev)
    }
  }, [])

  const toggleCamera = useCallback(() => {
    if (localStreamRef.current) {
      localStreamRef.current.getVideoTracks().forEach((t) => {
        t.enabled = !t.enabled
      })
      setIsCameraOff((prev) => !prev)
    }
  }, [])

  return {
    // State
    callState,
    callType,
    incomingCallerName,
    isMicMuted,
    isCameraOff,
    // Video element refs (attach to <video ref={...} />)
    localVideoRef,
    remoteVideoRef,
    // Actions
    startCall,
    acceptCall,
    rejectCall,
    hangup,
    toggleMic,
    toggleCamera,
    subscribeToSignaling,
  }
}
