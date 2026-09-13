import React, { useEffect, useState } from 'react'
import { KeyRound } from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'

export default function StaffSetupPage() {
  const navigate = useNavigate()
  const { session, loading, completeStaffSetup } = useAuth()
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    if (!loading && !session) setError('This staff invitation link is invalid or has expired. Ask your manager for a new invitation.')
  }, [loading, session])

  const submit = async (event) => {
    event.preventDefault()
    const validationError = validatePassword(password)
    if (validationError) return setError(validationError)
    if (password !== confirmPassword) return setError('Passwords do not match.')
    if (!session) return setError('This staff invitation link is invalid or has expired.')
    setSubmitting(true)
    setError('')
    try {
      await completeStaffSetup(password)
      navigate('/auth', { replace: true, state: { staffSetup: true } })
    } catch (setupError) {
      const message = String(setupError?.message || '').toLowerCase()
      setError(message.includes('expired') || message.includes('session')
        ? 'This staff invitation link is invalid or has expired.'
        : setupError?.message || 'Unable to set your password.')
    } finally { setSubmitting(false) }
  }

  return <div className="auth-page"><div className="auth-card">
    <div className="auth-message-card reset-heading"><KeyRound size={48} color="var(--primary)" /><h2>Set Up Staff Account</h2><p>Create a secure password for your TravelEase staff account.</p></div>
    {loading ? <div className="form-alert info" role="status">Validating invitation…</div> : <form onSubmit={submit} noValidate>
      <div className="form-group"><label>Set Password</label><input className="input" type="password" value={password} onChange={(event) => setPassword(event.target.value)} autoComplete="new-password" disabled={!session || submitting} /></div>
      <div className="form-group"><label>Confirm Password</label><input className="input" type="password" value={confirmPassword} onChange={(event) => setConfirmPassword(event.target.value)} autoComplete="new-password" disabled={!session || submitting} /></div>
      <div className="field-note">Use at least 8 characters with uppercase, lowercase, and a number.</div>
      {error && <div className="form-alert error" role="alert">{error}</div>}
      <button className="btn btn-primary auth-submit" type="submit" disabled={!session || submitting}>{submitting ? 'Setting Password…' : 'Set Password'}</button>
    </form>}
  </div></div>
}

function validatePassword(password) {
  if (!password) return 'Password is required.'
  if (password.length < 8) return 'Password must be at least 8 characters.'
  if (!/[A-Z]/.test(password)) return 'Password must include an uppercase letter.'
  if (!/[a-z]/.test(password)) return 'Password must include a lowercase letter.'
  if (!/[0-9]/.test(password)) return 'Password must include a number.'
  return ''
}

