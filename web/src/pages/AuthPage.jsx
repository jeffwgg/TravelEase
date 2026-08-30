import React, { useState } from 'react'
import { ShieldCheck } from 'lucide-react'
import { useLocation, useNavigate } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'

const initialRegistration = {
  institutionName: '',
  institutionType: '',
  officialContact: '',
  serviceAddress: '',
  email: '',
  password: '',
  confirmPassword: '',
  registrationDocument: null,
}

export default function AuthPage() {
  const navigate = useNavigate()
  const location = useLocation()
  const { signIn, registerInstitution, sendPasswordReset } = useAuth()
  const [mode, setMode] = useState('login')
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [registration, setRegistration] = useState(initialRegistration)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState(
    location.state?.passwordReset ? 'Password updated successfully. Sign in with your new password.' : '',
  )

  const switchMode = (nextMode) => {
    setMode(nextMode)
    setError('')
    setSuccess('')
  }

  const handleLogin = async (event) => {
    event.preventDefault()
    const validationError = validateEmail(email) || (!password ? 'Password is required.' : '')
    if (validationError) return setError(validationError)
    await runRequest(async () => {
      await signIn(email.trim().toLowerCase(), password)
      navigate('/dashboard', { replace: true })
    })
  }

  const handleRegister = async (event) => {
    event.preventDefault()
    const validationError = validateRegistration(registration)
    if (validationError) {
      console.warn('[InstitutionRegistration][AuthPage] Validation stopped submission:', validationError)
      return setError(validationError)
    }
    await runRequest(async () => {
      console.log('[InstitutionRegistration][AuthPage] Calling AuthContext.registerInstitution()', {
        formKeys: Object.keys(registration),
        hasDocument: registration.registrationDocument instanceof File,
        documentName: registration.registrationDocument?.name,
        documentType: registration.registrationDocument?.type,
        documentSize: registration.registrationDocument?.size,
      })
      await registerInstitution(registration)
      console.log('[InstitutionRegistration][AuthPage] Registration resolved; navigating to verification page')
      navigate(`/verify-email?email=${encodeURIComponent(registration.email.trim())}`)
    })
  }

  const handleForgotPassword = async (event) => {
    event.preventDefault()
    const validationError = validateEmail(email)
    if (validationError) return setError(validationError)
    await runRequest(async () => {
      await sendPasswordReset(email.trim().toLowerCase())
      setSuccess('If an institution account exists for this email, a reset link has been sent.')
    })
  }

  const runRequest = async (action) => {
    setError('')
    setSuccess('')
    setSubmitting(true)
    try {
      await action()
    } catch (requestError) {
      setError(friendlyAuthError(requestError))
    } finally {
      setSubmitting(false)
    }
  }

  const updateRegistration = (field, value) => {
    setRegistration((current) => ({ ...current, [field]: value }))
  }

  return (
    <div className="auth-page">
      <div className={`auth-card ${mode === 'register' ? 'auth-card-wide' : ''}`}>
        <div className="auth-logo">
          <img src="/logo.png" alt="TravelEase Logo" className="auth-logo-image" />
          <h2>TravelEase Dashboard</h2>
          <div className="auth-subtitle">Institutional Accessibility &amp; Support Portal</div>
        </div>

        {mode === 'register' ? (
          <form onSubmit={handleRegister} noValidate>
            <div className="form-grid">
              <Field label="Institution Name">
                <input className="input" value={registration.institutionName} onChange={(event) => updateRegistration('institutionName', event.target.value)} autoComplete="organization" />
              </Field>
              <Field label="Institution Type">
                <select className="input" value={registration.institutionType} onChange={(event) => updateRegistration('institutionType', event.target.value)}>
                  <option value="">Select institution type</option>
                  <option value="airport_transport">Airport / Transportation Hub</option>
                  <option value="hotel_hospitality">Hotel &amp; Hospitality</option>
                  <option value="tourist_attraction">Tourist Attraction</option>
                  <option value="healthcare">Healthcare Facility</option>
                  <option value="government">Government Agency</option>
                  <option value="other">Other</option>
                </select>
              </Field>
              <Field label="Official Contact">
                <input className="input" value={registration.officialContact} onChange={(event) => updateRegistration('officialContact', event.target.value)} placeholder="Phone number or official contact" />
              </Field>
              <Field label="Institution Email">
                <input className="input" type="email" value={registration.email} onChange={(event) => updateRegistration('email', event.target.value)} autoComplete="email" />
              </Field>
              <Field label="Service Address" fullWidth>
                <textarea className="input" rows={3} value={registration.serviceAddress} onChange={(event) => updateRegistration('serviceAddress', event.target.value)} />
              </Field>
              <Field label="Registration Documentation" fullWidth>
                <input className="input" type="file" accept=".pdf,image/jpeg,image/png" onChange={(event) => updateRegistration('registrationDocument', event.target.files?.[0] || null)} />
                <div className="field-note">PDF, JPG, or PNG. Maximum file size: 10 MB.</div>
              </Field>
              <Field label="Password">
                <input className="input" type="password" value={registration.password} onChange={(event) => updateRegistration('password', event.target.value)} autoComplete="new-password" />
              </Field>
              <Field label="Confirm Password">
                <input className="input" type="password" value={registration.confirmPassword} onChange={(event) => updateRegistration('confirmPassword', event.target.value)} autoComplete="new-password" />
              </Field>
            </div>
            {error && <Alert type="error">{error}</Alert>}
            <button type="submit" className="btn btn-primary auth-submit" disabled={submitting}>{submitting ? 'Creating Account…' : 'Register Institution'}</button>
            <button type="button" className="auth-text-button" onClick={() => switchMode('login')}>Already registered? Sign in</button>
          </form>
        ) : (
          <form onSubmit={mode === 'forgot' ? handleForgotPassword : handleLogin} noValidate>
            {mode === 'forgot' && <p className="auth-instructions">Enter the institution email address and we will send a secure password reset link.</p>}
            <Field label="Institution Email">
              <input type="email" className="input" placeholder="institution@example.com" value={email} onChange={(event) => setEmail(event.target.value)} autoComplete="email" />
            </Field>
            {mode === 'login' && (
              <Field label="Password">
                <input type="password" className="input" placeholder="Enter your password" value={password} onChange={(event) => setPassword(event.target.value)} autoComplete="current-password" />
              </Field>
            )}
            {error && <Alert type="error">{error}</Alert>}
            {success && <Alert type="success">{success}</Alert>}
            <button type="submit" className="btn btn-primary auth-submit" disabled={submitting}>
              {submitting ? 'Please wait…' : mode === 'forgot' ? 'Send Reset Link' : 'Sign In to Dashboard'}
            </button>
            {mode === 'login' ? (
              <div className="auth-links">
                <button type="button" className="auth-text-button" onClick={() => switchMode('forgot')}>Forgot Password?</button>
                <button type="button" className="auth-text-button" onClick={() => switchMode('register')}>Register Institution</button>
              </div>
            ) : (
              <button type="button" className="auth-text-button" onClick={() => switchMode('login')}>Back to sign in</button>
            )}
          </form>
        )}

        <div className="auth-security-note"><ShieldCheck size={16} color="var(--primary)" /> Authorized institution account access only.</div>
      </div>
    </div>
  )
}

