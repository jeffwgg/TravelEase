import React, { useState, useEffect, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { 
  Clock, 
  MessageSquare, 
  CheckCircle2, 
  AlertCircle, 
  AlertTriangle,
  MessageCircle, 
  MapPin, 
  Ticket, 
  Briefcase,
  UserCheck,
  Search,
  User,
  Phone,
  X,
  Check,
  ShieldCheck,
  Eye,
  Radio,
  Image as ImageIcon,
  ZoomIn,
  FileText,
  LifeBuoy
} from 'lucide-react'
import { assistanceRepository } from '../repositories/assistanceRepository'
import { useAuth } from '../context/AuthContext'
import LiveLocationMap from '../components/LiveLocationMap'

export default function AssistanceRequestPage({ staffOnly = false, staffDashboard = false }) {
  const navigate = useNavigate()
  const { staffContext } = useAuth()
  const institutionId = staffContext?.institution_id
  const myStaffId = staffContext?.staff?.id
  const [requests, setRequests] = useState([])
  const [loading, setLoading] = useState(true)
  const [statusFilter, setStatusFilter] = useState('All Statuses')
  const [searchQuery, setSearchQuery] = useState('')

  // Top-level Navigation Tab: 'requests' | 'barriers'
  const [mainTab, setMainTab] = useState('requests')

  // Accessibility Barrier Reports State (Module 5 & 7)
  const [barrierReports, setBarrierReports] = useState([])
  const [loadingBarriers, setLoadingBarriers] = useState(true)
  const [barrierStatusFilter, setBarrierStatusFilter] = useState('All Statuses')
  const [barrierSearchQuery, setBarrierSearchQuery] = useState('')
  const [selectedBarrier, setSelectedBarrier] = useState(null)
  const [isBarrierModalOpen, setIsBarrierModalOpen] = useState(false)
  const [barrierNewStatus, setBarrierNewStatus] = useState('reported')
  const [barrierNewNotes, setBarrierNewNotes] = useState('')
  const [savingBarrier, setSavingBarrier] = useState(false)
  const [zoomPhotoUrl, setZoomPhotoUrl] = useState(null)

  // Modal State
  const [isModalOpen, setIsModalOpen] = useState(false)
  const [selectedReq, setSelectedReq] = useState(null)
  const [showAssignMap, setShowAssignMap] = useState(false)
  const [detailModalReq, setDetailModalReq] = useState(null)
  const [staffList, setStaffList] = useState([])
  const [loadingStaff, setLoadingStaff] = useState(false)
  const [staffSearch, setStaffSearch] = useState('')
  const [staffFilterAvailable, setStaffFilterAvailable] = useState(true)
  const [submittingAssignId, setSubmittingAssignId] = useState(null)
  const [toastMessage, setToastMessage] = useState(null)

  useEffect(() => {
    loadRequests()
    if (!staffOnly) {
      loadBarrierReports()
    }

    const unsubscribe = assistanceRepository.subscribeToRequests(() => {
      loadRequests()
    })
    const unsubscribeBarriers = !staffOnly
      ? assistanceRepository.subscribeToAccessibilityReports(() => {
          loadBarrierReports()
        })
      : null

    return () => {
      if (unsubscribe) unsubscribe()
      if (unsubscribeBarriers) unsubscribeBarriers()
    }
  }, [staffOnly])

  // Live-refresh staff availability while the assign modal is open
  useEffect(() => {
    if (!isModalOpen || !institutionId) return

    const unsubscribeStaff = assistanceRepository.subscribeToStaff(institutionId, async () => {
      const staffData = await assistanceRepository.getInstitutionStaff(institutionId)
      setStaffList(staffData || [])
    })

    return () => {
      if (unsubscribeStaff) unsubscribeStaff()
    }
  }, [isModalOpen, institutionId])


  async function loadRequests() {
    setLoading(true)
    const data = await assistanceRepository.getAssistanceRequests()
    setRequests(data || [])
    setLoading(false)
  }

  async function loadBarrierReports() {
    setLoadingBarriers(true)
    const data = await assistanceRepository.getAccessibilityIssueReports()
    setBarrierReports(data || [])
    setLoadingBarriers(false)
  }

  function openBarrierModal(report) {
    setSelectedBarrier(report)
    setBarrierNewStatus(report.status || 'reported')
    setBarrierNewNotes(report.admin_notes || '')
    setIsBarrierModalOpen(true)
  }

  async function handleSaveBarrier() {
    if (!selectedBarrier) return
    setSavingBarrier(true)
    try {
      const updated = await assistanceRepository.updateAccessibilityReport(selectedBarrier.id, {
        status: barrierNewStatus,
        adminNotes: barrierNewNotes
      })
      if (updated) {
        showToast(`Barrier report #${selectedBarrier.report_code} updated successfully`)
        setIsBarrierModalOpen(false)
        await loadBarrierReports()
      } else {
        showToast('Failed to update report. Please try again.')
      }
    } catch (err) {
      console.error('Failed to update barrier report:', err)
      showToast('Error updating barrier report.')
    } finally {
      setSavingBarrier(false)
    }
  }

  const rawVenueName = staffContext?.institutions?.name
  const scopedBarriers = useMemo(() => {
    if (!rawVenueName) return barrierReports
    const target = rawVenueName.trim().toLowerCase()
    return barrierReports.filter(b => (b.venue_name || '').trim().toLowerCase() === target)
  }, [barrierReports, rawVenueName])

  const scopedRequests = useMemo(() => {
    if (!rawVenueName) return requests
    const target = rawVenueName.trim().toLowerCase()
    return requests.filter(r => (r.venue_name || '').trim().toLowerCase() === target)
  }, [requests, rawVenueName])

  const filteredBarriers = useMemo(() => {
    return scopedBarriers.filter(b => {
      const s = (b.status || '').toLowerCase()
      const matchesStatus = barrierStatusFilter === 'All Statuses' ||
        (barrierStatusFilter === 'Reported' && s === 'reported') ||
        (barrierStatusFilter === 'Investigating' && (s === 'investigating' || s === 'in_progress')) ||
        (barrierStatusFilter === 'Resolved' && (s === 'resolved' || s === 'closed'))
      const q = barrierSearchQuery.toLowerCase().trim()
      const matchesSearch = !q ||
        (b.report_code && b.report_code.toLowerCase().includes(q)) ||
        (b.location_zone && b.location_zone.toLowerCase().includes(q)) ||
        (b.description && b.description.toLowerCase().includes(q)) ||
        (b.issue_type && b.issue_type.toLowerCase().includes(q)) ||
        (b.traveler_name && b.traveler_name.toLowerCase().includes(q))
      return matchesStatus && matchesSearch
    })
  }, [scopedBarriers, barrierStatusFilter, barrierSearchQuery])

  const barrierPendingCount = scopedBarriers.filter(b => b.status === 'reported').length
  const barrierInvestigatingCount = scopedBarriers.filter(b => b.status === 'investigating' || b.status === 'in_progress').length
  const barrierResolvedCount = scopedBarriers.filter(b => b.status === 'resolved' || b.status === 'closed').length
  const barrierSevereCount = scopedBarriers.filter(b => (b.severity || '').toLowerCase() === 'severe').length

  const getBarrierStatusBadge = (status) => {
    switch (status?.toLowerCase()) {
      case 'reported':
        return <span className="badge primary">Reported</span>
      case 'investigating':
      case 'in_progress':
        return <span className="badge secondary">Investigating</span>
      case 'resolved':
      case 'closed':
        return <span className="badge success">Resolved</span>
      default:
        return <span className="badge secondary">{status || 'Reported'}</span>
    }
  }

  const getBarrierSeverityBadge = (severity) => {
    switch (severity?.toLowerCase()) {
      case 'minor':
        return <span className="badge success">Minor</span>
      case 'severe':
        return <span className="badge emergency">Severe</span>
      case 'moderate':
      default:
        return <span className="badge secondary">Moderate</span>
    }
  }

  const getBarrierIssueLabel = (issueType) => {
    switch (issueType?.toLowerCase()) {
      case 'visual': return 'No Visual Announcement'
      case 'queue': return 'Sound-Only Queue'
      case 'sign': return 'No Sign Language'
      case 'alert': return 'Missing Visual Alert'
      case 'access': return 'Inaccessible Area'
      case 'other': return 'Other Issue'
      default: return issueType || 'General'
    }
  }

  async function openAssignModal(req) {
    setSelectedReq(req)
    setIsModalOpen(true)
    setStaffSearch('')
    setLoadingStaff(true)
    const staffData = await assistanceRepository.getInstitutionStaff(institutionId)
    setStaffList(staffData || [])
    setLoadingStaff(false)
  }

  function closeAssignModal() {
    setIsModalOpen(false)
    setSelectedReq(null)
  }

  async function handleAssignStaff(staff) {
    if (!selectedReq) return
    setSubmittingAssignId(staff.id)
    try {
      await assistanceRepository.assignStaffToRequest(selectedReq.id, staff.id, staff.name)
      showToast(`Assigned ${staff.name} to Request ${selectedReq.request_code}`)
      closeAssignModal()
      await loadRequests()
    } catch (err) {
      console.error('Failed to assign staff:', err)
      showToast('Failed to assign staff. Please try again.')
    } finally {
      setSubmittingAssignId(null)
    }
  }

  async function handleResolveRequest(req) {
    try {
      await assistanceRepository.updateRequestStatus(req.id, 'resolved')
      showToast(`Request ${req.request_code} marked as resolved`)
      await loadRequests()
    } catch (err) {
      console.error('Failed to resolve request:', err)
      showToast('Failed to resolve request. Please try again.')
    }
  }

  function showToast(msg) {
    setToastMessage(msg)
    setTimeout(() => {
      setToastMessage(null)
    }, 4000)
  }

  const baseRequests = staffOnly
    ? scopedRequests.filter(req => req.assigned_staff_id === myStaffId)
    : scopedRequests

  const filteredRequests = baseRequests.filter(req => {
    const isUnassigned = !req.assigned_staff_name || req.assigned_staff_name === 'Unassigned'
    const isEscalated = req.is_escalated === true
    const minutesWaiting = req.created_at
      ? Math.floor((Date.now() - new Date(req.created_at).getTime()) / 60000)
      : 0
    const shouldEscalate = !isEscalated && req.status === 'pending' && minutesWaiting >= 10
    const isEscalatedOrPendingLong = isEscalated || shouldEscalate

    const matchesStatus =
      statusFilter === 'All Statuses' ||
      (statusFilter === 'Pending' && req.status === 'pending') ||
      (statusFilter === 'Unassigned' && isUnassigned && req.status !== 'resolved' && req.status !== 'closed') ||
      (statusFilter === 'Escalated' && isEscalatedOrPendingLong) ||
      (statusFilter === 'In Progress' && req.status === 'in_progress') ||
      (statusFilter === 'Resolved' && (req.status === 'resolved' || req.status === 'closed'))

    const matchesSearch =
      !searchQuery ||
      (req.request_code && req.request_code.toLowerCase().includes(searchQuery.toLowerCase())) ||
      (req.traveler_name && req.traveler_name.toLowerCase().includes(searchQuery.toLowerCase())) ||
      (req.location_zone && req.location_zone.toLowerCase().includes(searchQuery.toLowerCase()))

    return matchesStatus && matchesSearch
  }).sort((a, b) => {
    const aResolved = a.status === 'resolved' || a.status === 'closed' ? 1 : 0
    const bResolved = b.status === 'resolved' || b.status === 'closed' ? 1 : 0
    if (aResolved !== bResolved) {
      return aResolved - bResolved // Unresolved (0) before Resolved (1)
    }
    return new Date(b.created_at || 0) - new Date(a.created_at || 0)
  })

  const filteredStaff = staffList.filter(staff => {
    const matchesAvailability = !staffFilterAvailable || staff.status === 'available'
    const query = staffSearch.toLowerCase()
    const matchesSearch =
      !query ||
      (staff.name && staff.name.toLowerCase().includes(query)) ||
      (staff.role && staff.role.toLowerCase().includes(query)) ||
      (staff.department && staff.department.toLowerCase().includes(query))

    return matchesAvailability && matchesSearch
  })

  // Calculate dynamic stats (scoped to staff's own requests when staffOnly)
  const pendingCount = baseRequests.filter(r => r.status === 'pending').length
  const inProgressCount = baseRequests.filter(r => r.status === 'in_progress').length
  const resolvedCount = baseRequests.filter(r => r.status === 'resolved' || r.status === 'closed').length
  const highPriorityCount = baseRequests.filter(r => r.urgency === 'high' || r.urgency === 'urgent').length

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

  const getReachBadge = (method) => {
    if (method === 'location') {
      return (
        <span
          className="badge secondary"
          style={{
            display: 'inline-flex',
            alignItems: 'center',
            gap: '5px',
            background: 'rgba(245, 158, 11, 0.12)',
            color: '#b45309',
            border: '1px solid rgba(245, 158, 11, 0.25)',
            fontSize: '11px',
            fontWeight: 500,
            padding: '3px 8px',
            borderRadius: '6px'
          }}
        >
          <MapPin size={12} /> In-Person
        </span>
      )
    }
    return (
      <span
        className="badge primary"
        style={{
          display: 'inline-flex',
          alignItems: 'center',
          gap: '5px',
          fontSize: '11px',
          fontWeight: 500,
          padding: '3px 8px',
          borderRadius: '6px'
        }}
      >
        <MessageSquare size={12} /> In-App Chat
      </span>
    )
  }

  const getStaffStatusBadge = (status) => {
    switch (status) {
      case 'available':
        return (
          <span className="badge success" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', padding: '4px 8px' }}>
            <span style={{ width: '6px', height: '6px', borderRadius: '50%', background: 'var(--success)' }}></span> Available
          </span>
        )
      case 'busy':
        return (
          <span className="badge secondary" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', padding: '4px 8px', background: 'rgba(245, 158, 11, 0.15)', color: '#d97706' }}>
            <span style={{ width: '6px', height: '6px', borderRadius: '50%', background: '#d97706' }}></span> Busy
          </span>
        )
      case 'offline':
      default:
        return (
          <span className="badge" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', padding: '4px 8px', background: '#f3f4f6', color: '#6b7280' }}>
            <span style={{ width: '6px', height: '6px', borderRadius: '50%', background: '#9ca3af' }}></span> Offline
          </span>
        )
    }
  }

  return (
    <div>
      {/* Toast Notification */}
      {toastMessage && (
        <div style={{
          position: 'fixed',
          top: '24px',
          right: '24px',
          zIndex: 9999,
          background: 'var(--text-main, #1e293b)',
          color: '#ffffff',
          padding: '12px 20px',
          borderRadius: '8px',
          boxShadow: '0 10px 25px rgba(0,0,0,0.2)',
          display: 'flex',
          alignItems: 'center',
          gap: '10px',
          fontWeight: 500,
          animation: 'fadeIn 0.2s ease-out'
        }}>
          <CheckCircle2 size={18} color="#22c55e" />
          <span>{toastMessage}</span>
        </div>
      )}

      <div className="page-header">
        <div>
          <h2>{staffOnly ? 'My Assigned Requests' : 'Assistance Request Dispatch'}</h2>
          <div className="header-subtitle">
            {staffOnly
              ? 'Assistance requests assigned to you.'
              : 'Real-time incoming assistance requests from travelers requiring physical or communication support.'}
          </div>
        </div>
      </div>

      <div className="page-body">
        {/* Navigation Tabs (Managers only: manage both requests and barrier reports) */}
        {!staffOnly && (
          <div style={{ display: 'flex', gap: '10px', marginBottom: '24px', borderBottom: '1px solid var(--border-color, #e2e8f0)', paddingBottom: '12px' }}>
            <button
              className={`btn ${mainTab === 'requests' ? 'btn-primary' : 'btn-outline'}`}
              onClick={() => setMainTab('requests')}
              style={{ display: 'inline-flex', alignItems: 'center', gap: '8px', cursor: 'pointer' }}
            >
              <LifeBuoy size={16} />
              Immediate Assistance Requests
              <span style={{
                background: mainTab === 'requests' ? 'rgba(255,255,255,0.25)' : 'rgba(0,0,0,0.06)',
                padding: '2px 8px',
                borderRadius: '12px',
                fontSize: '11px',
                fontWeight: 600
              }}>
                {baseRequests.length}
              </span>
            </button>
            <button
              className={`btn ${mainTab === 'barriers' ? 'btn-primary' : 'btn-outline'}`}
              onClick={() => setMainTab('barriers')}
              style={{ display: 'inline-flex', alignItems: 'center', gap: '8px', cursor: 'pointer' }}
            >
              <AlertTriangle size={16} />
              Accessibility Barrier Reports
              <span style={{
                background: mainTab === 'barriers' ? 'rgba(255,255,255,0.25)' : 'rgba(0,0,0,0.06)',
                padding: '2px 8px',
                borderRadius: '12px',
                fontSize: '11px',
                fontWeight: 600
              }}>
                {scopedBarriers.length}
              </span>
            </button>
          </div>
        )}

        {mainTab === 'requests' || staffOnly ? (
          <>
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
                    style={{ width: '180px' }}
                    value={statusFilter}
                    onChange={(e) => setStatusFilter(e.target.value)}
                  >
                    <option>All Statuses</option>
                    <option>Pending</option>
                    <option>Unassigned</option>
                    <option>Escalated</option>
                    <option>In Progress</option>
                    <option>Resolved</option>
                  </select>
                  <input
                    type="text"
                    className="input"
                    placeholder="Search traveler, code..."
                    style={{ width: '220px' }}
                    value={searchQuery}
                    onChange={(e) => setSearchQuery(e.target.value)}
                  />
                </div>
              </div>

              <table className="data-table">
                <thead>
                  <tr>
                    <th>Request Code</th>
                    <th>Traveler</th>
                    <th>Category</th>
                    <th>Urgency</th>
                    <th>Contact</th>
                    <th>Location / Zone</th>
                    {!staffOnly && <th>Assigned Staff</th>}
                    <th>Status</th>
                    <th>Actions</th>
                  </tr>
                </thead>
                <tbody>
                  {loading ? (
                    <tr>
                      <td colSpan={staffOnly ? "8" : "9"} style={{ textAlign: 'center', padding: '32px' }}>Loading requests from Supabase...</td>
                    </tr>
                  ) : filteredRequests.length === 0 ? (
                    <tr>
                      <td colSpan={staffOnly ? "8" : "9"} style={{ textAlign: 'center', padding: '32px' }}>No assistance requests match your filter.</td>
                    </tr>
                  ) : (
                    filteredRequests.map((req) => {
                      const isUnassigned = !req.assigned_staff_name || req.assigned_staff_name === 'Unassigned'
                      const isEscalated = req.is_escalated === true
                      const minutesWaiting = req.created_at
                        ? Math.floor((Date.now() - new Date(req.created_at).getTime()) / 60000)
                        : 0
                      const shouldEscalate = !isEscalated && req.status === 'pending' && minutesWaiting >= 10
                      const showEscalationBadge = isEscalated || shouldEscalate

                      return (
                        <tr key={req.id} style={{ background: showEscalationBadge ? 'rgba(239, 68, 68, 0.02)' : undefined }}>
                          <td>
                            <strong>{req.request_code}</strong>
                            {showEscalationBadge && (
                              <div style={{
                                display: 'inline-flex',
                                alignItems: 'center',
                                gap: '4px',
                                background: 'rgba(239, 68, 68, 0.1)',
                                color: '#ef4444',
                                border: '1px solid rgba(239, 68, 68, 0.25)',
                                borderRadius: '4px',
                                padding: '2px 6px',
                                fontSize: '10px',
                                fontWeight: '700',
                                marginTop: '4px',
                                whiteSpace: 'nowrap'
                              }}>
                                <AlertTriangle size={11} color="#ef4444" />
                                <span>ESCALATED — Waiting {minutesWaiting} min</span>
                              </div>
                            )}
                          </td>
                          <td>
                            <div style={{ fontWeight: 600, color: 'var(--text-main)' }}>{req.traveler_name}</div>
                            <div style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>
                              {new Date(req.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                            </div>
                          </td>
                          <td>
                            <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                              {getCategoryIcon(req.category)}
                              <span style={{ textTransform: 'capitalize' }}>{req.category}</span>
                            </div>
                          </td>
                          <td>{getUrgencyBadge(req.urgency)}</td>
                          <td>{getReachBadge(req.preferred_communication)}</td>
                          <td>
                            <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                              <MapPin size={14} color="var(--accent)" />
                              <span>{req.location_zone}</span>
                            </div>
                          </td>
                          {!staffOnly && (
                            <td>
                              {isUnassigned ? (
                                <span style={{
                                  color: '#dc2626',
                                  background: 'rgba(220, 38, 38, 0.08)',
                                  border: '1px dashed rgba(220, 38, 38, 0.4)',
                                  padding: '2px 8px',
                                  borderRadius: '6px',
                                  fontSize: '12px',
                                  fontWeight: 500,
                                  display: 'inline-flex',
                                  alignItems: 'center',
                                  gap: '4px'
                                }}>
                                  <AlertCircle size={12} /> Unassigned
                                </span>
                              ) : (
                                <div style={{ display: 'flex', flexDirection: 'column' }}>
                                  <span style={{ fontWeight: 500 }}>{req.assigned_staff_name}</span>
                                  {req.status === 'in_progress' && (
                                    <span style={{
                                      fontSize: '11px',
                                      color: '#2563eb',
                                      display: 'inline-flex',
                                      alignItems: 'center',
                                      gap: '3px',
                                      marginTop: '2px'
                                    }}>
                                      {req.preferred_communication === 'location'
                                        ? <><MapPin size={10} /> On-Site Assistance</>
                                        : <><MessageSquare size={10} /> Active in Chat</>}
                                    </span>
                                  )}
                                </div>
                              )}
                            </td>
                          )}
                          <td>{getStatusBadge(req.status)}</td>
                          <td>
                            <div style={{ display: 'flex', gap: '6px', alignItems: 'center' }}>
                              <button
                                className="btn btn-outline btn-sm"
                                onClick={() => setDetailModalReq(req)}
                                title="View Details & Live Map"
                                style={{ padding: '6px 8px', display: 'inline-flex', alignItems: 'center' }}
                              >
                                <Eye size={13} />
                              </button>
                              {req.status === 'pending' ? (
                                !staffOnly && (
                                  <button
                                    className="btn btn-primary btn-sm"
                                    style={{ display: 'inline-flex', alignItems: 'center', gap: '6px' }}
                                    onClick={() => openAssignModal(req)}
                                  >
                                    <UserCheck size={14} /> Assign Staff
                                  </button>
                                )
                              ) : req.status === 'in_progress' ? (
                                staffOnly ? (
                                  req.preferred_communication === 'location' ? (
                                    <>
                                      <button
                                        className="btn btn-secondary btn-sm"
                                        style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}
                                        onClick={() => setDetailModalReq(req)}
                                      >
                                        <MapPin size={14} /> View Location
                                      </button>
                                      <button
                                        className="btn btn-sm"
                                        style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', background: 'var(--success)', color: '#ffffff' }}
                                        onClick={() => handleResolveRequest(req)}
                                      >
                                        <CheckCircle2 size={14} /> Resolve
                                      </button>
                                    </>
                                  ) : (
                                    <>
                                      <button
                                        className="btn btn-primary btn-sm"
                                        style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}
                                        onClick={() => navigate('/chat', { state: { requestId: req.id } })}
                                      >
                                        <MessageSquare size={14} /> Open Chat
                                      </button>
                                      <button
                                        className="btn btn-sm"
                                        style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', background: 'var(--success)', color: '#ffffff' }}
                                        onClick={() => handleResolveRequest(req)}
                                      >
                                        <CheckCircle2 size={14} /> Resolve
                                      </button>
                                    </>
                                  )
                                ) : (
                                  <button
                                    className="btn btn-secondary btn-sm"
                                    onClick={() => openAssignModal(req)}
                                  >
                                    Reassign
                                  </button>
                                )
                              ) : staffOnly ? (
                                req.preferred_communication !== 'location' && (
                                  <button
                                    className="btn btn-secondary btn-sm"
                                    onClick={() => navigate('/chat', { state: { requestId: req.id } })}
                                  >
                                    View Chat
                                  </button>
                                )
                              ) : null}
                            </div>
                          </td>
                        </tr>
                      )
                    })
                  )}
                </tbody>
              </table>
            </div>
          </>
        ) : (
          <>
            {/* Barrier Stats Grid */}
            <div className="stats-grid">
              <div className="stat-card">
                <div className="stat-icon primary"><AlertCircle size={22} color="var(--primary)" /></div>
                <div>
                  <div className="stat-value">{scopedBarriers.length}</div>
                  <div className="stat-label">Total Barriers Filed</div>
                </div>
              </div>
              <div className="stat-card">
                <div className="stat-icon secondary"><Clock size={22} color="var(--secondary-dark)" /></div>
                <div>
                  <div className="stat-value">{barrierPendingCount}</div>
                  <div className="stat-label">Reported (New)</div>
                </div>
              </div>
              <div className="stat-card">
                <div className="stat-icon warning"><AlertTriangle size={22} color="#f59e0b" /></div>
                <div>
                  <div className="stat-value">{barrierInvestigatingCount}</div>
                  <div className="stat-label">Investigating / Action</div>
                </div>
              </div>
              <div className="stat-card">
                <div className="stat-icon success"><CheckCircle2 size={22} color="var(--success)" /></div>
                <div>
                  <div className="stat-value">{barrierResolvedCount}</div>
                  <div className="stat-label">Resolved Barriers</div>
                </div>
              </div>
            </div>

            <div className="card">
              <div className="card-header">
                <div>
                  <h3>Reported Accessibility Barriers</h3>
                  <div style={{ margin: '4px 0 0', fontSize: '13px', color: '#64748b' }}>
                    Infrastructural and communication barriers reported by travelers. Review issues, inspect photos, and record processing results.
                  </div>
                </div>
                <div style={{ display: 'flex', gap: '8px', alignItems: 'center' }}>
                  <select
                    className="input"
                    style={{ width: '170px' }}
                    value={barrierStatusFilter}
                    onChange={(e) => setBarrierStatusFilter(e.target.value)}
                  >
                    <option>All Statuses</option>
                    <option>Reported</option>
                    <option>Investigating</option>
                    <option>Resolved</option>
                  </select>
                  <div style={{ position: 'relative' }}>
                    <Search size={16} color="#94a3b8" style={{ position: 'absolute', left: '10px', top: '10px' }} />
                    <input
                      type="text"
                      className="input"
                      placeholder="Search code, zone, issue..."
                      style={{ paddingLeft: '32px', width: '220px' }}
                      value={barrierSearchQuery}
                      onChange={(e) => setBarrierSearchQuery(e.target.value)}
                    />
                  </div>
                </div>
              </div>

              <table className="data-table">
                <thead>
                  <tr>
                    <th>Report Code</th>
                    <th>Date & Time</th>
                    <th>Issue Category</th>
                    <th>Location Zone</th>
                    <th>Severity</th>
                    <th>Photo Evidence</th>
                    <th>Description</th>
                    <th>Status</th>
                    <th>Processing Result</th>
                    <th>Action</th>
                  </tr>
                </thead>
                <tbody>
                  {loadingBarriers ? (
                    <tr>
                      <td colSpan="10" style={{ textAlign: 'center', padding: '32px', color: '#64748b' }}>
                        Loading accessibility barrier reports...
                      </td>
                    </tr>
                  ) : filteredBarriers.length === 0 ? (
                    <tr>
                      <td colSpan="10" style={{ textAlign: 'center', padding: '32px', color: '#64748b' }}>
                        No barrier reports found matching your filter criteria.
                      </td>
                    </tr>
                  ) : (
                    filteredBarriers.map((b) => {
                      return (
                        <tr key={b.id}>
                          <td>
                            <span style={{
                              fontWeight: 'bold',
                              color: 'var(--primary)',
                              background: 'rgba(59, 130, 246, 0.08)',
                              padding: '3px 7px',
                              borderRadius: '5px',
                              fontSize: '12px'
                            }}>
                              {b.report_code}
                            </span>
                          </td>
                          <td style={{ fontSize: '12px', color: '#64748b', whiteSpace: 'nowrap' }}>
                            {new Date(b.created_at).toLocaleDateString()} {new Date(b.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}
                          </td>
                          <td>
                            <span style={{ fontSize: '13px', fontWeight: 500, color: '#1e293b' }}>
                              {getBarrierIssueLabel(b.issue_type)}
                            </span>
                          </td>
                          <td>
                            <span style={{ fontSize: '13px', display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
                              <MapPin size={13} color="#64748b" />
                              {b.location_zone || b.venue_name || '—'}
                            </span>
                          </td>
                          <td>{getBarrierSeverityBadge(b.severity)}</td>
                          <td>
                            {b.photo_url ? (
                              <button
                                type="button"
                                onClick={() => setZoomPhotoUrl(b.photo_url)}
                                title="Click to zoom photo"
                                style={{
                                  border: 'none',
                                  background: 'transparent',
                                  padding: 0,
                                  cursor: 'pointer',
                                  display: 'inline-flex',
                                  alignItems: 'center',
                                  position: 'relative'
                                }}
                              >
                                <img
                                  src={b.photo_url}
                                  alt="Barrier photo evidence"
                                  style={{
                                    width: '40px',
                                    height: '40px',
                                    borderRadius: '6px',
                                    objectFit: 'cover',
                                    border: '1px solid #e2e8f0'
                                  }}
                                />
                                <span style={{
                                  position: 'absolute',
                                  right: '2px',
                                  bottom: '2px',
                                  background: 'rgba(0,0,0,0.6)',
                                  borderRadius: '3px',
                                  padding: '1px'
                                }}>
                                  <ZoomIn size={10} color="#ffffff" />
                                </span>
                              </button>
                            ) : (
                              <span style={{ color: '#94a3b8', fontSize: '12px' }}>None</span>
                            )}
                          </td>
                          <td style={{ maxWidth: '220px' }}>
                            <span
                              title={b.description}
                              style={{
                                fontSize: '13px',
                                color: '#334155',
                                display: '-webkit-box',
                                WebkitLineClamp: 2,
                                WebkitBoxOrient: 'vertical',
                                overflow: 'hidden'
                              }}
                            >
                              {b.description || '—'}
                            </span>
                          </td>
                          <td>{getBarrierStatusBadge(b.status)}</td>
                          <td style={{ maxWidth: '180px' }}>
                            {b.admin_notes ? (
                              <span
                                title={b.admin_notes}
                                style={{
                                  fontSize: '12px',
                                  color: '#047857',
                                  display: '-webkit-box',
                                  WebkitLineClamp: 2,
                                  WebkitBoxOrient: 'vertical',
                                  overflow: 'hidden'
                                }}
                              >
                                {b.admin_notes}
                              </span>
                            ) : (
                              <span style={{ fontSize: '12px', color: '#94a3b8', fontStyle: 'italic' }}>
                                Awaiting review
                              </span>
                            )}
                          </td>
                          <td>
                            <button
                              className="btn btn-outline btn-sm"
                              onClick={() => openBarrierModal(b)}
                              style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', whiteSpace: 'nowrap' }}
                            >
                              <Eye size={13} /> Review & Action
                            </button>
                          </td>
                        </tr>
                      )
                    })
                  )}
                </tbody>
              </table>
            </div>
          </>
        )}
      </div>

      {/* Staff Assignment Modal */}
      {isModalOpen && selectedReq && (
        <div style={{
          position: 'fixed',
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          backgroundColor: 'rgba(15, 23, 42, 0.65)',
          backdropFilter: 'blur(4px)',
          zIndex: 9000,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          padding: '16px'
        }}>
          <div style={{
            background: 'var(--card-bg, #ffffff)',
            borderRadius: '16px',
            width: '100%',
            maxWidth: '620px',
            maxHeight: '85vh',
            display: 'flex',
            flexDirection: 'column',
            boxShadow: '0 20px 50px rgba(0,0,0,0.3)',
            overflow: 'hidden',
            border: '1px solid rgba(226, 232, 240, 0.8)'
          }}>
            {/* Modal Header */}
            <div style={{
              padding: '20px 24px',
              borderBottom: '1px solid var(--border-color, #e2e8f0)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              background: '#f8fafc'
            }}>
              <div>
                <h3 style={{ margin: 0, fontSize: '18px', fontWeight: 600, color: 'var(--text-main, #0f172a)' }}>
                  Assign Staff Member
                </h3>
              </div>
              <button
                onClick={closeAssignModal}
                style={{
                  background: 'none',
                  border: 'none',
                  cursor: 'pointer',
                  padding: '6px',
                  borderRadius: '50%',
                  color: '#64748b',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center'
                }}
              >
                <X size={20} />
              </button>
            </div>

            {/* Target Request Info Box */}
            <div style={{
              padding: '16px 24px',
              background: 'rgba(239, 246, 255, 0.7)',
              borderBottom: '1px solid #dbeafe',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              gap: '12px'
            }}>
              <div>
                <div style={{ fontSize: '12px', fontWeight: 600, textTransform: 'uppercase', color: '#1d4ed8', letterSpacing: '0.5px' }}>
                  Request #{selectedReq.request_code}
                </div>
                <div style={{ fontWeight: 600, fontSize: '15px', color: '#1e293b', marginTop: '2px' }}>
                  {selectedReq.traveler_name}
                </div>
                <div style={{ fontSize: '13px', color: '#475569', marginTop: '4px', display: 'flex', alignItems: 'center', gap: '8px', flexWrap: 'wrap' }}>
                  <span>Location: <strong>{selectedReq.location_zone}</strong></span>
                  <span>•</span>
                  <span style={{ textTransform: 'capitalize' }}>Category: <strong>{selectedReq.category}</strong></span>
                </div>
              </div>
              <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: '6px' }}>
                {getUrgencyBadge(selectedReq.urgency)}
                {getReachBadge(selectedReq.preferred_communication)}
              </div>
            </div>

            {/* Live Location Map Drawer in Assign Modal */}
            {selectedReq.share_location && (
              <div style={{ padding: '12px 24px', background: '#f8fafc', borderBottom: '1px solid #e2e8f0' }}>
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '12px', fontWeight: 600, color: '#16a34a' }}>
                    <Radio size={13} color="#16a34a" /> Traveler Live Location Available
                  </div>
                  <button
                    type="button"
                    onClick={() => setShowAssignMap(!showAssignMap)}
                    style={{
                      background: '#ffffff',
                      border: '1px solid #cbd5e1',
                      borderRadius: '6px',
                      padding: '3px 10px',
                      fontSize: '11px',
                      fontWeight: 600,
                      color: 'var(--primary)',
                      cursor: 'pointer'
                    }}
                  >
                    {showAssignMap ? 'Hide Live Map' : 'Preview Live Map'}
                  </button>
                </div>
                {showAssignMap && (
                  <div style={{ height: '220px', width: '100%', marginTop: '10px' }}>
                    <LiveLocationMap
                      sessionId={selectedReq.id}
                      sessionType="assistance"
                      initialLat={selectedReq.latitude}
                      initialLng={selectedReq.longitude}
                      travelerName={selectedReq.traveler_name}
                      locationZone={selectedReq.location_zone}
                      height="220px"
                      compact
                    />
                  </div>
                )}
              </div>
            )}

            {/* Modal Body & Filters */}
            <div style={{ padding: '16px 24px', flex: 1, overflowY: 'auto' }}>
              <div style={{ display: 'flex', gap: '12px', marginBottom: '16px', alignItems: 'center' }}>
                <div style={{ position: 'relative', flex: 1 }}>
                  <Search size={16} color="#94a3b8" style={{ position: 'absolute', left: '12px', top: '50%', transform: 'translateY(-50%)' }} />
                  <input
                    type="text"
                    className="input"
                    placeholder="Search staff name, role, zone..."
                    value={staffSearch}
                    onChange={(e) => setStaffSearch(e.target.value)}
                    style={{ paddingLeft: '36px', width: '100%' }}
                  />
                </div>
                <button
                  type="button"
                  className={`btn ${staffFilterAvailable ? 'btn-primary' : 'btn-secondary'}`}
                  style={{ fontSize: '13px', whiteSpace: 'nowrap', padding: '8px 14px' }}
                  onClick={() => setStaffFilterAvailable(!staffFilterAvailable)}
                >
                  {staffFilterAvailable ? 'Available Only' : 'Show All Staff'}
                </button>
              </div>

              {/* Staff List */}
              {loadingStaff ? (
                <div style={{ textAlign: 'center', padding: '40px', color: '#64748b' }}>
                  Loading available staff from database...
                </div>
              ) : filteredStaff.length === 0 ? (
                <div style={{ textAlign: 'center', padding: '40px', color: '#64748b', background: '#f8fafc', borderRadius: '8px', border: '1px dashed #cbd5e1' }}>
                  No staff members match your criteria. Try toggling "Show All Staff".
                </div>
              ) : (
                <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
                  {filteredStaff.map((staff) => {
                    const isCurrentlyAssigned = selectedReq.assigned_staff_name === staff.name
                    const isAssigning = submittingAssignId === staff.id

                    return (
                      <div
                        key={staff.id}
                        style={{
                          display: 'flex',
                          alignItems: 'center',
                          justifyContent: 'space-between',
                          padding: '14px 16px',
                          borderRadius: '10px',
                          border: isCurrentlyAssigned ? '2px solid var(--primary)' : '1px solid #e2e8f0',
                          background: isCurrentlyAssigned ? 'rgba(59, 130, 246, 0.04)' : '#ffffff',
                          transition: 'all 0.15s ease'
                        }}
                      >
                        <div style={{ display: 'flex', alignItems: 'center', gap: '12px' }}>
                          <div style={{
                            width: '42px',
                            height: '42px',
                            borderRadius: '50%',
                            background: staff.status === 'available' ? 'rgba(34, 197, 94, 0.15)' : '#f1f5f9',
                            color: staff.status === 'available' ? '#15803d' : '#475569',
                            display: 'flex',
                            alignItems: 'center',
                            justifyContent: 'center',
                            fontWeight: 600,
                            fontSize: '15px'
                          }}>
                            {staff.name.split(' ').map(n => n[0]).join('').substring(0, 2)}
                          </div>
                          <div>
                            <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                              <span style={{ fontWeight: 600, fontSize: '15px', color: '#0f172a' }}>{staff.name}</span>
                              {getStaffStatusBadge(staff.status)}
                            </div>
                            <div style={{ fontSize: '13px', color: 'var(--primary)', fontWeight: 500, marginTop: '1px' }}>
                              {staff.role}
                            </div>
                            <div style={{ fontSize: '12px', color: '#64748b', marginTop: '2px', display: 'flex', alignItems: 'center', gap: '10px' }}>
                              <span style={{ display: 'flex', alignItems: 'center', gap: '3px' }}>
                                <MapPin size={11} /> {staff.department || 'General'}
                              </span>
                              {staff.contact_number && (
                                <span style={{ display: 'flex', alignItems: 'center', gap: '3px' }}>
                                  <Phone size={11} /> {staff.contact_number}
                                </span>
                              )}
                            </div>
                          </div>
                        </div>

                        <div>
                          {isCurrentlyAssigned ? (
                            <span style={{
                              display: 'inline-flex',
                              alignItems: 'center',
                              gap: '4px',
                              padding: '6px 12px',
                              borderRadius: '6px',
                              background: '#e0e7ff',
                              color: '#3730a3',
                              fontWeight: 600,
                              fontSize: '12px'
                            }}>
                              <Check size={14} /> Currently Assigned
                            </span>
                          ) : (
                            <button
                              className={`btn ${staff.status === 'available' ? 'btn-primary' : 'btn-secondary'} btn-sm`}
                              disabled={isAssigning || staff.status !== 'available'}
                              style={{ minWidth: '100px' }}
                              onClick={() => handleAssignStaff(staff)}
                            >
                              {isAssigning ? 'Assigning...' : staff.status === 'available' ? 'Assign Staff' : 'Busy'}
                            </button>
                          )}
                        </div>
                      </div>
                    )
                  })}
                </div>
              )}
            </div>

            {/* Modal Footer */}
            <div style={{
              padding: '16px 24px',
              borderTop: '1px solid #e2e8f0',
              background: '#f8fafc',
              display: 'flex',
              justifyContent: 'flex-end',
              gap: '10px'
            }}>
              <button className="btn btn-secondary" onClick={closeAssignModal}>
                Cancel
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Request Detail & Live Tracking Modal */}
      {detailModalReq && (
        <div style={{
          position: 'fixed',
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          backgroundColor: 'rgba(15, 23, 42, 0.7)',
          backdropFilter: 'blur(6px)',
          zIndex: 9000,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          padding: '16px'
        }}>
          <div style={{
            background: 'var(--card-bg, #ffffff)',
            borderRadius: '20px',
            width: '100%',
            maxWidth: '680px',
            maxHeight: '90vh',
            display: 'flex',
            flexDirection: 'column',
            boxShadow: '0 25px 60px rgba(0,0,0,0.3)',
            overflow: 'hidden',
            border: '1px solid rgba(226, 232, 240, 0.8)'
          }}>
            {/* Header */}
            <div style={{
              padding: '18px 24px',
              borderBottom: '1px solid var(--border-color, #e2e8f0)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              background: '#f8fafc'
            }}>
              <div>
                <div style={{ fontSize: '11px', fontWeight: 700, color: 'var(--primary)', textTransform: 'uppercase', letterSpacing: '0.6px' }}>
                  Request #{detailModalReq.request_code}
                </div>
                <h3 style={{ margin: '2px 0 0', fontSize: '18px', fontWeight: 700, color: '#0f172a' }}>
                  {detailModalReq.traveler_name}
                </h3>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                {getStatusBadge(detailModalReq.status)}
                <button
                  onClick={() => setDetailModalReq(null)}
                  style={{
                    background: 'none',
                    border: 'none',
                    cursor: 'pointer',
                    padding: '6px',
                    borderRadius: '50%',
                    color: '#64748b',
                    display: 'flex',
                    alignItems: 'center',
                    justifyContent: 'center'
                  }}
                >
                  <X size={20} />
                </button>
              </div>
            </div>

            {/* Modal Body */}
            <div style={{ padding: '20px 24px', flex: 1, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: '16px' }}>
              {/* Quick Info Badges */}
              <div style={{ display: 'flex', gap: '8px', flexWrap: 'wrap', alignItems: 'center' }}>
                {getReachBadge(detailModalReq.preferred_communication)}
                {getUrgencyBadge(detailModalReq.urgency)}
                <span className="badge secondary" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', textTransform: 'capitalize' }}>
                  {getCategoryIcon(detailModalReq.category)} {detailModalReq.category}
                </span>
                {detailModalReq.assigned_staff_name && detailModalReq.assigned_staff_name !== 'Unassigned' && (
                  <span className="badge secondary" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
                    <ShieldCheck size={12} color="var(--primary)" /> Staff: {detailModalReq.assigned_staff_name}
                  </span>
                )}
              </div>

              {/* FindMy Live Location Map */}
              <div>
                <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '8px' }}>
                  <label style={{ fontSize: '12px', fontWeight: 600, color: '#475569', textTransform: 'uppercase', letterSpacing: '0.5px' }}>
                    Traveler Location (FindMy Live View)
                  </label>
                  {detailModalReq.share_location && (
                    <span style={{ fontSize: '11px', color: '#16a34a', fontWeight: 600, display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
                      <Radio size={11} color="#16a34a" /> Live Stream Active
                    </span>
                  )}
                </div>
                <LiveLocationMap
                  sessionId={detailModalReq.id}
                  sessionType="assistance"
                  initialLat={detailModalReq.latitude}
                  initialLng={detailModalReq.longitude}
                  travelerName={detailModalReq.traveler_name}
                  locationZone={detailModalReq.location_zone}
                  height="340px"
                />
              </div>

              {/* Description Box */}
              {detailModalReq.description && (
                <div style={{ background: '#f8fafc', padding: '14px 16px', borderRadius: '10px', border: '1px solid #e2e8f0' }}>
                  <div style={{ fontSize: '11px', fontWeight: 600, color: '#64748b', textTransform: 'uppercase', marginBottom: '4px' }}>
                    Description
                  </div>
                  <div style={{ fontSize: '13px', color: '#334155', lineHeight: 1.5 }}>
                    {detailModalReq.description}
                  </div>
                </div>
              )}
            </div>

            {/* Footer */}
            <div style={{
              padding: '16px 24px',
              borderTop: '1px solid #e2e8f0',
              background: '#f8fafc',
              display: 'flex',
              justifyContent: 'space-between',
              alignItems: 'center'
            }}>
              <div style={{ fontSize: '12px', color: '#64748b' }}>
                Zone: <strong>{detailModalReq.location_zone}</strong>
              </div>
              <div style={{ display: 'flex', gap: '8px' }}>
                {!staffOnly && detailModalReq.status === 'pending' && (
                  <button
                    className="btn btn-primary btn-sm"
                    onClick={() => {
                      const target = detailModalReq
                      setDetailModalReq(null)
                      openAssignModal(target)
                    }}
                  >
                    <UserCheck size={14} /> Assign Staff
                  </button>
                )}
                {staffOnly && detailModalReq.status === 'in_progress' && detailModalReq.preferred_communication !== 'location' && (
                  <button
                    className="btn btn-primary btn-sm"
                    onClick={() => {
                      const id = detailModalReq.id
                      setDetailModalReq(null)
                      navigate('/chat', { state: { requestId: id } })
                    }}
                  >
                    <MessageSquare size={14} /> Open Chat
                  </button>
                )}
                {staffOnly && detailModalReq.status === 'in_progress' && (
                  <button
                    className="btn btn-sm"
                    style={{ display: 'inline-flex', alignItems: 'center', gap: '4px', background: 'var(--success)', color: '#ffffff' }}
                    onClick={() => {
                      const req = detailModalReq
                      setDetailModalReq(null)
                      handleResolveRequest(req)
                    }}
                  >
                    <CheckCircle2 size={14} /> Resolve
                  </button>
                )}
                <button className="btn btn-secondary btn-sm" onClick={() => setDetailModalReq(null)}>
                  Close
                </button>
              </div>
            </div>
          </div>
        </div>
      )}

      {/* Barrier Review & Processing Modal (UC504 / Module 5 & 7) */}
      {isBarrierModalOpen && selectedBarrier && (
        <div style={{
          position: 'fixed',
          top: 0,
          left: 0,
          right: 0,
          bottom: 0,
          background: 'rgba(15, 23, 42, 0.6)',
          backdropFilter: 'blur(4px)',
          zIndex: 1000,
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'center',
          padding: '16px'
        }}>
          <div style={{
            background: 'var(--card-bg, #ffffff)',
            borderRadius: '20px',
            width: '100%',
            maxWidth: '700px',
            maxHeight: '90vh',
            display: 'flex',
            flexDirection: 'column',
            boxShadow: '0 25px 60px rgba(0,0,0,0.3)',
            overflow: 'hidden',
            border: '1px solid rgba(226, 232, 240, 0.8)'
          }}>
            {/* Header */}
            <div style={{
              padding: '18px 24px',
              borderBottom: '1px solid var(--border-color, #e2e8f0)',
              display: 'flex',
              alignItems: 'center',
              justifyContent: 'space-between',
              background: '#f8fafc'
            }}>
              <div>
                <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
                  <span style={{ fontSize: '11px', fontWeight: 700, color: 'var(--primary)', textTransform: 'uppercase', letterSpacing: '0.6px' }}>
                    Barrier Report #{selectedBarrier.report_code || selectedBarrier.id?.slice(0, 8)}
                  </span>
                  {getBarrierStatusBadge(selectedBarrier.status)}
                  {getBarrierSeverityBadge(selectedBarrier.severity)}
                </div>
                <h3 style={{ margin: '4px 0 0', fontSize: '18px', fontWeight: 700, color: '#0f172a' }}>
                  {getBarrierIssueLabel(selectedBarrier.issue_type)}
                </h3>
              </div>
              <button
                onClick={() => setIsBarrierModalOpen(false)}
                style={{
                  background: 'none',
                  border: 'none',
                  cursor: 'pointer',
                  padding: '6px',
                  borderRadius: '50%',
                  color: '#64748b',
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'center'
                }}
              >
                <X size={20} />
              </button>
            </div>

            {/* Scrollable Content */}
            <div style={{ padding: '24px', overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: '20px' }}>
              {/* Meta Info Grid */}
              <div style={{
                display: 'grid',
                gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))',
                gap: '12px',
                padding: '14px 16px',
                background: '#f8fafc',
                borderRadius: '12px',
                border: '1px solid #e2e8f0'
              }}>
                <div>
                  <div style={{ fontSize: '11px', color: '#64748b', fontWeight: 600, textTransform: 'uppercase' }}>Venue</div>
                  <div style={{ fontSize: '13px', fontWeight: 600, color: '#1e293b', marginTop: '2px' }}>
                    {selectedBarrier.venue_name || 'TravelEase Venue'}
                  </div>
                </div>
                <div>
                  <div style={{ fontSize: '11px', color: '#64748b', fontWeight: 600, textTransform: 'uppercase' }}>Area / Location</div>
                  <div style={{ fontSize: '13px', fontWeight: 600, color: '#1e293b', marginTop: '2px', display: 'flex', alignItems: 'center', gap: '4px' }}>
                    <MapPin size={13} color="var(--primary)" />
                    {selectedBarrier.location_zone || 'Not specified'}
                  </div>
                </div>
                <div>
                  <div style={{ fontSize: '11px', color: '#64748b', fontWeight: 600, textTransform: 'uppercase' }}>Reported At</div>
                  <div style={{ fontSize: '13px', color: '#334155', marginTop: '2px' }}>
                    {new Date(selectedBarrier.created_at).toLocaleString()}
                  </div>
                </div>
                <div>
                  <div style={{ fontSize: '11px', color: '#64748b', fontWeight: 600, textTransform: 'uppercase' }}>Reporter</div>
                  <div style={{ fontSize: '12px', color: '#334155', fontWeight: 500, marginTop: '2px' }}>
                    {selectedBarrier.traveler_name || 'Anonymous'}
                    <span style={{ fontSize: '11px', color: selectedBarrier.analytics_consent ? '#16a34a' : '#64748b', display: 'block' }}>
                      {selectedBarrier.analytics_consent ? '✓ Consent for analytics' : 'Standard report'}
                    </span>
                  </div>
                </div>
              </div>

              {/* Description */}
              <div>
                <label style={{ fontSize: '12px', fontWeight: 700, color: '#475569', textTransform: 'uppercase', letterSpacing: '0.5px', display: 'block', marginBottom: '6px' }}>
                  Barrier Description
                </label>
                <div style={{
                  padding: '14px 16px',
                  borderRadius: '10px',
                  background: '#ffffff',
                  border: '1px solid #e2e8f0',
                  fontSize: '14px',
                  color: '#1e293b',
                  lineHeight: 1.5,
                  whiteSpace: 'pre-wrap'
                }}>
                  {selectedBarrier.description || 'No description provided.'}
                </div>
              </div>

              {/* Photo Evidence */}
              <div>
                <label style={{ fontSize: '12px', fontWeight: 700, color: '#475569', textTransform: 'uppercase', letterSpacing: '0.5px', display: 'block', marginBottom: '8px' }}>
                  Photo Evidence
                </label>
                {selectedBarrier.photo_url ? (
                  <div style={{ display: 'flex', flexDirection: 'column', gap: '8px' }}>
                    <div
                      onClick={() => setZoomPhotoUrl(selectedBarrier.photo_url)}
                      style={{
                        position: 'relative',
                        maxWidth: '320px',
                        borderRadius: '12px',
                        overflow: 'hidden',
                        border: '1px solid #cbd5e1',
                        cursor: 'pointer',
                        boxShadow: '0 4px 12px rgba(0,0,0,0.06)'
                      }}
                      title="Click to zoom in"
                    >
                      <img
                        src={selectedBarrier.photo_url}
                        alt="Accessibility barrier evidence"
                        style={{
                          width: '100%',
                          height: '180px',
                          objectFit: 'cover',
                          display: 'block'
                        }}
                      />
                      <div style={{
                        position: 'absolute',
                        bottom: '8px',
                        right: '8px',
                        background: 'rgba(0,0,0,0.7)',
                        color: '#ffffff',
                        padding: '4px 8px',
                        borderRadius: '6px',
                        fontSize: '11px',
                        fontWeight: 600,
                        display: 'flex',
                        alignItems: 'center',
                        gap: '4px'
                      }}>
                        <ZoomIn size={12} /> Click to zoom
                      </div>
                    </div>
                  </div>
                ) : (
                  <div style={{
                    padding: '14px 16px',
                    borderRadius: '10px',
                    background: '#f8fafc',
                    border: '1px dashed #cbd5e1',
                    fontSize: '13px',
                    color: '#64748b',
                    display: 'flex',
                    alignItems: 'center',
                    gap: '8px'
                  }}>
                    <ImageIcon size={16} /> No photo was uploaded with this report.
                  </div>
                )}
              </div>

              {/* Review & Status Processing (UC504) */}
              <div style={{
                borderTop: '1px solid #e2e8f0',
                paddingTop: '18px',
                display: 'flex',
                flexDirection: 'column',
                gap: '14px'
              }}>
                <h4 style={{ margin: 0, fontSize: '14px', fontWeight: 700, color: '#0f172a' }}>
                  Review & Processing (Visible to Traveler in History)
                </h4>

                <div>
                  <label style={{ fontSize: '12px', fontWeight: 600, color: '#475569', display: 'block', marginBottom: '6px' }}>
                    Update Status
                  </label>
                  <select
                    className="form-control"
                    value={barrierNewStatus}
                    onChange={(e) => setBarrierNewStatus(e.target.value)}
                    style={{
                      width: '100%',
                      padding: '10px 14px',
                      borderRadius: '8px',
                      border: '1px solid #cbd5e1',
                      fontSize: '14px',
                      background: '#ffffff'
                    }}
                  >
                    <option value="reported">Reported (Pending Review)</option>
                    <option value="investigating">Investigating (Staff dispatched / under active review)</option>
                    <option value="resolved">Resolved (Barrier addressed / cleared)</option>
                  </select>
                </div>

                <div>
                  <label style={{ fontSize: '12px', fontWeight: 600, color: '#475569', display: 'block', marginBottom: '6px' }}>
                    Processing Notes & Resolution Details
                  </label>
                  <div style={{ fontSize: '12px', color: '#64748b', marginBottom: '6px' }}>
                    Provide details on the investigation, scheduled fix, or workaround. This will be shown directly to the traveler under their report's <strong>Processing Result</strong> on the mobile app.
                  </div>
                  <textarea
                    className="form-control"
                    rows={4}
                    value={barrierNewNotes}
                    onChange={(e) => setBarrierNewNotes(e.target.value)}
                    placeholder="e.g., Facility team dispatched at 14:15. Obstacle removed from tactile paving pathway. Access restored."
                    style={{
                      width: '100%',
                      padding: '10px 14px',
                      borderRadius: '8px',
                      border: '1px solid #cbd5e1',
                      fontSize: '14px',
                      lineHeight: 1.5,
                      resize: 'vertical'
                    }}
                  />
                </div>
              </div>
            </div>

            {/* Footer */}
            <div style={{
              padding: '16px 24px',
              borderTop: '1px solid #e2e8f0',
              background: '#f8fafc',
              display: 'flex',
              justifyContent: 'flex-end',
              alignItems: 'center',
              gap: '10px'
            }}>
              <button
                type="button"
                className="btn btn-secondary btn-sm"
                onClick={() => setIsBarrierModalOpen(false)}
                disabled={savingBarrier}
              >
                Cancel
              </button>
              <button
                type="button"
                className="btn btn-primary btn-sm"
                onClick={handleSaveBarrier}
                disabled={savingBarrier}
                style={{ display: 'flex', alignItems: 'center', gap: '6px' }}
              >
                {savingBarrier ? (
                  'Saving...'
                ) : (
                  <>
                    <Check size={14} /> Save Processing Results
                  </>
                )}
              </button>
            </div>
          </div>
        </div>
      )}

      {/* Photo Fullscreen Zoom Modal */}
      {zoomPhotoUrl && (
        <div
          onClick={() => setZoomPhotoUrl(null)}
          style={{
            position: 'fixed',
            top: 0,
            left: 0,
            right: 0,
            bottom: 0,
            background: 'rgba(0, 0, 0, 0.85)',
            backdropFilter: 'blur(6px)',
            zIndex: 1200,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            padding: '24px'
          }}
        >
          <div
            onClick={(e) => e.stopPropagation()}
            style={{
              position: 'relative',
              maxWidth: '90vw',
              maxHeight: '90vh',
              display: 'flex',
              flexDirection: 'column',
              alignItems: 'center'
            }}
          >
            <button
              onClick={() => setZoomPhotoUrl(null)}
              style={{
                position: 'absolute',
                top: '-40px',
                right: '0',
                background: 'rgba(255, 255, 255, 0.2)',
                border: 'none',
                color: '#ffffff',
                width: '32px',
                height: '32px',
                borderRadius: '50%',
                cursor: 'pointer',
                display: 'flex',
                alignItems: 'center',
                justifyContent: 'center'
              }}
              title="Close zoom"
            >
              <X size={20} />
            </button>
            <img
              src={zoomPhotoUrl}
              alt="Barrier zoom preview"
              style={{
                maxWidth: '90vw',
                maxHeight: '85vh',
                objectFit: 'contain',
                borderRadius: '12px',
                boxShadow: '0 20px 50px rgba(0,0,0,0.5)',
                border: '1px solid rgba(255,255,255,0.2)'
              }}
            />
          </div>
        </div>
      )}
    </div>
  )
}
