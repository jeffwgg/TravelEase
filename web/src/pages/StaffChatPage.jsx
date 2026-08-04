import React, { useState, useEffect } from 'react'
import { MapPin, Mic, Zap, Send, CheckCircle2 } from 'lucide-react'
import { assistanceRepository } from '../repositories/assistanceRepository'

export default function StaffChatPage() {
  const [requests, setRequests] = useState([])
  const [selectedReq, setSelectedReq] = useState(null)
  const [messages, setMessages] = useState([])
  const [inputText, setInputText] = useState('')
  const [loadingMsg, setLoadingMsg] = useState(false)

  useEffect(() => {
    loadRequests()

    const unsubscribeReq = assistanceRepository.subscribeToRequests(() => {
      loadRequests()
    })

    return () => {
      if (unsubscribeReq) unsubscribeReq()
    }
  }, [])

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

  return (
    <div style={{ padding: '0' }}>
      <div className="page-header" style={{ padding: '16px 32px' }}>
        <div>
          <h2>Staff Communication Console</h2>
          <div className="header-subtitle">Real-time two-way dialogue console with automatic speech-to-text and sign translation support. (Connected to Supabase)</div>
        </div>
        <div style={{ display: 'flex', gap: '8px' }}>
          <span className="badge success" style={{ padding: '6px 12px', fontSize: '12px', display: 'flex', alignItems: 'center', gap: '6px' }}>
            <span style={{ width: '8px', height: '8px', borderRadius: '50%', background: 'var(--success)' }}></span> Online & Accepting Chats
          </span>
        </div>
      </div>

      <div style={{ display: 'flex', height: 'calc(100vh - 85px)' }}>
        {/* Chat sidebar */}
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

        {/* Chat main area */}
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: 'var(--bg)' }}>
          {selectedReq ? (
            <>
              {/* Top chat info */}
              <div style={{ padding: '16px 24px', background: 'var(--surface)', borderBottom: '1px solid var(--divider)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <div>
                  <h3 style={{ fontSize: '16px', fontWeight: '700' }}>{selectedReq.traveler_name} (Deaf Traveler)</h3>
                  <div style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>
                    Location: {selectedReq.location_zone} • Prefers: {selectedReq.preferred_communication} • Request: {selectedReq.category}
                  </div>
                </div>
                <div style={{ display: 'flex', gap: '8px' }}>
                  <button className="btn btn-outline btn-sm"><MapPin size={14} /> View on Map</button>
                  <button
                    className="btn btn-primary btn-sm"
                    style={{ background: 'var(--success)' }}
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

