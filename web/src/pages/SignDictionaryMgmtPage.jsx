import React from 'react'

export default function SignDictionaryMgmtPage() {
  return (
    <div>
      <div className="page-header">
        <div>
          <h2>Sign Dictionary Content Management</h2>
          <div className="header-subtitle">Manage verified Malaysian Sign Language (BIM) and ASL visual video assets and phrase categories.</div>
        </div>
        <button className="btn btn-primary">+ Upload New Sign Video</button>
      </div>

      <div className="page-body">
        <div className="grid-3" style={{ marginBottom: '24px' }}>
          <div className="card">
            <div className="stat-value" style={{ fontSize: '32px' }}>1,240</div>
            <div className="stat-label">Total Verified Signs</div>
          </div>
          <div className="card">
            <div className="stat-value" style={{ fontSize: '32px' }}>850</div>
            <div className="stat-label">BIM (Bahasa Isyarat Malaysia)</div>
          </div>
          <div className="card">
            <div className="stat-value" style={{ fontSize: '32px' }}>390</div>
            <div className="stat-label">ASL (American Sign Language)</div>
          </div>
        </div>

        <div className="card">
          <div className="card-header">
            <h3>Sign Language Library Assets</h3>
            <div style={{ display: 'flex', gap: '8px' }}>
              <select className="input" style={{ width: '140px' }}>
                <option>All Languages</option>
                <option>BIM</option>
                <option>ASL</option>
              </select>
              <select className="input" style={{ width: '140px' }}>
                <option>All Domains</option>
                <option>Airport</option>
                <option>Hotel</option>
                <option>Emergency</option>
              </select>
              <input type="text" className="input" placeholder="Search phrase..." style={{ width: '180px' }} />
            </div>
          </div>

          <table className="data-table">
            <thead>
              <tr>
                <th>Phrase / Word</th>
                <th>Sign Language</th>
                <th>Domain Category</th>
                <th>Video Status</th>
                <th>Audio Sync</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td><strong>Where is the gate?</strong><br/><span style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>Di mana pintu masuk?</span></td>
                <td><span className="badge primary">BIM</span></td>
                <td>Airport</td>
                <td><span className="badge success">HD Video Active</span></td>
                <td><span className="badge success">Synced</span></td>
                <td>
                  <button className="btn btn-outline btn-sm">Edit</button>
                </td>
              </tr>
              <tr>
                <td><strong>I need to check in</strong><br/><span style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>Saya nak daftar masuk</span></td>
                <td><span className="badge primary">BIM</span></td>
                <td>Hotel / Airport</td>
                <td><span className="badge success">HD Video Active</span></td>
                <td><span className="badge success">Synced</span></td>
                <td>
                  <button className="btn btn-outline btn-sm">Edit</button>
                </td>
              </tr>
              <tr>
                <td><strong>Emergency Evacuation</strong><br/><span style={{ fontSize: '12px', color: 'var(--text-secondary)' }}>Pindahan kecemasan</span></td>
                <td><span className="badge secondary">ASL</span></td>
                <td>Emergency</td>
                <td><span className="badge success">HD Video Active</span></td>
                <td><span className="badge success">Synced</span></td>
                <td>
                  <button className="btn btn-outline btn-sm">Edit</button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
