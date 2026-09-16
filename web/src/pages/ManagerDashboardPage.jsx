import React, { useEffect, useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  LifeBuoy, Clock, Siren, Megaphone, ListOrdered, Users,
  Activity, BarChart3, FileText, RefreshCw, MessageSquare
} from 'lucide-react'
import { useAuth } from '../context/AuthContext'
import { KpiCard } from '../components/charts'
import { assistanceRepository } from '../repositories/assistanceRepository'
import { sosRequestRepository } from '../repositories/sosRequestRepository'
import { queueRepository } from '../repositories/queueRepository'
import { announcementRepository } from '../repositories/announcementRepository'

const URGENCY_RANK = { urgent: 0, high: 1, medium: 2, low: 3 }

function ShortcutTile({ icon: Icon, label, desc, badge, tone, onClick }) {
  return (
    <button
      type="button"
      className={`shortcut-tile${tone ? ` ${tone}` : ''}`}
      onClick={onClick}
      aria-label={label}
    >
      <span className={`stat-icon ${tone === 'emergency-active' ? 'emergency' : 'primary'}`}>
        <Icon size={20} aria-hidden="true" />
      </span>
      <span className="shortcut-body">
        <span className="shortcut-label">{label}</span>
        <span className="shortcut-desc">{desc}</span>
      </span>
      {badge > 0 && <span className={`badge ${tone === 'emergency-active' ? 'emergency' : 'secondary'}`}>{badge}</span>}
    </button>
  )
}

