import React, { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'
import { queueRepository } from '../repositories/queueRepository'

const initialForm = {
  name: '', serviceArea: '', counter: '', prefix: '', currentNumber: '', upcomingNumber: '',
  status: 'active', estimatedServiceMinutes: '5', operatingHours: '', staffNotes: '',
}

export default function AddQueueLinePage() {
  const navigate = useNavigate()
  const { session, staffContext } = useAuth()
  const [form, setForm] = useState(initialForm)
  const [fieldErrors, setFieldErrors] = useState({})
  const [error, setError] = useState('')
  const [submitting, setSubmitting] = useState(false)

  const update = (field) => (event) => {
    setForm((current) => ({ ...current, [field]: event.target.value }))
    setFieldErrors((current) => ({ ...current, [field]: '' }))
  }

  const validate = () => {
    const next = {}
    if (!form.name.trim()) next.name = 'Queue line name is required.'
    if (!form.serviceArea.trim()) next.serviceArea = 'Service area is required.'
    if (!form.counter.trim()) next.counter = 'Counter is required.'
    if (!form.prefix.trim()) next.prefix = 'Queue prefix is required.'
    if (!form.currentNumber.trim()) next.currentNumber = 'Current number is required.'
    if (!form.upcomingNumber.trim()) next.upcomingNumber = 'Upcoming number is required.'
    if (!form.status) next.status = 'Queue status is required.'
    const minutes = Number(form.estimatedServiceMinutes)
    if (!Number.isInteger(minutes) || minutes < 1 || minutes > 240) next.estimatedServiceMinutes = 'Enter a whole number from 1 to 240.'
    setFieldErrors(next)
    return Object.keys(next).length === 0
  }

  const submit = async (event) => {
    event.preventDefault()
    if (!validate()) return
    setSubmitting(true)
    setError('')
    try {
      await queueRepository.createQueueLine({
        institution_id: staffContext.institution_id,
        name: form.name.trim(),
        service_area: form.serviceArea.trim(),
        counter: form.counter.trim(),
        prefix: form.prefix.trim().toUpperCase(),
        current_number: form.currentNumber.trim().toUpperCase(),
        upcoming_number: form.upcomingNumber.trim().toUpperCase(),
        status: form.status,
        estimated_service_minutes: Number(form.estimatedServiceMinutes),
        operating_hours: form.operatingHours.trim() || null,
        staff_notes: form.staffNotes.trim() || null,
        created_by: session.user.id,
      })
      navigate('/queue', { replace: true })
    } catch (submitError) {
      setError(submitError.message || 'Unable to create the queue line.')
    } finally {
      setSubmitting(false)
    }
  }

  const fieldError = (name) => fieldErrors[name] && <div className="field-error" role="alert">{fieldErrors[name]}</div>

  return (
    <div>
      <div className="page-header">
        <div><h2>Add Queue Line</h2><div className="header-subtitle">Set up a service queue and its initial serving information.</div></div>
        <Link to="/queue" className="btn btn-outline">Back to Queue Management</Link>
      </div>
      <div className="page-body">
        <form className="card" style={{ maxWidth: 820 }} onSubmit={submit} noValidate>
          {error && <div className="form-alert error" role="alert">{error}</div>}
          <div className="form-grid">
            <div className="form-group"><label htmlFor="queue-name">Queue Line Name <span className="required-mark">*</span></label><input id="queue-name" className={`input ${fieldErrors.name ? 'invalid' : ''}`} value={form.name} onChange={update('name')} placeholder="e.g. A Series" />{fieldError('name')}</div>
            <div className="form-group"><label htmlFor="queue-service">Service Area <span className="required-mark">*</span></label><input id="queue-service" className={`input ${fieldErrors.serviceArea ? 'invalid' : ''}`} value={form.serviceArea} onChange={update('serviceArea')} placeholder="e.g. General Ticketing" />{fieldError('serviceArea')}</div>
            <div className="form-group"><label htmlFor="queue-counter">Counter <span className="required-mark">*</span></label><input id="queue-counter" className={`input ${fieldErrors.counter ? 'invalid' : ''}`} value={form.counter} onChange={update('counter')} placeholder="e.g. Counter #1 — Main Service Desk" />{fieldError('counter')}</div>
            <div className="form-group"><label htmlFor="queue-prefix">Queue Prefix <span className="required-mark">*</span></label><input id="queue-prefix" className={`input ${fieldErrors.prefix ? 'invalid' : ''}`} value={form.prefix} onChange={update('prefix')} placeholder="e.g. A" maxLength={8} />{fieldError('prefix')}</div>
            <div className="form-group"><label htmlFor="queue-current">Current Number <span className="required-mark">*</span></label><input id="queue-current" className={`input ${fieldErrors.currentNumber ? 'invalid' : ''}`} value={form.currentNumber} onChange={update('currentNumber')} placeholder="e.g. A-001" />{fieldError('currentNumber')}</div>
            <div className="form-group"><label htmlFor="queue-upcoming">Upcoming Number <span className="required-mark">*</span></label><input id="queue-upcoming" className={`input ${fieldErrors.upcomingNumber ? 'invalid' : ''}`} value={form.upcomingNumber} onChange={update('upcomingNumber')} placeholder="e.g. A-002" />{fieldError('upcomingNumber')}</div>
            <div className="form-group"><label htmlFor="queue-status">Queue Status <span className="required-mark">*</span></label><select id="queue-status" className={`input ${fieldErrors.status ? 'invalid' : ''}`} value={form.status} onChange={update('status')}><option value="active">Active</option><option value="paused">Paused</option><option value="closed">Closed</option></select>{fieldError('status')}</div>
            <div className="form-group"><label htmlFor="queue-minutes">Estimated Service Time (Minutes) <span className="required-mark">*</span></label><input id="queue-minutes" type="number" min="1" max="240" className={`input ${fieldErrors.estimatedServiceMinutes ? 'invalid' : ''}`} value={form.estimatedServiceMinutes} onChange={update('estimatedServiceMinutes')} placeholder="e.g. 5" />{fieldError('estimatedServiceMinutes')}</div>
            <div className="form-group"><label htmlFor="queue-hours">Operating Hours (Optional)</label><input id="queue-hours" className="input" value={form.operatingHours} onChange={update('operatingHours')} placeholder="e.g. 6:00 AM – 11:00 PM" /></div>
          </div>
          <div className="form-group"><label htmlFor="queue-notes">Staff Notes (Optional)</label><textarea id="queue-notes" className="input" rows={4} value={form.staffNotes} onChange={update('staffNotes')} maxLength={2000} placeholder="Add operational notes for staff managing this queue..." /></div>
          <div className="modal-actions"><Link to="/queue" className="btn btn-outline">Cancel</Link><button type="submit" className="btn btn-primary" disabled={submitting}>{submitting ? 'Creating…' : 'Create Queue Line'}</button></div>
        </form>
      </div>
    </div>
  )
}
