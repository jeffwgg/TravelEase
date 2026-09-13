import React, { useState, useEffect, useRef } from 'react'
import {
  ShieldCheck,
  Building2,
  Lock,
  Mail,
  Phone,
  MapPin,
  UploadCloud,
  X,
  AlertCircle,
  CheckCircle2,
  ArrowRight,
  HelpCircle,
  FileCheck
} from 'lucide-react'
import { useNavigate, useLocation } from 'react-router-dom'
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

export default function AuthModal({ isOpen, onClose, initialMode = 'login' }) {
  const navigate = useNavigate()
  const location = useLocation()
  const { signIn, registerInstitution, sendPasswordReset } = useAuth()

  const [mode, setMode] = useState(initialMode)
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [registration, setRegistration] = useState(initialRegistration)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState(
    location.state?.passwordReset ? 'Password updated successfully. Sign in with your new password.' : ''
  )
  const [dragActive, setDragActive] = useState(false)
  const modalRef = useRef(null)

  useEffect(() => {
    if (initialMode) {
      setMode(initialMode)
      setError('')
      setSuccess('')
    }
  }, [initialMode, isOpen])

  // Handle ESC key press
  useEffect(() => {
    if (!isOpen) return
    const handleKeyDown = (e) => {
      if (e.key === 'Escape') {
        onClose?.()
      }
    }
    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [isOpen, onClose])

  // Lock background scroll when open
  useEffect(() => {
    if (isOpen) {
      document.body.style.overflow = 'hidden'
    } else {
      document.body.style.overflow = ''
    }
    return () => {
      document.body.style.overflow = ''
    }
  }, [isOpen])

  if (!isOpen) return null

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
      onClose?.()
      navigate('/dashboard', { replace: true })
    })
  }

  const handleRegister = async (event) => {
    event.preventDefault()
    const validationError = validateRegistration(registration)
    if (validationError) {
      return setError(validationError)
    }

    await runRequest(async () => {
      await registerInstitution(registration)
      onClose?.()
      navigate(`/verify-email?email=${encodeURIComponent(registration.email.trim())}`)
    })
  }

  const handleForgotPassword = async (event) => {
    event.preventDefault()
    const validationError = validateEmail(email)
    if (validationError) return setError(validationError)

    await runRequest(async () => {
      await sendPasswordReset(email.trim().toLowerCase())
      setSuccess('If an institutional account exists for this address, a secure reset link has been dispatched.')
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

  const handleFileDrop = (e) => {
    e.preventDefault()
    e.stopPropagation()
    setDragActive(false)
    if (e.dataTransfer.files && e.dataTransfer.files[0]) {
      updateRegistration('registrationDocument', e.dataTransfer.files[0])
    }
  }

  return (
    <div
      className="auth-modal-overlay"
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose?.()
      }}
      role="dialog"
      aria-modal="true"
      aria-labelledby="auth-modal-title"
    >
      <div
        className={`auth-modal-card ${mode === 'register' ? 'auth-modal-card-wide' : ''}`}
        ref={modalRef}
      >
        <button
          type="button"
          className="auth-modal-close-btn"
          onClick={onClose}
          aria-label="Close dialog"
        >
          <X size={20} />
        </button>

        <div className="auth-modal-header">
          <div className="auth-modal-badge">
            <ShieldCheck size={14} />
            <span>Authorized Institution Gateway</span>
          </div>

          <div className="auth-modal-branding">
            <img src="/logo.png" alt="TravelEase Logo" className="auth-modal-logo" />
            <div>
              <h2 id="auth-modal-title">TravelEase Console</h2>
              <p className="auth-modal-subtitle">
                Institutional Accessibility &amp; Assistance Management
              </p>
            </div>
          </div>

          {/* Mode Switcher Tabs */}
          <div className="auth-modal-tabs" role="tablist">
            <button
              type="button"
              role="tab"
              aria-selected={mode === 'login'}
              className={`auth-modal-tab ${mode === 'login' ? 'active' : ''}`}
              onClick={() => switchMode('login')}
            >
              Sign In
            </button>
            <button
              type="button"
              role="tab"
              aria-selected={mode === 'register'}
              className={`auth-modal-tab ${mode === 'register' ? 'active' : ''}`}
              onClick={() => switchMode('register')}
            >
              Register Facility
            </button>
            <button
              type="button"
              role="tab"
              aria-selected={mode === 'forgot'}
              className={`auth-modal-tab ${mode === 'forgot' ? 'active' : ''}`}
              onClick={() => switchMode('forgot')}
            >
              Recovery
            </button>
          </div>
        </div>

        {/* Content Body */}
        <div className="auth-modal-body">
          {error && (
            <div className="form-alert error" role="alert">
              <AlertCircle size={16} />
              <span>{error}</span>
            </div>
          )}

          {success && (
            <div className="form-alert success" role="status">
              <CheckCircle2 size={16} />
              <span>{success}</span>
            </div>
          )}

          {mode === 'register' ? (
            <form onSubmit={handleRegister} noValidate className="auth-modal-form">
              <div className="form-grid">
                <div className="form-group">
                  <label>
                    <Building2 size={14} className="form-label-icon" />
                    Institution Name
                    <span className="required-mark"> *</span>
                  </label>
                  <input
                    className="input"
                    placeholder="e.g. Metro Airport Terminal 2"
                    value={registration.institutionName}
                    onChange={(e) => updateRegistration('institutionName', e.target.value)}
                    autoComplete="organization"
                  />
                </div>

                <div className="form-group">
                  <label>
                    Institution Type
                    <span className="required-mark"> *</span>
                  </label>
                  <select
                    className="input"
                    value={registration.institutionType}
                    onChange={(e) => updateRegistration('institutionType', e.target.value)}
                  >
                    <option value="">Select Facility Category</option>
                    <option value="airport_transport">Airport / Transportation Hub</option>
                    <option value="hotel_hospitality">Hotel &amp; Hospitality</option>
                    <option value="tourist_attraction">Tourist Attraction / Culture</option>
                    <option value="healthcare">Healthcare / Medical Center</option>
                    <option value="government">Civic &amp; Government Agency</option>
                    <option value="other">Other Commercial Facility</option>
                  </select>
                </div>

                <div className="form-group">
                  <label>
                    <Phone size={14} className="form-label-icon" />
                    Official Contact
                    <span className="required-mark"> *</span>
                  </label>
                  <input
                    className="input"
                    value={registration.officialContact}
                    onChange={(e) => updateRegistration('officialContact', e.target.value)}
                    placeholder="Duty phone or emergency hotline"
                  />
                </div>

                <div className="form-group">
                  <label>
                    <Mail size={14} className="form-label-icon" />
                    Institution Email
                    <span className="required-mark"> *</span>
                  </label>
                  <input
                    className="input"
                    type="email"
                    placeholder="ops@facility.org"
                    value={registration.email}
                    onChange={(e) => updateRegistration('email', e.target.value)}
                    autoComplete="email"
                  />
                </div>

                <div className="form-group auth-field-full">
                  <label>
                    <MapPin size={14} className="form-label-icon" />
                    Service Address
                    <span className="required-mark"> *</span>
                  </label>
                  <textarea
                    className="input"
                    rows={2}
                    placeholder="Official physical address of service facility / terminal"
                    value={registration.serviceAddress}
                    onChange={(e) => updateRegistration('serviceAddress', e.target.value)}
                  />
                </div>

                <div className="form-group auth-field-full">
                  <label>
                    <UploadCloud size={14} className="form-label-icon" />
                    Official Accreditation / Documentation
                    <span className="required-mark"> *</span>
                  </label>
                  <div
                    className={`auth-file-dropzone ${dragActive ? 'drag-active' : ''} ${
                      registration.registrationDocument ? 'has-file' : ''
                    }`}
                    style={{
                      display: 'flex',
                      flexDirection: 'column',
                      alignItems: 'center',
                      justifyContent: 'center',
                      textAlign: 'center',
                      width: '100%',
                    }}
                    onDragEnter={(e) => {
                      e.preventDefault()
                      setDragActive(true)
                    }}
                    onDragLeave={(e) => {
                      e.preventDefault()
                      setDragActive(false)
                    }}
                    onDragOver={(e) => e.preventDefault()}
                    onDrop={handleFileDrop}
                  >
                    <input
                      type="file"
                      id="institution-doc-upload"
                      className="auth-file-input"
                      accept=".pdf,image/jpeg,image/png"
                      onChange={(e) =>
                        updateRegistration('registrationDocument', e.target.files?.[0] || null)
                      }
                    />
                    <label
                      htmlFor="institution-doc-upload"
                      className="auth-file-label"
                      style={{
                        display: 'flex',
                        flexDirection: 'column',
                        alignItems: 'center',
                        justifyContent: 'center',
                        textAlign: 'center',
                        width: '100%',
                        cursor: 'pointer',
                        margin: 0,
                      }}
                    >
                      {registration.registrationDocument ? (
                        <div
                          className="auth-file-selected"
                          style={{
                            display: 'flex',
                            alignItems: 'center',
                            justifyContent: 'center',
                            gap: '12px',
                            width: '100%',
                          }}
                        >
                          <FileCheck size={24} className="text-teal" />
                          <div>
                            <span className="auth-file-name">
                              {registration.registrationDocument.name}
                            </span>
                            <span className="auth-file-size">
                              {(registration.registrationDocument.size / (1024 * 1024)).toFixed(2)} MB
                            </span>
                          </div>
                        </div>
                      ) : (
                        <div
                          className="auth-file-prompt"
                          style={{
                            display: 'flex',
                            flexDirection: 'column',
                            alignItems: 'center',
                            justifyContent: 'center',
                            textAlign: 'center',
                            width: '100%',
                            gap: '8px',
                          }}
                        >
                          <UploadCloud
                            size={28}
                            className="auth-upload-icon"
                            style={{ margin: '0 auto 4px auto' }}
                          />
                          <span
                            className="auth-upload-text"
                            style={{ textAlign: 'center', width: '100%', display: 'block' }}
                          >
                            <strong>Click to upload</strong> or drag facility certificate here
                          </span>
                          <span
                            className="auth-upload-hint"
                            style={{ textAlign: 'center', width: '100%', display: 'block' }}
                          >
                            PDF, JPG, or PNG (Maximum 10 MB)
                          </span>
                        </div>
                      )}
                    </label>
                  </div>
                </div>

                <div className="form-group">
                  <label>
                    <Lock size={14} className="form-label-icon" />
                    Console Password
                    <span className="required-mark"> *</span>
                  </label>
                  <input
                    className="input"
                    type="password"
                    placeholder="Min 8 chars, mixed case & numbers"
                    value={registration.password}
                    onChange={(e) => updateRegistration('password', e.target.value)}
                    autoComplete="new-password"
                  />
                </div>

                <div className="form-group">
                  <label>
                    <Lock size={14} className="form-label-icon" />
                    Confirm Password
                    <span className="required-mark"> *</span>
                  </label>
                  <input
                    className="input"
                    type="password"
                    placeholder="Re-enter password"
                    value={registration.confirmPassword}
                    onChange={(e) => updateRegistration('confirmPassword', e.target.value)}
                    autoComplete="new-password"
                  />
                </div>
              </div>

              <button
                type="submit"
                className="btn btn-primary auth-submit-btn"
                disabled={submitting}
              >
                {submitting ? 'Verifying Credentials…' : 'Submit Institution Application'}
                <ArrowRight size={16} />
              </button>

              <div className="auth-bottom-switch">
                <span>Already an authorized institution?</span>
                <button
                  type="button"
                  className="auth-link-btn"
                  onClick={() => switchMode('login')}
                >
                  Sign In to Console
                </button>
              </div>
            </form>
          ) : mode === 'forgot' ? (
            <form onSubmit={handleForgotPassword} noValidate className="auth-modal-form">
              <div className="auth-instructions-box">
                <HelpCircle size={18} className="text-teal" />
                <p>
                  Provide the institutional email connected to your venue. A cryptographically signed
                  recovery link will be generated for your verified administrator.
                </p>
              </div>

              <div className="form-group">
                <label>
                  <Mail size={14} className="form-label-icon" />
                  Registered Institutional Email
                  <span className="required-mark"> *</span>
                </label>
                <input
                  type="email"
                  className="input"
                  placeholder="admin@facility.org"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  autoComplete="email"
                />
              </div>

              <button
                type="submit"
                className="btn btn-primary auth-submit-btn"
                disabled={submitting}
              >
                {submitting ? 'Dispatching Recovery Link…' : 'Dispatch Password Reset Link'}
                <ArrowRight size={16} />
              </button>

              <div className="auth-bottom-switch">
                <button
                  type="button"
                  className="auth-link-btn"
                  onClick={() => switchMode('login')}
                >
                  Return to Sign In
                </button>
              </div>
            </form>
          ) : (
            <form onSubmit={handleLogin} noValidate className="auth-modal-form">
              <div className="form-group">
                <label>
                  <Mail size={14} className="form-label-icon" />
                  Institutional Email
                  <span className="required-mark"> *</span>
                </label>
                <input
                  type="email"
                  className="input"
                  placeholder="officer@airport-authority.com"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  autoComplete="email"
                  autoFocus
                />
              </div>

              <div className="form-group">
                <div className="form-label-row">
                  <label className="auth-form-label" style={{ color: '#FFFFFF', fontWeight: 600, display: 'inline-flex', alignItems: 'center' }}>
                    <Lock size={14} className="form-label-icon" />
                    Console Access Password
                    <span className="required-mark"> *</span>
                  </label>
                  <button
                    type="button"
                    className="auth-inline-forgot"
                    onClick={() => switchMode('forgot')}
                  >
                    Forgot Password?
                  </button>
                </div>
                <input
                  type="password"
                  className="input"
                  placeholder="••••••••••••"
                  value={password}
                  onChange={(e) => setPassword(e.target.value)}
                  autoComplete="current-password"
                />
              </div>

              <button
                type="submit"
                className="btn btn-primary auth-submit-btn"
                disabled={submitting}
              >
                {submitting ? 'Authenticating Station…' : 'Sign In to Operations Console'}
                <ArrowRight size={16} />
              </button>

              <div className="auth-bottom-switch">
                <span>Need to onboard a new public venue or hotel?</span>
                <button
                  type="button"
                  className="auth-link-btn"
                  onClick={() => switchMode('register')}
                >
                  Register Institution
                </button>
              </div>
            </form>
          )}
        </div>

        <div className="auth-modal-footer">
          <ShieldCheck size={14} className="text-teal" />
          <span>Encrypted TLS 1.3 · Restricted to Authorized Institutional Personnel Only</span>
        </div>
      </div>
    </div>
  )
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
  if (!/[A-Z]/.test(password) || !/[a-z]/.test(password) || !/[0-9]/.test(password)) {
    return 'Password must include uppercase, lowercase, and a number.'
  }
  return ''
}