export default function ManagerDashboardPage() {
  const navigate = useNavigate()
  const { staffContext } = useAuth()
  const institutionId = staffContext?.institution_id

  const [requests, setRequests] = useState([])
  const [sos, setSos] = useState([])
  const [waitingNumbers, setWaitingNumbers] = useState(0)
  const [liveAnnouncements, setLiveAnnouncements] = useState(0)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let active = true
    const load = async () => {
      const [reqs, sosRows, lines, anns] = await Promise.all([
        assistanceRepository.getAssistanceRequests().catch(() => []),
        institutionId ? sosRequestRepository.listForInstitution(institutionId).catch(() => []) : Promise.resolve([]),
        institutionId ? queueRepository.getQueueLines(institutionId).catch(() => []) : Promise.resolve([]),
        institutionId ? announcementRepository.getAnnouncements(institutionId).catch(() => []) : Promise.resolve([]),
      ])
      if (!active) return
      setRequests(reqs || [])
      setSos(sosRows || [])
      setWaitingNumbers(
        (lines || []).flatMap((l) => l.queue_numbers || [])
          .filter((n) => n.status === 'waiting' || n.status === 'called').length
      )
      setLiveAnnouncements((anns || []).filter((a) => a.status === 'active').length)
      setLoading(false)
    }
    load()
    const unsubs = [
      assistanceRepository.subscribeToRequests(() => load()),
      institutionId ? sosRequestRepository.subscribe(institutionId, () => load()) : () => {},
    ]
    return () => { active = false; unsubs.forEach((u) => u?.()) }
  }, [institutionId])

  const activeRequests = useMemo(
    () => requests.filter((r) => r.status === 'pending' || r.status === 'in_progress'),
    [requests]
  )
  const pending = activeRequests.filter((r) => r.status === 'pending')
  const unassignedPending = pending.filter((r) => !r.assigned_staff_id)
  const inProgress = activeRequests.filter((r) => r.status === 'in_progress')
  const activeSos = sos.filter((s) => s.status === 'sent')

  const needsAttention = useMemo(
    () => [...activeRequests]
      .sort((a, b) => {
        const byUrgency = (URGENCY_RANK[a.urgency] ?? 4) - (URGENCY_RANK[b.urgency] ?? 4)
        if (byUrgency !== 0) return byUrgency
        return new Date(a.created_at || 0) - new Date(b.created_at || 0)
      })
      .slice(0, 5),
    [activeRequests]
  )

  const statusInfo = (status) => status === 'pending'
    ? { label: 'Pending', color: '#f59e0b' }
    : { label: 'In Progress', color: '#3b82f6' }

  const tiles = [
    { to: '/requests', icon: LifeBuoy, label: 'Assistance Requests', desc: 'Triage and assign traveller requests', badge: activeRequests.length },
    { to: '/sos', icon: Siren, label: 'SOS / Emergency', desc: 'Live emergency alerts', badge: activeSos.length, tone: activeSos.length > 0 ? 'emergency-active' : undefined },
    { to: '/announcements', icon: Megaphone, label: 'Announcements', desc: 'Publish venue-wide messages', badge: liveAnnouncements },
    { to: '/queue', icon: ListOrdered, label: 'Queue Updates', desc: 'Manage queue lines and calling', badge: waitingNumbers },
    { to: '/staff', icon: Users, label: 'Staff Management', desc: 'Accounts, roles and shifts' },
    { to: '/usage', icon: Activity, label: 'Service Analytics', desc: 'SLA, queue and communication usage' },
    { to: '/analytics', icon: BarChart3, label: 'Accessibility Analytics', desc: 'Barriers, trends and area hotspots' },
    { to: '/reports', icon: FileText, label: 'Reports', desc: 'Generate and export period reports' },
  ]

  return (
    <div>
      <div className="page-header">
        <div>
          <h2>Operations Dashboard</h2>
          <div className="header-subtitle">
            {staffContext?.institutions?.name || 'Your venue'} — what needs attention right now.
          </div>
        </div>
        <div className="header-actions">
          <button className="btn btn-outline btn-sm" onClick={() => window.location.reload()}>
            <RefreshCw size={14} /> Refresh
          </button>
        </div>
      </div>

      <div className="page-body">
        <div className="stats-grid">
          <KpiCard
            loading={loading}
            icon={<LifeBuoy size={22} />}
            tone="primary"
            label="Open Requests"
            value={activeRequests.length}
            sub={`${pending.length} pending · ${inProgress.length} in progress`}
          />
          <KpiCard
            loading={loading}
            icon={<Clock size={22} />}
            tone="secondary"
            label="Unassigned"
            value={unassignedPending.length}
            sub={unassignedPending.length ? 'Waiting for a staff assignment' : 'All pending requests are assigned'}
          />
          <KpiCard
            loading={loading}
            icon={<Siren size={22} />}
            tone={activeSos.length ? 'emergency' : 'success'}
            label="Active SOS"
            value={activeSos.length}
            sub={activeSos.length ? 'Acknowledge immediately' : 'No live emergency alerts'}
          />
          <KpiCard
            loading={loading}
            icon={<MessageSquare size={22} />}
            tone="accent"
            label="Queue Waiting"
            value={waitingNumbers}
            sub={`${liveAnnouncements} live announcement${liveAnnouncements === 1 ? '' : 's'}`}
          />
        </div>

        <div className="card section-gap">
          <div className="card-header">
            <h3>Quick Links</h3>
          </div>
          <div className="shortcut-grid">
            {tiles.map((t) => (
              <ShortcutTile key={t.to} {...t} onClick={() => navigate(t.to)} />
            ))}
          </div>
        </div>

        <div className="card">
          <div className="card-header">
            <h3>Needs Attention</h3>
            <button className="btn btn-outline btn-sm" onClick={() => navigate('/requests')}>View All</button>
          </div>
          {loading ? (
            <div className="table-message">Loading…</div>
          ) : needsAttention.length === 0 ? (
            <div className="chart-placeholder" style={{ height: '120px' }}>
              Nothing needs attention right now.
            </div>
          ) : (
            <div className="chart-groups" style={{ gap: '10px' }}>
              {needsAttention.map((req) => {
                const { label, color } = statusInfo(req.status)
                return (
                  <button
                    key={req.id}
                    type="button"
                    className="recent-request"
                    onClick={() => navigate('/requests')}
                  >
                    <div className="recent-request-body">
                      <span className="recent-request-title">
                        {req.request_code || req.id?.slice(0, 8)} · {req.traveler_name || 'Traveler'}
                      </span>
                      <span className="recent-request-meta">
                        {(req.request_category || req.category || 'assistance')
                          + (req.location_zone ? ` · ${req.location_zone}` : '')
                          + (req.urgency ? ` · ${req.urgency}` : '')}
                        {req.assigned_staff_name ? ` · ${req.assigned_staff_name}` : ' · unassigned'}
                      </span>
                    </div>
                    <span
                      className="status-pill"
                      style={{ background: `${color}22`, color, border: `1px solid ${color}44` }}
                    >
                      {label}
                    </span>
                  </button>
                )
              })}
            </div>
          )}
          <div className="panel-footnote">
            Sorted by urgency, then oldest first. SOS alerts and new requests also surface as desktop
            notifications when enabled.
          </div>
        </div>
      </div>
    </div>
  )
}
