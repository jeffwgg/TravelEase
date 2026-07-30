import React from 'react'
import { MapPin, Mic, Zap, Send, CheckCircle2 } from 'lucide-react'

export default function StaffChatPage() {
  return (
    <div style={{ padding: '0' }}>
      <div className="page-header" style={{ padding: '16px 32px' }}>
        <div>
          <h2>Staff Communication Console</h2>
          <div className="header-subtitle">Real-time two-way dialogue console with automatic speech-to-text and sign translation support.</div>
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
            <div style={{ padding: '16px', borderBottom: '1px solid var(--divider)', background: 'var(--primary-alpha)', cursor: 'pointer' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '4px' }}>
                <strong style={{ fontSize: '14px' }}>Jeff Wong (#REQ-2847)</strong>
                <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>10:38 AM</span>
              </div>
              <div style={{ fontSize: '12px', color: 'var(--text-secondary)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                How do I get to Gate B12 from here?
              </div>
              <div style={{ display: 'flex', gap: '6px', marginTop: '8px' }}>
                <span className="badge primary">Gate A5</span>
                <span className="badge secondary">In Progress</span>
              </div>
            </div>

            <div style={{ padding: '16px', borderBottom: '1px solid var(--divider)', cursor: 'pointer' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginBottom: '4px' }}>
                <strong style={{ fontSize: '14px' }}>Liew Jie Er (#REQ-2848)</strong>
                <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>10:15 AM</span>
              </div>
              <div style={{ fontSize: '12px', color: 'var(--text-secondary)', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
                Looking for the accessible check-in counter...
              </div>
              <div style={{ display: 'flex', gap: '6px', marginTop: '8px' }}>
                <span className="badge emergency">Pending</span>
              </div>
            </div>
          </div>
        </div>

        {/* Chat main area */}
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', background: 'var(--bg)' }}>
          {/* Top chat info */}
          <div style={{ padding: '16px 24px', background: 'var(--surface)', borderBottom: '1px solid var(--divider)', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <div>
              <h3 style={{ fontSize: '16px', fontWeight: '700' }}>Jeff Wong (Deaf Traveler)</h3>
              <div style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>
                Location: Gate A5 Area • Prefers: BIM Sign Language & Text • Request: Communication Support
              </div>
            </div>
            <div style={{ display: 'flex', gap: '8px' }}>
              <button className="btn btn-outline btn-sm"><MapPin size={14} /> View on Map</button>
              <button className="btn btn-primary btn-sm" style={{ background: 'var(--success)' }}><CheckCircle2 size={14} /> Mark Resolved</button>
            </div>
          </div>

          {/* Messages list */}
          <div style={{ flex: 1, padding: '24px', overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: '16px' }}>
            <div style={{ alignSelf: 'center', background: 'var(--surface-variant)', padding: '4px 12px', borderRadius: '12px', fontSize: '12px', color: 'var(--text-muted)' }}>
              Assistance session initiated for #REQ-2847
            </div>

            <div style={{ alignSelf: 'flex-start', maxWidth: '60%', background: 'var(--surface)', padding: '14px', borderRadius: '16px', border: '1px solid var(--card-border)' }}>
              <div style={{ fontSize: '12px', fontWeight: '600', color: 'var(--primary)', marginBottom: '4px' }}>Ahmad Khan (Staff)</div>
              <div style={{ fontSize: '14px' }}>Hello! I'm Ahmad from KLIA guest services. I see you need communication help. How can I assist you?</div>
              <div style={{ fontSize: '10px', color: 'var(--text-muted)', textAlign: 'right', marginTop: '4px' }}>10:35 AM • STT/Typed</div>
            </div>

            <div style={{ alignSelf: 'flex-end', maxWidth: '60%', background: 'var(--primary)', color: '#fff', padding: '14px', borderRadius: '16px' }}>
              <div style={{ fontSize: '12px', fontWeight: '600', color: 'var(--primary-light)', marginBottom: '4px' }}>Jeff Wong (Traveler)</div>
              <div style={{ fontSize: '14px' }}>Hi Ahmad! I need help understanding the boarding announcement. My flight is MH370.</div>
              <div style={{ fontSize: '10px', color: 'rgba(255,255,255,0.7)', textAlign: 'right', marginTop: '4px' }}>10:36 AM • Sign-to-Text (BIM)</div>
            </div>

            <div style={{ alignSelf: 'flex-start', maxWidth: '60%', background: 'var(--surface)', padding: '14px', borderRadius: '16px', border: '1px solid var(--card-border)' }}>
              <div style={{ fontSize: '12px', fontWeight: '600', color: 'var(--primary)', marginBottom: '4px' }}>Ahmad Khan (Staff)</div>
              <div style={{ fontSize: '14px' }}>Of course! Your flight MH370 has been moved to Gate B12. Boarding starts at 11:15 AM. You have about 35 minutes.</div>
              <div style={{ fontSize: '10px', color: 'var(--text-muted)', textAlign: 'right', marginTop: '4px' }}>10:37 AM • STT/Typed</div>
            </div>

            <div style={{ alignSelf: 'flex-end', maxWidth: '60%', background: 'var(--primary)', color: '#fff', padding: '14px', borderRadius: '16px' }}>
              <div style={{ fontSize: '12px', fontWeight: '600', color: 'var(--primary-light)', marginBottom: '4px' }}>Jeff Wong (Traveler)</div>
              <div style={{ fontSize: '14px' }}>Thank you! How do I get to Gate B12 from here?</div>
              <div style={{ fontSize: '10px', color: 'rgba(255,255,255,0.7)', textAlign: 'right', marginTop: '4px' }}>10:38 AM • Typed Text</div>
            </div>
          </div>

          {/* Quick response templates */}
          <div style={{ padding: '8px 24px', background: 'var(--surface)', borderTop: '1px solid var(--divider)', display: 'flex', gap: '8px', overflowX: 'auto' }}>
            <button className="btn btn-outline btn-sm" style={{ whiteSpace: 'nowrap', display: 'flex', alignItems: 'center', gap: '4px' }}>
              <Zap size={14} /> Gate Direction Template
            </button>
            <button className="btn btn-outline btn-sm" style={{ whiteSpace: 'nowrap', display: 'flex', alignItems: 'center', gap: '4px' }}>
              <Zap size={14} /> Delay Explanation
            </button>
            <button className="btn btn-outline btn-sm" style={{ whiteSpace: 'nowrap', display: 'flex', alignItems: 'center', gap: '4px' }}>
              <Zap size={14} /> Staff Dispatching Notice
            </button>
          </div>

          {/* Input box */}
          <div style={{ padding: '16px 24px', background: 'var(--surface)', borderTop: '1px solid var(--divider)', display: 'flex', gap: '12px' }}>
            <button className="btn btn-outline" style={{ padding: '10px' }} title="Microphone Speech-to-Text">
              <Mic size={18} />
            </button>
            <input type="text" className="input" placeholder="Type your response to the traveler..." style={{ flex: 1 }} />
            <button className="btn btn-primary">
              <Send size={16} /> Send Response
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}
