import React, { createContext, useContext, useState, useEffect, useRef, useCallback } from 'react'
import { useNavigate, useLocation } from 'react-router-dom'
import {
  Phone,
  PhoneIncoming,
  PhoneOff,
  PhoneCall,
  Video,
  VideoOff,
  Mic,
  MicOff,
  MessageSquare,
} from 'lucide-react'
import { supabase } from '../lib/supabase'
import { useAuth } from './AuthContext'
import { shouldAcceptCallOffer } from '../lib/chatNotifications'
import { assistanceRepository } from '../repositories/assistanceRepository'

const WebRTCContext = createContext(null)

const ICE_SERVERS = [
  { urls: 'stun:stun.l.google.com:19302' },
  { urls: 'stun:stun1.l.google.com:19302' },
]

function createRingtonePlayer() {
  let ctx = null
  let timer = null
  let isPlaying = false

  function playRingBurst() {
    if (!isPlaying) return
    try {
      const AudioContextClass = window.AudioContext || window.webkitAudioContext
      if (!AudioContextClass) return
      if (!ctx || ctx.state === 'closed') {
        ctx = new AudioContextClass()
      }
      if (ctx.state === 'suspended') {
        ctx.resume()
      }
      const now = ctx.currentTime

      const osc1 = ctx.createOscillator()
      const osc2 = ctx.createOscillator()
      const gain = ctx.createGain()

      osc1.type = 'sine'
      osc1.frequency.setValueAtTime(440, now) // Standard telephone ring frequencies
      osc2.type = 'sine'
      osc2.frequency.setValueAtTime(480, now)

      gain.gain.setValueAtTime(0.08, now)
      gain.gain.setValueAtTime(0.08, now + 1.5)
      gain.gain.exponentialRampToValueAtTime(0.001, now + 1.6)

      osc1.connect(gain)
      osc2.connect(gain)
      gain.connect(ctx.destination)

      osc1.start(now)
      osc2.start(now)
      osc1.stop(now + 1.6)
      osc2.stop(now + 1.6)
    } catch (_) {
      // AudioContext blocked before interaction
    }
  }

  return {
    start() {
      if (isPlaying) return
      isPlaying = true
      playRingBurst()
      timer = setInterval(playRingBurst, 3500)
    },
    stop() {
      isPlaying = false
      if (timer) {
        clearInterval(timer)
        timer = null
      }
      if (ctx && ctx.state !== 'closed') {
        try {
          ctx.close()
        } catch (_) {}
        ctx = null
      }
    },
  }
}

