import React from 'react'
import { MailCheck } from 'lucide-react'
import { Link, useSearchParams } from 'react-router-dom'

export default function VerifyEmailPage() {
  const [params] = useSearchParams()
  const email = params.get('email')
  return (
    <div className="auth-page">
      <div className="auth-card auth-message-card">
        <MailCheck size={54} color="var(--primary)" />
        <h2>Verify your email</h2>
        <p>We sent a verification link{email ? <> to <strong>{email}</strong></> : ''}. Open it to activate your institution account.</p>
        <p className="field-note">After verification, return here and sign in using your institution credentials.</p>
        <Link className="btn btn-primary auth-submit" to="/auth">Back to Sign In</Link>
      </div>
    </div>
  )
}