function Field({ label, fullWidth = false, children }) {
  return <div className={`form-group ${fullWidth ? 'auth-field-full' : ''}`}><label>{label}<span className="required-mark"> *</span></label>{children}</div>
}

function Alert({ type, children }) {
  return <div className={`form-alert ${type}`} role="alert">{children}</div>
}

function validateEmail(email) {
  const value = email.trim()
  if (!value) return 'Email is required.'
  if (value.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)) return 'Enter a valid email address.'
  return ''
}

function validatePassword(password) {
  if (!password) return 'Password is required.'
  if (password.length < 8) return 'Password must be at least 8 characters.'
  if (!/[A-Z]/.test(password) || !/[a-z]/.test(password) || !/[0-9]/.test(password)) return 'Password must include uppercase, lowercase, and a number.'
  return ''
}

function validateRegistration(form) {
  if (form.institutionName.trim().length < 2 || form.institutionName.trim().length > 120) return 'Institution name must be between 2 and 120 characters.'
  if (!form.institutionType) return 'Select an institution type.'
  if (form.officialContact.trim().length < 5 || form.officialContact.trim().length > 100) return 'Enter a valid official contact.'
  if (form.serviceAddress.trim().length < 10 || form.serviceAddress.trim().length > 500) return 'Service address must be between 10 and 500 characters.'
  const emailError = validateEmail(form.email)
  if (emailError) return emailError
  if (!form.registrationDocument) return 'Registration documentation is required.'
  if (!['application/pdf', 'image/jpeg', 'image/png'].includes(form.registrationDocument.type)) return 'Registration document must be a PDF, JPG, or PNG.'
  if (form.registrationDocument.size > 10 * 1024 * 1024) return 'Registration document must be 10 MB or smaller.'
  const passwordError = validatePassword(form.password)
  if (passwordError) return passwordError
  if (form.password !== form.confirmPassword) return 'Passwords do not match.'
  return ''
}

function friendlyAuthError(error) {
  const message = String(error?.message || '').toLowerCase()
  if (message.includes('already registered') || message.includes('already exists')) return 'An institution account with this email already exists.'
  if (message.includes('email not confirmed')) return 'Verify your email before signing in.'
  if (message.includes('invalid login credentials')) return 'Incorrect email or password.'
  if (message.includes('rate') || message.includes('too many') || error?.status === 429) return 'Too many attempts. Please wait and try again.'
  if (message.includes('network') || message.includes('fetch')) return 'Unable to connect. Check your internet connection and try again.'
  return error?.message || 'Unable to complete the request. Please try again.'
}
