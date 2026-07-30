import React from 'react'
import { useNavigate } from 'react-router-dom'
import { Clock, MessageSquare, CheckCircle2, AlertCircle, MessageCircle, MapPin, Ticket, Briefcase } from 'lucide-react'

export default function AssistanceRequestPage() {
  const navigate = useNavigate()

  return (
    <div>
      <div className="page-header">
        <div>
          <h2>Assistance Request Dispatch</h2>
          <div className="header-subtitle">Real-time incoming assistance requests from travelers requiring physical or communication support.</div>
        </div>
        <button className="btn btn-primary">+ Log Manual Request</button>
      </div>

      <div className="page-body">
        <div className="stats-grid">
          <div className="stat-card">
            <div className="stat-icon secondary"><Clock size={22} color="var(--secondary-dark)" /></div>
            <div>
              <div className="stat-value">3</div>
              <div className="stat-label">Pending Response</div>
            </div>
          </div>
          <div className="stat-card">
            <div className="stat-icon primary"><MessageSquare size={22} color="var(--primary)" /></div>
            <div>
              <div className="stat-value">8</div>
              <div className="stat-label">In Progress (Active Chat)</div>
            </div>
          </div>
          <div className="stat-card">
            <div className="stat-icon success"><CheckCircle2 size={22} color="var(--success)" /></div>
            <div>
              <div className="stat-value">28</div>
              <div className="stat-label">Resolved Today</div>
            </div>
          </div>
          <div className="stat-card">
            <div className="stat-icon emergency"><AlertCircle size={22} color="var(--emergency)" /></div>
            <div>
              <div className="stat-value">1</div>
              <div className="stat-label">High Priority / Urgent</div>
            </div>
          </div>
        </div>

        <div className="card">
          <div className="card-header">
            <h3>Incoming Assistance Requests</h3>
            <div style={{ display: 'flex', gap: '8px' }}>
              <select className="input" style={{ width: '160px' }}>
                <option>All Statuses</option>
                <option>Pending</option>
                <option>In Progress</option>
                <option>Resolved</option>
              </select>
              <input type="text" className="input" placeholder="Search ID, traveler..." style={{ width: '200px' }} />
            </div>
          </div>

          <table className="data-table">
            <thead>
              <tr>
                <th>Request ID</th>
                <th>Traveler Name</th>
                <th>Category</th>
                <th>Location / Zone</th>
                <th>Urgency</th>
                <th>Assigned Staff</th>
                <th>Status</th>
                <th>Actions</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td><strong>#REQ-2847</strong></td>
                <td>Jeff Wong<br/><span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Prefers: BIM / Text</span></td>
                <td>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                    <MessageCircle size={16} color="var(--primary)" /> Communication Help
                  </div>
                </td>
                <td>Gate A5 Area</td>
                <td><span className="badge secondary">Medium</span></td>
                <td>Ahmad Khan</td>
                <td><span className="badge secondary">In Progress</span></td>
                <td>
                  <button className="btn btn-primary btn-sm" onClick={() => navigate('/chat')}>Open Chat</button>
                </td>
              </tr>
              <tr>
                <td><strong>#REQ-2848</strong></td>
                <td>Liew Jie Er<br/><span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Prefers: Text Only</span></td>
                <td>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                    <MapPin size={16} color="var(--accent)" /> Finding Location
                  </div>
                </td>
                <td>Main Departure Hall</td>
                <td><span className="badge emergency">High</span></td>
                <td>Unassigned</td>
                <td><span className="badge emergency">Pending</span></td>
                <td>
                  <button className="btn btn-primary btn-sm">Assign Staff</button>
                </td>
              </tr>
              <tr>
                <td><strong>#REQ-2831</strong></td>
                <td>Ethan Tan<br/><span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Prefers: ASL</span></td>
                <td>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                    <Ticket size={16} color="var(--secondary-dark)" /> Check-in Help
                  </div>
                </td>
                <td>Counter 14</td>
                <td><span className="badge primary">Low</span></td>
                <td>Siti Nurhaliza</td>
                <td><span className="badge success">Resolved</span></td>
                <td>
                  <button className="btn btn-outline btn-sm" onClick={() => navigate('/chat')}>View Log</button>
                </td>
              </tr>
              <tr>
                <td><strong>#REQ-2820</strong></td>
                <td>Wong Yan Thong<br/><span style={{ fontSize: '11px', color: 'var(--text-muted)' }}>Prefers: Text</span></td>
                <td>
                  <div style={{ display: 'flex', alignItems: 'center', gap: '6px' }}>
                    <Briefcase size={16} color="var(--text-secondary)" /> Luggage Issue
                  </div>
                </td>
                <td>Baggage Belt 3</td>
                <td><span className="badge primary">Low</span></td>
                <td>Jason Tan</td>
                <td><span className="badge success">Resolved</span></td>
                <td>
                  <button className="btn btn-outline btn-sm" onClick={() => navigate('/chat')}>View Log</button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </div>
  )
}
