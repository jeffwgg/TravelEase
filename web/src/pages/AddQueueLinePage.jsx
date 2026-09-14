import React, { useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'
import { queueRepository } from '../repositories/queueRepository'
import { serviceAreaRepository } from '../repositories/serviceAreaRepository'
import { useAutoDismiss } from '../hooks/useAutoDismiss'

const initialForm = {
  name: '', serviceAreaId: '', prefix: '', firstNumber: '',
  status: 'active', estimatedServiceMinutes: '5', maxTrackingNumber: '',
  operatingHours: '', staffNotes: '',
}

const formatQueueNumber = (prefix, value) => {
  const cleanPrefix = prefix.trim().toUpperCase().replace(/[-\s]+$/, '')
  if (value === '') return ''
  const number = Number(value)
  if (!cleanPrefix || !Number.isInteger(number) || number < 0) return ''
  return `${cleanPrefix}-${String(number).padStart(3, '0')}`
}

export default function AddQueueLinePage() {
  const navigate = useNavigate()
  const { session, staffContext } = useAuth()
  const [form, setForm] = useState(initialForm)
  const [serviceAreas, setServiceAreas] = useState([])
  const [loadingServiceAreas, setLoadingServiceAreas] = useState(true)
  const [fieldErrors, setFieldErrors] = useState({})
  const [error, setError] = useState('')
  const [submitting, setSubmitting] = useState(false)
  useAutoDismiss(error, () => setError(''))

  useEffect(() => {
    let active = true
    serviceAreaRepository.list(staffContext)
      .then((areas) => { if (active) setServiceAreas(areas.filter((area) => area.active)) })
      .catch((loadError) => { if (active) setError(loadError.message || 'Unable to load service areas.') })
      .finally(() => { if (active) setLoadingServiceAreas(false) })
    return () => { active = false }
  }, [staffContext])

  const update = (field) => (event) => {
    setForm((current) => ({ ...current, [field]: event.target.value }))
    setFieldErrors((current) => ({ ...current, [field]: '' }))
  }

  const validate = () => {
    const next = {}
    if (!form.name.trim()) next.name = 'Queue line name is required.'
    if (!form.serviceAreaId) next.serviceAreaId = 'Select a service area.'
    if (!form.prefix.trim()) next.prefix = 'Queue prefix is required.'
    const firstNumber = Number(form.firstNumber)
    if (form.firstNumber !== '' && (!Number.isInteger(firstNumber) || firstNumber < 0)) next.firstNumber = 'Enter a whole number of 0 or greater.'
    if (!form.status) next.status = 'Queue status is required.'
    const minutes = Number(form.estimatedServiceMinutes)
    if (!Number.isInteger(minutes) || minutes < 1 || minutes > 240) next.estimatedServiceMinutes = 'Enter a whole number from 1 to 240.'
    const maxTracking = Number(form.maxTrackingNumber)
    if (form.maxTrackingNumber !== '' && (!Number.isInteger(maxTracking) || maxTracking < 1 || maxTracking > 500)) next.maxTrackingNumber = 'Enter a whole number from 1 to 500.'
    setFieldErrors(next)
    return Object.keys(next).length === 0
  }

  const submit = async (event) => {
    event.preventDefault()
    if (!validate()) return
    setSubmitting(true)
    setError('')
    try {
      const serviceArea = serviceAreas.find((area) => area.id === form.serviceAreaId)
      if (!serviceArea) {
        setFieldErrors((current) => ({ ...current, serviceAreaId: 'Select an active service area.' }))
        return
      }
      // Empty inputs fall back to the defaults shown as placeholders.
      const firstNumber = form.firstNumber === '' ? 1 : Number(form.firstNumber)
      const maxTrackingNumber = form.maxTrackingNumber === '' ? 100 : Number(form.maxTrackingNumber)
      const currentNumber = formatQueueNumber(form.prefix, firstNumber)
      const upcomingNumber = formatQueueNumber(form.prefix, firstNumber + 1)
      await queueRepository.createQueueLine({
        institution_id: staffContext.institution_id,
        name: form.name.trim(),
        service_area_id: serviceArea.id,
        // Kept as a denormalised display label for existing queue screens.
        service_area: serviceArea.name,
        prefix: form.prefix.trim().toUpperCase(),
        current_number: currentNumber,
        upcoming_number: upcomingNumber,
        status: form.status,
        estimated_service_minutes: Number(form.estimatedServiceMinutes),
        max_tracking_number: maxTrackingNumber,
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
        <form className="card full-width-form" onSubmit={submit} noValidate>
          {error && <div className="form-alert error" role="alert">{error}</div>}
          <div className="form-grid">
            <div className="form-group"><label htmlFor="queue-name">Queue Line Name <span className="required-mark">*</span></label><input id="queue-name" className={`input ${fieldErrors.name ? 'invalid' : ''}`} value={form.name} onChange={update('name')} placeholder="e.g. A Series" />{fieldError('name')}</div>
            <div className="form-group"><label htmlFor="queue-service-area">Service Area <span className="required-mark">*</span></label><select id="queue-service-area" className={`input ${fieldErrors.serviceAreaId ? 'invalid' : ''}`} value={form.serviceAreaId} onChange={update('serviceAreaId')} disabled={loadingServiceAreas}><option value="">{loadingServiceAreas ? 'Loading service areas…' : serviceAreas.length ? 'Select a service area' : 'No active service areas'}</option>{serviceAreas.map((area) => <option key={area.id} value={area.id}>{area.name}</option>)}</select>{fieldError('serviceAreaId')}{!loadingServiceAreas && serviceAreas.length === 0 && <div className="field-note">Create an active service area in the institution profile before creating a queue line.</div>}</div>
            <div className="form-group"><label htmlFor="queue-prefix">Queue Prefix <span className="required-mark">*</span></label><input id="queue-prefix" className={`input ${fieldErrors.prefix ? 'invalid' : ''}`} value={form.prefix} onChange={update('prefix')} placeholder="e.g. A" maxLength={8} />{fieldError('prefix')}</div>
            <div className="form-group"><label htmlFor="queue-first-number">First Number</label><input id="queue-first-number" type="number" min="0" step="1" className={`input ${fieldErrors.firstNumber ? 'invalid' : ''}`} value={form.firstNumber} onChange={update('firstNumber')} placeholder="1" />{fieldError('firstNumber')}<div className="field-note">Numbers only; defaults to 1 when left empty. The queue prefix is added automatically.</div><div className="queue-number-preview" role="note"><div><span>Current number</span><strong>{formatQueueNumber(form.prefix, form.firstNumber === '' ? 1 : form.firstNumber) || 'A-001'}</strong></div><span className="queue-number-preview-arrow">→</span><div><span>Next number (+1)</span><strong>{formatQueueNumber(form.prefix, form.firstNumber === '' ? 2 : Number(form.firstNumber) + 1) || 'A-002'}</strong></div></div></div>
            <div className="form-group"><label htmlFor="queue-status">Queue Status <span className="required-mark">*</span></label><select id="queue-status" className={`input ${fieldErrors.status ? 'invalid' : ''}`} value={form.status} onChange={update('status')}><option value="active">Active</option><option value="paused">Paused</option><option value="closed">Closed</option></select>{fieldError('status')}</div>
            <div className="form-group"><label htmlFor="queue-minutes">Estimated Service Time (Minutes) <span className="required-mark">*</span></label><input id="queue-minutes" type="number" min="1" max="240" className={`input ${fieldErrors.estimatedServiceMinutes ? 'invalid' : ''}`} value={form.estimatedServiceMinutes} onChange={update('estimatedServiceMinutes')} placeholder="e.g. 5" />{fieldError('estimatedServiceMinutes')}</div>
            <div className="form-group"><label htmlFor="queue-max-tracking">Maximum Queue Number</label><input id="queue-max-tracking" type="number" min="1" max="500" step="1" className={`input ${fieldErrors.maxTrackingNumber ? 'invalid' : ''}`} value={form.maxTrackingNumber} onChange={update('maxTrackingNumber')} placeholder="100" />{fieldError('maxTrackingNumber')}<div className="field-note">Queue numbers stop at this value (default 100); no larger numbers can be called or tracked.</div></div>
            <div className="form-group"><label htmlFor="queue-hours">Operating Hours (Optional)</label><input id="queue-hours" className="input" value={form.operatingHours} onChange={update('operatingHours')} placeholder="e.g. 6:00 AM – 11:00 PM" /></div>
          </div>
          <div className="form-group"><label htmlFor="queue-notes">Staff Notes (Optional)</label><textarea id="queue-notes" className="input" rows={4} value={form.staffNotes} onChange={update('staffNotes')} maxLength={2000} placeholder="Add operational notes for staff managing this queue..." /></div>
          <div className="modal-actions"><Link to="/queue" className="btn btn-outline">Cancel</Link><button type="submit" className="btn btn-primary" disabled={submitting}>{submitting ? 'Creating…' : 'Create Queue Line'}</button></div>
        </form>
      </div>
    </div>
  )
}
