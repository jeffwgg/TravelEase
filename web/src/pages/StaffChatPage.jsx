import React, { useState, useEffect, useRef } from 'react'
import { useLocation } from 'react-router-dom'
import { 
  MapPin, 
  Mic, 
  MicOff, 
  Zap, 
  Send, 
  CheckCircle2, 
  Video, 
  VideoOff, 
  PhoneCall, 
  PhoneOff, 
  Phone, 
  PhoneIncoming, 
  X, 
  AlertTriangle,
  Star,
  AlertCircle,
  Paperclip,
  Loader2,
  Radio
} from 'lucide-react'
import { assistanceRepository } from '../repositories/assistanceRepository'
import { useWebRTC } from '../hooks/useWebRTC'
import { useNotifications } from '../context/NotificationContext'
import { useAuth } from '../context/AuthContext'
import LiveLocationMap from '../components/LiveLocationMap'

export default function StaffChatPage() {
  const location = useLocation()
  const targetRequestId = location.state?.requestId
  const { setActiveChatId } = useNotifications()
  const { staffContext } = useAuth()
  const myStaffId = staffContext?.staff?.id

  const [requests, setRequests] = useState([])
  const [selectedReq, setSelectedReq] = useState(null)
  const [messages, setMessages] = useState([])
  const [inputText, setInputText] = useState('')
  const [loadingMsg, setLoadingMsg] = useState(false)
  const [showMapModal, setShowMapModal] = useState(false)
  const [searchQuery, setSearchQuery] = useState('')
  const [isUploading, setIsUploading] = useState(false)
  const [lightboxUrl, setLightboxUrl] = useState(null)

  const [chatFilter, setChatFilter] = useState('unsolved') // 'unsolved' | 'solved' | 'all'

  const messagesEndRef = useRef(null)
  const fileInputRef = useRef(null)

  const scrollToBottom = (smooth = true) => {
    if (messagesEndRef.current) {
      messagesEndRef.current.scrollIntoView({ behavior: smooth ? 'smooth' : 'auto' })
    }
  }

  // Scroll to bottom when conversation loads or changes
  useEffect(() => {
    scrollToBottom(false)
  }, [selectedReq?.id])

  // Scroll to bottom whenever messages are added/received
  useEffect(() => {
    scrollToBottom(true)
  }, [messages])

  // Let NotificationProvider know which conversation is open to suppress popups for this chat
  useEffect(() => {
    setActiveChatId(selectedReq?.id ?? null)
    return () => setActiveChatId(null)
  }, [selectedReq?.id, setActiveChatId])

  const handleIncomingCall = React.useCallback((reqId) => {
    setRequests((prev) => {
      const match = prev.find((r) => r.id === reqId)
      if (match) setSelectedReq(match)
      return prev
    })
  }, [])

  // WebRTC hook — wired to the selected request's ID
  const {
    callState,
    callType,
    incomingCallerName,
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
    subscribeToSignaling,
  } = useWebRTC(selectedReq?.id ?? null, handleIncomingCall)

  // Track the cleanup function for signaling subscription
  const unsubscribeSignalingRef = useRef(null)

  // ── Load requests & realtime subscription ─────────────────────────────────
  useEffect(() => {
    loadRequests()

    const unsubscribeReq = assistanceRepository.subscribeToRequests(() => {
      loadRequests()
    })

    return () => {
      if (unsubscribeReq) unsubscribeReq()
    }
  }, [])

  const rawVenueName = staffContext?.institutions?.name
  // Filter requests to ONLY assigned chat requests, respecting chatFilter ('unsolved' by default)
  const assignedChatRequests = requests.filter(
    (r) => r.preferred_communication !== 'location' &&
      r.assigned_staff_id === myStaffId &&
      (!rawVenueName || (r.venue_name || '').trim().toLowerCase() === rawVenueName.trim().toLowerCase())
  )

  const unsolvedCount = assignedChatRequests.filter(
    (r) => r.status !== 'resolved' && r.status !== 'closed'
  ).length

  const solvedCount = assignedChatRequests.filter(
    (r) => r.status === 'resolved' || r.status === 'closed'
  ).length

  const filteredChatRequests = assignedChatRequests
    .filter((req) => {
      const isSolved = req.status === 'resolved' || req.status === 'closed'
      if (chatFilter === 'unsolved' && isSolved) return false
      if (chatFilter === 'solved' && !isSolved) return false

      if (!searchQuery.trim()) return true
      const q = searchQuery.toLowerCase()
      return (
        (req.traveler_name && req.traveler_name.toLowerCase().includes(q)) ||
        (req.request_code && req.request_code.toLowerCase().includes(q)) ||
        (req.location_zone && req.location_zone.toLowerCase().includes(q)) ||
        (req.description && req.description.toLowerCase().includes(q)) ||
        (req.assigned_staff_name && req.assigned_staff_name.toLowerCase().includes(q))
      )
    })
    .sort((a, b) => {
      const aResolved = a.status === 'resolved' || a.status === 'closed' ? 1 : 0
      const bResolved = b.status === 'resolved' || b.status === 'closed' ? 1 : 0
      if (aResolved !== bResolved) {
        return aResolved - bResolved // Unresolved (0) before Resolved (1)
      }
      return new Date(b.created_at || 0) - new Date(a.created_at || 0)
    })

  // Keep selected request in sync with filtered list or route state
  useEffect(() => {
    if (targetRequestId && requests.length > 0) {
      const match = requests.find((r) => r.id === targetRequestId)
      if (match) {
        const isSolved = match.status === 'resolved' || match.status === 'closed'
        if (isSolved && chatFilter === 'unsolved') setChatFilter('solved')
        if (!isSolved && chatFilter === 'solved') setChatFilter('unsolved')
        setSelectedReq(match)
        return
      }
    }

    if (filteredChatRequests.length > 0) {
      const exists = filteredChatRequests.some((r) => r.id === selectedReq?.id)
      if (!exists) {
        setSelectedReq(filteredChatRequests[0])
      }
    } else {
      setSelectedReq(null)
    }
  }, [filteredChatRequests.length, chatFilter, targetRequestId, requests])

  // ── Subscribe to WebRTC signaling whenever selected request changes ────────
  useEffect(() => {
    // Cleanup previous signaling subscription
    if (unsubscribeSignalingRef.current) {
      unsubscribeSignalingRef.current()
      unsubscribeSignalingRef.current = null
    }

    // Subscribe even with no chat selected: the global channel still needs
    // its call_offer handler so incoming calls from travelers can ring.
    const cleanup = subscribeToSignaling()
    unsubscribeSignalingRef.current = cleanup

    return () => {
      if (cleanup) cleanup()
    }
  }, [selectedReq?.id, subscribeToSignaling])

  // ── Load messages when request changes ────────────────────────────────────
  useEffect(() => {
    if (!selectedReq) return

    loadMessages(selectedReq.id)

    const unsubscribeMsg = assistanceRepository.subscribeToMessages(selectedReq.id, (newMsg) => {
      setMessages((prev) => {
        if (prev.some((m) => m.id === newMsg.id)) return prev
        return [...prev, newMsg]
      })
    })

    return () => {
      if (unsubscribeMsg) unsubscribeMsg()
    }
  }, [selectedReq])

  async function loadRequests() {
    const data = await assistanceRepository.getAssistanceRequests()
    setRequests(data || [])
  }

  async function loadMessages(requestId) {
    setLoadingMsg(true)
    const data = await assistanceRepository.getChatMessages(requestId)
    setMessages(data || [])
    setLoadingMsg(false)
  }

  async function handleSend(e) {
    e.preventDefault()
    if (!inputText.trim() || !selectedReq) return
    if (selectedReq.status === 'resolved' || selectedReq.status === 'closed') return

    const staffDisplayName =
      selectedReq.assigned_staff_name && selectedReq.assigned_staff_name !== 'Unassigned'
        ? `${selectedReq.assigned_staff_name} (Staff)`
        : 'Staff'
    const newMsgPayload = {
      request_id: selectedReq.id,
      sender_type: 'staff',
      sender_name: staffDisplayName,
      content: inputText.trim(),
      message_type: 'text',
      is_read: true,
      created_at: new Date().toISOString()
    }

    setInputText('')
    try {
      const inserted = await assistanceRepository.sendChatMessage(newMsgPayload)
      if (inserted) {
        setMessages((prev) => {
          if (prev.some((m) => m.id === inserted.id)) return prev
          return [...prev, inserted]
        })
      }
    } catch (err) {
      console.error('Failed to send message:', err)
    }
  }

  async function handleMarkResolved() {
    if (!selectedReq) return
    const staffName =
      selectedReq.assigned_staff_name && selectedReq.assigned_staff_name !== 'Unassigned'
        ? selectedReq.assigned_staff_name
        : null
    await assistanceRepository.updateRequestStatus(selectedReq.id, 'resolved', staffName)
    loadRequests()
  }

  function insertTemplate(templateText) {
    setInputText((prev) => (prev ? prev + ' ' + templateText : templateText))
  }

  async function handleMediaSelect(e) {
    const file = e.target.files?.[0]
    if (!file || !selectedReq) return
    if (selectedReq.status === 'resolved' || selectedReq.status === 'closed') return
    // Reset input so same file can be re-selected
    e.target.value = ''

    const isImage = file.type.startsWith('image/')
    const isVideo = file.type.startsWith('video/')
    if (!isImage && !isVideo) return

    setIsUploading(true)
    try {
      const url = await assistanceRepository.uploadChatMedia(file, selectedReq.id)
      const staffDisplayName =
        selectedReq.assigned_staff_name && selectedReq.assigned_staff_name !== 'Unassigned'
          ? `${selectedReq.assigned_staff_name} (Staff)`
          : 'Staff'
      const payload = {
        request_id: selectedReq.id,
        sender_type: 'staff',
        sender_name: staffDisplayName,
        content: url,
        message_type: isImage ? 'image' : 'video',
        is_read: true,
        created_at: new Date().toISOString()
      }
      const inserted = await assistanceRepository.sendChatMessage(payload)
      if (inserted) {
        setMessages((prev) => {
          if (prev.some((m) => m.id === inserted.id)) return prev
          return [...prev, inserted]
        })
      }
    } catch (err) {
      console.error('Failed to upload media:', err)
    } finally {
      setIsUploading(false)
    }
  }

  const isInCall = callState === 'connected' || callState === 'calling'

  // Once the request is resolved (or closed), the conversation becomes read-only
  const isChatLocked =
    !!selectedReq && (selectedReq.status === 'resolved' || selectedReq.status === 'closed')

  // Keep the open conversation's row fresh as realtime status updates arrive,
  // even when it drops out of the current sidebar filter
  useEffect(() => {
    if (!selectedReq?.id) return
    const fresh = requests.find((r) => r.id === selectedReq.id)
    if (fresh && fresh !== selectedReq) setSelectedReq(fresh)
  }, [requests, selectedReq])

  // ── Call summary log ("Video call · 1:23") ─────────────────────────────────
  // Only the side that DIALED writes the summary row, so each call is logged
  // exactly once (the other side receives it via the realtime message feed).
  const prevCallStateRef = useRef('idle')
  const initiatedCallRef = useRef(false)
  const connectedAtRef = useRef(null)

  function handleStartCall(type) {
    initiatedCallRef.current = true
    startCall(type)
  }

  useEffect(() => {
    const prev = prevCallStateRef.current
    if (callState === 'connected' && prev !== 'connected') {
      connectedAtRef.current = Date.now()
    }
    if (callState === 'idle' && prev !== 'idle') {
      if (initiatedCallRef.current && connectedAtRef.current && selectedReq?.id) {
        const seconds = Math.round((Date.now() - connectedAtRef.current) / 1000)
        if (seconds > 0) {
          assistanceRepository.sendChatMessage({
            request_id: selectedReq.id,
            sender_type: 'staff',
            sender_name: 'Call Log',
            content: `${callType}|${seconds}`,
            message_type: 'call',
            is_read: true,
            created_at: new Date().toISOString(),
          }).catch((err) => console.error('Failed to log call summary:', err))
        }
      }
      initiatedCallRef.current = false
      connectedAtRef.current = null
    }
    prevCallStateRef.current = callState
  }, [callState, callType, selectedReq?.id])

  return (
    <div style={{ padding: '0' }}>

      {/* ── Incoming Call Banner (Mobile → Web) ─────────────────────────────── */}
      {callState === 'incoming' && (
        <div style={{
          position: 'fixed',
          top: 0, left: 0, right: 0, bottom: 0,
          backgroundColor: 'rgba(15, 23, 42, 0.75)',
          backdropFilter: 'blur(6px)',
          zIndex: 9999,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
        }}>
          <div style={{
            background: '#1e293b',
            borderRadius: '24px',
            padding: '40px 48px',
            textAlign: 'center',
            boxShadow: '0 32px 80px rgba(0,0,0,0.5)',
            minWidth: '320px',
          }}>
            {/* Animated avatar ring */}
            <div style={{
              width: '80px', height: '80px',
              borderRadius: '50%',
              background: 'rgba(59,130,246,0.2)',
              border: '2px solid rgba(59,130,246,0.5)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              margin: '0 auto 20px',
              animation: 'pulse 1.5s infinite',
            }}>
              <PhoneIncoming size={36} color="#60a5fa" />
            </div>
            <div style={{ fontSize: '13px', color: '#94a3b8', marginBottom: '6px', textTransform: 'uppercase', letterSpacing: '1px' }}>
              Incoming {callType === 'video' ? 'Video' : 'Voice'} Call
            </div>
            <div style={{ fontSize: '22px', fontWeight: '700', color: '#f1f5f9', marginBottom: '8px' }}>
              {incomingCallerName}
            </div>
            <div style={{ fontSize: '13px', color: '#64748b', marginBottom: '32px' }}>
              {selectedReq?.request_code} · {selectedReq?.location_zone}
            </div>
            <div style={{ display: 'flex', gap: '16px', justifyContent: 'center' }}>
              <button
                onClick={rejectCall}
                style={{
                  width: '56px', height: '56px', borderRadius: '50%',
                  background: '#ef4444', border: 'none', cursor: 'pointer',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  boxShadow: '0 4px 12px rgba(239,68,68,0.4)',
                }}
              >
                <PhoneOff size={22} color="white" />
              </button>
              <button
                onClick={acceptCall}
                style={{
                  width: '56px', height: '56px', borderRadius: '50%',
                  background: '#22c55e', border: 'none', cursor: 'pointer',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  boxShadow: '0 4px 12px rgba(34,197,94,0.4)',
                }}
              >
                {callType === 'video' ? <Video size={22} color="white" /> : <Phone size={22} color="white" />}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* ── Active Call Overlay ──────────────────────────────────────────────── */}
      {isInCall && (
        <div style={{
          position: 'fixed',
          top: 0, left: 0, right: 0, bottom: 0,
          background: '#0f172a',
          zIndex: 9998,
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          justifyContent: 'center',
        }}>
          {/* Remote video (large) */}
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

          {/* Calling state overlay */}
          {callState === 'calling' && (
            <div style={{
              position: 'absolute', inset: 0,
              display: 'flex', flexDirection: 'column',
              alignItems: 'center', justifyContent: 'center',
              color: 'white',
            }}>
              <PhoneCall size={60} color="#60a5fa" style={{ marginBottom: '16px' }} />
              <div style={{ fontSize: '20px', fontWeight: '600', marginBottom: '8px' }}>
                Calling {selectedReq?.traveler_name}...
              </div>
              <div style={{ color: '#94a3b8', fontSize: '14px' }}>Waiting for traveler to accept</div>
            </div>
          )}

          {/* Local video PIP */}
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
                zIndex: 1,
              }}
            />
          )}

          {/* Call controls bar */}
          <div style={{
            position: 'absolute',
            bottom: '32px',
            display: 'flex',
            gap: '16px',
            alignItems: 'center',
            background: 'rgba(255,255,255,0.1)',
            backdropFilter: 'blur(12px)',
            borderRadius: '50px',
            padding: '12px 24px',
          }}>
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

            <button
              onClick={() => hangup()}
              style={{
                width: '56px', height: '56px', borderRadius: '50%',
                background: '#ef4444', border: 'none', cursor: 'pointer',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                boxShadow: '0 4px 16px rgba(239,68,68,0.5)',
              }}
              title="End Call"
            >
              <PhoneOff size={24} color="white" />
            </button>
          </div>
        </div>
      )}

      {/* ── Page Header ──────────────────────────────────────────────────────── */}
      <div className="page-header" style={{ padding: '16px 32px' }}>
        <div>
          <h2>Staff Chat</h2>
          <div className="header-subtitle">Chat with your assigned travelers.</div>
        </div>
        <div style={{ display: 'flex', gap: '8px' }}>
          <span className="badge success" style={{ padding: '6px 12px', fontSize: '12px', display: 'flex', alignItems: 'center', gap: '6px' }}>
            <span style={{ width: '8px', height: '8px', borderRadius: '50%', background: 'var(--success)' }}></span> Online
          </span>
        </div>
      </div>

      <div style={{ display: 'flex', height: 'calc(100vh - 85px)' }}>
        {/* ── Chat Sidebar ───────────────────────────────────────────────────── */}
        <div style={{ width: '330px', borderRight: '1px solid var(--divider)', background: 'var(--surface)', display: 'flex', flexDirection: 'column' }}>
          <div style={{ padding: '14px 16px', borderBottom: '1px solid var(--divider)', display: 'flex', flexDirection: 'column', gap: '10px' }}>
            <input
              type="text"
              className="input"
              placeholder="Search assigned chats..."
              value={searchQuery}
              onChange={(e) => setSearchQuery(e.target.value)}
            />
            {/* Filter Tabs */}
            <div style={{ display: 'flex', background: 'var(--surface-variant, #f1f5f9)', borderRadius: '8px', padding: '3px', gap: '2px' }}>
              <button
                type="button"
                style={{
                  flex: 1,
                  border: 'none',
                  padding: '6px 0',
                  fontSize: '12px',
                  fontWeight: chatFilter === 'unsolved' ? 600 : 500,
                  borderRadius: '6px',
                  background: chatFilter === 'unsolved' ? '#ffffff' : 'transparent',
                  color: chatFilter === 'unsolved' ? 'var(--primary)' : 'var(--text-secondary)',
                  boxShadow: chatFilter === 'unsolved' ? '0 1px 3px rgba(0,0,0,0.1)' : 'none',
                  cursor: 'pointer',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  gap: '4px',
                  transition: 'all 0.15s ease'
                }}
                onClick={() => setChatFilter('unsolved')}
              >
                <span>Active</span>
                <span style={{
                  fontSize: '10px',
                  background: chatFilter === 'unsolved' ? 'var(--primary-alpha)' : '#e2e8f0',
                  color: chatFilter === 'unsolved' ? 'var(--primary)' : '#64748b',
                  borderRadius: '10px',
                  padding: '1px 5px',
                  fontWeight: 700
                }}>
                  {unsolvedCount}
                </span>
              </button>
              <button
                type="button"
                style={{
                  flex: 1,
                  border: 'none',
                  padding: '6px 0',
                  fontSize: '12px',
                  fontWeight: chatFilter === 'solved' ? 600 : 500,
                  borderRadius: '6px',
                  background: chatFilter === 'solved' ? '#ffffff' : 'transparent',
                  color: chatFilter === 'solved' ? 'var(--primary)' : 'var(--text-secondary)',
                  boxShadow: chatFilter === 'solved' ? '0 1px 3px rgba(0,0,0,0.1)' : 'none',
                  cursor: 'pointer',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  gap: '4px',
                  transition: 'all 0.15s ease'
                }}
                onClick={() => setChatFilter('solved')}
              >
                <span>Solved</span>
                <span style={{
                  fontSize: '10px',
                  background: chatFilter === 'solved' ? 'var(--primary-alpha)' : '#e2e8f0',
                  color: chatFilter === 'solved' ? 'var(--primary)' : '#64748b',
                  borderRadius: '10px',
                  padding: '1px 5px',
                  fontWeight: 700
                }}>
                  {solvedCount}
                </span>
              </button>
              <button
                type="button"
                style={{
                  flex: 1,
                  border: 'none',
                  padding: '6px 0',
                  fontSize: '12px',
                  fontWeight: chatFilter === 'all' ? 600 : 500,
                  borderRadius: '6px',
                  background: chatFilter === 'all' ? '#ffffff' : 'transparent',
                  color: chatFilter === 'all' ? 'var(--primary)' : 'var(--text-secondary)',
                  boxShadow: chatFilter === 'all' ? '0 1px 3px rgba(0,0,0,0.1)' : 'none',
                  cursor: 'pointer',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center',
                  gap: '4px',
                  transition: 'all 0.15s ease'
                }}
                onClick={() => setChatFilter('all')}
              >
                <span>All</span>
                <span style={{
                  fontSize: '10px',
                  background: chatFilter === 'all' ? 'var(--primary-alpha)' : '#e2e8f0',
                  color: chatFilter === 'all' ? 'var(--primary)' : '#64748b',
                  borderRadius: '10px',
                  padding: '1px 5px',
                  fontWeight: 700
                }}>
                  {assignedChatRequests.length}
                </span>
              </button>
            </div>
          </div>
          <div style={{ flex: 1, overflowY: 'auto' }}>
            {filteredChatRequests.length === 0 ? (
              <div style={{ textAlign: 'center', padding: '32px 16px', color: 'var(--text-muted)', fontSize: '13px' }}>
                {chatFilter === 'unsolved'
                  ? 'No active assigned chats.'
                  : chatFilter === 'solved'
                  ? 'No resolved chats found.'
                  : 'No assigned chat requests.'}
              </div>
            ) : (
              filteredChatRequests.map((req) => {
                const isSelected = selectedReq && selectedReq.id === req.id
                const isEscalated = req.is_escalated === true
                const minutesWaiting = req.created_at
                  ? Math.floor((Date.now() - new Date(req.created_at).getTime()) / 60000)
                  : 0
                // Auto-escalate client-side if pending > 10 min
                const shouldEscalate = !isEscalated && req.status === 'pending' && minutesWaiting >= 10
                return (
                  <div
                    key={req.id}
                    style={{
                      padding: '16px',
                      borderBottom: '1px solid var(--divider)',
                      background: isSelected
                        ? 'var(--primary-alpha)'
                        : (isEscalated || shouldEscalate) ? 'rgba(239,68,68,0.04)' : 'transparent',
                      cursor: 'pointer',
                      borderLeft: (isEscalated || shouldEscalate) ? '3px solid #ef4444' : undefined,
                    }}
                    onClick={() => setSelectedReq(req)}
                  >
                    <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '4px', alignItems: 'center' }}>
                      <strong style={{ fontSize: '14px' }}>{req.traveler_name}</strong>
                      <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                        {new Date(req.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                      </span>
                    </div>
                    {(isEscalated || shouldEscalate) && (
                      <div style={{
                        display: 'flex', alignItems: 'center', gap: '5px',
                        background: 'rgba(239,68,68,0.1)', borderRadius: '6px',
                        padding: '4px 8px', marginBottom: '6px', width: 'fit-content',
                      }}>
                        <AlertTriangle size={13} color="#ef4444" />
                        <span style={{ fontSize: '11px', fontWeight: '700', color: '#ef4444' }}>
                          ESCALATED — {minutesWaiting} min
                        </span>
                      </div>
                    )}
                    <div style={{ fontSize: '12px', color: 'var(--text-secondary)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                      {req.description}
                    </div>
                    <div style={{ display: 'flex', gap: '6px', marginTop: '8px', alignItems: 'center' }}>
                      <span className="badge primary">{req.location_zone}</span>
                      <span
                        className={`badge ${
                          req.status === 'pending' ? 'emergency' : req.status === 'in_progress' ? 'secondary' : 'success'
                        }`}
                      >
                        {req.status}
                      </span>
                      {req.urgency === 'high' && (
                        <AlertCircle size={14} color="#ef4444" style={{ flexShrink: 0 }} />
                      )}
                    </div>
                  </div>
                )
              })
            )}
          </div>
        </div>

        {/* ── Chat Main Area ─────────────────────────────────────────────────── */}
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: 'var(--bg)' }}>
          {selectedReq ? (
            <>
              {/* Top chat info bar */}
              <div style={{ padding: '16px 24px', background: 'var(--surface)', borderBottom: '1px solid var(--divider)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <div>
                  <h3 style={{ fontSize: '16px', fontWeight: '700' }}>{selectedReq.traveler_name}</h3>
                  <div style={{ fontSize: '12px', color: 'var(--text-secondary)', display: 'flex', alignItems: 'center', gap: '8px', marginTop: '3px' }}>
                    <span style={{ textTransform: 'capitalize' }}>{selectedReq.category} · {selectedReq.location_zone}</span>
                    {selectedReq.share_location && (
                      <span style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', color: '#16a34a', fontWeight: 600 }}>
                        <Radio size={13} color="#16a34a" /> Live
                      </span>
                    )}
                  </div>
                </div>
                <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                  {/* Voice call button */}
                  <button
                    className="btn btn-secondary btn-sm"
                    style={{
                      display: 'flex', alignItems: 'center', gap: '6px',
                      opacity: isChatLocked ? 0.45 : 1,
                    }}
                    onClick={() => handleStartCall('voice')}
                    disabled={isChatLocked}
                    title={isChatLocked ? 'Calls unavailable — request resolved' : 'Start Voice Call'}
                  >
                    <Phone size={14} /> Voice
                  </button>
                  {/* Video call button */}
                  <button
                    className="btn btn-secondary btn-sm"
                    style={{
                      display: 'flex', alignItems: 'center', gap: '6px',
                      opacity: isChatLocked ? 0.45 : 1,
                    }}
                    onClick={() => handleStartCall('video')}
                    disabled={isChatLocked}
                    title={isChatLocked ? 'Calls unavailable — request resolved' : 'Start Video Call'}
                  >
                    <Video size={14} /> Video
                  </button>
                  <button
                    className="btn btn-outline btn-sm"
                    style={{ display: 'flex', alignItems: 'center', gap: '4px' }}
                    onClick={() => setShowMapModal(true)}
                    title={selectedReq.share_location ? 'Live Map' : 'View Location'}
                  >
                    <MapPin size={14} />
                  </button>
                  {!isChatLocked && (
                    <button
                      className="btn btn-primary btn-sm"
                      style={{ background: 'var(--success)', display: 'flex', alignItems: 'center', gap: '4px' }}
                      onClick={handleMarkResolved}
                    >
                      <CheckCircle2 size={14} /> Resolve
                    </button>
                  )}
                </div>
              </div>

              {/* ── Traveler Resolution Feedback Banner ── */}
              {(selectedReq.resolution_outcome || selectedReq.user_rating) && (
                <div style={{
                  margin: '12px 24px 0',
                  padding: '10px 16px',
                  borderRadius: '12px',
                  background: selectedReq.resolution_outcome === 'fully_resolved'
                    ? 'rgba(34, 197, 94, 0.1)'
                    : 'rgba(245, 158, 11, 0.1)',
                  border: `1px solid ${selectedReq.resolution_outcome === 'fully_resolved' ? 'rgba(34, 197, 94, 0.3)' : 'rgba(245, 158, 11, 0.3)'}`,
                  display: 'flex',
                  alignItems: 'center',
                  gap: '10px',
                  flexWrap: 'wrap',
                  fontSize: '13px',
                }}>
                  <span style={{ fontWeight: '700', display: 'flex', alignItems: 'center', gap: '5px', color: selectedReq.resolution_outcome === 'fully_resolved' ? '#22c55e' : '#f59e0b' }}>
                    {selectedReq.resolution_outcome === 'fully_resolved' ? (
                      <><CheckCircle2 size={15} color="#22c55e" /> Resolved</>
                    ) : selectedReq.resolution_outcome === 'partially_resolved' ? (
                      <><AlertTriangle size={15} color="#f59e0b" /> Partially resolved</>
                    ) : (
                      <><AlertCircle size={15} color="#ef4444" /> Unresolved</>
                    )}
                  </span>
                  {selectedReq.user_rating && (
                    <span style={{ fontWeight: '700', color: '#f59e0b', display: 'flex', alignItems: 'center', gap: '4px' }}>
                      <Star size={13} fill="#f59e0b" /> {selectedReq.user_rating}/5
                    </span>
                  )}
                  {selectedReq.user_feedback_comment && (
                    <span style={{ color: 'var(--text-secondary)', fontStyle: 'italic' }}>
                      "{selectedReq.user_feedback_comment}"
                    </span>
                  )}
                </div>
              )}

              {/* Messages list */}
              <div style={{ flex: 1, padding: '24px', overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: '16px' }}>
                <div style={{ alignSelf: 'center', background: 'var(--surface-variant)', padding: '4px 12px', borderRadius: '12px', fontSize: '12px', color: 'var(--text-muted)' }}>
                  Conversation started
                </div>

                {loadingMsg ? (
                  <div style={{ textAlign: 'center', color: 'var(--text-muted)' }}>Loading chat history...</div>
                ) : messages.length === 0 ? (
                  <div style={{ textAlign: 'center', color: 'var(--text-muted)' }}>No messages yet.</div>
                ) : (
                  messages.map((msg) => {
                    const isStaff = msg.sender_type === 'staff'
                    const msgType = msg.message_type || 'text'
                    
                    // Robust timestamp parsing supporting Postgres and ISO formats with fallback
                    let timeStr = ''
                    if (msg.created_at) {
                      try {
                        let d = new Date(msg.created_at)
                        if (isNaN(d.getTime()) && typeof msg.created_at === 'string') {
                          const normalized = msg.created_at.replace(' ', 'T').replace(/([+-]\d{2})$/, '$1:00')
                          d = new Date(normalized)
                        }
                        if (!isNaN(d.getTime())) {
                          timeStr = d.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
                        }
                      } catch {
                        // ignore and use fallback
                      }
                    }
                    if (!timeStr) {
                      timeStr = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
                    }

                    // Call summary row: content is '<video|voice>|<seconds>'
                    if (msgType === 'call') {
                      const [rawType, rawSeconds] = String(msg.content || '').split('|')
                      const isVideoCall = rawType === 'video'
                      const secs = parseInt(rawSeconds || '0', 10) || 0
                      const dur = `${Math.floor(secs / 60)}:${String(secs % 60).padStart(2, '0')}`
                      return (
                        <div
                          key={msg.id}
                          style={{
                            alignSelf: 'center',
                            display: 'flex',
                            alignItems: 'center',
                            gap: '6px',
                            background: 'var(--surface-variant, #f1f5f9)',
                            padding: '4px 12px',
                            borderRadius: '12px',
                            fontSize: '12px',
                            color: 'var(--text-muted)',
                          }}
                        >
                          {isVideoCall ? <Video size={13} /> : <Phone size={13} />}
                          {isVideoCall ? 'Video call' : 'Voice call'} · {dur} · {timeStr}
                        </div>
                      )
                    }

                    return (
                      <div
                        key={msg.id}
                        style={{
                          alignSelf: isStaff ? 'flex-end' : 'flex-start',
                          maxWidth: '85%',
                          minWidth: '72px',
                          background: isStaff ? 'var(--success)' : 'var(--surface)',
                          color: isStaff ? '#fff' : 'var(--text)',
                          padding: msgType === 'text' ? '10px 14px 12px 14px' : '8px',
                          borderRadius: '16px',
                          border: isStaff ? 'none' : '1px solid var(--card-border)',
                          boxShadow: '0 1px 2px rgba(0, 0, 0, 0.05)',
                        }}
                      >
                        {msgType === 'image' ? (
                          <div>
                            <img
                              src={msg.content}
                              alt="Shared image"
                              onClick={() => setLightboxUrl(msg.content)}
                              style={{
                                maxWidth: '260px',
                                maxHeight: '200px',
                                width: '100%',
                                borderRadius: '10px',
                                display: 'block',
                                cursor: 'zoom-in',
                                objectFit: 'cover',
                              }}
                            />
                            <div style={{ fontSize: '10px', color: isStaff ? 'rgba(255,255,255,0.8)' : 'var(--text-muted)', textAlign: 'right', marginTop: '6px', padding: '0 4px 2px' }}>
                              {timeStr}
                            </div>
                          </div>
                        ) : msgType === 'video' ? (
                          <div>
                            <video
                              controls
                              src={msg.content}
                              style={{
                                maxWidth: '300px',
                                maxHeight: '220px',
                                width: '100%',
                                borderRadius: '10px',
                                display: 'block',
                                background: '#000',
                              }}
                            />
                            <div style={{ fontSize: '10px', color: isStaff ? 'rgba(255,255,255,0.8)' : 'var(--text-muted)', textAlign: 'right', marginTop: '6px', padding: '0 4px 2px' }}>
                              {timeStr}
                            </div>
                          </div>
                        ) : (
                          <div style={{ display: 'flex', flexDirection: 'column' }}>
                            <div
                              style={{
                                fontSize: '14px',
                                lineHeight: '1.5',
                                wordBreak: 'break-word',
                                paddingBottom: '6px', // Extra bottom padding to avoid overlapping the line/timing
                              }}
                            >
                              {msg.content}
                            </div>
                            <div
                              style={{
                                fontSize: '10px',
                                color: isStaff ? 'rgba(255,255,255,0.8)' : 'var(--text-muted)',
                                textAlign: 'right',
                                lineHeight: '1.2',
                                alignSelf: 'flex-end',
                                userSelect: 'none',
                              }}
                            >
                              {timeStr}
                            </div>
                          </div>
                        )}
                      </div>
                    )
                  })
                )}
                <div ref={messagesEndRef} />
              </div>

              {isChatLocked ? (
                /* ── Read-only notice once the request is resolved/closed ── */
                <div style={{
                  padding: '16px 24px',
                  background: 'var(--surface)',
                  borderTop: '1px solid var(--divider)',
                  display: 'flex',
                  alignItems: 'center',
                  gap: '8px',
                  color: 'var(--text-muted)',
                  fontSize: '13px',
                }}>
                  <CheckCircle2 size={16} color="var(--success)" />
                  {selectedReq.status === 'closed'
                    ? 'This request is closed. The conversation is view-only.'
                    : 'Marked as resolved — waiting for the traveler to confirm. Chat is now view-only.'}
                </div>
              ) : (
                <>
              {/* Quick response templates */}
              <div style={{ padding: '8px 24px', background: 'var(--surface)', borderTop: '1px solid var(--divider)', display: 'flex', gap: '8px', overflowX: 'auto' }}>
                <button
                  className="btn btn-outline btn-sm"
                  style={{ whiteSpace: 'nowrap' }}
                  onClick={() => insertTemplate('Please proceed to Gate B12. Staff are waiting for you there.')}
                >
                  <Zap size={14} /> Gate
                </button>
                <button
                  className="btn btn-outline btn-sm"
                  style={{ whiteSpace: 'nowrap' }}
                  onClick={() => insertTemplate('Sorry for the delay — your flight is delayed by 25 minutes.')}
                >
                  <Zap size={14} /> Delay
                </button>
                <button
                  className="btn btn-outline btn-sm"
                  style={{ whiteSpace: 'nowrap' }}
                  onClick={() => insertTemplate('An accessibility team member is on the way to you.')}
                >
                  <Zap size={14} /> Dispatch
                </button>
              </div>

              {/* Input box */}
              <form
                onSubmit={handleSend}
                style={{ padding: '16px 24px', background: 'var(--surface)', borderTop: '1px solid var(--divider)', display: 'flex', gap: '12px', alignItems: 'center' }}
              >
                {/* Hidden file input for media */}
                <input
                  ref={fileInputRef}
                  type="file"
                  accept="image/*,video/*"
                  style={{ display: 'none' }}
                  onChange={handleMediaSelect}
                />
                <button
                  type="button"
                  className="btn btn-outline"
                  style={{ padding: '10px' }}
                  title="Attach Image or Video"
                  onClick={() => fileInputRef.current?.click()}
                  disabled={isUploading}
                >
                  {isUploading
                    ? <Loader2 size={18} style={{ animation: 'spin 1s linear infinite' }} />
                    : <Paperclip size={18} />}
                </button>
                <input
                  type="text"
                  className="input"
                  placeholder="Type a message..."
                  style={{ flex: 1 }}
                  value={inputText}
                  onChange={(e) => setInputText(e.target.value)}
                  disabled={isUploading}
                />
                <button type="submit" className="btn btn-primary" disabled={isUploading}>
                  <Send size={16} /> Send
                </button>
              </form>
                </>
              )}
            </>
          ) : (
            <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--text-muted)' }}>
              Select a conversation to begin.
            </div>
          )}
        </div>
      </div>
      {/* ── Image Lightbox Modal ──────────────────────────────────────────────── */}
      {lightboxUrl && (
        <div
          onClick={() => setLightboxUrl(null)}
          style={{
            position: 'fixed',
            top: 0, left: 0, right: 0, bottom: 0,
            backgroundColor: 'rgba(0,0,0,0.9)',
            zIndex: 10000,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            cursor: 'zoom-out',
            padding: '24px',
          }}
        >
          <button
            onClick={() => setLightboxUrl(null)}
            style={{
              position: 'absolute', top: '20px', right: '20px',
              background: 'rgba(255,255,255,0.1)', border: 'none',
              borderRadius: '50%', width: '40px', height: '40px',
              cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}
          >
            <X size={20} color="white" />
          </button>
          <img
            src={lightboxUrl}
            alt="Full size"
            onClick={(e) => e.stopPropagation()}
            style={{ maxWidth: '90vw', maxHeight: '90vh', borderRadius: '12px', objectFit: 'contain' }}
          />
        </div>
      )}

      {/* ── View on Map Modal ────────────────────────────────────────────────── */}
      {showMapModal && selectedReq && (
        <div style={{
          position: 'fixed',
          top: 0, left: 0, right: 0, bottom: 0,
          backgroundColor: 'rgba(15, 23, 42, 0.75)',
          backdropFilter: 'blur(6px)',
          zIndex: 9999,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          padding: '24px',
        }}>
          <div style={{
            background: 'var(--surface)',
            borderRadius: '20px',
            border: '1px solid var(--card-border)',
            width: '100%',
            maxWidth: '720px',
            boxShadow: '0 25px 50px -12px rgba(0, 0, 0, 0.5)',
            overflow: 'hidden',
            display: 'flex',
            flexDirection: 'column',
          }}>
            {/* Header */}
            <div style={{
              padding: '20px 24px',
              borderBottom: '1px solid var(--divider)',
              display: 'flex',
              justify: 'space-between',
              alignItems: 'center',
              background: 'var(--surface-variant)'
            }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: '10px' }}>
                <div style={{
                  width: '36px', height: '36px', borderRadius: '10px',
                  background: 'rgba(59, 130, 246, 0.15)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center'
                }}>
                  <MapPin size={20} color="var(--primary)" />
                </div>
                <div>
                  <h3 style={{ fontSize: '16px', fontWeight: '700', margin: 0 }}>
                    Traveler Location — {selectedReq.traveler_name}
                  </h3>
                  <span style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
                    Request #{selectedReq.request_code} · {selectedReq.location_zone}
                  </span>
                </div>
              </div>
              <button
                onClick={() => setShowMapModal(false)}
                style={{
                  background: 'transparent', border: 'none', cursor: 'pointer',
                  padding: '8px', borderRadius: '50%', color: 'var(--text-muted)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center'
                }}
              >
                <X size={20} />
              </button>
            </div>

            {/* Map Content */}
            <div style={{ position: 'relative', height: '420px', width: '100%' }}>
              <LiveLocationMap
                sessionId={selectedReq.id}
                sessionType="assistance"
                initialLat={selectedReq.latitude}
                initialLng={selectedReq.longitude}
                travelerName={selectedReq.traveler_name}
                locationZone={selectedReq.location_zone}
                height="420px"
              />
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
