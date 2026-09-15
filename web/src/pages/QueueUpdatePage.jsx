import React, { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'
import { queueRepository } from '../repositories/queueRepository'
import { serviceAreaRepository } from '../repositories/serviceAreaRepository'
import { useAutoDismiss } from '../hooks/useAutoDismiss'

const labelStatus = (status) => status ? status[0].toUpperCase() + status.slice(1) : ''

const numericQueueValue = (value) => {
  const match = String(value || '').match(/(\d+)\s*$/)
  return match ? parseInt(match[1], 10) : null
}

// Real waiters are numbers a traveller actually holds (claimed by tracking
// it in the mobile app) that have not been called yet. The traceable window
// pre-registers future numbers as 'waiting' with no traveller, so counting
// those would always show at least one person waiting.
const realWaitingCount = (line) => {
  const current = numericQueueValue(line.current_number)
  const waiting = line.queue_numbers?.filter((number) => {
    if (number.status !== 'waiting' || !number.traveler_id) return false
    const value = numericQueueValue(number.number)
    return current == null || value == null || value > current
  }).length
  return waiting || 0
}

// The two closest numbers before the currently called number provide staff a
// compact, actionable record without turning each queue card into a full
// history table.
const recentPastRecords = (line) => {
  const current = numericQueueValue(line.current_number)
  return (line.queue_numbers || [])
    .filter((number) => {
      const value = numericQueueValue(number.number)
      return value != null && value !== current && (current == null || value < current)
    })
    .sort((left, right) => (numericQueueValue(right.number) || 0) - (numericQueueValue(left.number) || 0))
    .slice(0, 2)
}

export default function QueueUpdatePage() {
  const { session, staffContext } = useAuth()
  const [lines, setLines] = useState([])
  const [serviceAreas, setServiceAreas] = useState([])
  const [editing, setEditing] = useState(null)
  const [directLineId, setDirectLineId] = useState('')
  const [directNumber, setDirectNumber] = useState('')
  const [lookupNumber, setLookupNumber] = useState('')
  const [lookupLineId, setLookupLineId] = useState('')
  const [lookupResult, setLookupResult] = useState(null)
  const [lookupError, setLookupError] = useState('')
  const [lineStatusFilter, setLineStatusFilter] = useState('active')
  const [serviceAreaFilter, setServiceAreaFilter] = useState('all')
  const [loading, setLoading] = useState(true)
  const [busyId, setBusyId] = useState('')
  const [error, setError] = useState('')
  const [editingError, setEditingError] = useState('')
  const [success, setSuccess] = useState('')
  useAutoDismiss(error, () => setError(''))
  useAutoDismiss(editingError, () => setEditingError(''))
  useAutoDismiss(success, () => setSuccess(''))
  useAutoDismiss(lookupError, () => setLookupError(''))
  const filteredLines = lines.filter((line) => {
    const matchesStatus = lineStatusFilter === 'all' || line.status === lineStatusFilter
    const matchesServiceArea = serviceAreaFilter === 'all' || line.service_area_id === serviceAreaFilter
    return matchesStatus && matchesServiceArea && line.status !== 'reset'
  })
  const operationalLines = filteredLines.filter((line) => line.status !== 'closed')

  // A line is exhausted once its upcoming number would exceed the maximum
  // queue number; calling and notifying must stop there.
  const maxQueueNumberReached = (line) => {
    const cap = Number(line.max_tracking_number)
    if (!Number.isFinite(cap) || cap <= 0) return false
    const upcoming = numericQueueValue(line.upcoming_number)
    return upcoming != null && upcoming > cap
  }

  const loadLines = useCallback(async (quiet = false) => {
    if (!quiet) setLoading(true)
    try {
      const data = await queueRepository.getQueueLines(staffContext.institution_id)
      setLines(data)
      const firstOperational = data.find((line) => !['closed', 'reset'].includes(line.status))
      setDirectLineId((current) => {
        const validSelection = data.find((line) => line.id === current && !['closed', 'reset'].includes(line.status))
        if (!validSelection) setDirectNumber(firstOperational?.upcoming_number || '')
        else setDirectNumber((number) => number || validSelection.upcoming_number)
        return validSelection?.id || firstOperational?.id || ''
      })
      setError('')
    } catch (loadError) {
      setError(loadError.message || 'Unable to load queue lines.')
    } finally {
      if (!quiet) setLoading(false)
    }
  }, [staffContext.institution_id])

  useEffect(() => {
    loadLines()
    const unsubscribe = queueRepository.subscribe(staffContext.institution_id, () => loadLines(true))
    // Realtime can silently miss events (publication/RLS on either table), so
    // poll as a fallback — the waiting count, serving number and statuses
    // must stay current without a manual page refresh.
    const pollTimer = setInterval(() => loadLines(true), 15000)
    return () => {
      unsubscribe?.()
      clearInterval(pollTimer)
    }
  }, [loadLines, staffContext.institution_id])

  useEffect(() => {
    let active = true
    serviceAreaRepository.list(staffContext)
      .then((areas) => {
        if (active) setServiceAreas(areas.filter((area) => area.active))
      })
      .catch((loadError) => {
        if (active) setError(loadError.message || 'Unable to load service areas.')
      })
    return () => { active = false }
  }, [staffContext])

  const openManage = (line) => {
    setEditing({ ...line, was_closed: line.status === 'closed', originalStatus: line.status })
    setError('')
    setEditingError('')
  }

  const saveLine = async () => {
    const serviceArea = serviceAreas.find((area) => area.id === editing.service_area_id)
    if (!editing.name.trim() || !serviceArea) {
      setEditingError('Queue line name and an active service area are required.')
      return
    }
    if (editing.status !== editing.originalStatus) {
      const statusWarnings = {
        closed: 'Travellers will no longer see this queue line, and its queue numbers become read-only until it is reopened.',
        active: 'Staff can call the next number and travellers can track it again.',
      }
      const confirmed = window.confirm(
        `Change the status of "${editing.name}" from ${labelStatus(editing.originalStatus)} to ${labelStatus(editing.status)}?\n\n${statusWarnings[editing.status] || ''}`,
      )
      if (!confirmed) return
    }
    setBusyId(editing.id)
    setEditingError('')
    try {
      await queueRepository.updateQueueLine(editing.id, {
        name: editing.name.trim(),
        service_area_id: serviceArea.id,
        service_area: serviceArea.name,
        status: editing.status,
        estimated_service_minutes: Number(editing.estimated_service_minutes),
        max_tracking_number: Number(editing.max_tracking_number) > 0 ? Number(editing.max_tracking_number) : 100,
        operating_hours: editing.operating_hours?.trim() || null,
        staff_notes: editing.staff_notes?.trim() || null,
      }, session.user.id)
      setEditing(null)
      setSuccess('Queue information updated.')
      await loadLines(true)
    } catch (saveError) {
      setEditingError(saveError.message || 'Unable to update the queue line.')
    } finally {
      setBusyId('')
    }
  }

  const resetNumbers = async () => {
    const firstNumber = `${(editing.prefix || '').toUpperCase()}-001`
    const waiting = realWaitingCount(editing)
    const reminder = waiting > 0
      ? `Reminder: ${waiting} traveller(s) are still waiting in line. Resetting will cancel their queued numbers and they will need to take a new number.`
      : 'Reminder: make sure no one is waiting in line — resetting cancels any queued numbers and those travellers will need to take a new number.'
    const confirmed = window.confirm(
      `Reset "${editing.name}"?\n\nThis archives the old queue line with Reset status and creates a new queue line (new queue ID) beginning at ${firstNumber}. ${reminder}`,
    )
    if (!confirmed) return
    setBusyId(editing.id)
    setEditingError('')
    try {
      const updated = await queueRepository.resetQueueLineNumbers(editing.id, session.user.id)
      setEditing(null)
      setSuccess(`${updated.name} was created as a new queue line — now serving ${updated.current_number}.`)
      await loadLines(true)
    } catch (resetError) {
      setEditingError(resetError.message || 'Unable to reset the queue numbers.')
    } finally {
      setBusyId('')
    }
  }

  const callNext = async (line) => {
    setBusyId(line.id)
    setError('')
    setSuccess('')
    try {
      const updated = await queueRepository.callNext(line.id)
      setSuccess(`${updated.current_number} is now being called at ${updated.service_area}.`)
      await loadLines(true)
    } catch (callError) {
      setError(callError.message || 'Unable to call the next queue number.')
    } finally {
      setBusyId('')
    }
  }

  const notifyDirect = async () => {
    if (!directLineId || !directNumber.trim()) {
      setError('Select a queue line and enter the queue number to call.')
      return
    }
    setBusyId('direct')
    setError('')
    setSuccess('')
    try {
      await queueRepository.notifyNumber(directLineId, directNumber)
      setSuccess(`${directNumber.trim().toUpperCase()} was notified.`)
    } catch (notifyError) {
      setError(notifyError.message || 'Unable to notify the queue number.')
    } finally {
      setBusyId('')
    }
  }

  const notifyQueueNumber = async (line, record) => {
    const busyKey = `notify-${line.id}-${record.id}`
    setBusyId(busyKey)
    setError('')
    setSuccess('')
    try {
      await queueRepository.notifyNumber(line.id, record.number)
      setSuccess(`${record.number} was notified.`)
      await loadLines(true)
    } catch (notifyError) {
      setError(notifyError.message || `Unable to notify ${record.number}.`)
    } finally {
      setBusyId('')
    }
  }

  const markNumber = async (queueLineId, number, status, refreshLookup = false) => {
    setBusyId(`status-${queueLineId}`)
    setError('')
    setSuccess('')
    try {
      const result = await queueRepository.markNumber(queueLineId, number, status)
      setSuccess(result.line
        ? `${result.number.number} was marked ${result.number.status}. ${result.line.current_number} was called next.`
        : `${result.number.number} was marked ${result.number.status}.`)
      await loadLines(true)
      if (refreshLookup) {
        const refreshed = await queueRepository.findQueueNumber(staffContext.institution_id, number, lines.find((line) => line.id === queueLineId) || null)
        setLookupResult(refreshed)
      }
    } catch (actionError) {
      setError(actionError.message || `Unable to mark the queue number as ${status}.`)
    } finally {
      setBusyId('')
    }
  }

  const searchNumberStatus = async () => {
    if (!lookupNumber.trim()) {
      setLookupError('Enter a queue number to search.')
      return
    }
    setBusyId('lookup')
    setLookupError('')
    setLookupResult(null)
    try {
      const result = await queueRepository.findQueueNumber(staffContext.institution_id, lookupNumber, lines.find((line) => line.id === lookupLineId) || null)
      if (!result) {
        setLookupError(`Queue number ${lookupNumber.trim().toUpperCase()} was not found.`)
      } else {
        setLookupResult(result)
      }
    } catch (lookupError) {
      setLookupError(lookupError.message || 'Unable to search for this queue number.')
    } finally {
      setBusyId('')
    }
  }

  return (
    <div>
      <div className="page-header">
        <div><h2>Queue Management</h2><div className="header-subtitle">Create queue lines, update serving information and notify travelers visually.</div></div>
        <Link to="/queue/add" className="btn btn-primary">+ Add Queue Line</Link>
      </div>

      <div className="page-body">
        {error && <div className="form-alert error" role="alert">{error}</div>}
        {success && <div className="form-alert success" role="status">{success}</div>}
        {loading ? <div className="card table-message">Loading queue lines…</div> : <>
          <div className="queue-call-scroll" aria-label="Queue lines available to call">
            {!operationalLines.length && <div className="form-alert info" role="note">No active queue lines match the selected filters.</div>}
            {operationalLines.map((line) => {
              const waiting = realWaitingCount(line)
              const pastRecords = recentPastRecords(line)
              return <div key={line.id} className="card queue-call-card" style={{ background: 'linear-gradient(135deg, var(--dark-bg), var(--dark-surface))', color: '#fff' }}>
                <div className="queue-card-heading">
                  <span>{line.name}</span>
                  <button className="btn btn-outline btn-sm" onClick={() => openManage(line)}>Manage</button>
                </div>
                <div style={{ fontSize: '56px', fontWeight: '800', color: 'var(--primary-light)', margin: '16px 0' }}>{line.current_number}</div>
                <div style={{ display: 'flex', gap: '8px', marginBottom: '16px', flexWrap: 'wrap' }}>
                  <button className="btn btn-primary" style={{ flex: 1, justifyContent: 'center' }} disabled={busyId === line.id || line.status !== 'active' || maxQueueNumberReached(line)} title={maxQueueNumberReached(line) ? 'Maximum queue number reached' : undefined} onClick={() => callNext(line)}>{busyId === line.id ? 'Calling…' : `Call Next (${line.upcoming_number})`}</button>
                </div>
                <div className="queue-current-actions">
                  <button className="btn btn-outline btn-sm" disabled={busyId === `notify-${line.id}-current` || busyId === `status-${line.id}` || line.status !== 'active'} onClick={() => notifyQueueNumber(line, { id: 'current', number: line.current_number })}>{busyId === `notify-${line.id}-current` ? 'Notifying…' : 'Notify'}</button>
                  <button className="btn btn-outline btn-sm" disabled={busyId === `status-${line.id}` || line.status !== 'active'} onClick={() => markNumber(line.id, line.current_number, 'completed')}>Complete</button>
                  <button className="btn btn-danger btn-sm" disabled={busyId === `status-${line.id}` || line.status !== 'active'} onClick={() => markNumber(line.id, line.current_number, 'cancelled')}>Cancel</button>
                </div>
                {pastRecords.length > 0 && <div className="queue-past-records">
                  <div className="queue-past-records-title">Recent records</div>
                  {pastRecords.map((record) => {
                    const terminal = ['completed', 'cancelled'].includes(record.status)
                    const statusBusy = busyId === `status-${line.id}`
                    const notifyBusy = busyId === `notify-${line.id}-${record.id}`
                    const disabled = line.status !== 'active' || terminal
                    return <div className="queue-past-record" key={record.id}>
                      <strong>{record.number}</strong>
                      <div className="queue-past-actions">
                        <button className="btn btn-outline btn-sm" disabled={disabled || notifyBusy || statusBusy} onClick={() => notifyQueueNumber(line, record)}>{notifyBusy ? 'Notifying…' : 'Notify'}</button>
                        <button className="btn btn-outline btn-sm" disabled={disabled || notifyBusy || statusBusy} onClick={() => markNumber(line.id, record.number, 'completed')}>Complete</button>
                        <button className="btn btn-danger btn-sm" disabled={disabled || notifyBusy || statusBusy} onClick={() => markNumber(line.id, record.number, 'cancelled')}>Cancel</button>
                      </div>
                    </div>
                  })}
                </div>}
                <div style={{ fontSize: '12px', color: 'rgba(255,255,255,0.5)', textAlign: 'center' }}>{line.service_area} • {waiting} waiting{maxQueueNumberReached(line) ? ' • Maximum queue number reached' : ''}</div>
              </div>
            })}
          </div>
            {lines.length ?
          <div className="queue-tools-row">
            <div className="card queue-lookup-card queue-tool-card">
            <div className="card-header"><div><h3>Queue Number Status Lookup</h3><div className="header-subtitle">Search a queue number to view its latest status and service information.</div></div></div>
            <div className="queue-lookup-form">
              <div className="form-group"><label htmlFor="lookup-queue-line">Queue Line (Optional)</label><select id="lookup-queue-line" className="input" value={lookupLineId} onChange={(event) => { setLookupLineId(event.target.value); setLookupResult(null); setLookupError('') }}><option value="">Search all queue lines</option>{lines.filter((line) => line.status !== 'reset').map((line) => <option key={line.id} value={line.id}>{line.name} — {line.service_area}</option>)}</select></div>
              <div className="form-group"><label htmlFor="queue-status-number">Queue Number</label><input id="queue-status-number" className={`input ${lookupError ? 'invalid' : ''}`} value={lookupNumber} onChange={(event) => { setLookupNumber(event.target.value); setLookupResult(null); setLookupError('') }} onKeyDown={(event) => { if (event.key === 'Enter') searchNumberStatus() }} placeholder={lookupLineId ? 'e.g. 071, A071 or A-071' : 'e.g. A071 or A-071'} /></div>
              <button className="btn btn-outline" disabled={busyId === 'lookup'} onClick={searchNumberStatus}>{busyId === 'lookup' ? 'Searching…' : 'Search Status'}</button>
            </div>
            {lookupError && <div className="form-alert error compact" role="alert">{lookupError}</div>}
            {lookupResult && <div className="queue-lookup-result" role="status">
              <div><span>Queue Number</span><strong>{lookupResult.number}</strong></div>
              <div><span>Status</span><strong className={`queue-status-text ${lookupResult.status}`}>{labelStatus(lookupResult.status)}</strong></div>
              <div><span>Queue Line</span><strong>{lookupResult.queue_lines.name}</strong></div>
              <div><span>Service</span><strong>{lookupResult.queue_lines.service_area}</strong></div>
              <div><span>Now Serving</span><strong>{lookupResult.queue_lines.current_number}</strong></div>
              <div><span>Line Status</span><strong>{lookupResult.queue_lines.status}</strong></div>
              {lookupResult.virtual && <div className="queue-lookup-actions"><span className="field-note">This valid queue number is Waiting. It has not been stored yet and will be created only when it is called or claimed by a traveller.</span></div>}
              {!lookupResult.virtual && !['completed', 'cancelled'].includes(lookupResult.status) && <div className="queue-lookup-actions">
                {lookupResult.queue_lines.status === 'closed' ? <span className="field-note">This queue line is closed — number statuses are locked.</span> : 
                <>
                  <span>Update Status</span>
                  <div>
                    <button className="btn btn-outline btn-sm" disabled={busyId === `status-${lookupResult.queue_line_id}`} onClick={() => markNumber(lookupResult.queue_line_id, lookupResult.number, 'completed', true)}>Mark Complete</button>
                    <button className="btn btn-danger btn-sm" disabled={busyId === `status-${lookupResult.queue_line_id}`} onClick={() => markNumber(lookupResult.queue_line_id, lookupResult.number, 'cancelled', true)}>Cancel Number</button>              
                    <button className="btn btn-outline btn-sm" disabled={busyId === `notify-${lookupResult.queue_line_id}-${lookupResult.id}`} onClick={() => notifyQueueNumber({ id: lookupResult.queue_line_id }, lookupResult)}>{busyId === `notify-${lookupResult.queue_line_id}-${lookupResult.id}` ? 'Notifying…' : 'Notify Traveler Now'}</button>
                  </div>
                </>}
              </div>}
            </div>}
            </div>
          </div> : <></>}

          <div className="card">
            <div className="card-header"><div><h3>Queue Lines</h3><div className="header-subtitle">Filter queue lines by status or service area. Reset lines are archived and excluded from lookup.</div></div><div className="queue-line-filters"><select className="input" value={lineStatusFilter} onChange={(event) => setLineStatusFilter(event.target.value)} aria-label="Filter queue lines by status"><option value="all">All statuses</option><option value="active">Active</option><option value="closed">Closed</option></select><select className="input" value={serviceAreaFilter} onChange={(event) => setServiceAreaFilter(event.target.value)} aria-label="Filter queue lines by service area"><option value="all">All service areas</option>{serviceAreas.map((area) => <option key={area.id} value={area.id}>{area.name}</option>)}</select></div></div>
            {!filteredLines.length ? <div className="table-message">No queue lines match these filters.</div> : <table className="data-table">
              <thead><tr><th>Queue Line</th><th>Current</th><th>Upcoming</th><th>Status</th><th>Action</th></tr></thead>
              <tbody>{filteredLines.map((line) => <tr key={line.id}>
                <td><strong>{line.name}</strong><br/><span style={{ fontSize: 12, color: 'var(--text-secondary)' }}>{line.service_area}</span></td>
                <td><span className="badge primary">{line.current_number}</span></td><td>{line.upcoming_number}</td>
                <td><span className={`badge ${line.status === 'active' ? 'success' : 'muted'}`}>{labelStatus(line.status)}</span></td>
                <td><button className="btn btn-outline btn-sm" onClick={() => openManage(line)}>Manage</button></td>
              </tr>)}</tbody>
            </table>}
          </div>
        </>}
      </div>

      {editing && <div className="modal-backdrop" role="presentation" onMouseDown={() => setEditing(null)}>
        <div className="modal-card" role="dialog" aria-modal="true" aria-labelledby="manage-queue-title" onMouseDown={(event) => event.stopPropagation()}>
          <div className="card-header"><div><h3 id="manage-queue-title">Manage {editing.name}</h3><div className="header-subtitle">View or edit the current queue-line information.</div></div><button className="modal-close" onClick={() => setEditing(null)} aria-label="Close">×</button></div>
          {editingError && <div className="form-alert error compact modal-form-alert" role="alert">{editingError}</div>}
          <div className="form-grid">
            <div className="form-group"><label>Queue Line Name</label><input className="input" disabled={editing.was_closed} value={editing.name} onChange={(event) => setEditing({ ...editing, name: event.target.value })} /></div>
            <div className="form-group"><label>Current Number</label><div className="input queue-readonly-value" aria-label="Current Number">{editing.current_number}</div></div>
            <div className="form-group"><label>Upcoming Number</label><div className="input queue-readonly-value" aria-label="Upcoming Number">{editing.upcoming_number}</div></div>
            <div className="form-group"><label>Service Area</label><select className="input" disabled={editing.was_closed} value={editing.service_area_id || ''} onChange={(event) => setEditing({ ...editing, service_area_id: event.target.value })}><option value="">Select an active service area</option>{serviceAreas.map((area) => <option key={area.id} value={area.id}>{area.name}</option>)}</select>{!editing.was_closed && serviceAreas.length === 0 && <div className="field-note">No active service areas are available. Create one in the institution profile first.</div>}</div>
            <div className="form-group"><label>Estimated Service Time (Minutes)</label><input type="number" min="1" max="240" className="input" disabled={editing.was_closed} value={editing.estimated_service_minutes} onChange={(event) => setEditing({ ...editing, estimated_service_minutes: event.target.value })} /></div>
            <div className="form-group"><label>Maximum Queue Number</label><input type="number" min="1" max="500" step="1" className="input" disabled={editing.was_closed} value={editing.max_tracking_number ?? 100} onChange={(event) => setEditing({ ...editing, max_tracking_number: event.target.value })} /><div className="field-note">Queue numbers stop at this value; no larger numbers can be called or tracked.</div></div>
            <div className="form-group"><label>Operating Hours</label><input className="input" disabled={editing.was_closed} value={editing.operating_hours || ''} onChange={(event) => setEditing({ ...editing, operating_hours: event.target.value })} placeholder="e.g. 6:00 AM – 11:00 PM" /></div>
            <div className="form-group"><label>Queue Line Status</label><select className="input" value={editing.status} onChange={(event) => setEditing({ ...editing, status: event.target.value })}><option value="active">Active</option><option value="closed">Closed</option></select></div>
          </div>
          <div className="form-group"><label>Staff Notes (Optional)</label><textarea className="input" rows={3} disabled={editing.was_closed} value={editing.staff_notes || ''} onChange={(event) => setEditing({ ...editing, staff_notes: event.target.value })} placeholder="Add operational notes for staff managing this queue." /></div>
          {!editing.was_closed && <div className="form-group">
            <label>Reset Queue Numbers</label>
            <div><button type="button" className="btn btn-danger btn-sm" disabled={busyId === editing.id} onClick={resetNumbers}>Reset Numbers to {(editing.prefix || '').toUpperCase()}-001</button></div>
            <div className="field-note">Reminder: if travellers are still waiting in line, resetting will cancel their queued numbers and they will need to take a new number. </div>
          </div>}
          {editing.was_closed && <div className="form-alert info compact" role="note">This queue line is closed. Only its status can be changed.</div>}
          <div className="modal-actions queue-manage-actions"><button className="btn btn-outline" onClick={() => setEditing(null)}>Close</button><button className="btn btn-primary" disabled={busyId === editing.id} onClick={saveLine}>{busyId === editing.id ? 'Saving…' : 'Save Queue Information'}</button></div>
        </div>
      </div>}
    </div>
  )
}
