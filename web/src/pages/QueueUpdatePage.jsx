import React, { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'
import { queueRepository } from '../repositories/queueRepository'
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

export default function QueueUpdatePage() {
  const { session, staffContext } = useAuth()
  const [lines, setLines] = useState([])
  const [editing, setEditing] = useState(null)
  const [directLineId, setDirectLineId] = useState('')
  const [directNumber, setDirectNumber] = useState('')
  const [lookupNumber, setLookupNumber] = useState('')
  const [lookupLineId, setLookupLineId] = useState('')
  const [lookupResult, setLookupResult] = useState(null)
  const [lookupError, setLookupError] = useState('')
  const [loading, setLoading] = useState(true)
  const [busyId, setBusyId] = useState('')
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')
  useAutoDismiss(error, () => setError(''))
  useAutoDismiss(success, () => setSuccess(''))
  useAutoDismiss(lookupError, () => setLookupError(''))
  const operationalLines = lines.filter((line) => line.status !== 'closed')

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
      const firstOperational = data.find((line) => line.status !== 'closed')
      setDirectLineId((current) => {
        const validSelection = data.find((line) => line.id === current && line.status !== 'closed')
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

  const openManage = (line) => {
    setEditing({ ...line, was_closed: line.status === 'closed', originalStatus: line.status })
    setError('')
  }

  const saveLine = async () => {
    if (!editing.name.trim() || !editing.service_area.trim()) {
      setError('Queue line name and service area are required.')
      return
    }
    if (editing.status !== editing.originalStatus) {
      const statusWarnings = {
        closed: 'Travellers will no longer see this queue line, and its queue numbers become read-only until it is reopened.',
        paused: 'Calling the next number is paused until the line is set back to Active.',
        active: 'Staff can call the next number and travellers can track it again.',
      }
      const confirmed = window.confirm(
        `Change the status of "${editing.name}" from ${labelStatus(editing.originalStatus)} to ${labelStatus(editing.status)}?\n\n${statusWarnings[editing.status] || ''}`,
      )
      if (!confirmed) return
    }
    setBusyId(editing.id)
    setError('')
    try {
      await queueRepository.updateQueueLine(editing.id, {
        name: editing.name.trim(),
        service_area: editing.service_area.trim(),
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
      setError(saveError.message || 'Unable to update the queue line.')
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
      `Reset the queue numbers of "${editing.name}" back to ${firstNumber}?\n\n${reminder}`,
    )
    if (!confirmed) return
    setBusyId(editing.id)
    setError('')
    try {
      const updated = await queueRepository.resetQueueLineNumbers(editing.id, session.user.id)
      setEditing(null)
      setSuccess(`${updated.name} was reset — now serving ${updated.current_number}.`)
      await loadLines(true)
    } catch (resetError) {
      setError(resetError.message || 'Unable to reset the queue numbers.')
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
      const updated = await queueRepository.notifyNumber(directLineId, directNumber)
      setSuccess(`${updated.current_number} was called and travelers were notified visually.`)
      await loadLines(true)
    } catch (notifyError) {
      setError(notifyError.message || 'Unable to notify the queue number.')
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
        <div><h2>Queue Management Console</h2><div className="header-subtitle">Create queue lines, update serving information and notify travelers visually.</div></div>
        <Link to="/queue/add" className="btn btn-primary">+ Add Queue Line</Link>
      </div>

      <div className="page-body">
        {error && <div className="form-alert error" role="alert">{error}</div>}
        {success && <div className="form-alert success" role="status">{success}</div>}
        {loading ? <div className="card table-message">Loading queue lines…</div> : <>
          <div className="queue-call-scroll" aria-label="Queue lines available to call">
            {!operationalLines.length && <div className="form-alert info" role="note">No active or paused queue lines are available for calling.</div>}
            {operationalLines.map((line) => {
              const waiting = realWaitingCount(line)
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
                  <button className="btn btn-outline btn-sm" disabled={busyId === `status-${line.id}` || line.status !== 'active'} onClick={() => markNumber(line.id, line.current_number, 'completed')}>Mark {line.current_number} Complete</button>
                  <button className="btn btn-danger btn-sm" disabled={busyId === `status-${line.id}` || line.status !== 'active'} onClick={() => markNumber(line.id, line.current_number, 'cancelled')}>Cancel {line.current_number}</button>
                </div>
                <div style={{ fontSize: '12px', color: 'rgba(255,255,255,0.5)', textAlign: 'center' }}>{line.service_area} • {waiting} waiting{maxQueueNumberReached(line) ? ' • Maximum queue number reached' : ''}</div>
              </div>
            })}
          </div>
            {lines.length ?
          <div className="queue-tools-row">
            <div className="card queue-lookup-card queue-tool-card">
            <div className="card-header"><div><h3>Queue Number Status Lookup</h3><div className="header-subtitle">Search a queue number to view its latest status and service information.</div></div></div>
            <div className="queue-lookup-form">
              <div className="form-group"><label htmlFor="lookup-queue-line">Queue Line (Optional)</label><select id="lookup-queue-line" className="input" value={lookupLineId} onChange={(event) => { setLookupLineId(event.target.value); setLookupResult(null); setLookupError('') }}><option value="">Search all queue lines</option>{lines.map((line) => <option key={line.id} value={line.id}>{line.name} — {line.service_area}</option>)}</select></div>
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
              {!['completed', 'cancelled'].includes(lookupResult.status) && <div className="queue-lookup-actions">
                {lookupResult.queue_lines.status === 'closed' ? <span className="field-note">This queue line is closed — number statuses are locked.</span> : 
                <>
                  <span>Update Status</span>
                  <div>
                    <button className="btn btn-outline btn-sm" disabled={busyId === `status-${lookupResult.queue_line_id}`} onClick={() => markNumber(lookupResult.queue_line_id, lookupResult.number, 'completed', true)}>Mark Complete</button>
                    <button className="btn btn-danger btn-sm" disabled={busyId === `status-${lookupResult.queue_line_id}`} onClick={() => markNumber(lookupResult.queue_line_id, lookupResult.number, 'cancelled', true)}>Cancel Number</button>              
                    <button className="btn btn-outline btn-sm" disabled={busyId === 'direct' || !operationalLines.length} onClick={notifyDirect}>{busyId === 'direct' ? 'Notifying…' : 'Notify Traveler Now'}</button>
                  </div>
                </>}
              </div>}
            </div>}
            </div>
          </div> : <></>}

          <div className="card">
            <div className="card-header"><h3>Queue Lines</h3></div>
            {!lines.length ? <div className="table-message">No queue lines have been created.</div> : <table className="data-table">
              <thead><tr><th>Queue Line</th><th>Current</th><th>Upcoming</th><th>Status</th><th>Action</th></tr></thead>
              <tbody>{lines.map((line) => <tr key={line.id}>
                <td><strong>{line.name}</strong><br/><span style={{ fontSize: 12, color: 'var(--text-secondary)' }}>{line.service_area}</span></td>
                <td><span className="badge primary">{line.current_number}</span></td><td>{line.upcoming_number}</td>
                <td><span className={`badge ${line.status === 'active' ? 'success' : line.status === 'paused' ? 'secondary' : 'muted'}`}>{labelStatus(line.status)}</span></td>
                <td><button className="btn btn-outline btn-sm" onClick={() => openManage(line)}>Manage</button></td>
              </tr>)}</tbody>
            </table>}
          </div>
        </>}
      </div>

      {editing && <div className="modal-backdrop" role="presentation" onMouseDown={() => setEditing(null)}>
        <div className="modal-card" role="dialog" aria-modal="true" aria-labelledby="manage-queue-title" onMouseDown={(event) => event.stopPropagation()}>
          <div className="card-header"><div><h3 id="manage-queue-title">Manage {editing.name}</h3><div className="header-subtitle">View or edit the current queue-line information.</div></div><button className="modal-close" onClick={() => setEditing(null)} aria-label="Close">×</button></div>
          <div className="form-grid">
            <div className="form-group"><label>Queue Line Name</label><input className="input" disabled={editing.was_closed} value={editing.name} onChange={(event) => setEditing({ ...editing, name: event.target.value })} /></div>
            <div className="form-group"><label>Current Number</label><div className="input queue-readonly-value" aria-label="Current Number">{editing.current_number}</div></div>
            <div className="form-group"><label>Upcoming Number</label><div className="input queue-readonly-value" aria-label="Upcoming Number">{editing.upcoming_number}</div></div>
            <div className="form-group"><label>Service Area</label><input className="input" disabled={editing.was_closed} value={editing.service_area} onChange={(event) => setEditing({ ...editing, service_area: event.target.value })} /></div>
            <div className="form-group"><label>Estimated Service Time (Minutes)</label><input type="number" min="1" max="240" className="input" disabled={editing.was_closed} value={editing.estimated_service_minutes} onChange={(event) => setEditing({ ...editing, estimated_service_minutes: event.target.value })} /></div>
            <div className="form-group"><label>Maximum Queue Number</label><input type="number" min="1" max="500" step="1" className="input" disabled={editing.was_closed} value={editing.max_tracking_number ?? 100} onChange={(event) => setEditing({ ...editing, max_tracking_number: event.target.value })} /><div className="field-note">Queue numbers stop at this value; no larger numbers can be called or tracked.</div></div>
            <div className="form-group"><label>Operating Hours</label><input className="input" disabled={editing.was_closed} value={editing.operating_hours || ''} onChange={(event) => setEditing({ ...editing, operating_hours: event.target.value })} placeholder="e.g. 6:00 AM – 11:00 PM" /></div>
            <div className="form-group"><label>Queue Line Status</label><select className="input" value={editing.status} onChange={(event) => setEditing({ ...editing, status: event.target.value })}><option value="active">Active</option><option value="paused">Paused</option><option value="closed">Closed</option></select></div>
          </div>
          <div className="form-group"><label>Staff Notes (Optional)</label><textarea className="input" rows={3} disabled={editing.was_closed} value={editing.staff_notes || ''} onChange={(event) => setEditing({ ...editing, staff_notes: event.target.value })} /></div>
          {!editing.was_closed && <div className="form-group">
            <label>Reset Queue Numbers</label>
            <div><button type="button" className="btn btn-danger btn-sm" disabled={busyId === editing.id} onClick={resetNumbers}>Reset Numbers to {(editing.prefix || '').toUpperCase()}-001</button></div>
            <div className="field-note">Reminder: if travellers are still waiting in line, resetting will cancel their queued numbers and they will need to take a new number. This confirmation appears again before the reset is applied.</div>
          </div>}
          {editing.was_closed && <div className="form-alert info compact" role="note">This queue line is closed. Only its status can be changed.</div>}
          <div className="modal-actions queue-manage-actions"><button className="btn btn-outline" onClick={() => setEditing(null)}>Close</button><button className="btn btn-primary" disabled={busyId === editing.id} onClick={saveLine}>{busyId === editing.id ? 'Saving…' : 'Save Queue Information'}</button></div>
        </div>
      </div>}
    </div>
  )
}