function validateRegistration(form) {
  if (form.institutionName.trim().length < 2 || form.institutionName.trim().length > 120) {
    return 'Institution name must be between 2 and 120 characters.'
  }
  if (!form.institutionType) return 'Select a valid facility category.'
  if (form.officialContact.trim().length < 5 || form.officialContact.trim().length > 100) {
    return 'Enter a valid official duty contact phone or email.'
  }
  if (form.serviceAddress.trim().length < 10 || form.serviceAddress.trim().length > 500) {
    return 'Service address must be between 10 and 500 characters.'
  }
  const emailError = validateEmail(form.email)
  if (emailError) return emailError
  if (!form.registrationDocument) return 'Official accreditation/registration document is required.'
  if (!['application/pdf', 'image/jpeg', 'image/png'].includes(form.registrationDocument.type)) {
    return 'Registration document must be a PDF, JPG, or PNG file.'
  }
  if (form.registrationDocument.size > 10 * 1024 * 1024) {
    return 'Registration document must be 10 MB or smaller.'
  }
  const passwordError = validatePassword(form.password)
  if (passwordError) return passwordError
  if (form.password !== form.confirmPassword) return 'Passwords do not match.'
  return ''
}

function friendlyAuthError(error) {
  const message = String(error?.message || '').toLowerCase()
  if (message.includes('already registered') || message.includes('already exists')) {
    return 'An institutional account with this email address already exists.'
  }
  if (message.includes('email not confirmed')) {
    return 'Verify your institutional email before signing in.'
  }
  if (message.includes('invalid login credentials')) {
    return 'Incorrect email address or security password.'
  }
  if (message.includes('rate') || message.includes('too many') || error?.status === 429) {
    return 'Too many authentication attempts. Please wait 60 seconds and try again.'
  }
  if (message.includes('network') || message.includes('fetch')) {
    return 'Network connection failure. Verify internet connectivity.'
  }
  return error?.message || 'Unable to complete request. Please verify details and try again.'
}
