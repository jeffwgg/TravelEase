import { useEffect, useState } from 'react'
import { KeyRound, UserRound } from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'
import useStaffWorkspace from '../hooks/useStaffWorkspace'
import { staffRepository } from '../repositories/staffRepository'
import { validateNewPassword } from '../lib/accountAccess'
import { staffStatusLabel } from '../components/StaffSosOverview'

export default function StaffProfilePage() {
  const { session, staffContext, refreshStaffContext, updatePassword } = useAuth()
  const { staff, loading, error: loadError, refresh } = useStaffWorkspace()
  const [name, setName] = useState('')
  const [password, setPassword] = useState('')
  const [confirmation, setConfirmation] = useState('')
  const [busy, setBusy] = useState('')
  const [error, setError] = useState('')
  const [message, setMessage] = useState('')
  const navigate = useNavigate()
  useEffect(() => { if (staff?.name) setName(staff.name) }, [staff?.name])
  const saveName = async event => {
    event.preventDefault()
    setMessage(''); setError('')
    if (!name.trim() || name.trim().length > 100) return setError('Name must be between 1 and 100 characters.')
    setBusy('name')
    try {
      await staffRepository.updateOwnName(name)
      await refreshStaffContext()
      refresh()
      setMessage('Your name has been updated.')
    } catch (err) { setError(err.message || 'Unable to update your name.') }
    finally { setBusy('') }
  }
  const changePassword = async event => {
    event.preventDefault()
    setMessage(''); setError('')
    const validation = validateNewPassword(password, confirmation)
    if (validation) return setError(validation)
    setBusy('password')
    try {
      await updatePassword(password)
      setPassword(''); setConfirmation('')
      navigate('/auth', { replace: true, state: { passwordReset: true } })
    } catch (err) { setError(err.message || 'Unable to change your password.') }
    finally { setBusy('') }
  }
  return <div className="page staff-workspace">
    <header className="staff-workspace-header"><div><span className="staff-eyebrow">STAFF ACCOUNT</span><h1>My profile</h1><p>Your details and account security.</p></div><UserRound size={26} /></header>
    {(error || loadError) && <div className="form-alert error" role="alert">{error || loadError}</div>}
    {message && <div className="form-alert success" role="status">{message}</div>}
    {loading ? <p role="status">Loading your profile…</p> : <div className="staff-profile-grid">
      <section className="card staff-profile-card"><h2>Personal details</h2><form onSubmit={saveName}>
        <div className="form-group"><label htmlFor="staff-name">Name</label><input id="staff-name" className="input" value={name} onChange={event => setName(event.target.value)} maxLength={100} autoComplete="name" required disabled={Boolean(busy) || !staff} /></div>
        <div className="form-group"><label htmlFor="staff-email">Email</label><input id="staff-email" className="input" type="email" value={session?.user?.email || staff?.email || ''} readOnly aria-describedby="staff-email-help" /><small id="staff-email-help">Your institution manages your email address.</small></div>
        <dl className="staff-profile-details"><div><dt>Institution</dt><dd>{staffContext?.institutions?.name}</dd></div><div><dt>Role</dt><dd>Institution Staff</dd></div><div><dt>Availability</dt><dd><span className={`sos-status ${staff?.status === 'free' ? 'resolved' : 'assigned'}`}>{staffStatusLabel(staff)}</span></dd></div></dl>
        <p className="staff-muted">Availability updates automatically with your assigned tasks.</p>
        <button className="btn btn-primary btn-sm" disabled={Boolean(busy) || !staff}>{busy === 'name' ? 'Saving…' : 'Save name'}</button>
      </form></section>
      <section className="card staff-profile-card"><h2><KeyRound size={18} /> Change password</h2><p className="staff-muted">Use at least 8 characters with uppercase, lowercase, and a number. Sign in again after changing it.</p><form onSubmit={changePassword}>
        <div className="form-group"><label htmlFor="staff-password">New password</label><input id="staff-password" className="input" type="password" autoComplete="new-password" value={password} onChange={event => setPassword(event.target.value)} required disabled={Boolean(busy)} /></div>
        <div className="form-group"><label htmlFor="staff-password-confirm">Confirm new password</label><input id="staff-password-confirm" className="input" type="password" autoComplete="new-password" value={confirmation} onChange={event => setConfirmation(event.target.value)} required disabled={Boolean(busy)} /></div>
        <button className="btn btn-primary btn-sm" disabled={Boolean(busy) || !staff}>{busy === 'password' ? 'Updating…' : 'Change password'}</button>
      </form></section>
    </div>}
  </div>
}
