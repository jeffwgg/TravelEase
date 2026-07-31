import React, { useState } from 'react'
import { Link } from 'react-router-dom'

const initialLines = [
  { id: 1, name: 'A Series', serviceArea: 'General Ticketing', current: 'A-042', upcoming: 'A-043', counter: 'Counter #1 — Main Service Desk', status: 'Active', waiting: 24, deafTravelers: 3, wait: '3.5 mins' },
  { id: 2, name: 'B Series', serviceArea: 'Accessibility Services', current: 'B-018', upcoming: 'B-019', counter: 'Counter #2 — Special Assistance', status: 'Active', waiting: 6, deafTravelers: 4, wait: '5.0 mins' },
]

export default function QueueUpdatePage() {
  const [lines, setLines] = useState(initialLines)
  const [editing, setEditing] = useState(null)
  const [actionNumber, setActionNumber] = useState('')
  const [numberAction, setNumberAction] = useState(null)

  const openManage = (line) => {
    setEditing({ ...line })
    setActionNumber(line.current)
    setNumberAction(null)
  }
  const saveLine = () => {
    setLines((items) => items.map((item) => item.id === editing.id ? editing : item))
    setEditing(null)
  }
  const markNumber = (status) => setNumberAction({ number: actionNumber, status })

  return (
    <div>
      <div className="page-header">
        <div>
          <h2>Queue Management Console</h2>
          <div className="header-subtitle">Create queue lines, update serving information and notify travelers visually.</div>
        </div>
        <Link to="/queue/add" className="btn btn-primary">+ Add Queue Line</Link>
      </div>

      <div className="page-body">
        <div className="grid-3" style={{ marginBottom: '24px' }}>
          {lines.map((line) => (
            <div key={line.id} className="card" style={{ background: 'linear-gradient(135deg, var(--dark-bg), var(--dark-surface))', color: '#fff' }}>
              <div style={{ fontSize: '13px', color: 'rgba(255,255,255,0.6)' }}>{line.counter}</div>
              <div style={{ fontSize: '56px', fontWeight: '800', color: 'var(--primary-light)', margin: '16px 0' }}>{line.current}</div>
              <div style={{ display: 'flex', gap: '8px', marginBottom: '16px', flexWrap: 'wrap' }}>
                <button className="btn btn-primary" style={{ flex: 1, justifyContent: 'center' }}>Call Next ({line.upcoming})</button>
                <button className="btn btn-outline btn-sm" style={{ color: '#fff', borderColor: 'rgba(255,255,255,0.35)' }} onClick={() => openManage(line)}>Manage</button>
              </div>
              <div style={{ fontSize: '12px', color: 'rgba(255,255,255,0.5)', textAlign: 'center' }}>
                {line.serviceArea} • {line.waiting} waiting
              </div>
            </div>
          ))}

          <div className="card">
            <div className="card-header"><h3>Direct Call Number</h3></div>
            <div className="form-group">
              <label>Select Queue Line</label>
              <select className="input">{lines.map((line) => <option key={line.id}>{line.name} — {line.serviceArea}</option>)}</select>
            </div>
            <div className="form-group">
              <label>Number to Call</label>
              <input type="text" className="input" defaultValue="A-047" />
            </div>
            <button className="btn btn-primary" style={{ width: '100%', justifyContent: 'center' }}>Notify Traveler Now</button>
          </div>
        </div>

        <div className="card">
          <div className="card-header"><h3>Active Queue Lines</h3></div>
          <table className="data-table">
            <thead><tr><th>Queue Line</th><th>Current</th><th>Upcoming</th><th>Counter</th><th>Status</th><th>Action</th></tr></thead>
            <tbody>
              {lines.map((line) => (
                <tr key={line.id}>
                  <td><strong>{line.name}</strong><br/><span style={{ fontSize: 12, color: 'var(--text-secondary)' }}>{line.serviceArea}</span></td>
                  <td><span className="badge primary">{line.current}</span></td>
                  <td>{line.upcoming}</td>
                  <td>{line.counter}</td>
                  <td><span className={`badge ${line.status === 'Active' ? 'success' : line.status === 'Paused' ? 'secondary' : 'muted'}`}>{line.status}</span></td>
                  <td><button className="btn btn-outline btn-sm" onClick={() => openManage(line)}>Manage</button></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>

      {editing && (
        <div className="modal-backdrop" role="presentation" onMouseDown={() => setEditing(null)}>
          <div className="modal-card" role="dialog" aria-modal="true" aria-labelledby="manage-queue-title" onMouseDown={(event) => event.stopPropagation()}>
            <div className="card-header">
              <div><h3 id="manage-queue-title">Manage {editing.name}</h3><div className="header-subtitle">View or edit the current queue information.</div></div>
              <button className="modal-close" onClick={() => setEditing(null)} aria-label="Close">×</button>
            </div>
            <div className="form-grid">
              <div className="form-group"><label>Current Number</label><input className="input" value={editing.current} onChange={(e) => setEditing({ ...editing, current: e.target.value })} /></div>
              <div className="form-group"><label>Upcoming Number</label><input className="input" value={editing.upcoming} onChange={(e) => setEditing({ ...editing, upcoming: e.target.value })} /></div>
              <div className="form-group"><label>Counter</label><input className="input" value={editing.counter} onChange={(e) => setEditing({ ...editing, counter: e.target.value })} /></div>
              <div className="form-group"><label>Service Area</label><input className="input" value={editing.serviceArea} onChange={(e) => setEditing({ ...editing, serviceArea: e.target.value })} /></div>
              <div className="form-group"><label>Queue Line Status</label><select className="input" value={editing.status} onChange={(e) => setEditing({ ...editing, status: e.target.value })}><option>Active</option><option>Paused</option><option>Closed</option></select></div>
            </div>
            <div className="queue-status-actions">
              <div className="queue-number-action-field">
                <label>Queue Number Action</label>
                <input className="input" value={actionNumber} onChange={(event) => { setActionNumber(event.target.value); setNumberAction(null) }} placeholder="e.g. A-047" />
              </div>
              <button className="btn btn-outline btn-sm" disabled={!actionNumber.trim()} onClick={() => markNumber('Missed')}>Mark Number Missed</button>
              <button className="btn btn-danger btn-sm" disabled={!actionNumber.trim()} onClick={() => markNumber('Cancelled')}>Cancel Number</button>
              {numberAction && <div className={`queue-number-result ${numberAction.status.toLowerCase()}`}>Queue number <strong>{numberAction.number}</strong> marked as {numberAction.status.toLowerCase()}.</div>}
            </div>
            <div className="modal-actions"><button className="btn btn-outline" onClick={() => setEditing(null)}>Cancel</button><button className="btn btn-primary" onClick={saveLine}>Save Queue Information</button></div>
          </div>
        </div>
      )}
    </div>
  )
}
