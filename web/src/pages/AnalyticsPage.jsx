import React from 'react'
import { BarChart3, MapPin, Megaphone, Target, Download, AlertCircle, AlertTriangle, CheckCircle2 } from 'lucide-react'

export default function AnalyticsPage() {
  return (
    <div>
      <div className="page-header">
        <div>
          <h2>Accessibility Analytics & Heatmaps</h2>
          <div className="header-subtitle">Analyze confirmed accessibility barriers, problem locations, and recurring service gaps across your facility.</div>
        </div>
        <div style={{ display: 'flex', gap: '8px' }}>
          <select className="input" style={{ width: '160px' }}>
            <option>Last 30 Days</option>
            <option>Last 7 Days</option>
            <option>This Quarter</option>
            <option>Year to Date</option>
          </select>
          <button className="btn btn-outline">
            <Download size={16} /> Export Heatmap Data
          </button>
        </div>
      </div>

      <div className="page-body">
        <div className="stats-grid">
          <div className="stat-card">
            <div className="stat-icon primary"><BarChart3 size={22} color="var(--primary)" /></div>
            <div>
              <div className="stat-value">142</div>
              <div className="stat-label">Total Reported Barriers</div>
              <div className="stat-change down">↓ 12% vs last month</div>
            </div>
          </div>

          <div className="stat-card">
            <div className="stat-icon secondary"><MapPin size={22} color="var(--secondary-dark)" /></div>
            <div>
              <div className="stat-value">Gate A5</div>
              <div className="stat-label">Highest Barrier Location</div>
              <div className="stat-change">34 reports</div>
            </div>
          </div>

          <div className="stat-card">
            <div className="stat-icon accent"><Megaphone size={22} color="var(--accent)" /></div>
            <div>
              <div className="stat-value">48%</div>
              <div className="stat-label">No Visual Announcement</div>
              <div className="stat-change">Top Issue Category</div>
            </div>
          </div>

          <div className="stat-card">
            <div className="stat-icon success"><Target size={22} color="var(--success)" /></div>
            <div>
              <div className="stat-value">91.4%</div>
              <div className="stat-label">Issue Resolution Rate</div>
              <div className="stat-change up">↑ 4.2% improvement</div>
            </div>
          </div>
        </div>

        <div className="grid-2" style={{ marginBottom: '24px' }}>
          {/* Heatmap visualization card */}
          <div className="card">
            <div className="card-header">
              <h3>Facility Accessibility Barrier Heatmap</h3>
              <span className="badge secondary">Terminal 1 Overview</span>
            </div>
            <div className="chart-placeholder" style={{ background: '#1e293b', color: '#fff', flexDirection: 'column', gap: '16px' }}>
              <div style={{ fontSize: '16px', fontWeight: '600', display: 'flex', alignItems: 'center', gap: '8px' }}>
                <MapPin size={20} color="var(--primary-light)" /> Interactive Facility Heatmap
              </div>
              <div style={{ display: 'flex', gap: '20px', fontSize: '13px' }}>
                <span style={{ color: '#ef4444', display: 'flex', alignItems: 'center', gap: '4px' }}>
                  <AlertCircle size={14} /> Gate A5 (High Density: 34)
                </span>
                <span style={{ color: '#f59e0b', display: 'flex', alignItems: 'center', gap: '4px' }}>
                  <AlertTriangle size={14} /> Counter 14 (Medium: 18)
                </span>
                <span style={{ color: '#10b981', display: 'flex', alignItems: 'center', gap: '4px' }}>
                  <CheckCircle2 size={14} /> Gate C4 (Low: 3)
                </span>
              </div>
              <div style={{ fontSize: '12px', color: 'rgba(255,255,255,0.5)' }}>[ Visual Grid & Spatial Barrier Density Overlay ]</div>
            </div>
          </div>

          {/* Issue category breakdown */}
          <div className="card">
            <div className="card-header">
              <h3>Barrier Category Distribution</h3>
            </div>
            <div className="chart-placeholder">
              [ Bar / Donut Chart: 48% No Visual Announcement, 28% Sound-Only Queue, 14% Sign Language Support, 10% Other ]
            </div>
          </div>
        </div>

        <div className="card">
          <div className="card-header">
            <h3>High-Frequency Problem Areas & Recommendations</h3>
          </div>
          <table className="data-table">
            <thead>
              <tr>
                <th>Location / Zone</th>
                <th>Main Problem Category</th>
                <th>Reports Count</th>
                <th>Impact Level</th>
                <th>Suggested Action</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td><strong>Gate A5 Area</strong></td>
                <td>Missing Visual Announcements</td>
                <td>34 reports</td>
                <td><span className="badge emergency">High Impact</span></td>
                <td>Install dedicated digital caption display screen at Gate A5</td>
              </tr>
              <tr>
                <td><strong>Check-in Counter 14-20</strong></td>
                <td>Sound-Only Queue System</td>
                <td>22 reports</td>
                <td><span className="badge secondary">Medium Impact</span></td>
                <td>Enable TravelEase app visual queue sync for counter series</td>
              </tr>
              <tr>
                <td><strong>Information Desk Zone B</strong></td>
                <td>Lack of Sign Language Staff</td>
                <td>16 reports</td>
                <td><span className="badge secondary">Medium Impact</span></td>
                <td>Deploy BIM-certified staff or enable digital dialogue tablet</td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
