import { ArrowUpRight, CheckCircle2, Clock3, MapPin, ShieldCheck, Siren } from 'lucide-react'
import { Link } from 'react-router-dom'
import { useState } from 'react'

export const taskStatusLabel = status => ({ assigned: 'Assigned', en_route: 'On The Way', resolved: 'Resolved' }[status] || status)
export const staffStatusLabel = staff => !staff ? 'Unavailable' : !staff.active ? 'Inactive' : staff.status === 'free' ? 'Free' : 'Assigned / Busy'

export default function StaffSosOverview({ tasks, staff }) {
  const [showAllCompleted, setShowAllCompleted] = useState(false)
  const active = tasks.filter(task => ['assigned', 'en_route'].includes(task.status))
  const resolved = tasks.filter(task => task.status === 'resolved')
    .sort((a, b) => new Date(b.resolved_at || b.triggered_at) - new Date(a.resolved_at || a.triggered_at))
  return <>
    <div className="staff-metrics">
      <div><Siren size={18} /><strong>{active.length}</strong><span>Active SOS tasks</span></div>
      <div><Clock3 size={18} /><strong>{active.filter(task => task.status === 'en_route').length}</strong><span>On The Way</span></div>
      <div><CheckCircle2 size={18} /><strong>{resolved.length}</strong><span>Resolved</span></div>
      <div><ShieldCheck size={18} /><strong className="staff-availability">{staffStatusLabel(staff)}</strong><span>Current availability</span></div>
    </div>
    <section className="staff-current-task card" aria-labelledby="current-task-title">
      <div className="staff-section-heading"><div><span className="staff-eyebrow">YOUR RESPONSE DESK</span><h2 id="current-task-title">Current emergency task</h2></div><Siren size={22} /></div>
      {active.length ? active.map(task => <div key={task.id} className="staff-active-task">
        <div><span className={`sos-status ${task.status}`}>{taskStatusLabel(task.status)}</span><h3>{task.traveller?.full_name || 'Traveller'}</h3>
          <p><MapPin size={14} /> {task.service_area?.name || 'Location available in task'}</p>
          <small>{task.status === 'assigned' ? 'Your next step: mark On The Way when you start responding.' : 'Your next step: mark Resolved after assisting the traveller.'}</small></div>
        <Link className="btn btn-primary btn-sm" to={`/sos?task=${encodeURIComponent(task.id)}`}>Open task <ArrowUpRight size={15} /></Link>
      </div>) : <div className="staff-no-task"><ShieldCheck size={28} /><div><h3>No active emergency task</h3><p>Your next assignment will appear here automatically.</p></div></div>}
    </section>
    <section className="card staff-recent" aria-labelledby="recent-tasks-title">
      <div className="staff-section-heading"><h2 id="recent-tasks-title">{showAllCompleted ? 'Completed tasks' : 'Recent completed tasks'}</h2>{resolved.length > 5 && <button className="btn btn-outline btn-sm" onClick={() => setShowAllCompleted(value => !value)}>{showAllCompleted ? 'Show recent' : 'View all completed'}</button>}</div>
      {resolved.length ? <ul className="staff-task-list">{(showAllCompleted ? resolved : resolved.slice(0, 5)).map(task => <li key={task.id}>
        <div><strong>{task.traveller?.full_name?.trim() || 'Name unavailable'}</strong><small>{task.service_area?.name || 'Service area'} · {new Date(task.resolved_at || task.triggered_at).toLocaleString()}</small></div>
        <span className="sos-status resolved">Resolved</span><Link to={`/sos?task=${encodeURIComponent(task.id)}`} aria-label={`View completed task for ${task.traveller?.full_name?.trim() || 'unnamed traveller'}`}><ArrowUpRight size={17} /></Link>
      </li>)}</ul> : <p className="staff-muted">Your completed SOS tasks will appear here.</p>}
    </section>
  </>
}
