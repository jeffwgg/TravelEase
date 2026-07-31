import React from 'react'
import { Link } from 'react-router-dom'

export default function AnnouncementPage() {
  return (
    <div>
      <div className="page-header">
        <div>
          <h2>Announcement Management</h2>
          <div className="header-subtitle">Broadcast real-time visual announcements and PA captions directly to deaf travelers in your venue.</div>
        </div>
        <Link to="/announcements/create" className="btn btn-primary">+ Create Announcement</Link>
      </div>

      <div className="page-body">
        <div style={{ marginBottom: '24px' }}>
          <div className="card">
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