export function WebRTCProvider({ children }) {
  const navigate = useNavigate()
  const location = useLocation()
  const { staffContext } = useAuth()

  const [callState, setCallState] = useState('idle') // idle | calling | incoming | connected | ended
  const [callType, setCallType] = useState('video') // video | voice
  const [incomingCallerName, setIncomingCallerName] = useState('')
  const [incomingReqDetails, setIncomingReqDetails] = useState(null)
  const [activeRequestId, setActiveRequestId] = useState(null)
  const [isMicMuted, setIsMicMuted] = useState(false)
  const [isCameraOff, setIsCameraOff] = useState(false)

  const pcRef = useRef(null)
  const localStreamRef = useRef(null)
  const remoteStreamRef = useRef(null)
  const iceCandidateQueueRef = useRef([])
  const incomingOfferRef = useRef(null)

  const globalChannelRef = useRef(null)
  const roomChannelRef = useRef(null)

  const staffContextRef = useRef(staffContext)
  const ringtoneRef = useRef(null)
  const assignmentCacheRef = useRef(new Map())

  const localVideoRef = useRef(null)
  const remoteVideoRef = useRef(null)

  const initiatedCallRef = useRef(false)
  const connectedAtRef = useRef(null)

  // Initialize ringtone player once
  useEffect(() => {
    ringtoneRef.current = createRingtonePlayer()
    return () => {
      ringtoneRef.current?.stop()
    }
  }, [])

  // Keep staffContext ref updated
  useEffect(() => {
    staffContextRef.current = staffContext
    if (staffContext?.role !== 'staff') {
      assignmentCacheRef.current.clear()
      if (callState !== 'idle') {
        hangup(false)
      }
    }
  }, [staffContext])

  // Attach srcObjects to video elements when active
  useEffect(() => {
    if (remoteVideoRef.current && remoteStreamRef.current) {
      remoteVideoRef.current.srcObject = remoteStreamRef.current
    }
    if (localVideoRef.current && localStreamRef.current) {
      localVideoRef.current.srcObject = localStreamRef.current
    }
  }, [callState, callType])

  // ─── Signaling Helpers ───────────────────────────────────────────────────

  function getRoomChannel(reqId) {
    if (!reqId) return null
    if (roomChannelRef.current && roomChannelRef.current.topic === `realtime:call_room_${reqId}`) {
      return roomChannelRef.current
    }
    if (roomChannelRef.current) {
      supabase.removeChannel(roomChannelRef.current)
      roomChannelRef.current = null
    }
    const ch = supabase.channel(`call_room_${reqId}`)
    setupRoomListeners(ch)
    ch.subscribe()
    roomChannelRef.current = ch
    return ch
  }

  async function sendSignal(event, payload) {
    const targetId = payload.requestId || activeRequestId
    const fullPayload = {
      ...payload,
      requestId: targetId,
    }

    if (targetId) {
      const rCh = getRoomChannel(targetId)
      if (rCh) {
        try {
          await rCh.send({ type: 'broadcast', event, payload: fullPayload })
        } catch (e) {
          console.warn('[WebRTCContext] Room signal send error:', e)
        }
      }
    }

    if (globalChannelRef.current) {
      try {
        await globalChannelRef.current.send({ type: 'broadcast', event, payload: fullPayload })
      } catch (e) {
        console.warn('[WebRTCContext] Global signal send error:', e)
      }
    }
  }

  async function flushIceCandidates() {
    if (!pcRef.current || !pcRef.current.remoteDescription || !pcRef.current.remoteDescription.type) return
    const queued = [...iceCandidateQueueRef.current]
    iceCandidateQueueRef.current = []
    for (const payload of queued) {
      try {
        await pcRef.current.addIceCandidate(new RTCIceCandidate(payload))
      } catch (err) {
        console.error('[WebRTCContext] Error adding queued ICE candidate:', err)
      }
    }
  }

  function cleanupPeer() {
    ringtoneRef.current?.stop()
    if (localStreamRef.current) {
      localStreamRef.current.getTracks().forEach((t) => t.stop())
      localStreamRef.current = null
    }
    if (remoteStreamRef.current) {
      remoteStreamRef.current.getTracks().forEach((t) => t.stop())
      remoteStreamRef.current = null
    }
    iceCandidateQueueRef.current = []
    if (pcRef.current) {
      pcRef.current.close()
      pcRef.current = null
    }
    if (localVideoRef.current) localVideoRef.current.srcObject = null
    if (remoteVideoRef.current) remoteVideoRef.current.srcObject = null
    incomingOfferRef.current = null
    if (roomChannelRef.current) {
      supabase.removeChannel(roomChannelRef.current)
      roomChannelRef.current = null
    }
  }

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
      const stream = (e.streams && e.streams[0]) ? e.streams[0] : new MediaStream([e.track])
      remoteStreamRef.current = stream
      if (remoteVideoRef.current) {
        remoteVideoRef.current.srcObject = stream
      }
    }

    pcRef.current = pc
    return pc
  }

  // ─── Event Handlers ──────────────────────────────────────────────────────

  async function handleCallOffer(payload) {
    if (payload.callerSide === 'web') return

    const currentContext = staffContextRef.current
    if (!currentContext || currentContext.role !== 'staff' || !currentContext.staff?.id) {
      return
    }

    const currentStaffId = currentContext.staff.id
    const targetRequestId = payload.requestId
    if (!targetRequestId) return

    // Verify assigned staff for this request
    let assignedStaffId = null
    let reqInfo = null

    const cached = assignmentCacheRef.current.get(targetRequestId)
    if (cached && Date.now() - cached.timestamp < 30000 && cached.assigned_staff_id === currentStaffId) {
      assignedStaffId = cached.assigned_staff_id
      reqInfo = cached.reqInfo
    } else {
      try {
        const { data: request, error } = await supabase
          .from('assistance_requests')
          .select('id, assigned_staff_id, request_code, location_zone, traveler_name')
          .eq('id', targetRequestId)
          .maybeSingle()

        if (error || !request) {
          console.warn('[WebRTCContext] Error looking up request for incoming call:', error)
          return
        }

        assignedStaffId = request.assigned_staff_id
        reqInfo = request
        if (assignedStaffId === currentStaffId) {
          assignmentCacheRef.current.set(targetRequestId, {
            assigned_staff_id: assignedStaffId,
            reqInfo: request,
            timestamp: Date.now(),
          })
        }
      } catch (err) {
        console.warn('[WebRTCContext] Failed to query request for call offer:', err)
        return
      }
    }

    const eligible = shouldAcceptCallOffer({
      role: currentContext.role,
      currentStaffId,
      callerSide: payload.callerSide,
      requestAssignedStaffId: assignedStaffId,
      activeRequestId,
      targetRequestId,
    })

    if (!eligible) {
      console.warn('[WebRTCContext] Call offer ignored: current staff not assigned to request nor viewing it', {
        targetRequestId,
        requestAssignedStaffId: assignedStaffId,
        currentStaffId,
        activeRequestId,
      })
      return
    }

    incomingOfferRef.current = payload
    setActiveRequestId(targetRequestId)
    setCallType(payload.callType || 'video')
    setIncomingCallerName(payload.callerName || reqInfo?.traveler_name || 'Traveler')
    setIncomingReqDetails(reqInfo)
    setCallState('incoming')

    // Start audible ringing so staff notices the incoming call
    ringtoneRef.current?.start()

    // Ensure room channel is ready
    getRoomChannel(targetRequestId)
  }

  async function handleCallAnswer(payload) {
    if (!pcRef.current || !payload.sdp) return

    // Guard against duplicate call_answer messages (e.g., received via both room and global channels)
    if (pcRef.current.signalingState !== 'have-local-offer') {
      console.log('[WebRTCContext] Ignoring call_answer received in signaling state:', pcRef.current.signalingState)
      return
    }

    try {
      await pcRef.current.setRemoteDescription(new RTCSessionDescription({ type: 'answer', sdp: payload.sdp }))
      await flushIceCandidates()
      setCallState('connected')
      connectedAtRef.current = Date.now()
      ringtoneRef.current?.stop()
    } catch (err) {
      console.error('[WebRTCContext] handleCallAnswer error:', err)
    }
  }

  async function handleIceCandidate(payload) {
    if (!payload || !payload.candidate) return
    if (pcRef.current && pcRef.current.remoteDescription && pcRef.current.remoteDescription.type) {
      try {
        await pcRef.current.addIceCandidate(new RTCIceCandidate(payload))
      } catch (err) {
        console.error('[WebRTCContext] handleIceCandidate error:', err)
      }
    } else {
      iceCandidateQueueRef.current.push(payload)
    }
  }

  function setupRoomListeners(channel) {
    channel
      .on('broadcast', { event: 'call_offer' }, ({ payload }) => handleCallOffer(payload))
      .on('broadcast', { event: 'call_answer' }, ({ payload }) => handleCallAnswer(payload))
      .on('broadcast', { event: 'ice_candidate' }, ({ payload }) => handleIceCandidate(payload))
      .on('broadcast', { event: 'call_end' }, () => hangup(false))
      .on('broadcast', { event: 'call_reject' }, () => {
        cleanupPeer()
        setCallState('idle')
      })
  }

  // ─── Global Signaling Subscription ───────────────────────────────────────
  // Subscribes globally at root whenever staff is logged in, so calls can be
  // received from ANY page (Dashboard, Requests, SOS, Chat, etc.)
  useEffect(() => {
    if (staffContext?.role !== 'staff' || !staffContext?.staff?.id) {
      if (globalChannelRef.current) {
        supabase.removeChannel(globalChannelRef.current)
        globalChannelRef.current = null
      }
      return
    }

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

    return () => {
      if (globalChannelRef.current) {
        supabase.removeChannel(globalChannelRef.current)
        globalChannelRef.current = null
      }
    }
  }, [staffContext?.role, staffContext?.staff?.id])

  // ─── Call Actions ────────────────────────────────────────────────────────

  const startCall = useCallback(async (type = 'video', targetId, travelerName, targetUserId) => {
    const reqId = targetId || activeRequestId
    if (!reqId) {
      console.warn('[WebRTCContext] startCall called with no target requestId')
      return
    }

    setCallType(type)
    setCallState('calling')
    setActiveRequestId(reqId)
    setIncomingCallerName(travelerName || 'Traveler')
    initiatedCallRef.current = true
    connectedAtRef.current = null
    iceCandidateQueueRef.current = []

    let finalTargetUserId = targetUserId
    if (!finalTargetUserId && reqId) {
      try {
        const { data: reqRow } = await supabase
          .from('assistance_requests')
          .select('user_id')
          .eq('id', reqId)
          .maybeSingle()
        finalTargetUserId = reqRow?.user_id || null
      } catch (err) {
        console.warn('[WebRTCContext] Failed to lookup user_id for call:', err)
      }
    }

    try {
      const constraints = type === 'video'
        ? { audio: true, video: true }
        : { audio: true, video: false }

      const stream = await navigator.mediaDevices.getUserMedia(constraints)
      localStreamRef.current = stream

      if (localVideoRef.current) {
        localVideoRef.current.srcObject = stream
      }

      getRoomChannel(reqId)

      const pc = createPeer()
      stream.getTracks().forEach((track) => pc.addTrack(track, stream))

      const offer = await pc.createOffer()
      await pc.setLocalDescription(offer)

      await sendSignal('call_offer', {
        sdp: offer.sdp,
        callType: type,
        callerName: 'Staff',
        callerSide: 'web',
        requestId: reqId,
        targetUserId: finalTargetUserId,
      })
    } catch (err) {
      console.error('[WebRTCContext] startCall error:', err)
      cleanupPeer()
      setCallState('idle')
    }
  }, [activeRequestId])

  const acceptCall = useCallback(async () => {
    const offer = incomingOfferRef.current
    if (!offer) return

    ringtoneRef.current?.stop()
    setCallState('connected')
    connectedAtRef.current = Date.now()

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
        new RTCSessionDescription({ type: 'offer', sdp: offer.sdp })
      )

      await flushIceCandidates()

      const answer = await pc.createAnswer()
      await pc.setLocalDescription(answer)

      await sendSignal('call_answer', { sdp: answer.sdp, requestId: activeRequestId })
      incomingOfferRef.current = null

      // Automatically open chat for this request so staff has notes and traveler info
      if (activeRequestId && location.pathname !== '/chat') {
        navigate('/chat', { state: { requestId: activeRequestId } })
      }
    } catch (err) {
      console.error('[WebRTCContext] acceptCall error:', err)
      cleanupPeer()
      setCallState('idle')
    }
  }, [callType, activeRequestId, location.pathname, navigate])

  const rejectCall = useCallback(async () => {
    ringtoneRef.current?.stop()
    await sendSignal('call_reject', { reason: 'rejected', requestId: activeRequestId })
    cleanupPeer()
    setCallState('idle')
  }, [activeRequestId])

  const hangup = useCallback(async (notifyRemote = true) => {
    ringtoneRef.current?.stop()

    // Log call summary if this device dialed
    if (initiatedCallRef.current && connectedAtRef.current && activeRequestId) {
      const seconds = Math.round((Date.now() - connectedAtRef.current) / 1000)
      if (seconds > 0) {
        assistanceRepository.sendChatMessage({
          request_id: activeRequestId,
          sender_type: 'staff',
          sender_name: 'Call Log',
          content: `${callType}|${seconds}`,
          message_type: 'call',
          is_read: true,
          created_at: new Date().toISOString(),
        }).catch((err) => console.error('[WebRTCContext] Failed to log call summary:', err))
      }
    }

    initiatedCallRef.current = false
    connectedAtRef.current = null

    if (notifyRemote) {
      await sendSignal('call_end', { reason: 'hangup', requestId: activeRequestId })
    }

    cleanupPeer()
    setCallState('idle')
  }, [activeRequestId, callType])

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

  const isInCall = callState === 'connected' || callState === 'calling'

  return (
    <WebRTCContext.Provider
      value={{
        callState,
        callType,
        incomingCallerName,
        activeRequestId,
        isMicMuted,
        isCameraOff,
        localVideoRef,
        remoteVideoRef,
        startCall,
        acceptCall,
        rejectCall,
        hangup,
        toggleMic,
        toggleCamera,
      }}
    >
      {children}

      {/* ── Global Incoming Call Modal (Mobile → Web) ────────────────────────── */}
      {callState === 'incoming' && (
        <div
          style={{
            position: 'fixed',
            top: 0, left: 0, right: 0, bottom: 0,
            backgroundColor: 'rgba(15, 23, 42, 0.85)',
            backdropFilter: 'blur(8px)',
            zIndex: 99999,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
          }}
        >
          <div
            style={{
              background: '#1e293b',
              borderRadius: '24px',
              padding: '40px 48px',
              textAlign: 'center',
              boxShadow: '0 32px 80px rgba(0,0,0,0.6)',
              minWidth: '340px',
              border: '1px solid rgba(59, 130, 246, 0.3)',
            }}
          >
            <div
              style={{
                width: '80px', height: '80px',
                borderRadius: '50%',
                background: 'rgba(59,130,246,0.2)',
                border: '2px solid rgba(59,130,246,0.5)',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                margin: '0 auto 20px',
              }}
            >
              <PhoneIncoming size={36} color="#60a5fa" />
            </div>

            <div style={{ fontSize: '13px', color: '#94a3b8', marginBottom: '6px', textTransform: 'uppercase', letterSpacing: '1px' }}>
              Incoming {callType === 'video' ? 'Video' : 'Voice'} Call
            </div>

            <div style={{ fontSize: '22px', fontWeight: '700', color: '#f1f5f9', marginBottom: '8px' }}>
              {incomingCallerName}
            </div>

            {incomingReqDetails && (
              <div style={{ fontSize: '13px', color: '#64748b', marginBottom: '32px' }}>
                {incomingReqDetails.request_code} · {incomingReqDetails.location_zone}
              </div>
            )}

            <div style={{ display: 'flex', gap: '20px', justifyContent: 'center' }}>
              <button
                onClick={rejectCall}
                title="Decline Call"
                style={{
                  width: '56px', height: '56px', borderRadius: '50%',
                  background: '#ef4444', border: 'none', cursor: 'pointer',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  boxShadow: '0 4px 14px rgba(239,68,68,0.4)',
                  transition: 'transform 0.15s ease',
                }}
              >
                <PhoneOff size={22} color="white" />
              </button>

              <button
                onClick={acceptCall}
                title="Accept Call"
                style={{
                  width: '56px', height: '56px', borderRadius: '50%',
                  background: '#22c55e', border: 'none', cursor: 'pointer',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  boxShadow: '0 4px 14px rgba(34,197,94,0.4)',
                  transition: 'transform 0.15s ease',
                }}
              >
                {callType === 'video' ? <Video size={22} color="white" /> : <Phone size={22} color="white" />}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── Global Active Call Overlay ───────────────────────────────────────── */}
      {isInCall && (
        <div
          style={{
            position: 'fixed',
            top: 0, left: 0, right: 0, bottom: 0,
            background: '#0f172a',
            zIndex: 99998,
            display: 'flex',
            flexDirection: 'column',
            alignItems: 'center',
            justifyContent: 'center',
          }}
        >
          {/* Remote Video */}
          <video
            ref={remoteVideoRef}
            autoPlay
            playsInline
            style={{
              position: 'absolute', inset: 0,
              width: '100%', height: '100%',
              objectFit: 'cover',
              opacity: callType === 'video' ? 1 : 0,
            }}
          />

          {/* Calling State Indicator */}
          {callState === 'calling' && (
            <div
              style={{
                position: 'absolute', inset: 0,
                display: 'flex', flexDirection: 'column',
                alignItems: 'center', justifyContent: 'center',
                color: 'white',
                zIndex: 2,
              }}
            >
              <PhoneCall size={60} color="#60a5fa" style={{ marginBottom: '16px' }} />
              <div style={{ fontSize: '20px', fontWeight: '600', marginBottom: '8px' }}>
                Calling {incomingCallerName}...
              </div>
              <div style={{ color: '#94a3b8', fontSize: '14px' }}>Waiting for traveler to accept</div>
            </div>
          )}

          {/* Voice-only caller banner */}
          {callType === 'voice' && callState === 'connected' && (
            <div
              style={{
                position: 'absolute', inset: 0,
                display: 'flex', flexDirection: 'column',
                alignItems: 'center', justifyContent: 'center',
                color: 'white',
              }}
            >
              <div
                style={{
                  width: '100px', height: '100px',
                  borderRadius: '50%',
                  background: 'rgba(59,130,246,0.2)',
                  border: '2px solid rgba(59,130,246,0.5)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  marginBottom: '20px',
                }}
              >
                <Phone size={44} color="#60a5fa" />
              </div>
              <div style={{ fontSize: '24px', fontWeight: '700', marginBottom: '8px' }}>
                {incomingCallerName}
              </div>
              <div style={{ color: '#22c55e', fontSize: '14px', fontWeight: '600' }}>Voice Call Connected</div>
            </div>
          )}

          {/* Local Video PIP */}
          {callType === 'video' && (
            <video
              ref={localVideoRef}
              autoPlay
              playsInline
              muted
              style={{
                position: 'absolute',
                bottom: '120px', right: '24px',
                width: '180px', height: '130px',
                objectFit: 'cover',
                borderRadius: '12px',
                border: '2px solid rgba(255,255,255,0.2)',
                zIndex: 3,
                background: '#000',
              }}
            />
          )}

          {/* Call Controls Bar */}
          <div
            style={{
              position: 'absolute',
              bottom: '32px',
              display: 'flex',
              gap: '16px',
              alignItems: 'center',
              background: 'rgba(255,255,255,0.12)',
              backdropFilter: 'blur(16px)',
              borderRadius: '50px',
              padding: '12px 24px',
              zIndex: 4,
            }}
          >
            <button
              onClick={toggleMic}
              style={{
                width: '48px', height: '48px', borderRadius: '50%',
                background: isMicMuted ? '#ef4444' : 'rgba(255,255,255,0.15)',
                border: 'none', cursor: 'pointer',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}
              title={isMicMuted ? 'Unmute' : 'Mute'}
            >
              {isMicMuted ? <MicOff size={20} color="white" /> : <Mic size={20} color="white" />}
            </button>

            {callType === 'video' && (
              <button
                onClick={toggleCamera}
                style={{
                  width: '48px', height: '48px', borderRadius: '50%',
                  background: isCameraOff ? '#ef4444' : 'rgba(255,255,255,0.15)',
                  border: 'none', cursor: 'pointer',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                }}
                title={isCameraOff ? 'Turn Camera On' : 'Turn Camera Off'}
              >
                {isCameraOff ? <VideoOff size={20} color="white" /> : <Video size={20} color="white" />}
              </button>
            )}

            {activeRequestId && (
              <button
                onClick={() => {
                  navigate('/chat', { state: { requestId: activeRequestId } })
                }}
                style={{
                  width: '48px', height: '48px', borderRadius: '50%',
                  background: 'rgba(59,130,246,0.3)',
                  border: '1px solid rgba(59,130,246,0.5)',
                  cursor: 'pointer',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                }}
                title="Open Chat Panel"
              >
                <MessageSquare size={20} color="#60a5fa" />
              </button>
            )}

            <button
              onClick={() => hangup(true)}
              style={{
                width: '48px', height: '48px', borderRadius: '50%',
                background: '#ef4444',
                border: 'none', cursor: 'pointer',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}
              title="End Call"
            >
              <PhoneOff size={20} color="white" />
            </button>
          </div>
        </div>
      )}
    </WebRTCContext.Provider>
  )
}

export function useWebRTCContext() {
  const ctx = useContext(WebRTCContext)
  if (!ctx) {
    throw new Error('useWebRTCContext must be used within a WebRTCProvider')
  }
  return ctx
}
