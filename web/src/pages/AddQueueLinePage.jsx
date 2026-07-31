import React from 'react'
import { Link } from 'react-router-dom'

export default function AddQueueLinePage() {
  return (
    <div>
      <div className="page-header">
        <div><h2>Add Queue Line</h2><div className="header-subtitle">Set up a service queue and its initial serving information.</div></div>
        <Link to="/queue" className="btn btn-outline">Back to Queue Management</Link>
      </div>
      <div className="page-body">
        <div className="card" style={{ maxWidth: 820 }}>
          <div className="form-grid">
            <div className="form-group"><label>Queue Line Name</label><input className="input" placeholder="e.g. A Series" /></div>
            <div className="form-group"><label>Service Area</label><input className="input" placeholder="e.g. General Ticketing" /></div>
            <div className="form-group"><label>Counter</label><input className="input" placeholder="e.g. Counter #1 — Main Service Desk" /></div>
            <div className="form-group"><label>Queue Prefix</label><input className="input" placeholder="e.g. A" maxLength={4} /></div>
            <div className="form-group"><label>Current Number</label><input className="input" placeholder="e.g. A-001" /></div>
            <div className="form-group"><label>Upcoming Number</label><input className="input" placeholder="e.g. A-002" /></div>
            <div className="form-group"><label>Queue Status</label><select className="input"><option>Active</option><option>Paused</option><option>Closed</option></select></div>
            <div className="form-group"><label>Estimated Service Time</label><input className="input" placeholder="e.g. 5 minutes per person" /></div>
          </div>
          <div className="form-group"><label>Staff Notes (Optional)</label><textarea className="input" rows={4} placeholder="Add operational notes for staff managing this queue..." /></div>
          <div className="modal-actions"><Link to="/queue" className="btn btn-outline">Cancel</Link><button className="btn btn-primary">Create Queue Line</button></div>
        </div>
      </div>
    </div>
  )
}
