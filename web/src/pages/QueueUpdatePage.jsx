import React from 'react'

export default function QueueUpdatePage() {
  return (
    <div>
      <div className="page-header">
        <div>
          <h2>Queue Management Console</h2>
          <div className="header-subtitle">Push real-time visual queue updates and haptic alerts directly to travelers waiting in line.</div>
        </div>
        <button className="btn btn-primary">+ Add Queue Counter</button>
      </div>

      <div className="page-body">
        <div className="grid-3" style={{ marginBottom: '24px' }}>
          <div className="card" style={{ background: 'linear-gradient(135deg, var(--dark-bg), var(--dark-surface))', color: '#fff' }}>
            <div style={{ fontSize: '13px', color: 'rgba(255,255,255,0.6)' }}>Counter #1 — Main Service Desk</div>
            <div style={{ fontSize: '56px', fontWeight: '800', color: 'var(--primary-light)', margin: '16px 0' }}>A-042</div>
            <div style={{ display: 'flex', gap: '12px', marginBottom: '16px' }}>
              <button className="btn btn-outline" style={{ color: '#fff', borderColor: 'rgba(255,255,255,0.3)' }}>Prev (A-041)</button>
              <button className="btn btn-primary" style={{ flex: 1, justifyContent: 'center' }}>Call Next (A-043)</button>
            </div>
            <div style={{ fontSize: '12px', color: 'rgba(255,255,255,0.4)', textAlign: 'center' }}>
              Deaf traveler waiting: <strong>A-047 (Jeff W.)</strong> • 5 numbers away
            </div>
          </div>

          <div className="card" style={{ background: 'linear-gradient(135deg, var(--dark-bg), var(--dark-surface))', color: '#fff' }}>
            <div style={{ fontSize: '13px', color: 'rgba(255,255,255,0.6)' }}>Counter #2 — Special Assistance</div>
            <div style={{ fontSize: '56px', fontWeight: '800', color: 'var(--secondary-light)', margin: '16px 0' }}>B-018</div>
            <div style={{ display: 'flex', gap: '12px', marginBottom: '16px' }}>
              <button className="btn btn-outline" style={{ color: '#fff', borderColor: 'rgba(255,255,255,0.3)' }}>Prev (B-017)</button>
              <button className="btn btn-primary" style={{ flex: 1, justifyContent: 'center', background: 'var(--secondary)' }}>Call Next (B-019)</button>
            </div>
            <div style={{ fontSize: '12px', color: 'rgba(255,255,255,0.4)', textAlign: 'center' }}>
              Deaf traveler waiting: <strong>B-020 (Tan W.L.)</strong> • 2 numbers away
            </div>
          </div>

          <div className="card">
            <div className="card-header">
              <h3>Direct Call Number</h3>
            </div>
            <div className="form-group">
              <label>Select Queue Line</label>
              <select className="input">
                <option>A Series — Check-in & Ticketing</option>
                <option>B Series — Special Assistance</option>
                <option>C Series — Customs & Info</option>
              </select>
            </div>
            <div className="form-group">
              <label>Number to Call</label>
              <input type="text" className="input" defaultValue="A-047" />
            </div>
            <button className="btn btn-primary" style={{ width: '100%', justifyContent: 'center' }}>
              Notify Traveler Now (Vibrate App)
            </button>
          </div>
        </div>

        <div className="card">
          <div className="card-header">
            <h3>Active Queue Lines</h3>
          </div>
          <table className="data-table">
            <thead>
              <tr>
                <th>Queue Line</th>
                <th>Current Number</th>
                <th>Total Waiting</th>
                <th>Deaf Travelers In Line</th>
                <th>Est. Wait per Person</th>
                <th>Action</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td><strong>A Series (General Ticketing)</strong></td>
                <td><span className="badge primary" style={{ fontSize: '14px' }}>A-042</span></td>
                <td>24 people</td>
                <td><span className="badge secondary">3 travelers</span></td>
                <td>3.5 mins</td>
                <td><button className="btn btn-outline btn-sm">Manage</button></td>
              </tr>
              <tr>
                <td><strong>B Series (Accessibility Services)</strong></td>
                <td><span className="badge primary" style={{ fontSize: '14px' }}>B-018</span></td>
                <td>6 people</td>
                <td><span className="badge secondary">4 travelers</span></td>
                <td>5.0 mins</td>
                <td><button className="btn btn-outline btn-sm">Manage</button></td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
