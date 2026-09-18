import { useState } from 'react'
import { Clock3, MapPin, Users, Search, Phone, CheckCircle2, ArrowRight } from 'lucide-react'

export default function SosRequestCard({ request, busy, onView, onAcknowledge, onResolve, staff = [], onAssign, onEnRoute, isManager = false, canRespond = false, focused = false }) {
  const [staffId, setStaffId] = useState('')
  const [search, setSearch] = useState('')
  const selectedStaff = staff.find((member) => member.id === staffId)
  const visibleStaff = staff.filter((member) => `${member.name} ${member.role}`.toLowerCase().includes(search.toLowerCase()))
  const stages = ['sent', 'acknowledged', 'assigned', 'en_route', 'resolved']
  const isResolved = request.status === 'resolved'
  const travellerName = request.traveller?.full_name || 'Traveller'
  const serviceAreaName = request.service_area?.name || 'Unknown Service Area'
  return <article id={`sos-task-${request.id}`} tabIndex={-1} className={`card sos-request-card ${isResolved ? 'resolved' : 'active'} ${focused ? 'focused' : ''}`}>
    <div className="sos-request-topline">
      <div><strong>{travellerName}</strong><span><Clock3 size={14} /> {formatTime(request.triggered_at)}</span></div>
      <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
        <span className={`sos-status ${request.status}`}>{statusLabel(request.status)}</span>
      </div>
    </div>
    {!isResolved && <ol className="sos-workflow" aria-label="Emergency response progress">
      {stages.map((stage, index) => <li key={stage} className={stage === request.status ? 'current' : ''} aria-current={stage === request.status ? 'step' : undefined}>
        <span>{index + 1}</span><small>{statusLabel(stage)}</small>
      </li>)}
    </ol>}
    <dl className="sos-request-details">
      <div><dt>Service Area</dt><dd>{serviceAreaName}</dd></div>
      <div><dt>Assigned staff</dt><dd>{request.assigned_staff?.name || 'Not assigned'}</dd></div>
      {request.assigned_staff?.contact_number && <div><dt>Staff contact</dt><dd>{request.assigned_staff.contact_number}</dd></div>}
      <div><dt>Trigger Coordinates</dt><dd>{formatCoordinate(request.latitude)}, {formatCoordinate(request.longitude)}</dd></div>
    </dl>
    {isManager && request.status === 'acknowledged' && <details className="sos-assignment" aria-label="Assign a responder">
      <summary>Assign Staff · {staff.length} available</summary>
      <div className="sos-assignment-heading"><span className="sos-team-icon"><Users size={21} /></span><div><h3>Assign Staff</h3><p>Choose an active, free responder from your institution.</p></div></div>
      <label className="sos-staff-search"><Search size={17} /><input aria-label="Search responders" placeholder="Search by name or role…" value={search} onChange={(event) => setSearch(event.target.value)} /></label>
      <div className="sos-staff-options" role="group" aria-label="Available responders">
        {visibleStaff.map((member) => <button type="button" key={member.id} className={`sos-staff-option ${staffId === member.id ? 'selected' : ''}`} aria-pressed={staffId === member.id} disabled={busy} onClick={() => setStaffId(member.id)}>
          <span className="sos-staff-avatar">{member.name?.split(/\s+/).map((part) => part[0]).slice(0, 2).join('') || '?'}</span>
          <span className="sos-staff-info"><strong>{member.name}</strong><small>{member.status === 'free' || member.status === 'available' ? 'Available' : member.status === 'assigned' || member.status === 'busy' ? 'Currently assigned' : 'Availability not recorded'}</small>{member.contact_number && <small><Phone size={12} /> {member.contact_number}</small>}</span>
          <span className="sos-staff-radio">{staffId === member.id && <CheckCircle2 size={20} />}</span>
        </button>)}
        {visibleStaff.length === 0 && <p className="sos-staff-empty">{staff.length ? 'No matching staff. Try another name.' : 'No free staff available. A responder becomes available when their task is resolved.'}</p>}
      </div>
      <div className="sos-assignment-footer"><span>{selectedStaff ? `${selectedStaff.name} selected` : 'Select a responder to continue'}</span><button className="btn btn-primary btn-sm" disabled={busy || !selectedStaff} onClick={() => onAssign(staffId)}>{busy ? 'Assigning…' : 'Confirm assignment'}<ArrowRight size={15} /></button></div>
    </details>}
    <div className="sos-request-actions">
      <button className="btn btn-outline btn-sm" onClick={onView}><MapPin size={14} /> View Location</button>
      {isManager && request.status === 'sent' && <button className="btn btn-primary btn-sm" disabled={busy} onClick={onAcknowledge}>{busy ? 'Acknowledging…' : 'Acknowledge'}</button>}
      {isManager && ['assigned', 'en_route'].includes(request.status) && <span className="sos-monitor-note">Monitoring · Your assigned responder will update progress.</span>}
      {canRespond && request.status === 'assigned' && <button className="btn btn-primary btn-sm" disabled={busy} onClick={onEnRoute}>{busy ? 'Updating…' : 'Mark On The Way'}</button>}
      {canRespond && request.status === 'en_route' && <button className="btn btn-primary btn-sm" disabled={busy} onClick={onResolve}>{busy ? 'Updating…' : 'Mark Resolved'}</button>}
    </div>
  </article>
}

function statusLabel(status) {
  if (status === 'assigned') return 'Assigned'
  if (status === 'en_route') return 'On The Way'
  if (status === 'acknowledged') return 'Acknowledged'
  if (status === 'resolved') return 'Resolved'
  return 'Sent'
}

function formatTime(value) {
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? 'Unknown time' : date.toLocaleString()
}

export function formatCoordinate(value) {
  const coordinate = Number(value)
  return Number.isFinite(coordinate) ? coordinate.toFixed(6) : 'Unavailable'
}
