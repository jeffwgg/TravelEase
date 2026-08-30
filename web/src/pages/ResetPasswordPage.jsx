import React, { useState } from 'react'
import { KeyRound } from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'

export default function ResetPasswordPage() {
  const navigate = useNavigate()
  const { session, updatePassword } = useAuth()
  const [password, setPassword] = useState('')
  const [confirmPassword, setConfirmPassword] = useState('')
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState('')

  const handleSubmit = async (event) => {
    event.preventDefault()
    const validationError = validatePassword(password)
    if (validationError) return setError(validationError)
    if (password !== confirmPassword) return setError('Passwords do not match.')
    if (!session) return setError('This reset link is invalid or has expired. Request a new link.')
    setSubmitting(true)
    setError('')
    try {
      await updatePassword(password)
      navigate('/auth', { replace: true, state: { passwordReset: true } })
    } catch (updateError) {
      const message = String(updateError?.message || '').toLowerCase()
      setError(message.includes('expired') || message.includes('session') ? 'This reset link is invalid or has expired.' : updateError?.message || 'Unable to update the password.')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="auth-page">
      <div className="auth-card">
        <div className="auth-message-card reset-heading">
          <KeyRound size={48} color="var(--primary)" />
          <h2>Reset Password</h2>
          <p>Choose a secure new password for your institution account.</p>
        </div>
        <form onSubmit={handleSubmit} noValidate>
          <div className="form-group"><label>New Password</label><input className="input" type="password" value={password} onChange={(event) => setPassword(event.target.value)} autoComplete="new-password" /></div>
          <div className="form-group"><label>Confirm New Password</label><input className="input" type="password" value={confirmPassword} onChange={(event) => setConfirmPassword(event.target.value)} autoComplete="new-password" /></div>
          {error && <div className="form-alert error" role="alert">{error}</div>}
          <button className="btn btn-primary auth-submit" type="submit" disabled={submitting}>{submitting ? 'Updating Password…' : 'Update Password'}</button>
        </form>
      </div>
    </div>
  )
}

function validatePassword(password) {
  if (!password) return 'Password is required.'
  if (password.length < 8) return 'Password must be at least 8 characters.'
  if (!/[A-Z]/.test(password) || !/[a-z]/.test(password) || !/[0-9]/.test(password)) return 'Password must include uppercase, lowercase, and a number.'
  return ''
}
