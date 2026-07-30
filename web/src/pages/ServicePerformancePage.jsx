import React from 'react'
import { Zap, Clock, Star, ThumbsUp, Download } from 'lucide-react'

export default function ServicePerformancePage() {
  return (
    <div>
      <div className="page-header">
        <div>
          <h2>Staff Service Performance Monitoring</h2>
          <div className="header-subtitle">Track response times, resolution speed, and user satisfaction ratings for staff assisting deaf travelers.</div>
        </div>
        <button className="btn btn-outline">
          <Download size={16} /> Download Performance Log
        </button>
      </div>

      <div className="page-body">
        <div className="stats-grid">
          <div className="stat-card">
            <div className="stat-icon primary"><Zap size={22} color="var(--primary)" /></div>
            <div>
              <div className="stat-value">2.4 min</div>
              <div className="stat-label">Avg. Initial Response Time</div>
              <div className="stat-change up">↑ 45s faster this week</div>
            </div>
          </div>

          <div className="stat-card">
            <div className="stat-icon accent"><Clock size={22} color="var(--accent)" /></div>
            <div>
              <div className="stat-value">8.1 min</div>
              <div className="stat-label">Avg. Resolution Time</div>
              <div className="stat-change up">Target: &lt; 10 min</div>
            </div>
          </div>

          <div className="stat-card">
            <div className="stat-icon secondary"><Star size={22} color="var(--secondary-dark)" /></div>
            <div>
              <div className="stat-value">4.8 / 5.0</div>
              <div className="stat-label">User Satisfaction Rating</div>
              <div className="stat-change up">Based on 118 ratings</div>
            </div>
          </div>

          <div className="stat-card">
            <div className="stat-icon success"><ThumbsUp size={22} color="var(--success)" /></div>
            <div>
              <div className="stat-value">94.2%</div>
              <div className="stat-label">First-Contact Resolution</div>
              <div className="stat-change up">High efficiency</div>
            </div>
          </div>
        </div>

        <div className="grid-2" style={{ marginBottom: '24px' }}>
          <div className="card">
            <div className="card-header">
              <h3>Response & Resolution Time Trends</h3>
            </div>
            <div className="chart-placeholder">
              [ Line Chart: Response time (blue: 2.4 min) vs Resolution time (indigo: 8.1 min) over time ]
            </div>
          </div>

          <div className="card">
            <div className="card-header">
              <h3>User Satisfaction Breakdown</h3>
            </div>
            <div className="chart-placeholder">
              [ Donut Chart: 85% 5-Star, 10% 4-Star, 3% 3-Star, 2% 1-2 Star ]
            </div>
          </div>
        </div>

        <div className="card">
          <div className="card-header">
            <h3>Staff Service Leaderboard & Metrics</h3>
          </div>
          <table className="data-table">
            <thead>
              <tr>
                <th>Staff Name</th>
                <th>Requests Handled</th>
                <th>Avg. Response Time</th>
                <th>Avg. Resolution Time</th>
                <th>Satisfaction Score</th>
                <th>Status</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td><strong>Ahmad Khan</strong></td>
                <td>42 requests</td>
                <td>1.8 mins</td>
                <td>6.5 mins</td>
                <td><span className="badge success">★ 4.9</span></td>
                <td><span className="badge success">On Duty</span></td>
              </tr>
              <tr>
                <td><strong>Siti Nurhaliza</strong></td>
                <td>38 requests</td>
                <td>2.1 mins</td>
                <td>7.2 mins</td>
                <td><span className="badge success">★ 4.8</span></td>
                <td><span className="badge success">On Duty</span></td>
              </tr>
              <tr>
                <td><strong>Jason Tan</strong></td>
                <td>29 requests</td>
                <td>3.0 mins</td>
                <td>9.8 mins</td>
                <td><span className="badge primary">★ 4.6</span></td>
                <td><span className="badge muted">Off Duty</span></td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
