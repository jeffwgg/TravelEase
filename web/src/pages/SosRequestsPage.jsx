import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { AlertTriangle, CheckCircle2, RefreshCw, ShieldCheck, X } from 'lucide-react'
import { useAuth } from '../context/AuthContext'
import { availableSosStaff, sosRequestRepository } from '../repositories/sosRequestRepository'
import { staffRepository } from '../repositories/staffRepository'
import SosRequestCard, { formatCoordinate } from '../components/SosRequestCard'
import LiveLocationMap from '../components/LiveLocationMap'
import StaffSosOverview from '../components/StaffSosOverview'

export default function SosRequestsPage() {
  const { staffContext } = useAuth()
  const [searchParams, setSearchParams] = useSearchParams()
  const taskId = searchParams.get('task')
  const focusedTask = useRef(null)
  const staffOnly = staffContext?.role === 'staff'
  const isManager = staffContext?.role === 'manager'
  const assignedStaffId = staffOnly ? staffContext?.staff?.id : null
  const institutionId = staffContext?.institution_id || staffContext?.institutions?.id
  const [staff, setStaff] = useState([])
  const [ownStaff, setOwnStaff] = useState(null)
  const [requests, setRequests] = useState([])
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)
  const [busyId, setBusyId] = useState('')
  const [error, setError] = useState('')
  const [selectedLocation, setSelectedLocation] = useState(null)

  const load = useCallback(async ({ quiet = false } = {}) => {
    if (!institutionId || (!isManager && !assignedStaffId)) {
      setRequests([])
      setStaff([])
      setLoading(false)
      return
    }
    if (quiet) setRefreshing(true)
    else setLoading(true)
    setError('')
    try {
      const [nextRequests, nextStaff, nextOwnStaff] = await Promise.all([
        sosRequestRepository.listForInstitution(institutionId, assignedStaffId),
        isManager ? staffRepository.list({ institution_id: institutionId }) : Promise.resolve([]),
        assignedStaffId ? staffRepository.getOwn() : Promise.resolve(null),
      ])
      setRequests(nextRequests)
      setOwnStaff(nextOwnStaff)
      setStaff(availableSosStaff(nextStaff, nextRequests, institutionId))
    } catch (loadError) {
      setError(friendlyError(loadError))
    } finally {
      setLoading(false)
      setRefreshing(false)
    }
  }, [institutionId, isManager, assignedStaffId])

  useEffect(() => {
    load()
    if (!institutionId || (!isManager && !assignedStaffId)) return undefined
    const unsubscribe = sosRequestRepository.subscribe(institutionId, () => load({ quiet: true }), assignedStaffId)
    // Refresh availability even when another workflow changes a staff record.
    const timer = window.setInterval(() => load({ quiet: true }), 10000)
    return () => { unsubscribe(); window.clearInterval(timer) }
  }, [institutionId, isManager, assignedStaffId, load])

  const visibleRequests = useMemo(
    () => requests.filter((request) => request.institution_id === institutionId
      && (isManager || (assignedStaffId && request.assigned_staff_id === assignedStaffId))),
    [requests, institutionId, isManager, assignedStaffId],
  )
  const activeRequests = useMemo(
    () => visibleRequests.filter((request) => request.status !== 'resolved'),
    [visibleRequests],
  )
  const resolvedRequests = useMemo(
    () => visibleRequests.filter((request) => request.status === 'resolved'),
    [visibleRequests],
  )
  const locationRequest = visibleRequests.find((request) => request.id === selectedLocation?.id)
  const openedTask = staffOnly ? visibleRequests.find((request) => request.id === taskId) : null
  const closeTask = () => setSearchParams(current => {
    const next = new URLSearchParams(current)
    next.delete('task')
    return next
  })
  useEffect(() => {
    if (loading || !taskId || focusedTask.current === taskId) return
    const task = document.getElementById(`sos-task-${taskId}`)
    if (task) {
      task.scrollIntoView({ block: 'center', behavior: 'smooth' })
      task.focus({ preventScroll: true })
      focusedTask.current = taskId
    }
  }, [taskId, loading, visibleRequests])

  const updateStatus = async (request, status, staffId = null) => {
    setBusyId(request.id)
    setError('')
    try {
      const updated = await sosRequestRepository.updateStatus(
        institutionId,
        request.id,
        request.status,
        status,
        staffId,
      )
      setRequests((current) => current.map((item) => item.id === updated.id ? updated : item))
      if (status === 'assigned') setStaff((current) => current.filter((member) => member.id !== staffId))
      await load({ quiet: true })
    } catch (updateError) {
      await load({ quiet: true })
      setError(friendlyError(updateError))
    } finally {
      setBusyId('')
    }
  }

  const resolveRequest = (request) => {
    const confirmed = window.confirm(
      'Resolve this SOS request?\n\nThis marks the emergency as completed.',
    )
    if (confirmed) updateStatus(request, 'resolved')
  }

  return <div className="page sos-page">
    <div className="page-header sos-page-header">
      <div>
        <h1>{staffOnly ? 'My SOS Tasks' : 'Institution SOS Management'}</h1>
        <p>{staffOnly ? 'View your assigned traveller, follow their location, and update your response.' : 'Acknowledge emergencies, assign free staff, and monitor your institution.'}</p>
      </div>
      <button className="btn btn-outline" onClick={() => load({ quiet: true })} disabled={refreshing}>
        <RefreshCw size={16} className={refreshing ? 'spin' : ''} />
        {refreshing ? 'Refreshing…' : 'Refresh'}
      </button>
    </div>

    {error && <div className="form-alert error" role="alert">{error}</div>}
    {loading ? <div className="card sos-empty">Loading SOS requests…</div> : <>
      {staffOnly ? <div className="sos-staff-overview"><StaffSosOverview tasks={visibleRequests} staff={ownStaff} /></div> : <div className="sos-overview-strip" aria-label="SOS overview"><span><strong>{activeRequests.length}</strong> Active</span><span><strong>{activeRequests.filter(request => request.status === 'en_route').length}</strong> On The Way</span><span><strong>{resolvedRequests.length}</strong> Resolved</span></div>}
      {isManager && <><section className="sos-section" aria-labelledby="active-sos-title">
        <div className="sos-section-heading emergency">
          <div>
            <span className="sos-heading-icon"><AlertTriangle size={20} /></span>
            <div><h2 id="active-sos-title">{staffOnly ? 'My Active Tasks' : 'Active SOS Requests'}</h2><p>{staffOnly ? 'Only emergencies assigned to your account appear here.' : 'Ongoing emergencies awaiting or receiving assistance.'}</p></div>
          </div>
          <span className="sos-count">{activeRequests.length}</span>
        </div>
        {activeRequests.length === 0
          ? <div className="card sos-empty"><ShieldCheck size={30} /><strong>{staffOnly ? 'No active assigned tasks' : 'No active SOS requests'}</strong><span>{staffOnly ? 'Tasks will appear when your manager assigns you.' : 'New institution-linked alerts will appear here automatically.'}</span></div>
          : <div className="sos-grid">{activeRequests.map((request) =>
            <SosRequestCard
              key={request.id}
              request={request}
              focused={request.id === taskId}
              isManager={isManager}
              canRespond={staffOnly && request.assigned_staff_id === assignedStaffId}
              busy={busyId === request.id}
              onView={() => setSelectedLocation(request)}
              onAcknowledge={() => updateStatus(request, 'acknowledged')}
              staff={staff}
              onAssign={(staffId) => updateStatus(request, 'assigned', staffId)}
              onEnRoute={() => updateStatus(request, 'en_route')}
              onResolve={() => resolveRequest(request)}
            />,
          )}</div>}
      </section>

      <section className="sos-section" aria-labelledby="resolved-sos-title">
        <div className="sos-section-heading">
          <div>
            <span className="sos-heading-icon resolved"><CheckCircle2 size={20} /></span>
            <div><h2 id="resolved-sos-title">Resolved Requests</h2><p>Completed SOS requests, newest first.</p></div>
          </div>
          <span className="sos-count muted">{resolvedRequests.length}</span>
        </div>
        {resolvedRequests.length === 0
          ? <div className="card sos-empty compact"><span>No resolved SOS requests yet.</span></div>
          : <div className="sos-grid">{resolvedRequests.map((request) =>
            <SosRequestCard
              key={request.id}
              request={request}
              busy={false}
              focused={request.id === taskId}
              onView={() => setSelectedLocation(request)}
            />,
          )}</div>}
      </section></>}
    </>}

    {openedTask && <div className="sos-map-backdrop" onMouseDown={event => { if (event.target === event.currentTarget) closeTask() }} onKeyDown={event => { if (event.key === 'Escape') closeTask() }}>
      <div className="sos-map-dialog" role="dialog" aria-modal="true" aria-labelledby="staff-task-title">
        <div className="sos-map-header"><h2 id="staff-task-title">Emergency task</h2><button className="icon-button" onClick={closeTask} aria-label="Close task"><X size={20} /></button></div>
        <SosRequestCard request={openedTask} busy={busyId === openedTask.id}
          canRespond={openedTask.assigned_staff_id === assignedStaffId}
          onView={() => setSelectedLocation(openedTask)}
          onEnRoute={() => updateStatus(openedTask, 'en_route')}
          onResolve={() => resolveRequest(openedTask)} />
      </div>
    </div>}

    {locationRequest && <LocationModal request={locationRequest} onClose={() => setSelectedLocation(null)} />}
  </div>
}

