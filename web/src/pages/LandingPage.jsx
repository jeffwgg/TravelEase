import React, { useState, useEffect } from 'react'
import {
  ShieldCheck,
  Building2,
  LogIn,
  ArrowRight,
  Radio,
  Siren,
  ListOrdered,
  LifeBuoy,
  MessageSquare,
  Activity,
  CheckCircle2,
  Plane,
  Train,
  Hotel,
  Landmark,
  Check,
  Lock,
  FileCheck,
  Zap,
  ArrowUpRight,
  LayoutDashboard,
  MapPin,
  Clock,
  Video,
  FileText
} from 'lucide-react'
import { useNavigate, useLocation, Link } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'
import AuthModal from '../components/AuthModal'

const VENUE_DEMOS = {
  airport: {
    id: 'airport',
    name: 'Kuala Lumpur International Terminal',
    category: 'Airport / Transportation Hub',
    icon: Plane,
    queueLine: {
      name: 'Counter B — Gate Boarding Line',
      serving: 'A-12',
      upcoming: 'A-13',
      waitMinutes: 4,
      status: 'Active'
    },
    sosTicket: {
      id: 'SOS-KLIA-2041',
      zone: 'Departure Concourse B, Gate B14',
      coords: '2.7456° N, 101.7072° E',
      type: 'Wheelchair & Visual Gate Escort',
      traveler: 'Traveler #492 (Deaf Passenger)',
      time: '1 min ago'
    },
    assistance: {
      service: 'Special Assistance Escort',
      zone: 'Departure Gate B14',
      pax: 'Traveler #492 (Wheelchair Escort)',
      status: 'Dispatched',
      note: 'Assigned to duty staff for boarding transit & visual route guide.'
    },
    announcement: {
      title: 'Gate Change: Flight TE-402',
      detail: 'Boarding moved from Gate B14 to Gate B18. Visual guidance active.',
      priority: 'Urgent',
      lang: 'EN / MS'
    }
  },
  transit: {
    id: 'transit',
    name: 'Sentral Multi-Modal Transit Hub',
    category: 'Railway & Rapid Transit',
    icon: Train,
    queueLine: {
      name: 'Platform 3 — Express Line Queue',
      serving: 'T-08',
      upcoming: 'T-09',
      waitMinutes: 2,
      status: 'Active'
    },
    sosTicket: {
      id: 'SOS-STN-9014',
      zone: 'Platform 3 Underground Concourse',
      coords: '3.1340° N, 101.6865° E',
      type: 'Transfer Direction Assistance',
      traveler: 'Traveler #118 (Hard-of-Hearing)',
      time: 'Just now'
    },
    assistance: {
      service: 'Platform Transfer Guide',
      zone: 'Platform 3 Concourse',
      pax: 'Traveler #118 (Deaf Commuter)',
      status: 'En Route',
      note: 'Station duty staff assigned for visual tactile interchange routing.'
    },
    announcement: {
      title: 'Platform 3 Track Maintenance',
      detail: 'Intercity Regional 44 arriving on Platform 9.',
      priority: 'High',
      lang: 'EN / MS'
    }
  },
  hospitality: {
    id: 'hospitality',
    name: 'Aura Grand Hotel & Conference Center',
    category: 'Hotel & Hospitality',
    icon: Hotel,
    queueLine: {
      name: 'Front Office Check-In Counter',
      serving: 'H-03',
      upcoming: 'H-04',
      waitMinutes: 1,
      status: 'Active'
    },
    sosTicket: {
      id: 'SOS-HTL-7732',
      zone: 'Suite 1408, Tower West',
      coords: '3.1528° N, 101.7118° E',
      type: 'In-Room Visual Strobe Verification',
      traveler: 'Guest 1408 (Deaf Guest)',
      time: '2 min ago'
    },
    assistance: {
      service: 'In-Room Accessibility Strobe Check',
      zone: 'Suite 1408, West Wing',
      pax: 'Guest 1408 (Deaf Guest)',
      status: 'Confirmed',
      note: 'Visual door beacon and vibratory alarm inspection active.'
    },
    announcement: {
      title: 'Breakfast Visual Service Ready',
      detail: 'Executive Lounge Level 2 captioning displays online.',
      priority: 'Normal',
      lang: 'EN / MS'
    }
  }
}

