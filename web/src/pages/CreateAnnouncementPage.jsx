import React from 'react'
import { Link } from 'react-router-dom'

export default function CreateAnnouncementPage() {
  return (
    <div>
      <div className="page-header">
        <div>
          <h2>Create Announcement</h2>
          <div className="header-subtitle">Compose and broadcast a visual announcement to travelers in your venue.</div>
        </div>
        <Link to="/announcements" className="btn btn-outline">Back to Announcements</Link>
      </div>

      <div className="page-body">
        <div className="card" style={{ maxWidth: '720px' }}>
          <div className="form-group">
            <label>Target Zone / Area</label>
            <select className="input">
              <option>All Zones (All Travelers in Venue)</option>
              <option>Gate A1 - A10 Area</option>
              <option>Gate B1 - B12 Area</option>
              <option>Baggage Claim Hall</option>
            </select>
          </div>
          <div className="form-group">
            <label>Announcement Type</label>
            <select className="input">
              <option>Gate Change / Travel Update</option>
              <option>General Boarding Call</option>
              <option>Delay / Cancellation Notice</option>
              <option>Emergency Warning</option>
            </select>
          </div>
          <div className="form-group">
            <label>Message Content (English &amp; BM)</label>
            <textarea className="input" rows={6} placeholder="Type announcement text here..."></textarea>
          </div>
          <button className="btn btn-primary" style={{ width: '100%', justifyContent: 'center' }}>Broadcast Instantly</button>
        </div>
      </div>
    </div>
  )
}
