import React, { useCallback, useEffect, useState } from 'react'
import { useAuth } from '../context/AuthContext'
import { staffRepository } from '../repositories/staffRepository'
import { sosRequestRepository } from '../repositories/sosRequestRepository'

const emptyForm = { id: '', name: '', email: '', contact_number: '', role: 'staff', status: 'free' }

export default function StaffAccountManager() {
  const { staffContext } = useAuth()
  const [staff, setStaff] = useState([])
  const [loading, setLoading] = useState(true)
  const [busy, setBusy] = useState('')
  const [message, setMessage] = useState('')
  const [error, setError] = useState('')
  const [form, setForm] = useState(null)

  const load = useCallback(async ({ quiet = false } = {}) => {
    if (!quiet) { setLoading(true); setError('') }
    try { setStaff(await staffRepository.list(staffContext)) }
    catch (loadError) { setError(loadError.message || 'Unable to load staff accounts.') }
    finally { if (!quiet) setLoading(false) }
  }, [staffContext])

  useEffect(() => {
    load()
    const institutionId = staffContext?.institution_id || staffContext?.institutions?.id
    if (!institutionId) return undefined
    const refresh = () => load({ quiet: true })
    const unsubscribeStaff = staffRepository.subscribe(institutionId, refresh)
    const unsubscribeSos = sosRequestRepository.subscribe(institutionId, refresh)
    // Keep availability current even when Realtime is disconnected or disabled.
    const timer = window.setInterval(refresh, 10000)
    window.addEventListener('focus', refresh)
    return () => {
      unsubscribeStaff()
      unsubscribeSos()
      window.clearInterval(timer)
      window.removeEventListener('focus', refresh)
    }
  }, [load, staffContext])

  const save = async () => {
    const validation = validate(form)
    if (validation) return setError(validation)
    setBusy('save')
    setError('')
    try {
      if (form.id) await staffRepository.update(form.id, form)
      else await staffRepository.create(form)
      setForm(null)
      setMessage(form.id ? 'Staff profile updated.' : 'Staff invited. Supabase sent an account setup email.')
      await load()
    } catch (saveError) { setError(saveError.message || 'Unable to save staff.') }
    finally { setBusy('') }
  }

  const toggleActive = async (member) => {
    setBusy(member.id); setError(''); setMessage('')
    try {
      await staffRepository.setActive(member.id, !member.active)
      setMessage(member.active ? 'Staff account deactivated.' : 'Staff account activated.')
      await load()
    } catch (actionError) { setError(actionError.message || 'Unable to change account status.') }
    finally { setBusy('') }
  }

  const remove = async (member) => {
    if (!window.confirm(`Delete ${member.name}? Staff with existing request history will be deactivated instead.`)) return
    setBusy(member.id); setError(''); setMessage('')
    try {
      const result = await staffRepository.remove(member.id)
      setMessage(result.message || 'Staff account deleted.')
      await load()
    } catch (actionError) { setError(actionError.message || 'Unable to remove staff.') }
    finally { setBusy('') }
  }

  return <>
    <div className="card staff-account-card">
      <div className="card-header">
        <div><h3>Staff Account Management</h3><div className="staff-card-subtitle">Manage staff access and availability for this institution.</div></div>
        <button className="btn btn-outline btn-sm" onClick={() => { setForm({ ...emptyForm }); setError(''); setMessage('') }}>+ Invite Staff</button>
      </div>
      {error && !form && <div className="form-alert error" role="alert">{error}</div>}
      {message && <div className="form-alert success" role="status">{message}</div>}
      {loading ? <div className="form-alert info" role="status">Loading staff accounts…</div> : staff.length === 0 ?
        <div className="staff-empty">No staff accounts yet. Invite the first staff member to begin.</div> :
        <div className="staff-table-wrap"><table className="data-table staff-table">
          <thead><tr><th>Staff</th><th>Role</th><th>Availability</th><th>Account</th><th>Actions</th></tr></thead>
          <tbody>{staff.map((member) => <tr key={member.id} className={!member.active ? 'staff-row-inactive' : ''}>
            <td><strong>{member.name}</strong><small>{member.email || 'Legacy account — no email linked'}{member.contact_number ? ` · ${member.contact_number}` : ''}</small></td>
            <td><span className="badge primary">{title(member.role)}</span></td>
            <td><span className={`badge ${member.active && member.status === 'free' ? 'success' : 'muted'}`}>{member.active ? title(member.status) : 'Inactive'}</span></td>
            <td><span className={`badge ${member.active ? 'success' : 'muted'}`}>{member.active ? 'Active' : 'Inactive'}</span></td>
            <td><div className="staff-actions">
              <button className="btn btn-outline btn-sm" disabled={busy === member.id} onClick={() => { setForm({ ...member }); setError(''); setMessage('') }}>Edit</button>
              <button className="btn btn-outline btn-sm" disabled={busy === member.id} onClick={() => toggleActive(member)}>{member.active ? 'Deactivate' : 'Activate'}</button>
              <button className="btn btn-danger btn-sm" disabled={busy === member.id} onClick={() => remove(member)}>Delete</button>
            </div></td>
          </tr>)}</tbody>
        </table></div>}
    </div>
    {form && <StaffDialog form={form} setForm={setForm} saving={busy === 'save'} error={error} onClose={() => { setForm(null); setError('') }} onSave={save} />}
  </>
}

function StaffDialog({ form, setForm, saving, error, onClose, onSave }) {
  const update = (field) => (event) => setForm((current) => ({ ...current, [field]: event.target.value }))
  return <div className="service-area-backdrop" role="presentation" onMouseDown={onClose}>
    <div className="service-area-dialog staff-dialog" role="dialog" aria-modal="true" aria-labelledby="staff-dialog-title" onMouseDown={(event) => event.stopPropagation()}>
      <div className="service-area-dialog-header"><div><h3 id="staff-dialog-title">{form.id ? 'Edit Staff' : 'Invite Staff'}</h3><p>No password is stored here. New staff receive a secure Supabase invitation email.</p></div><button className="icon-button" aria-label="Close" onClick={onClose}>×</button></div>
      {error && <div className="form-alert error" role="alert">{error}</div>}
      <div className="staff-form-grid">
        <div className="form-group"><label>Full Name</label><input className="input" value={form.name} onChange={update('name')} disabled={saving} /></div>
        <div className="form-group"><label>Email</label><input type="email" className="input" value={form.email || ''} onChange={update('email')} disabled={saving} /></div>
        <div className="form-group"><label>Phone</label><input className="input" value={form.contact_number || ''} onChange={update('contact_number')} disabled={saving} /></div>
        {form.id && <div className="form-group"><label>Availability</label><select className="input" value={form.status} onChange={update('status')} disabled={saving || !form.active}><option value="free">Free</option><option value="assigned">Assigned</option></select></div>}
      </div>
      <div className="service-area-dialog-actions"><button className="btn btn-outline" onClick={onClose} disabled={saving}>Cancel</button><button className="btn btn-primary" onClick={onSave} disabled={saving}>{saving ? 'Saving…' : form.id ? 'Save Staff' : 'Send Invitation'}</button></div>
    </div>
  </div>
}

function validate(form) {
  if (!form || form.name.trim().length < 2 || form.name.trim().length > 120) return 'Full name must be between 2 and 120 characters.'
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(form.email.trim())) return 'Enter a valid staff email address.'
  if (form.contact_number?.trim().length > 40) return 'Phone number must be 40 characters or fewer.'
  return ''
}

function title(value) {
  const text = String(value || '')
  return text ? text.charAt(0).toUpperCase() + text.slice(1) : '—'
}