export default function LandingPage({ defaultModalOpen = false, defaultModalMode = 'login' }) {
  const navigate = useNavigate()
  const location = useLocation()
  const { session, staffContext } = useAuth()

  const [modalOpen, setModalOpen] = useState(defaultModalOpen)
  const [modalMode, setModalMode] = useState(defaultModalMode)
  const [activeVenue, setActiveVenue] = useState('airport')

  // Interactive state matching real system actions
  const [simServing, setSimServing] = useState('')
  const [simUpcoming, setSimUpcoming] = useState('')
  const [sosStatus, setSosStatus] = useState('sent') // 'sent' | 'acknowledged' | 'resolved'

  useEffect(() => {
    const venue = VENUE_DEMOS[activeVenue]
    setSimServing(venue.queueLine.serving)
    setSimUpcoming(venue.queueLine.upcoming)
    setSosStatus('sent')
  }, [activeVenue])

  useEffect(() => {
    if (location.pathname === '/auth') {
      setModalOpen(true)
      const params = new URLSearchParams(location.search)
      const modeParam = params.get('mode')
      if (modeParam === 'register' || modeParam === 'forgot') {
        setModalMode(modeParam)
      } else {
        setModalMode('login')
      }
    }
  }, [location])

  const openAuth = (mode = 'login') => {
    setModalMode(mode)
    setModalOpen(true)
    if (location.pathname !== '/auth') {
      window.history.pushState({}, '', '/auth')
    }
  }

  const closeAuth = () => {
    setModalOpen(false)
    if (window.location.pathname === '/auth') {
      window.history.pushState({}, '', '/')
    }
  }

  // Real system queue call next simulation
  const handleCallNext = () => {
    const currentNum = parseInt(simServing.split('-')[1], 10) || 14
    const nextNum = currentNum + 1
    const letter = simServing.split('-')[0]
    setSimServing(`${letter}-${nextNum}`)
    setSimUpcoming(`${letter}-${nextNum + 1}`)
  }

  const venueData = VENUE_DEMOS[activeVenue]
  const VenueIcon = venueData.icon

  return (
    <div className="landing-container">
      {/* 1. Navbar */}
      <header className="landing-navbar">
        <div className="landing-navbar-inner">
          <Link to="/" className="landing-brand">
            <img src="/logo.png" alt="TravelEase Logo" className="landing-logo" />
            <span className="brand-name">TravelEase</span>
          </Link>

          <nav className="landing-nav-links">
            <a href="#console" className="nav-link">Live Console</a>
            <a href="#modules" className="nav-link">System Modules</a>
            <a href="#sectors" className="nav-link">Venue Sectors</a>
            <a href="#onboarding" className="nav-link">Accreditation</a>
          </nav>

          <div className="landing-nav-actions">
            {session && staffContext ? (
              <Link to="/dashboard" className="btn btn-primary nav-cta-btn">
                <LayoutDashboard size={16} />
                <span>Open Dashboard</span>
              </Link>
            ) : (
              <>
                <button
                  type="button"
                  className="nav-link-btn"
                  onClick={() => openAuth('register')}
                >
                  <Building2 size={15} />
                  <span>Register Facility</span>
                </button>
                <button
                  type="button"
                  className="btn btn-primary nav-cta-btn"
                  onClick={() => openAuth('login')}
                >
                  <LogIn size={16} />
                  <span>Sign In</span>
                </button>
              </>
            )}
          </div>
        </div>
      </header>

      {/* 2. Hero Section */}
      <section className="landing-hero-section">
        <div className="landing-hero-glow" />
        <div className="landing-hero-inner">
          <div className="hero-eyebrow">
            <div className="hero-status-pulse" />
            <ShieldCheck size={14} className="text-teal" />
            <span>WCAG 2.2 Ready · Institutional Accessibility Infrastructure</span>
          </div>

          <h1 className="hero-title">
            Real-Time Visual Accessibility <br />
            <span className="hero-highlight">for Deaf Travelers</span>
          </h1>

          <p className="hero-subtitle">
            Equip airports, transit hubs, and hotels with live visual queue broadcasting, non-verbal
            emergency SOS dispatch, and real-time passenger assistance coordination.
          </p>

          <div className="hero-cta-group">
            {session && staffContext ? (
              <Link to="/dashboard" className="btn btn-primary btn-hero-primary">
                <span>Enter Operations Console</span>
                <ArrowRight size={18} />
              </Link>
            ) : (
              <>
                <button
                  type="button"
                  className="btn btn-primary btn-hero-primary"
                  onClick={() => openAuth('login')}
                >
                  <span>Sign In to Console</span>
                  <ArrowRight size={18} />
                </button>
                <button
                  type="button"
                  className="btn btn-secondary btn-hero-secondary"
                  onClick={() => openAuth('register')}
                >
                  <Building2 size={16} />
                  <span>Register Facility</span>
                </button>
              </>
            )}
          </div>

          {/* 4 Critical Metrics (Matching System SLAs) */}
          <div className="hero-trust-strip">
            <div className="trust-item">
              <span className="trust-stat">&lt; 30s</span>
              <span>SOS Response SLA</span>
            </div>
            <div className="trust-divider" />
            <div className="trust-item">
              <span className="trust-stat">100%</span>
              <span>Visual Redundancy</span>
            </div>
            <div className="trust-divider" />
            <div className="trust-item">
              <span className="trust-stat">&lt; 3 min</span>
              <span>Assistance Dispatch</span>
            </div>
            <div className="trust-divider" />
            <div className="trust-item">
              <span className="trust-stat">Zero</span>
              <span>Audio Reliance</span>
            </div>
          </div>
        </div>
      </section>

      {/* 3. Live System Simulator (Directly Demonstrates Real Working Code Logic) */}
      <section className="landing-simulator-section" id="console">
        <div className="landing-section-header">
          <div className="section-pill">
            <Activity size={14} className="text-teal" />
            <span>Interactive Console Architecture</span>
          </div>
          <h2 className="section-title">Tested Against Working System Logic</h2>
        </div>

        {/* Venue Switcher */}
        <div className="simulator-tabs" role="tablist">
          {Object.values(VENUE_DEMOS).map((venue) => {
            const VIcon = venue.icon
            const isActive = activeVenue === venue.id
            return (
              <button
                key={venue.id}
                type="button"
                role="tab"
                aria-selected={isActive}
                className={`simulator-tab-btn ${isActive ? 'active' : ''}`}
                onClick={() => setActiveVenue(venue.id)}
              >
                <VIcon size={16} />
                <span>{venue.name}</span>
                <span className="tab-facility-tag">{venue.category}</span>
              </button>
            )
          })}
        </div>

        {/* Live Simulator Console */}
        <div className="simulator-console-frame">
          <div className="console-topbar">
            <div className="console-window-dots">
              <span className="dot dot-red" />
              <span className="dot dot-yellow" />
              <span className="dot dot-green" />
            </div>
            <div className="console-station-info">
              <VenueIcon size={14} className="text-teal" />
              <span className="console-station-name">{venueData.name}</span>
              <span className="console-status-pill">
                <span className="live-pulse-indicator" /> Supabase Real-Time Synced
              </span>
            </div>
            <div className="console-latency-tag">
              <Zap size={12} />
              <span>SLA Latency: 14ms</span>
            </div>
          </div>

          <div className="console-content-grid">
            {/* Column 1: Live Queue Advance & Multi-Zone Announcement */}
            <div className="console-panel">
              <div className="panel-header">
                <div className="panel-title-group">
                  <ListOrdered size={16} className="text-teal" />
                  <h3>Queue Line Synchronization</h3>
                </div>
                <span className="panel-badge">Live Counter</span>
              </div>

              {/* Working Queue Box */}
              <div className="queue-card-demo" style={{ marginBottom: '14px' }}>
                <div className="queue-card-top">
                  <span className="queue-code">{venueData.queueLine.name}</span>
                  <span className="queue-badge badge-teal">{venueData.queueLine.status}</span>
                </div>
                <div style={{ display: 'flex', alignItems: 'baseline', gap: '16px', margin: '10px 0' }}>
                  <div>
                    <span style={{ fontSize: '11px', color: '#94A3B8', display: 'block' }}>Now Calling</span>
                    <strong style={{ fontSize: '26px', color: '#5EEAD4', fontFamily: 'monospace' }}>{simServing}</strong>
                  </div>
                  <div>
                    <span style={{ fontSize: '11px', color: '#94A3B8', display: 'block' }}>Next Ticket</span>
                    <span style={{ fontSize: '16px', color: '#94A3B8', fontFamily: 'monospace' }}>{simUpcoming}</span>
                  </div>
                  <div style={{ marginLeft: 'auto', textAlign: 'right' }}>
                    <span style={{ fontSize: '11px', color: '#94A3B8', display: 'block' }}>Est. Wait</span>
                    <span style={{ fontSize: '13px', color: '#CBD5E1', fontWeight: 600 }}>{venueData.queueLine.waitMinutes} mins</span>
                  </div>
                </div>
                <button
                  type="button"
                  className="btn btn-primary btn-sm"
                  style={{ width: '100%', justifyContent: 'center' }}
                  onClick={handleCallNext}
                >
                  Advance Queue &amp; Notify Traveler App
                </button>
              </div>

              {/* Working Multi-Zone Announcement Card */}
              <div className="queue-card-demo">
                <div className="queue-card-top">
                  <span className="queue-code">Zone Broadcast ({venueData.announcement.lang})</span>
                  <span className="queue-badge badge-amber">{venueData.announcement.priority}</span>
                </div>
                <div className="queue-title" style={{ fontSize: '13px', marginBottom: '4px' }}>
                  {venueData.announcement.title}
                </div>
                <p style={{ fontSize: '12px', color: '#94A3B8', margin: 0, lineHeight: 1.4 }}>
                  {venueData.announcement.detail}
                </p>
              </div>
            </div>

            {/* Column 2: Emergency SOS Dispatch (Real sent -> acknowledged -> resolved workflow) */}
            <div className="console-panel panel-sos">
              <div className="panel-header">
                <div className="panel-title-group">
                  <Siren size={16} className="text-emergency" />
                  <h3>Emergency SOS Ticket (GPS Geocoded)</h3>
                </div>
                <span className={`panel-badge-${sosStatus === 'resolved' ? 'teal' : 'emergency'}`}>
                  {sosStatus === 'sent' ? 'Sent (Pending)' : sosStatus === 'acknowledged' ? 'Acknowledged' : 'Resolved'}
                </span>
              </div>

              <div className="sos-ticket-box">
                <div className="sos-ticket-header">
                  <span className="sos-id-badge">{venueData.sosTicket.id}</span>
                  <span className="sos-time-tag">{venueData.sosTicket.time}</span>
                </div>

                <div className="sos-ticket-details">
                  <div className="sos-field">
                    <span className="field-title">Terminal Zone:</span>
                    <strong className="field-value">{venueData.sosTicket.zone}</strong>
                  </div>
                  <div className="sos-field">
                    <span className="field-title">GPS Coordinates:</span>
                    <span className="field-value" style={{ fontFamily: 'monospace', color: '#5EEAD4' }}>
                      {venueData.sosTicket.coords}
                    </span>
                  </div>
                  <div className="sos-field">
                    <span className="field-title">Assistance Need:</span>
                    <strong className="field-value text-teal">{venueData.sosTicket.type}</strong>
                  </div>
                </div>

                <div className="sos-action-bar">
                  {sosStatus === 'sent' && (
                    <button
                      type="button"
                      className="btn btn-primary btn-ack-sos"
                      onClick={() => setSosStatus('acknowledged')}
                    >
                      <Check size={15} />
                      <span>Acknowledge Ticket &amp; Dispatch Duty Staff</span>
                    </button>
                  )}
                  {sosStatus === 'acknowledged' && (
                    <div style={{ display: 'flex', flexDirection: 'column', gap: '8px', width: '100%' }}>
                      <div className="sos-status-confirmed">
                        <CheckCircle2 size={16} className="text-teal" />
                        <span>Duty Staff Dispatched (En Route)</span>
                      </div>
                      <button
                        type="button"
                        className="btn btn-secondary btn-sm"
                        style={{ width: '100%', justifyContent: 'center' }}
                        onClick={() => setSosStatus('resolved')}
                      >
                        Confirm Assistance &amp; Mark Resolved
                      </button>
                    </div>
                  )}
                  {sosStatus === 'resolved' && (
                    <div className="sos-status-confirmed" style={{ width: '100%' }}>
                      <CheckCircle2 size={16} className="text-teal" />
                      <span>Request Successfully Resolved &amp; Logged</span>
                    </div>
                  )}
                </div>
              </div>

              {/* Live Passenger Assistance Request Preview */}
              <div className="sign-knowledge-card">
                <div className="sign-card-top">
                  <LifeBuoy size={16} className="text-teal" />
                  <div>
                    <span className="sign-term">{venueData.assistance.service}</span>
                    <span className="sign-category">{venueData.assistance.zone} · {venueData.assistance.pax}</span>
                  </div>
                  <span className="sign-verified-badge">
                    <CheckCircle2 size={12} />
                    <span>{venueData.assistance.status}</span>
                  </span>
                </div>
                <div className="sign-card-note">
                  {venueData.assistance.note}
                </div>
              </div>
            </div>
          </div>

          <div className="console-footer-bar">
            <div className="console-footer-meta">
              <Lock size={12} className="text-teal" />
              <span>TLS 1.3 Security · Real-Time Station Protocol</span>
            </div>
            <button
              type="button"
              className="console-launch-btn"
              onClick={() => openAuth('login')}
            >
              <span>Launch Live Console</span>
              <ArrowUpRight size={14} />
            </button>
          </div>
        </div>
      </section>

      {/* 4. Real System Modules */}
      <section className="landing-pillars-section" id="modules">
        <div className="landing-section-header">
          <h2 className="section-title">Institutional Management Modules</h2>
        </div>

        <div className="pillars-grid">
          <div className="pillar-card">
            <div className="pillar-icon-box bg-teal-glow">
              <ListOrdered size={24} className="text-teal" />
            </div>
            <h3 className="pillar-title">Queue &amp; Boarding Sync</h3>
            <p className="pillar-desc">
              Advance counters, notify upcoming ticket holders, and broadcast live status to traveler
              smartphones without relying on voice speakers.
            </p>
          </div>

          <div className="pillar-card">
            <div className="pillar-icon-box bg-emergency-glow">
              <Siren size={24} className="text-emergency" />
            </div>
            <h3 className="pillar-title">Emergency SOS Dispatch</h3>
            <p className="pillar-desc">
              Deaf travelers trigger distress beacons with GPS coordinates. Staff acknowledge and
              resolve tickets with real-time Leaflet map routing.
            </p>
          </div>

          <div className="pillar-card">
            <div className="pillar-icon-box bg-amber-glow">
              <LifeBuoy size={24} className="text-amber" />
            </div>
            <h3 className="pillar-title">Passenger Assistance Dispatch</h3>
            <p className="pillar-desc">
              Log, assign, and resolve accessibility assistance requests including wheelchair transfers,
              guided escorts, and non-verbal traveler accommodations.
            </p>
          </div>

          <div className="pillar-card">
            <div className="pillar-icon-box bg-indigo-glow">
              <MessageSquare size={24} className="text-indigo" />
            </div>
            <h3 className="pillar-title">Two-Way Chat &amp; WebRTC</h3>
            <p className="pillar-desc">
              Coordinate passenger assistance via real-time text and WebRTC video calling for remote
              sign language interpretation.
            </p>
          </div>
        </div>
      </section>

      {/* 5. Supported Venue Sectors */}
      <section className="landing-solutions-section" id="sectors">
        <div className="landing-section-header">
          <h2 className="section-title">Supported Institution Categories</h2>
        </div>

        <div className="solutions-grid">
          <div className="solution-card">
            <div className="solution-icon-wrap">
              <Plane size={24} className="text-teal" />
            </div>
            <h3 className="solution-title">Airports &amp; Airlines</h3>
            <p className="solution-desc">Gates, baggage carousels, and priority boarding flow.</p>
          </div>

          <div className="solution-card">
            <div className="solution-icon-wrap">
              <Train size={24} className="text-teal" />
            </div>
            <h3 className="solution-title">Transit &amp; Rail Hubs</h3>
            <p className="solution-desc">Platform changes, schedule alerts, and transfer aid.</p>
          </div>

          <div className="solution-card">
            <div className="solution-icon-wrap">
              <Hotel size={24} className="text-teal" />
            </div>
            <h3 className="solution-title">Hotels &amp; Hospitality</h3>
            <p className="solution-desc">Visual check-in, guest services, and safety strobe sync.</p>
          </div>

          <div className="solution-card">
            <div className="solution-icon-wrap">
              <Landmark size={24} className="text-teal" />
            </div>
            <h3 className="solution-title">Civic &amp; Cultural Centers</h3>
            <p className="solution-desc">Accessible routing, queue pacing, and crowd safety.</p>
          </div>
        </div>
      </section>

      {/* 6. Onboarding Steps */}
      <section className="landing-compliance-section" id="onboarding">
        <div className="compliance-card">
          <div className="compliance-content">
            <div className="compliance-badge">
              <ShieldCheck size={16} />
              <span>Institutional Accreditation Workflow</span>
            </div>
            <h2 className="compliance-title">Fast Facility Verification</h2>
            <div className="onboarding-steps-list">
              <div className="onboarding-step-item">
                <span className="step-num">1</span>
                <div>
                  <strong>Register &amp; Upload Documentation</strong>
                  <p>Provide facility category, duty contact, and official accreditation (PDF/JPG/PNG).</p>
                </div>
              </div>
              <div className="onboarding-step-item">
                <span className="step-num">2</span>
                <div>
                  <strong>Institutional Verification</strong>
                  <p>Reviewed and authorized within 24 hours by compliance administrators.</p>
                </div>
              </div>
              <div className="onboarding-step-item">
                <span className="step-num">3</span>
                <div>
                  <strong>Define Service Area &amp; Broadcast</strong>
                  <p>Configure geofenced station bounds and start real-time communication.</p>
                </div>
              </div>
            </div>
          </div>

          <div className="compliance-action-box">
            <div className="compliance-action-title">Register Your Facility</div>
            <p className="compliance-action-text">
              Join certified public transportation and lodging stations.
            </p>
            <button
              type="button"
              className="btn btn-primary compliance-btn"
              onClick={() => openAuth('register')}
            >
              <Building2 size={16} />
              <span>Begin Facility Onboarding</span>
            </button>
            <button
              type="button"
              className="btn btn-secondary compliance-btn"
              onClick={() => openAuth('login')}
            >
              <LogIn size={16} />
              <span>Sign In to Existing Station</span>
            </button>
          </div>
        </div>
      </section>

      {/* 7. Footer */}
      <footer className="landing-footer">
        <div className="landing-footer-bottom">
          <div className="footer-brand">
            <img src="/logo.png" alt="TravelEase Logo" className="footer-logo" />
            <span className="footer-brand-name">TravelEase</span>
          </div>
          <div className="footer-quick-links">
            <button type="button" className="footer-link-btn" onClick={() => openAuth('login')}>
              Console Sign In
            </button>
            <button type="button" className="footer-link-btn" onClick={() => openAuth('register')}>
              Facility Registration
            </button>
            <button type="button" className="footer-link-btn" onClick={() => openAuth('forgot')}>
              Account Recovery
            </button>
          </div>
          <span className="footer-copy">&copy; {new Date().getFullYear()} TravelEase System. All rights reserved.</span>
        </div>
      </footer>

      {/* 8. Integrated Auth Modal */}
      <AuthModal
        isOpen={modalOpen}
        initialMode={modalMode}
        onClose={closeAuth}
      />
    </div>
  )
}