function LocationModal({ request, onClose }) {
  return <div className="sos-map-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose() }}>
    <div className="sos-map-dialog" role="dialog" aria-modal="true" aria-labelledby="sos-location-title" style={{ maxWidth: '680px', width: '100%', borderRadius: '20px', overflow: 'hidden' }}>
      <div className="sos-map-header" style={{ padding: '18px 24px' }}>
        <div>
          <h2 id="sos-location-title">Emergency Live Tracking — {request.traveller?.full_name || 'Traveller'}</h2>
          <p>Initial: {formatCoordinate(request.latitude)}, {formatCoordinate(request.longitude)}</p>
        </div>
        <button className="icon-button" onClick={onClose} aria-label="Close location map"><X size={20} /></button>
      </div>
      <div style={{ padding: '0 24px 20px' }}>
        <LiveLocationMap
          sessionId={request.id}
          sessionType="sos"
          initialLat={request.latitude}
          initialLng={request.longitude}
          travelerName={request.traveller?.full_name || 'Traveller'}
          height="400px"
        />
      </div>
      <div className="sos-map-actions" style={{ padding: '14px 24px', borderTop: '1px solid var(--divider)' }}>
        <button className="btn btn-outline" onClick={onClose}>Close</button>
      </div>
    </div>
  </div>
}

function friendlyError(error) {
  const message = String(error?.message || '')
  const lower = message.toLowerCase()
  if (lower.includes('sos_requests') && lower.includes('schema cache')) return 'SOS requests are not configured yet. Apply migrations 011 and 012 in Supabase.'
  if (lower.includes('permission') || lower.includes('row-level security')) return 'Your account is not allowed to perform this SOS action. Refresh to check your current assignment.'
  if (error?.code === 'PGRST116') return 'This SOS request changed or is no longer accessible. Refresh and try again.'
  return message || 'Unable to load SOS requests.'
}
