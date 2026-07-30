import React from 'react'

export default function AnnouncementPage() {
  return (
    <div>
      <div className="page-header">
        <div>
          <h2>Announcement Management</h2>
          <div className="header-subtitle">Broadcast real-time visual announcements and PA captions directly to deaf travelers in your venue.</div>
        </div>
        <button className="btn btn-primary">+ Create Announcement</button>
      </div>

      <div className="page-body">
        <div className="grid-3" style={{ marginBottom: '24px' }}>
          <div className="card">
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
              <label>Message Content (English & BM)</label>
              <textarea className="input" rows={4} placeholder="Type announcement text here..."></textarea>
            </div>
            <button className="btn btn-primary" style={{ width: '100%', justifyContent: 'center' }}>Broadcast Instantly</button>
          </div>

          <div style={{ gridColumn: 'span 2' }} className="card">
            <div className="card-header">
              <h3>Active & Recent Announcements</h3>
              <div style={{ display: 'flex', gap: '8px' }}>
                <input type="text" className="input" placeholder="Search broadcasts..." style={{ width: '200px' }} />
              </div>
            </div>
            <table className="data-table">
              <thead>
                <tr>
                  <th>Title / Subject</th>
                  <th>Target Zone</th>
                  <th>Priority</th>
                  <th>Sent At</th>
                  <th>Reach</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td><strong>Gate Change — MH370</strong><br/><span style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>Changed from A5 to B12</span></td>
                  <td>Gate A5 Area</td>
                  <td><span className="badge secondary">High</span></td>
                  <td>2 min ago</td>
                  <td>142 travelers</td>
                </tr>
                <tr>
                  <td><strong>Boarding Call — AK123</strong><br/><span style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>Now boarding at Gate C4</span></td>
                  <td>Gate C1-C10</td>
                  <td><span className="badge primary">Normal</span></td>
                  <td>8 min ago</td>
                  <td>89 travelers</td>
                </tr>
                <tr>
                  <td><strong>Security Reminder</strong><br/><span style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>Liquid restrictions apply</span></td>
                  <td>All Zones</td>
                  <td><span className="badge muted">Low</span></td>
                  <td>25 min ago</td>
                  <td>410 travelers</td>
                </tr>
                <tr>
                  <td><strong>Flight Delay — MH456</strong><br/><span style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>Delayed 45 mins</span></td>
                  <td>Gate D2 Area</td>
                  <td><span className="badge emergency">Urgent</span></td>
                  <td>1 hr ago</td>
                  <td>64 travelers</td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  )
}
