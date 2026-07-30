import React from 'react'

export default function SignFeedbackPage() {
  return (
    <div>
      <div className="page-header">
        <div>
          <h2>Sign Asset Feedback Review</h2>
          <div className="header-subtitle">Review traveler feedback on sign language gesture accuracy, video quality, and regional BIM dialect corrections.</div>
        </div>
      </div>

      <div className="page-body">
        <div className="card">
          <div className="card-header">
            <h3>Traveler Feedback Submissions</h3>
            <div style={{ display: 'flex', gap: '8px' }}>
              <select className="input" style={{ width: '160px' }}>
                <option>All Feedback</option>
                <option>Pending Review</option>
                <option>Approved / Updated</option>
              </select>
            </div>
          </div>

          <table className="data-table">
            <thead>
              <tr>
                <th>Phrase Asset</th>
                <th>Traveler Feedback</th>
                <th>Category</th>
                <th>Submitted By</th>
                <th>Date</th>
                <th>Status</th>
                <th>Action</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td><strong>Where is the gate? (BIM)</strong></td>
                <td>"The hand gesture for 'gate' in Northern BIM dialect uses a slightly wider movement. Please add regional variant."</td>
                <td>Dialect Correction</td>
                <td>Tan W.L.</td>
                <td>Jul 28, 2026</td>
                <td><span className="badge secondary">Pending Review</span></td>
                <td>
                  <button className="btn btn-primary btn-sm">Review & Update Asset</button>
                </td>
              </tr>
              <tr>
                <td><strong>I feel sick (ASL)</strong></td>
                <td>"Lighting in the video clip is a bit dim at the end. Video re-recording suggested."</td>
                <td>Video Quality</td>
                <td>John D.</td>
                <td>Jul 24, 2026</td>
                <td><span className="badge success">Resolved</span></td>
                <td>
                  <button className="btn btn-outline btn-sm">View Log</button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
