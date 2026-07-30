import React from 'react'

export default function ProfilePage() {
  return (
    <div>
      <div className="page-header">
        <div>
          <h2>Organization Profile Management</h2>
          <div className="header-subtitle">Manage venue profiles, branches, service zones, and staff access roles.</div>
        </div>
        <button className="btn btn-primary">Save Changes</button>
      </div>

      <div className="page-body">
        <div className="grid-2">
          {/* Org details */}
          <div className="card">
            <div className="card-header">
              <h3>Institution Details</h3>
              <span className="badge success">Verified Institution</span>
            </div>
            <div className="form-group">
              <label>Organization Name</label>
              <input type="text" className="input" defaultValue="Kuala Lumpur International Airport (KLIA)" />
            </div>
            <div className="form-group">
              <label>Category</label>
              <select className="input">
                <option>Airport / Transportation Hub</option>
                <option>Hotel & Hospitality</option>
                <option>Tourist Attraction</option>
                <option>Healthcare Facility</option>
              </select>
            </div>
            <div className="form-group">
              <label>Official Address</label>
              <textarea className="input" rows={3} defaultValue="64000 KLIA, Selangor, Malaysia"></textarea>
            </div>
            <div className="form-group">
              <label>Support Contact Hotline (SMS/Text)</label>
              <input type="text" className="input" defaultValue="+60 3-8777 8888" />
            </div>
          </div>

          {/* Zones & Staff */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>
            <div className="card">
              <div className="card-header">
                <h3>Active Service Zones / Branches</h3>
                <button className="btn btn-outline btn-sm">+ Add Zone</button>
              </div>
              <table className="data-table">
                <thead>
                  <tr>
                    <th>Zone Name</th>
                    <th>Staff On Duty</th>
                    <th>Status</th>
                  </tr>
                </thead>
                <tbody>
                  <tr>
                    <td>Terminal 1 — Main Terminal</td>
                    <td>14 staff</td>
                    <td><span className="badge success">Active</span></td>
                  </tr>
                  <tr>
                    <td>Terminal 1 — Satellite Building</td>
                    <td>8 staff</td>
                    <td><span className="badge success">Active</span></td>
                  </tr>
                  <tr>
                    <td>Terminal 2 — Budget Hub</td>
                    <td>12 staff</td>
                    <td><span className="badge success">Active</span></td>
                  </tr>
                </tbody>
              </table>
            </div>

            <div className="card">
              <div className="card-header">
                <h3>Staff Account Management</h3>
                <button className="btn btn-outline btn-sm">+ Invite Staff</button>
              </div>
              <table className="data-table">
                <thead>
                  <tr>
                    <th>Staff Name</th>
                    <th>Role</th>
                    <th>BIM Certified</th>
                  </tr>
                </thead>
                <tbody>
                  <tr>
                    <td>Ahmad Khan</td>
                    <td>Duty Manager</td>
                    <td><span className="badge primary">Level 3</span></td>
                  </tr>
                  <tr>
                    <td>Siti Nurhaliza</td>
                    <td>Guest Services</td>
                    <td><span className="badge primary">Level 2</span></td>
                  </tr>
                  <tr>
                    <td>Jason Tan</td>
                    <td>Emergency Responder</td>
                    <td><span className="badge secondary">Basic</span></td>
                  </tr>
                </tbody>
              </table>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
