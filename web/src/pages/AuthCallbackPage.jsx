import React from 'react'
import { CheckCircle2 } from 'lucide-react'
import { Link } from 'react-router-dom'

export default function AuthCallbackPage() {
  return (
    <div className="auth-page">
      <div className="auth-card auth-message-card">
        <CheckCircle2 size={54} color="var(--success)" />
        <h2>Email verified</h2>
        <p>Your institution email has been verified. You can now sign in to the portal.</p>
        <Link className="btn btn-primary auth-submit" to="/auth">Continue to Sign In</Link>
      </div>
    </div>
  )
}
