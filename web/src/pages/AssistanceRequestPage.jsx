import React, { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { Clock, MessageSquare, CheckCircle2, AlertCircle, MessageCircle, MapPin, Ticket, Briefcase } from 'lucide-react'
import { assistanceRepository } from '../repositories/assistanceRepository'

export default function AssistanceRequestPage() {
  const navigate = useNavigate()
  const [requests, setRequests] = useState([])
  const [loading, setLoading] = useState(true)
  const [statusFilter, setStatusFilter] = useState('All Statuses')
  const [searchQuery, setSearchQuery] = useState('')

  useEffect(() => {
    loadRequests()

    const unsubscribe = assistanceRepository.subscribeToRequests(() => {
      loadRequests()
    })

    return () => {
      if (unsubscribe) unsubscribe()
    }
  }, [])

  async function loadRequests() {
    setLoading(true)
    const data = await assistanceRepository.getAssistanceRequests()
    setRequests(data || [])
    setLoading(false)
  }

  const filteredRequests = requests.filter(req => {
    const matchesStatus =
      statusFilter === 'All Statuses' ||
      (statusFilter === 'Pending' && req.status === 'pending') ||
      (statusFilter === 'In Progress' && req.status === 'in_progress') ||
      (statusFilter === 'Resolved' && (req.status === 'resolved' || req.status === 'closed'))

    const matchesSearch =
      !searchQuery ||
      (req.request_code && req.request_code.toLowerCase().includes(searchQuery.toLowerCase())) ||
      (req.traveler_name && req.traveler_name.toLowerCase().includes(searchQuery.toLowerCase())) ||
      (req.location_zone && req.location_zone.toLowerCase().includes(searchQuery.toLowerCase()))

    return matchesStatus && matchesSearch
  })

  // Calculate dynamic stats
  const pendingCount = requests.filter(r => r.status === 'pending').length
  const inProgressCount = requests.filter(r => r.status === 'in_progress').length
  const resolvedCount = requests.filter(r => r.status === 'resolved' || r.status === 'closed').length
  const highPriorityCount = requests.filter(r => r.urgency === 'high' || r.urgency === 'urgent').length

  const getCategoryIcon = (category) => {
    switch (category) {
      case 'communication':
        return <MessageCircle size={16} color="var(--primary)" />
      case 'location':
        return <MapPin size={16} color="var(--accent)" />
      case 'checkin':
        return <Ticket size={16} color="var(--secondary-dark)" />
      case 'luggage':
        return <Briefcase size={16} color="var(--text-secondary)" />
      default:
        return <MessageCircle size={16} color="var(--primary)" />
    }
  }

  const getUrgencyBadge = (urgency) => {
    switch (urgency) {
      case 'low':
        return <span className="badge primary">Low</span>
      case 'medium':
        return <span className="badge secondary">Medium</span>
      case 'high':
      case 'urgent':
        return <span className="badge emergency">High</span>
      default:
        return <span className="badge secondary">{urgency}</span>
    }
  }

  const getStatusBadge = (status) => {
    switch (status) {
      case 'pending':
        return <span className="badge emergency">Pending</span>
      case 'in_progress':
        return <span className="badge secondary">In Progress</span>
      case 'resolved':
      case 'closed':
        return <span className="badge success">Resolved</span>
      default:
        return <span className="badge secondary">{status}</span>
    }
  }

  return (
    <div>
      <div className="page-header">
        <div>
          <h2>Assistance Request Dispatch</h2>
          <div className="header-subtitle">Real-time incoming assistance requests from travelers requiring physical or communication support. (Connected to Supabase)</div>
        </div>
        <button className="btn btn-primary" onClick={loadRequests}>↻ Refresh Live Data</button>
      </div>

      <div className="page-body">
        <div className="stats-grid">
          <div className="stat-card">
            <div className="stat-icon secondary"><Clock size={22} color="var(--secondary-dark)" /></div>
            <div>
              <div className="stat-value">{pendingCount}</div>
              <div className="stat-label">Pending Response</div>
            </div>
          </div>
          <div className="stat-card">
            <div className="stat-icon primary"><MessageSquare size={22} color="var(--primary)" /></div>
            <div>
              <div className="stat-value">{inProgressCount}</div>
              <div className="stat-label">In Progress (Active Chat)</div>
            </div>
          </div>
          <div className="stat-card">
            <div className="stat-icon success"><CheckCircle2 size={22} color="var(--success)" /></div>
            <div>
              <div className="stat-value">{resolvedCount}</div>
              <div className="stat-label">Resolved Today</div>
            </div>
          </div>
          <div className="stat-card">
            <div className="stat-icon emergency"><AlertCircle size={22} color="var(--emergency)" /></div>
            <div>
              <div className="stat-value">{highPriorityCount}</div>
              <div className="stat-label">High Priority / Urgent</div>
            </div>
          </div>
        </div>

        <div className="card">
          <div className="card-header">
            <h3>Incoming Assistance Requests</h3>
            <div style={{ display: 'flex', gap: '8px' }}>
              <select
                className="input"
                style={{ width: '160px' }}
                value={statusFilter}
                onChange={(e) => setStatusFilter(e.target.value)}
              >
                <option>All Statuses</option>
                <option>Pending</option>
                <option>In Progress</option>
                <option>Resolved</option>
              </select>
              <input
                type="text"
                className="input"
                placeholder="Search ID, traveler..."
                style={{ width: '200px' }}
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
              />
            </div>
          </div>

          <table className="data-table">
            <thead>
              <tr>
                <th>Request ID</th>
                <th>Traveler Name</th>
                <th>Category</th>
                <th>Location / Zone</th>
                <th>Urgency</th>
                <th>Assigned Staff</th>
                <th>Status</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr>
                  <td colSpan="8" style={{ textAlign: 'center', padding: '32px' }}>Loading requests from Supabase...</td>
                </tr>
              ) : filteredRequests.length === 0 ? (
                <tr>
                  <td colSpan="8" style={{ textAlign: 'center', padding: '32px' }}>No assistance requests match your filter.</td>
                </tr>
              ) : (
                filteredRequests.map((req) => (
                  <tr key={req.id}>
                    <td><strong>{req.request_code}</strong></td>
                    <td>
                      {req.traveler_name}<br />
                      <span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>
                        Prefers: {req.preferred_communication}
                      </span>
                    </td>
                    <td>
                      <div style={{ display: 'flex', alignItems: 'center', gap: '6px', textTransform: 'capitalize' }}>
                        {getCategoryIcon(req.category)} {req.category}
                      </div>
                    </td>
                    <td>{req.location_zone}</td>
                    <td>{getUrgencyBadge(req.urgency)}</td>
                    <td>{req.assigned_staff_name || 'Unassigned'}</td>
                    <td>{getStatusBadge(req.status)}</td>
                    <td>
                      <button
                        className="btn btn-primary btn-sm"
                        onClick={() => navigate('/chat')}
                      >
                        {req.status === 'pending' ? 'Assign Staff' : 'Open Chat'}
                      </button>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}

