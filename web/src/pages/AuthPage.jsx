import React, { useState } from 'react'
import { ShieldCheck } from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'

export default function AuthPage() {
  const navigate = useNavigate()
  const { signIn } = useAuth()
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState('')

  const handleSubmit = async (event) => {
    event.preventDefault()
    setError('')
    setSubmitting(true)
    try {
      await signIn(email.trim(), password)
      navigate('/dashboard', { replace: true })
    } catch (signInError) {
      setError(signInError.message || 'Unable to sign in. Please try again.')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="auth-page">
      <div className="auth-card">
        <div className="auth-logo">
          <img src="/logo.png" alt="TravelEase Logo" style={{ width: 72, height: 72, borderRadius: 18, marginBottom: 16, boxShadow: '0 4px 14px rgba(13, 148, 136, 0.3)' }} />
          <h2>TravelEase Dashboard</h2>
          <div className="auth-subtitle">Institutional Accessibility &amp; Support Portal</div>
        </div>

        <form onSubmit={handleSubmit}>
          <div className="form-group">
            <label htmlFor="institution-email">Institution Email</label>
            <input id="institution-email" type="email" className="input" placeholder="institution@example.com" value={email} onChange={(event) => setEmail(event.target.value)} required autoComplete="email" />
          </div>
          <div className="form-group">
            <label htmlFor="institution-password">Password</label>
            <input id="institution-password" type="password" className="input" placeholder="Enter your password" value={password} onChange={(event) => setPassword(event.target.value)} required autoComplete="current-password" />
          </div>
          {error && <div className="form-alert error" role="alert">{error}</div>}
          <button type="submit" className="btn btn-primary" disabled={submitting} style={{ width: '100%', justifyContent: 'center', padding: '12px' }}>
            {submitting ? 'Signing In…' : 'Sign In to Dashboard'}
          </button>
        </form>

        <div style={{ marginTop: '24px', padding: '12px', background: 'var(--surface-variant)', borderRadius: 'var(--radius-md)', fontSize: '12px', color: 'var(--text-secondary)', textAlign: 'center', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: '6px' }}>
          <ShieldCheck size={16} color="var(--primary)" /> Authorized institution account access only.
        </div>
      </div>
    </div>
  )
}
