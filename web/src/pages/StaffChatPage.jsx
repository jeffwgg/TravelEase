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
  ExternalLink, 
  Navigation,
  AlertTriangle,
  Star,
  AlertCircle,
  MessageSquare,
  ShieldCheck
} from 'lucide-react'
import { assistanceRepository } from '../repositories/assistanceRepository'
import { useWebRTC } from '../hooks/useWebRTC'
import { useNotifications } from '../context/NotificationContext'

export default function StaffChatPage() {
  const location = useLocation()
  const targetRequestId = location.state?.requestId
  const { setActiveChatId } = useNotifications()

  const [requests, setRequests] = useState([])
  const [selectedReq, setSelectedReq] = useState(null)
  const [messages, setMessages] = useState([])
  const [inputText, setInputText] = useState('')
  const [loadingMsg, setLoadingMsg] = useState(false)
  const [showMapModal, setShowMapModal] = useState(false)
  const [searchQuery, setSearchQuery] = useState('')

  const [chatFilter, setChatFilter] = useState('unsolved') // 'unsolved' | 'solved' | 'all'

  const messagesEndRef = useRef(null)

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

  // Filter requests to ONLY assigned chat requests, respecting chatFilter ('unsolved' by default)
  const assignedChatRequests = requests.filter(
    (r) => r.preferred_communication !== 'location' && r.assigned_staff_name && r.assigned_staff_name !== 'Unassigned'
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

    if (!selectedReq?.id) return

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

  const isInCall = callState === 'connected' || callState === 'calling'

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
                <Phone size={22} color="white" />
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
          <h2>Staff Communication Console</h2>
          <div className="header-subtitle">Real-time two-way dialogue console with automatic speech-to-text and sign translation support.</div>
        </div>
        <div style={{ display: 'flex', gap: '8px' }}>
          <span className="badge success" style={{ padding: '6px 12px', fontSize: '12px', display: 'flex', alignItems: 'center', gap: '6px' }}>
            <span style={{ width: '8px', height: '8px', borderRadius: '50%', background: 'var(--success)' }}></span> Online &amp; Accepting Chats
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
                      <strong style={{ fontSize: '14px' }}>{req.traveler_name} ({req.request_code})</strong>
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
                          ESCALATED — Waiting {minutesWaiting} min
                        </span>
                      </div>
                    )}
                    <div style={{ fontSize: '12px', color: 'var(--text-secondary)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                      {req.description}
                    </div>
                    <div style={{ display: 'flex', gap: '6px', marginTop: '8px', flexWrap: 'wrap' }}>
                      <span className="badge primary">{req.location_zone}</span>
                      <span
                        className={`badge ${
                          req.status === 'pending' ? 'emergency' : req.status === 'in_progress' ? 'secondary' : 'success'
                        }`}
                      >
                        {req.status}
                      </span>
                      {req.urgency === 'high' && (
                        <span className="badge emergency" style={{ display: 'inline-flex', alignItems: 'center', gap: '3px' }}>
                          <AlertCircle size={11} /> High
                        </span>
                      )}
                      {req.assigned_staff_name && (
                        <span className="badge secondary" style={{ display: 'inline-flex', alignItems: 'center', gap: '3px', fontSize: '10px' }}>
                          <ShieldCheck size={10} color="var(--primary)" /> {req.assigned_staff_name}
                        </span>
                      )}
                      {req.user_rating && (
                        <span className="badge secondary" style={{ display: 'inline-flex', alignItems: 'center', gap: '3px', background: 'rgba(245, 158, 11, 0.15)', color: '#f59e0b', fontWeight: '700' }}>
                          <Star size={11} fill="#f59e0b" /> {req.user_rating}/5
                        </span>
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
                  <h3 style={{ fontSize: '16px', fontWeight: '700' }}>{selectedReq.traveler_name} (Deaf Traveler)</h3>
                  <div style={{ fontSize: '12px', color: 'var(--text-secondary)', display: 'flex', alignItems: 'center', gap: '8px', marginTop: '3px' }}>
                    <span>Location: <strong>{selectedReq.location_zone}</strong></span>
                    <span>•</span>
                    <span>Reach: <strong>{selectedReq.preferred_communication === 'location' ? 'In-Person (Come to Location)' : 'In-App Chat'}</strong></span>
                    <span>•</span>
                    <span style={{ textTransform: 'capitalize' }}>Request: <strong>{selectedReq.category}</strong></span>
                  </div>
                </div>
                <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                  {/* Voice call button */}
                  <button
                    className="btn btn-secondary btn-sm"
                    style={{ display: 'flex', alignItems: 'center', gap: '6px' }}
                    onClick={() => startCall('voice')}
                    title="Start Voice Call"
                  >
                    <Phone size={14} /> Voice
                  </button>
                  {/* Video call button */}
                  <button
                    className="btn btn-primary btn-sm"
                    style={{ display: 'flex', alignItems: 'center', gap: '6px' }}
                    onClick={() => startCall('video')}
                    title="Start Video Call"
                  >
                    <Video size={14} /> Video Call
                  </button>
                  <button
                    className="btn btn-outline btn-sm"
                    style={{ display: 'flex', alignItems: 'center', gap: '4px' }}
                    onClick={() => setShowMapModal(true)}
                  >
                    <MapPin size={14} /> View on Map
                  </button>
                  <button
                    className="btn btn-primary btn-sm"
                    style={{ background: 'var(--success)', display: 'flex', alignItems: 'center', gap: '4px' }}
                    onClick={handleMarkResolved}
                  >
                    <CheckCircle2 size={14} /> Mark Resolved
                  </button>
                </div>
              </div>

              {/* ── Traveler Resolution Feedback Banner ── */}
              {(selectedReq.resolution_outcome || selectedReq.user_rating) && (
                <div style={{
                  margin: '16px 24px 0',
                  padding: '14px 20px',
                  borderRadius: '14px',
                  background: selectedReq.resolution_outcome === 'fully_resolved'
                    ? 'rgba(34, 197, 94, 0.1)'
                    : 'rgba(245, 158, 11, 0.1)',
                  border: `1px solid ${selectedReq.resolution_outcome === 'fully_resolved' ? 'rgba(34, 197, 94, 0.3)' : 'rgba(245, 158, 11, 0.3)'}`,
                  display: 'flex',
                  justifyContent: 'space-between',
                  alignItems: 'center'
                }}>
                  <div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '10px', marginBottom: '4px' }}>
                      <span style={{ fontSize: '13px', fontWeight: '700', color: selectedReq.resolution_outcome === 'fully_resolved' ? '#22c55e' : '#f59e0b', display: 'flex', alignItems: 'center', gap: '5px' }}>
                        {selectedReq.resolution_outcome === 'fully_resolved' ? (
                          <><CheckCircle2 size={15} color="#22c55e" /> Traveler Outcome: Fully Resolved</>
                        ) : selectedReq.resolution_outcome === 'partially_resolved' ? (
                          <><AlertTriangle size={15} color="#f59e0b" /> Traveler Outcome: Partially Resolved</>
                        ) : (
                          <><AlertCircle size={15} color="#ef4444" /> Traveler Outcome: Unresolved</>
                        )}
                      </span>
                      {selectedReq.user_rating && (
                        <span style={{ fontSize: '13px', fontWeight: '700', color: '#f59e0b', display: 'flex', alignItems: 'center', gap: '4px' }}>
                          <Star size={13} fill="#f59e0b" /> {selectedReq.user_rating} / 5
                        </span>
                      )}
                    </div>
                    {selectedReq.user_feedback_comment && (
                      <div style={{ fontSize: '12px', color: 'var(--text-secondary)', fontStyle: 'italic' }}>
                        "{selectedReq.user_feedback_comment}"
                      </div>
                    )}
                  </div>
                  <span className="badge" style={{
                    background: selectedReq.status === 'closed' ? 'var(--success)' : 'var(--secondary)',
                    color: '#fff',
                    padding: '6px 12px',
                    fontSize: '11px',
                    fontWeight: '700'
                  }}>
                    Ticket: {selectedReq.status.toUpperCase()}
                  </span>
                </div>
              )}

              {/* Messages list */}
              <div style={{ flex: 1, padding: '24px', overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: '16px' }}>
                <div style={{ alignSelf: 'center', background: 'var(--surface-variant)', padding: '4px 12px', borderRadius: '12px', fontSize: '12px', color: 'var(--text-muted)' }}>
                  Assistance session initiated for {selectedReq.request_code}
                </div>

                {loadingMsg ? (
                  <div style={{ textAlign: 'center', color: 'var(--text-muted)' }}>Loading chat history...</div>
                ) : messages.length === 0 ? (
                  <div style={{ textAlign: 'center', color: 'var(--text-muted)' }}>No messages yet. Send a response to greet the traveler.</div>
                ) : (
                  messages.map((msg) => {
                    const isStaff = msg.sender_type === 'staff'
                    return (
                      <div
                        key={msg.id}
                        style={{
                          alignSelf: isStaff ? 'flex-end' : 'flex-start',
                          maxWidth: '85%',
                          background: isStaff ? 'var(--success)' : 'var(--surface)',
                          color: isStaff ? '#fff' : 'var(--text)',
                          padding: '14px',
                          borderRadius: '16px',
                          border: isStaff ? 'none' : '1px solid var(--card-border)'
                        }}
                      >
                        <div style={{ fontSize: '14px' }}>{msg.content}</div>
                        <div
                          style={{
                            fontSize: '10px',
                            color: isStaff ? 'rgba(255,255,255,0.7)' : 'var(--text-muted)',
                            textAlign: 'right',
                            marginTop: '4px'
                          }}
                        >
                          {new Date(msg.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                        </div>
                      </div>
                    )
                  })
                )}
                <div ref={messagesEndRef} />
              </div>

              {/* Quick response templates */}
              <div style={{ padding: '8px 24px', background: 'var(--surface)', borderTop: '1px solid var(--divider)', display: 'flex', gap: '8px', overflowX: 'auto' }}>
                <button
                  className="btn btn-outline btn-sm"
                  style={{ whiteSpace: 'nowrap', display: 'flex', alignItems: 'center', gap: '4px' }}
                  onClick={() => insertTemplate('Please proceed to Gate B12. Our staff member is waiting for you there.')}
                >
                  <Zap size={14} /> Gate Direction Template
                </button>
                <button
                  className="btn btn-outline btn-sm"
                  style={{ whiteSpace: 'nowrap', display: 'flex', alignItems: 'center', gap: '4px' }}
                  onClick={() => insertTemplate('We apologize for the delay. Your flight is currently delayed by 25 minutes.')}
                >
                  <Zap size={14} /> Delay Explanation
                </button>
                <button
                  className="btn btn-outline btn-sm"
                  style={{ whiteSpace: 'nowrap', display: 'flex', alignItems: 'center', gap: '4px' }}
                  onClick={() => insertTemplate('An accessibility team member has been dispatched to your location.')}
                >
                  <Zap size={14} /> Staff Dispatching Notice
                </button>
              </div>

              {/* Input box */}
              <form
                onSubmit={handleSend}
                style={{ padding: '16px 24px', background: 'var(--surface)', borderTop: '1px solid var(--divider)', display: 'flex', gap: '12px' }}
              >
                <button type="button" className="btn btn-outline" style={{ padding: '10px' }} title="Microphone Speech-to-Text">
                  <Mic size={18} />
                </button>
                <input
                  type="text"
                  className="input"
                  placeholder="Type your response to the traveler..."
                  style={{ flex: 1 }}
                  value={inputText}
                  onChange={(e) => setInputText(e.target.value)}
                />
                <button type="submit" className="btn btn-primary">
                  <Send size={16} /> Send Response
                </button>
              </form>
            </>
          ) : (
            <div style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--text-muted)' }}>
              Select a traveler conversation from the left panel to begin.
            </div>
          )}
        </div>
      </div>
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
            <div style={{ position: 'relative', height: '380px', width: '100%', background: '#1e293b' }}>
              <iframe
                title="Traveler Location Map"
                width="100%"
                height="100%"
                style={{ border: 0 }}
                loading="lazy"
                src={`https://maps.google.com/maps?q=${encodeURIComponent(selectedReq.venue_name || selectedReq.location_zone)}&t=&z=15&ie=UTF8&iwloc=&output=embed`}
              />
            </div>

            {/* Footer / Location details */}
            <div style={{ padding: '20px 24px', display: 'flex', justifyContent: 'space-between', alignItems: 'center', background: 'var(--surface)' }}>
              <div>
                <div style={{ fontSize: '13px', fontWeight: '600', color: 'var(--text-primary)', marginBottom: '2px' }}>
                  {selectedReq.venue_name || selectedReq.location_zone}
                </div>
                <div style={{ fontSize: '12px', color: 'var(--text-muted)' }}>
                  Urgency: <span style={{ textTransform: 'capitalize', fontWeight: '600', color: selectedReq.urgency === 'high' ? 'var(--emergency)' : 'var(--secondary)' }}>{selectedReq.urgency}</span> · Category: {selectedReq.category}
                </div>
              </div>
              <a
                href={`https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(selectedReq.venue_name || selectedReq.location_zone)}`}
                target="_blank"
                rel="noopener noreferrer"
                className="btn btn-primary btn-sm"
                style={{ display: 'flex', alignItems: 'center', gap: '6px', textDecoration: 'none' }}
              >
                <Navigation size={14} /> Open in Google Maps <ExternalLink size={12} />
              </a>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
