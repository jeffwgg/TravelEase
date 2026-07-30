import React from 'react'
import { FileText } from 'lucide-react'

export default function ReportGenerationPage() {
  return (
    <div>
      <div className="page-header">
        <div>
          <h2>Accessibility Report Generation</h2>
          <div className="header-subtitle">Generate comprehensive monthly compliance, audit, and service improvement reports for management.</div>
        </div>
      </div>

      <div className="page-body">
        <div className="grid-2" style={{ marginBottom: '24px' }}>
          <div className="card">
            <div className="card-header">
              <h3>Generate Custom Accessibility Report</h3>
            </div>
            <form onSubmit={(e) => e.preventDefault()}>
              <div className="form-group">
                <label>Report Type</label>
                <select className="input">
                  <option>Monthly Accessibility Audit Report</option>
                  <option>Area-Specific Barrier & Heatmap Report</option>
                  <option>Staff Response & Performance Audit</option>
                  <option>Deaf Traveler Satisfaction & Outcome Summary</option>
                </select>
              </div>

              <div style={{ display: 'flex', gap: '16px' }} className="form-group">
                <div style={{ flex: 1 }}>
                  <label>Start Date</label>
                  <input type="date" className="input" defaultValue="2026-07-01" />
                </div>
                <div style={{ flex: 1 }}>
                  <label>End Date</label>
                  <input type="date" className="input" defaultValue="2026-07-30" />
                </div>
              </div>

              <div className="form-group">
                <label>Target Facility / Zone</label>
                <select className="input">
                  <option>All Zones (Entire Venue)</option>
                  <option>Terminal 1 Main Hub</option>
                  <option>Terminal 2 Transit Area</option>
                </select>
              </div>

              <div className="form-group">
                <label>Export Format</label>
                <div style={{ display: 'flex', gap: '16px', marginTop: '8px' }}>
                  <label style={{ fontSize: '14px', display: 'flex', alignItems: 'center', gap: '6px' }}>
                    <input type="radio" name="format" defaultChecked /> PDF Document
                  </label>
                  <label style={{ fontSize: '14px', display: 'flex', alignItems: 'center', gap: '6px' }}>
                    <input type="radio" name="format" /> CSV Data Sheet
                  </label>
                  <label style={{ fontSize: '14px', display: 'flex', alignItems: 'center', gap: '6px' }}>
                    <input type="radio" name="format" /> Excel (.xlsx)
                  </label>
                </div>
              </div>

              <button className="btn btn-primary" style={{ width: '100%', justifyContent: 'center', marginTop: '16px' }}>
                <FileText size={16} /> Generate & Download Report
              </button>
            </form>
          </div>

          <div className="card">
            <div className="card-header">
              <h3>Recently Generated Reports</h3>
            </div>
            <table className="data-table">
              <thead>
                <tr>
                  <th>Report Title</th>
                  <th>Date Range</th>
                  <th>Format</th>
                  <th>Action</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td><strong>Monthly Accessibility Audit (June 2026)</strong></td>
                  <td>Jun 1 - Jun 30</td>
                  <td><span className="badge primary">PDF</span></td>
                  <td><button className="btn btn-outline btn-sm">Download</button></td>
                </tr>
                <tr>
                  <td><strong>Gate Barrier Density Analysis</strong></td>
                  <td>Jun 15 - Jul 15</td>
                  <td><span className="badge success">CSV</span></td>
                  <td><button className="btn btn-outline btn-sm">Download</button></td>
                </tr>
                <tr>
                  <td><strong>Q2 Staff Performance Summary</strong></td>
                  <td>Apr 1 - Jun 30</td>
                  <td><span className="badge primary">PDF</span></td>
                  <td><button className="btn btn-outline btn-sm">Download</button></td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  )
}
