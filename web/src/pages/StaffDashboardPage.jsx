import React, { useEffect, useState, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  LifeBuoy, Clock, CheckCircle2, AlertCircle, Zap,
  MessageCircle, TrendingUp,
  Siren, ListOrdered
} from 'lucide-react'
import { useAuth } from '../context/AuthContext'
import { KpiCard, HBars } from '../components/charts'
import { assistanceRepository } from '../repositories/assistanceRepository'
import useStaffWorkspace from '../hooks/useStaffWorkspace'
import { staffStatusLabel } from '../components/StaffSosOverview'
import { mergeStaffAssignments } from '../lib/staffAssignments'

export default function StaffDashboardPage() {
  const navigate = useNavigate()
  const { staffContext } = useAuth()
  const myStaffId = staffContext?.staff?.id
  const { tasks: sosTasks, staff, loading: sosLoading, error: sosError } = useStaffWorkspace()
  const staffName = staffContext?.staff?.name || 'Staff'

  const [allRequests, setAllRequests] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let active = true
    const load = async () => {
      const data = await assistanceRepository.getAssistanceRequests()
      if (active) {
        setAllRequests(data || [])
        setLoading(false)
      }
    }
    load()
    const unsub = assistanceRepository.subscribeToRequests(() => load())
    return () => { active = false; unsub?.() }
  }, [])

  const venueName = staffContext?.institutions?.name
  const requests = useMemo(
    () => mergeStaffAssignments(
      allRequests.filter(r => !venueName || (r.venue_name || '').trim().toLowerCase() === venueName.trim().toLowerCase()),
      sosTasks,
      myStaffId,
    ),
    [allRequests, sosTasks, myStaffId, venueName]
  )

  const pending    = useMemo(() => requests.filter(r => ['pending', 'assigned'].includes(r.status)), [requests])
  const inProgress = useMemo(() => requests.filter(r => ['in_progress', 'en_route'].includes(r.status)), [requests])
  const resolved   = useMemo(() => requests.filter(r => r.status === 'resolved' || r.status === 'closed'), [requests])
  const highPrio   = useMemo(() => requests.filter(r => r.urgency === 'high' || r.urgency === 'urgent'), [requests])

  const categoryBreakdown = useMemo(() => {
    const map = {}
    requests.forEach(r => {
      const cat = r.request_category || r.category || 'other'
      map[cat] = (map[cat] || 0) + 1
    })
    return Object.entries(map).sort((a, b) => b[1] - a[1])
  }, [requests])

  const recent = useMemo(
    () => [...requests]
      .sort((a, b) => new Date(b.created_at || 0) - new Date(a.created_at || 0))
      .slice(0, 5),
    [requests]
  )

  const resolutionRate = requests.length > 0
    ? Math.round((resolved.length / requests.length) * 100)
    : 0

  const categoryLabel = cat => ({
    communication: 'Communication',
    location: 'Navigation / Location',
    checkin: 'Check-in',
    luggage: 'Luggage',
    other: 'Other',
    emergency: 'SOS / Emergency',
  }[cat] || cat)

  const statusColor = status => {
    if (['pending', 'assigned'].includes(status)) return '#f59e0b'
    if (['in_progress', 'en_route'].includes(status)) return '#3b82f6'
    if (status === 'resolved' || status === 'closed') return '#22c55e'
    return '#94a3b8'
  }

  const statusLabel = status => ({
    pending: 'Pending', in_progress: 'In Progress',
    assigned: 'Assigned', en_route: 'On The Way',
    resolved: 'Resolved', closed: 'Closed',
  }[status] || status)

  return (
    <div>
      <div className="page-header">
        <div>
          <h2>My Dashboard</h2>
          <div className="header-subtitle">
            Welcome back, <strong>{staffName}</strong> — here's your assignment overview.
          </div>
        </div>
        <div className="header-actions">
          {!sosLoading && <span role="status" aria-label="Current availability" className={`badge ${staff?.active && staff.status === 'free' ? 'success' : 'muted'}`}>{staffStatusLabel(staff)}</span>}
          <button className="btn btn-outline btn-sm" onClick={() => navigate('/requests')}>
            <LifeBuoy size={14} /> All Requests
          </button>
        </div>
      </div>

      <div className="page-body">
        {/* KPI Cards */}
        <div className="stats-grid">
          <KpiCard loading={loading || sosLoading} icon={<LifeBuoy size={22} />} tone="accent"    label="Total Assigned" value={requests.length} />
          <KpiCard loading={loading || sosLoading} icon={<Clock size={22} />}     tone="secondary" label="Pending"       value={pending.length} />
          <KpiCard loading={loading || sosLoading} icon={<Zap size={22} />}       tone="primary"   label="In Progress"   value={inProgress.length} />
          <KpiCard loading={loading || sosLoading} icon={<CheckCircle2 size={22} />} tone="success" label="Resolved"    value={resolved.length} />
        </div>
      {sosError && <div className="form-alert error" role="alert">{sosError}</div>}
      {loading || sosLoading ? (
        <div className="form-alert info">Loading your dashboard…</div>
      ) : (
        <>
        {/* Secondary row: resolution rate + high priority */}
        <div className="grid-2 section-gap">
          <div className="card">
            <div className="card-header">
              <h3>Resolution Rate</h3>
              <TrendingUp size={20} color="#10b981" aria-hidden="true" />
            </div>
            <div className="stat-row" style={{ marginBottom: '12px' }}>
              <span style={{ color: 'var(--text-secondary)', fontSize: '13px' }}>
                {resolved.length} of {requests.length} requests resolved
              </span>
              <strong style={{ fontSize: '28px', color: 'var(--success)', lineHeight: 1 }}>{resolutionRate}%</strong>
            </div>
            <div
              className="hbar-track"
              role="progressbar"
              aria-valuenow={resolutionRate}
              aria-valuemin={0}
              aria-valuemax={100}
              aria-label="Resolution rate"
              style={{ height: '10px' }}
            >
              <div
                className="hbar-fill"
                style={{ width: `${resolutionRate}%`, background: 'var(--success)' }}
              />
            </div>
          </div>

          <div className="card">
            <div className="card-header">
              <h3>High Priority</h3>
              <AlertCircle size={20} color={highPrio.length > 0 ? '#ef4444' : '#10b981'} aria-hidden="true" />
            </div>
            <div className="stat-value" style={{ color: highPrio.length > 0 ? 'var(--emergency)' : 'var(--success)', fontSize: '36px' }}>
              {highPrio.length}
            </div>
            <div className="stat-label">
              {highPrio.length === 0 ? 'No high priority requests' : 'Urgent requests need attention'}
            </div>
            {highPrio.length > 0 && (
              <button
                className="btn btn-primary btn-sm"
                style={{ marginTop: '12px' }}
                onClick={() => navigate(highPrio.find(request => request.request_type === 'sos')?.destination || '/requests')}
              >
                View Urgent Requests
              </button>
            )}
          </div>
        </div>

        {/* Category breakdown (side) + Recent requests (main) */}
        <div className="grid-main-side section-gap">
          <div className="card">
            <div className="card-header">
              <h3>Recent Assigned</h3>
              <button className="btn btn-outline btn-sm" onClick={() => navigate('/requests')}>View All</button>
            </div>
            {recent.length === 0 ? (
              <div className="chart-placeholder" style={{ height: '120px' }}>No requests assigned to you yet.</div>
            ) : (
              <div className="chart-groups" style={{ gap: '10px' }}>
                {recent.map(req => {
                  const color = statusColor(req.status)
                  return (
                    <button
                      key={`${req.request_type}:${req.id}`}
                      type="button"
                      className="recent-request"
                      onClick={() => navigate(req.destination)}
                    >
                      <div className="recent-request-body">
                        <span className="recent-request-title">
                          {req.request_code || req.id?.slice(0, 8)} · {req.traveler_name || 'Traveler'}
                        </span>
                        <span className="recent-request-meta">
                          {categoryLabel(req.request_category || req.category || 'other')}
                          {req.location_zone ? ` · ${req.location_zone}` : ''}
                        </span>
                      </div>
                      <span
                        className="status-pill"
                        style={{ background: `${color}22`, color, border: `1px solid ${color}44` }}
                      >
                        {statusLabel(req.status)}
                      </span>
                    </button>
                  )
                })}
              </div>
            )}
          </div>

          <div className="card">
            <div className="card-header">
              <h3>By Category</h3>
              {requests.length > 0 && <span className="badge muted">n = {requests.length}</span>}
            </div>
            {categoryBreakdown.length === 0 ? (
              <div className="chart-placeholder" style={{ height: '120px' }}>No requests yet.</div>
            ) : (
              <HBars
                items={categoryBreakdown.map(([cat, count]) => ({ key: cat, label: categoryLabel(cat), count }))}
                total={requests.length}
              />
            )}
          </div>
        </div>

        {/* Quick links */}
        <div className="button-row" style={{ flexWrap: 'nowrap' }}>
          <button className="btn btn-outline" onClick={() => navigate('/sos')}>
            <Siren size={15} /> SOS Alerts
          </button>
          <button className="btn btn-outline" onClick={() => navigate('/chat')}>
            <MessageCircle size={15} /> My Chats
          </button>
          <button className="btn btn-outline" onClick={() => navigate('/queue')}>
            <ListOrdered size={15} /> Queue Updates
          </button>
        </div>
        </>
      )}
      </div>
    </div>
  )
}
