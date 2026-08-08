import React, { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { 
  Clock, 
  MessageSquare, 
  CheckCircle2, 
  AlertCircle, 
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
  ShieldCheck
} from 'lucide-react'
import { assistanceRepository } from '../repositories/assistanceRepository'

export default function AssistanceRequestPage() {
  const navigate = useNavigate()
  const [requests, setRequests] = useState([])
  const [loading, setLoading] = useState(true)
  const [statusFilter, setStatusFilter] = useState('All Statuses')
  const [searchQuery, setSearchQuery] = useState('')

  // Modal State
  const [isModalOpen, setIsModalOpen] = useState(false)
  const [selectedReq, setSelectedReq] = useState(null)
  const [staffList, setStaffList] = useState([])
  const [loadingStaff, setLoadingStaff] = useState(false)
  const [staffSearch, setStaffSearch] = useState('')
  const [staffFilterAvailable, setStaffFilterAvailable] = useState(true)
  const [submittingAssignId, setSubmittingAssignId] = useState(null)
  const [toastMessage, setToastMessage] = useState(null)

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

  async function openAssignModal(req) {
    setSelectedReq(req)
    setIsModalOpen(true)
    setStaffSearch('')
    setLoadingStaff(true)
    const staffData = await assistanceRepository.getInstitutionStaff()
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

  function showToast(msg) {
    setToastMessage(msg)
    setTimeout(() => {
      setToastMessage(null)
    }, 4000)
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
                    <td>
                      {req.assigned_staff_name && req.assigned_staff_name !== 'Unassigned' ? (
                        <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                          <ShieldCheck size={14} color="var(--primary)" />
                          <span style={{ fontWeight: 500 }}>{req.assigned_staff_name}</span>
                        </div>
                      ) : (
                        <span style={{ color: 'var(--text-muted)', fontStyle: 'italic' }}>Unassigned</span>
                      )}
                    </td>
                    <td>{getStatusBadge(req.status)}</td>
                    <td>
                      {req.status === 'pending' ? (
                        <button
                          className="btn btn-primary btn-sm"
                          style={{ display: 'inline-flex', alignItems: 'center', gap: '6px' }}
                          onClick={() => openAssignModal(req)}
                        >
                          <UserCheck size={14} /> Assign Staff
                        </button>
                      ) : req.status === 'in_progress' ? (
                        <div style={{ display: 'flex', gap: '6px' }}>
                          <button
                            className="btn btn-secondary btn-sm"
                            onClick={() => openAssignModal(req)}
                          >
                            Reassign
                          </button>
                          <button
                            className="btn btn-primary btn-sm"
                            style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}
                            onClick={() => navigate('/chat')}
                          >
                            <MessageSquare size={14} /> Open Chat
                          </button>
                        </div>
                      ) : (
                        <button
                          className="btn btn-secondary btn-sm"
                          onClick={() => navigate('/chat')}
                        >
                          View Chat
                        </button>
                      )}
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
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
                <div style={{ fontSize: '13px', color: '#475569', marginTop: '2px', display: 'flex', alignItems: 'center', gap: '8px' }}>
                  <span>Location: <strong>{selectedReq.location_zone}</strong></span>
                  <span>•</span>
                  <span style={{ textTransform: 'capitalize' }}>Category: <strong>{selectedReq.category}</strong></span>
                </div>
              </div>
              <div>
                {getUrgencyBadge(selectedReq.urgency)}
              </div>
            </div>

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
                  {staffFilterAvailable ? '✓ Available Only' : 'Show All Staff'}
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
                              <span>📍 {staff.department || 'General'}</span>
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
                              disabled={isAssigning}
                              style={{ minWidth: '100px' }}
                              onClick={() => handleAssignStaff(staff)}
                            >
                              {isAssigning ? 'Assigning...' : staff.status === 'available' ? 'Assign Staff' : 'Assign (Busy)'}
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
    </div>
  )
}
