import React from 'react'
import { Accessibility, ShieldCheck } from 'lucide-react'

export default function AuthPage() {
  return (
    <div className="auth-page">
      <div className="auth-card">
        <div className="auth-logo">
          <img src="/logo.png" alt="TravelEase Logo" style={{ width: 72, height: 72, borderRadius: 18, marginBottom: 16, boxShadow: '0 4px 14px rgba(13, 148, 136, 0.3)' }} />
          <h2>TravelEase Dashboard</h2>
          <div className="auth-subtitle">Institutional Accessibility & Support Portal</div>
        </div>

        <form onSubmit={(e) => e.preventDefault()}>
          <div className="form-group">
            <label>Institution / Staff Email</label>
            <input type="email" className="input" placeholder="staff@klia.com.my" defaultValue="ahmad@klia.com.my" />
          </div>

          <div className="form-group">
            <label>Password</label>
            <input type="password" className="input" placeholder="••••••••" defaultValue="password123" />
          </div>

          <div className="form-group">
            <label>Facility / Branch</label>
            <select className="input">
              <option>KLIA Terminal 1 (Main Hub)</option>
              <option>KLIA Terminal 2</option>
              <option>Gateway@klia2 Hotel</option>
            </select>
          </div>

          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', margin: '20px 0' }}>
            <label style={{ fontSize: '13px', display: 'flex', alignItems: 'center', gap: '6px' }}>
              <input type="checkbox" defaultChecked /> Remember device
            </label>
            <a href="#" style={{ fontSize: '13px', color: 'var(--primary)', textDecoration: 'none' }}>Forgot Password?</a>
          </div>

          <button 
            type="button" 
            className="btn btn-primary" 
            style={{ width: '100%', justifyContent: 'center', padding: '12px' }}
            onClick={() => window.location.href = '/dashboard'}
          >
            Sign In to Dashboard
          </button>
        </form>

        <div style={{ marginTop: '24px', padding: '12px', background: 'var(--surface-variant)', borderRadius: 'var(--radius-md)', fontSize: '12px', color: 'var(--text-secondary)', textAlign: 'center', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '6px' }}>
          <ShieldCheck size={16} color="var(--primary)" /> Authorized staff access only. All interactions are logged for accessibility quality compliance.
        </div>
      </div>
    </div>
  )
}
