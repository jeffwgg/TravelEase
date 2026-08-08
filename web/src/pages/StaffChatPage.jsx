import React, { useState, useEffect, useRef } from 'react'
import { MapPin, Mic, MicOff, Zap, Send, CheckCircle2, Video, VideoOff, PhoneCall, PhoneOff, Phone, PhoneIncoming } from 'lucide-react'
import { assistanceRepository } from '../repositories/assistanceRepository'
import { useWebRTC } from '../hooks/useWebRTC'

export default function StaffChatPage() {
  const [requests, setRequests] = useState([])
  const [selectedReq, setSelectedReq] = useState(null)
  const [messages, setMessages] = useState([])
  const [inputText, setInputText] = useState('')
  const [loadingMsg, setLoadingMsg] = useState(false)

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
  } = useWebRTC(selectedReq?.id ?? null)

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
      setMessages((prev) => [...prev, newMsg])
    })

    return () => {
      if (unsubscribeMsg) unsubscribeMsg()
    }
  }, [selectedReq])

  async function loadRequests() {
    const data = await assistanceRepository.getAssistanceRequests()
    setRequests(data || [])
    if (data && data.length > 0 && !selectedReq) {
      setSelectedReq(data[0])
    }
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

    const newMsgPayload = {
      request_id: selectedReq.id,
      sender_type: 'staff',
      sender_name: 'Ahmad Khan (Staff)',
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
    await assistanceRepository.updateRequestStatus(selectedReq.id, 'resolved', 'Ahmad Khan')
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
          <div className="header-subtitle">Real-time two-way dialogue console with automatic speech-to-text and sign translation support. (Connected to Supabase)</div>
        </div>
        <div style={{ display: 'flex', gap: '8px' }}>
          <span className="badge success" style={{ padding: '6px 12px', fontSize: '12px', display: 'flex', alignItems: 'center', gap: '6px' }}>
            <span style={{ width: '8px', height: '8px', borderRadius: '50%', background: 'var(--success)' }}></span> Online &amp; Accepting Chats
          </span>
        </div>
      </div>

      <div style={{ display: 'flex', height: 'calc(100vh - 85px)' }}>
        {/* ── Chat Sidebar ───────────────────────────────────────────────────── */}
        <div style={{ width: '320px', borderRight: '1px solid var(--divider)', background: 'var(--surface)', display: 'flex', flexDirection: 'column' }}>
          <div style={{ padding: '16px', borderBottom: '1px solid var(--divider)' }}>
            <input type="text" className="input" placeholder="Search conversations..." />
          </div>
          <div style={{ flex: 1, overflowY: 'auto' }}>
            {requests.map((req) => {
              const isSelected = selectedReq && selectedReq.id === req.id
              return (
                <div
                  key={req.id}
                  style={{
                    padding: '16px',
                    borderBottom: '1px solid var(--divider)',
                    background: isSelected ? 'var(--primary-alpha)' : 'transparent',
                    cursor: 'pointer'
                  }}
                  onClick={() => setSelectedReq(req)}
                >
                  <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '4px' }}>
                    <strong style={{ fontSize: '14px' }}>{req.traveler_name} ({req.request_code})</strong>
                    <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                      {new Date(req.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                    </span>
                  </div>
                  <div style={{ fontSize: '12px', color: 'var(--text-secondary)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                    {req.description}
                  </div>
                  <div style={{ display: 'flex', gap: '6px', marginTop: '8px' }}>
                    <span className="badge primary">{req.location_zone}</span>
                    <span
                      className={`badge ${
                        req.status === 'pending' ? 'emergency' : req.status === 'in_progress' ? 'secondary' : 'success'
                      }`}
                    >
                      {req.status}
                    </span>
                  </div>
                </div>
              )
            })}
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
                  <div style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>
                    Location: {selectedReq.location_zone} • Prefers: {selectedReq.preferred_communication} • Request: {selectedReq.category}
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
                  <button className="btn btn-outline btn-sm" style={{ display: 'flex', alignItems: 'center', gap: '4px' }}>
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
                          alignSelf: isStaff ? 'flex-start' : 'flex-end',
                          maxWidth: '60%',
                          background: isStaff ? 'var(--surface)' : 'var(--primary)',
                          color: isStaff ? 'var(--text)' : '#fff',
                          padding: '14px',
                          borderRadius: '16px',
                          border: isStaff ? '1px solid var(--card-border)' : 'none'
                        }}
                      >
                        <div
                          style={{
                            fontSize: '12px',
                            fontWeight: '600',
                            color: isStaff ? 'var(--primary)' : 'var(--primary-light)',
                            marginBottom: '4px'
                          }}
                        >
                          {msg.sender_name}
                        </div>
                        <div style={{ fontSize: '14px' }}>{msg.content}</div>
                        <div
                          style={{
                            fontSize: '10px',
                            color: isStaff ? 'var(--text-muted)' : 'rgba(255,255,255,0.7)',
                            textAlign: 'right',
                            marginTop: '4px'
                          }}
                        >
                          {new Date(msg.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })} • {msg.message_type}
                        </div>
                      </div>
                    )
                  })
                )}
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
    </div>
  )
}
