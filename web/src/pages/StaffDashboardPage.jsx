import React, { useEffect, useState, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  LifeBuoy, Clock, CheckCircle2, AlertCircle, Zap,
  MessageCircle, MapPin, Ticket, Briefcase, TrendingUp,
  Siren, ListOrdered
} from 'lucide-react'
import { useAuth } from '../context/AuthContext'
import { assistanceRepository } from '../repositories/assistanceRepository'

export default function StaffDashboardPage() {
  const navigate = useNavigate()
  const { staffContext } = useAuth()
  const myStaffId = staffContext?.staff?.id
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

  const requests = useMemo(
    () => allRequests.filter(r => r.assigned_staff_id === myStaffId),
    [allRequests, myStaffId]
  )

  const pending    = useMemo(() => requests.filter(r => r.status === 'pending'), [requests])
  const inProgress = useMemo(() => requests.filter(r => r.status === 'in_progress'), [requests])
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
  }[cat] || cat)

  const categoryIcon = cat => {
    switch (cat) {
      case 'communication': return <MessageCircle size={15} />
      case 'location':      return <MapPin size={15} />
      case 'checkin':       return <Ticket size={15} />
      case 'luggage':       return <Briefcase size={15} />
      default:              return <LifeBuoy size={15} />
    }
  }

  const statusColor = status => {
    if (status === 'pending')     return '#f59e0b'
    if (status === 'in_progress') return '#3b82f6'
    if (status === 'resolved' || status === 'closed') return '#22c55e'
    return '#94a3b8'
  }

  const statusLabel = status => ({
    pending: 'Pending', in_progress: 'In Progress',
    resolved: 'Resolved', closed: 'Closed',
  }[status] || status)

  return (
    <div className="page" style={{ padding: '28px 32px', maxWidth: 1100, margin: '0 auto' }}>
      {/* Header */}
      <div style={{ marginBottom: 28 }}>
        <h2 style={{ margin: 0, fontSize: 22, fontWeight: 700 }}>My Dashboard</h2>
        <p style={{ margin: '4px 0 0', color: 'var(--text-secondary)', fontSize: 14 }}>
          Welcome back, <strong>{staffName}</strong> — here's your assignment overview.
        </p>
      </div>

      {loading ? (
        <div className="form-alert info">Loading your dashboard…</div>
      ) : (
        <>
          {/* KPI Cards */}
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 16, marginBottom: 24 }}>
            <KpiCard icon={<LifeBuoy size={20} />} label="Total Assigned" value={requests.length} color="#6366f1" />
            <KpiCard icon={<Clock size={20} />}     label="Pending"        value={pending.length}    color="#f59e0b" />
            <KpiCard icon={<Zap size={20} />}       label="In Progress"    value={inProgress.length} color="#3b82f6" />
            <KpiCard icon={<CheckCircle2 size={20} />} label="Resolved"   value={resolved.length}   color="#22c55e" />
          </div>

          {/* Secondary row */}
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 16, marginBottom: 24 }}>
            {/* Resolution rate */}
            <div className="card" style={{ padding: '20px 24px' }}>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 16 }}>
                <div>
                  <div style={{ fontWeight: 700, fontSize: 15 }}>Resolution Rate</div>
                  <div style={{ fontSize: 12, color: 'var(--text-secondary)', marginTop: 2 }}>
                    {resolved.length} of {requests.length} requests resolved
                  </div>
                </div>
                <TrendingUp size={20} color="#22c55e" />
              </div>
              <div style={{ height: 8, borderRadius: 99, background: 'rgba(255,255,255,0.08)', overflow: 'hidden' }}>
                <div style={{ height: '100%', width: `${resolutionRate}%`, background: '#22c55e', borderRadius: 99, transition: 'width 0.6s ease' }} />
              </div>
              <div style={{ marginTop: 8, fontSize: 28, fontWeight: 800, color: '#22c55e' }}>{resolutionRate}%</div>
            </div>

            {/* High priority */}
            <div className="card" style={{ padding: '20px 24px' }}>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8 }}>
                <div style={{ fontWeight: 700, fontSize: 15 }}>High Priority</div>
                <AlertCircle size={20} color="#ef4444" />
              </div>
              <div style={{ fontSize: 40, fontWeight: 800, color: highPrio.length > 0 ? '#ef4444' : '#22c55e' }}>
                {highPrio.length}
              </div>
              <div style={{ fontSize: 12, color: 'var(--text-secondary)', marginTop: 4 }}>
                {highPrio.length === 0 ? 'No high priority requests 🎉' : 'Urgent requests need attention'}
              </div>
              {highPrio.length > 0 && (
                <button
                  className="btn btn-primary btn-sm"
                  style={{ marginTop: 12 }}
                  onClick={() => navigate('/requests')}
                >
                  View Urgent Requests
                </button>
              )}
            </div>
          </div>

          {/* Category breakdown + Recent requests */}
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1.6fr', gap: 16 }}>
            {/* Category breakdown */}
            <div className="card" style={{ padding: '20px 24px' }}>
              <div style={{ fontWeight: 700, fontSize: 15, marginBottom: 16 }}>By Category</div>
              {categoryBreakdown.length === 0 ? (
                <div style={{ color: 'var(--text-secondary)', fontSize: 13 }}>No requests yet.</div>
              ) : (
                <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                  {categoryBreakdown.map(([cat, count]) => {
                    const pct = requests.length > 0 ? Math.round((count / requests.length) * 100) : 0
                    return (
                      <div key={cat}>
                        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 4, fontSize: 13 }}>
                          <span style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                            {categoryIcon(cat)} {categoryLabel(cat)}
                          </span>
                          <span style={{ fontWeight: 600 }}>{count} <span style={{ color: 'var(--text-secondary)', fontWeight: 400 }}>({pct}%)</span></span>
                        </div>
                        <div style={{ height: 5, borderRadius: 99, background: 'rgba(255,255,255,0.08)' }}>
                          <div style={{ height: '100%', width: `${pct}%`, background: 'var(--primary)', borderRadius: 99 }} />
                        </div>
                      </div>
                    )
                  })}
                </div>
              )}
            </div>

            {/* Recent requests */}
            <div className="card" style={{ padding: '20px 24px' }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
                <div style={{ fontWeight: 700, fontSize: 15 }}>Recent Assigned</div>
                <button className="btn btn-outline btn-sm" onClick={() => navigate('/requests')}>View All</button>
              </div>
              {recent.length === 0 ? (
                <div style={{ color: 'var(--text-secondary)', fontSize: 13 }}>No requests assigned to you yet.</div>
              ) : (
                <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
                  {recent.map(req => (
                    <div
                      key={req.id}
                      style={{
                        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
                        padding: '10px 14px', borderRadius: 10,
                        background: 'rgba(255,255,255,0.04)', cursor: 'pointer',
                        border: '1px solid rgba(255,255,255,0.07)',
                        transition: 'background 0.15s',
                      }}
                      onClick={() => navigate('/requests')}
                    >
                      <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
                        <span style={{ fontWeight: 600, fontSize: 13 }}>
                          {req.request_code || req.id?.slice(0, 8)} · {req.traveler_name || 'Traveler'}
                        </span>
                        <span style={{ fontSize: 12, color: 'var(--text-secondary)' }}>
                          {categoryLabel(req.request_category || req.category || 'other')}
                          {req.location_zone ? ` · ${req.location_zone}` : ''}
                        </span>
                      </div>
                      <span style={{
                        padding: '3px 10px', borderRadius: 99, fontSize: 11, fontWeight: 600,
                        background: `${statusColor(req.status)}22`,
                        color: statusColor(req.status),
                        border: `1px solid ${statusColor(req.status)}44`,
                      }}>
                        {statusLabel(req.status)}
                      </span>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>

          {/* Quick links */}
          <div style={{ display: 'flex', gap: 12, marginTop: 20 }}>
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
  )
}

function KpiCard({ icon, label, value, color }) {
  return (
    <div className="card" style={{ padding: '18px 22px', display: 'flex', alignItems: 'flex-start', gap: 14 }}>
      <div style={{
        width: 40, height: 40, borderRadius: 10, display: 'flex', alignItems: 'center', justifyContent: 'center',
        background: `${color}22`, color, flexShrink: 0,
      }}>
        {icon}
      </div>
      <div>
        <div style={{ fontSize: 26, fontWeight: 800, lineHeight: 1.1 }}>{value}</div>
        <div style={{ fontSize: 12, color: 'var(--text-secondary)', marginTop: 2 }}>{label}</div>
      </div>
    </div>
  )
}
