import React, { useCallback, useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'
import { queueRepository } from '../repositories/queueRepository'

const labelStatus = (status) => status ? status[0].toUpperCase() + status.slice(1) : ''

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
  const operationalLines = lines.filter((line) => line.status !== 'closed')

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
    return queueRepository.subscribe(staffContext.institution_id, () => loadLines(true))
  }, [loadLines, staffContext.institution_id])

  const openManage = (line) => {
    setEditing({ ...line, was_closed: line.status === 'closed' })
    setError('')
  }

  const saveLine = async () => {
    if (!editing.name.trim() || !editing.counter.trim() || !editing.service_area.trim()) {
      setError('Queue line name, counter, and service area are required.')
      return
    }
    setBusyId(editing.id)
    setError('')
    try {
      await queueRepository.updateQueueLine(editing.id, {
        name: editing.name.trim(),
        counter: editing.counter.trim(),
        service_area: editing.service_area.trim(),
        status: editing.status,
        estimated_service_minutes: Number(editing.estimated_service_minutes),
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

  const callNext = async (line) => {
    setBusyId(line.id)
    setError('')
    setSuccess('')
    try {
      const updated = await queueRepository.callNext(line.id)
      setSuccess(`${updated.current_number} is now being called at ${updated.counter}.`)
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
      setDirectNumber(updated.upcoming_number)
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
              const waiting = line.queue_numbers?.filter((number) => number.status === 'waiting').length || 0
              return <div key={line.id} className="card queue-call-card" style={{ background: 'linear-gradient(135deg, var(--dark-bg), var(--dark-surface))', color: '#fff' }}>
                <div className="queue-card-heading">
                  <span>{line.counter}</span>
                  <button className="btn btn-outline btn-sm" onClick={() => openManage(line)}>Manage</button>
                </div>
                <div style={{ fontSize: '56px', fontWeight: '800', color: 'var(--primary-light)', margin: '16px 0' }}>{line.current_number}</div>
                <div style={{ display: 'flex', gap: '8px', marginBottom: '16px', flexWrap: 'wrap' }}>
                  <button className="btn btn-primary" style={{ flex: 1, justifyContent: 'center' }} disabled={busyId === line.id || line.status !== 'active'} onClick={() => callNext(line)}>{busyId === line.id ? 'Calling…' : `Call Next (${line.upcoming_number})`}</button>
                </div>
                <div className="queue-current-actions">
                  <button className="btn btn-outline btn-sm" disabled={busyId === `status-${line.id}` || line.status !== 'active'} onClick={() => markNumber(line.id, line.current_number, 'completed')}>Mark {line.current_number} Complete</button>
                  <button className="btn btn-danger btn-sm" disabled={busyId === `status-${line.id}` || line.status !== 'active'} onClick={() => markNumber(line.id, line.current_number, 'cancelled')}>Cancel {line.current_number}</button>
                </div>
                <div style={{ fontSize: '12px', color: 'rgba(255,255,255,0.5)', textAlign: 'center' }}>{line.service_area} • {waiting} waiting</div>
              </div>
            })}
          </div>

          <div className="queue-tools-row">
            <div className="card queue-tool-card">
              <div className="card-header"><h3>Direct Call Number</h3></div>
              <div className="form-group"><label htmlFor="direct-queue-line">Select Queue Line</label><select id="direct-queue-line" className="input" value={directLineId} onChange={(event) => { const id = event.target.value; setDirectLineId(id); setDirectNumber(lines.find((line) => line.id === id)?.upcoming_number || '') }}>{operationalLines.map((line) => <option key={line.id} value={line.id}>{line.name} — {line.service_area}</option>)}</select></div>
              <div className="form-group"><label htmlFor="direct-number">Number to Call</label><input id="direct-number" className="input" value={directNumber} onChange={(event) => setDirectNumber(event.target.value)} placeholder="e.g. A-047" /></div>
              <button className="btn btn-primary" style={{ width: '100%', justifyContent: 'center' }} disabled={busyId === 'direct' || !operationalLines.length} onClick={notifyDirect}>{busyId === 'direct' ? 'Notifying…' : 'Notify Traveler Now'}</button>
            </div>
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
              <div><span>Counter</span><strong>{lookupResult.queue_lines.counter}</strong></div>
              <div><span>Now Serving</span><strong>{lookupResult.queue_lines.current_number}</strong></div>
              {!['completed', 'cancelled'].includes(lookupResult.status) && <div className="queue-lookup-actions">
                <span>Update Status</span>
                <div><button className="btn btn-outline btn-sm" disabled={busyId === `status-${lookupResult.queue_line_id}`} onClick={() => markNumber(lookupResult.queue_line_id, lookupResult.number, 'completed', true)}>Mark Complete</button><button className="btn btn-danger btn-sm" disabled={busyId === `status-${lookupResult.queue_line_id}`} onClick={() => markNumber(lookupResult.queue_line_id, lookupResult.number, 'cancelled', true)}>Cancel Number</button></div>
              </div>}
            </div>}
            </div>
          </div>

          <div className="card">
            <div className="card-header"><h3>Queue Lines</h3></div>
            {!lines.length ? <div className="table-message">No queue lines have been created.</div> : <table className="data-table">
              <thead><tr><th>Queue Line</th><th>Current</th><th>Upcoming</th><th>Counter</th><th>Status</th><th>Action</th></tr></thead>
              <tbody>{lines.map((line) => <tr key={line.id}>
                <td><strong>{line.name}</strong><br/><span style={{ fontSize: 12, color: 'var(--text-secondary)' }}>{line.service_area}</span></td>
                <td><span className="badge primary">{line.current_number}</span></td><td>{line.upcoming_number}</td><td>{line.counter}</td>
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
            <div className="form-group"><label>Counter</label><input className="input" disabled={editing.was_closed} value={editing.counter} onChange={(event) => setEditing({ ...editing, counter: event.target.value })} /></div>
            <div className="form-group"><label>Service Area</label><input className="input" disabled={editing.was_closed} value={editing.service_area} onChange={(event) => setEditing({ ...editing, service_area: event.target.value })} /></div>
            <div className="form-group"><label>Estimated Service Time (Minutes)</label><input type="number" min="1" max="240" className="input" disabled={editing.was_closed} value={editing.estimated_service_minutes} onChange={(event) => setEditing({ ...editing, estimated_service_minutes: event.target.value })} /></div>
            <div className="form-group"><label>Operating Hours</label><input className="input" disabled={editing.was_closed} value={editing.operating_hours || ''} onChange={(event) => setEditing({ ...editing, operating_hours: event.target.value })} placeholder="e.g. 6:00 AM – 11:00 PM" /></div>
            <div className="form-group"><label>Queue Line Status</label><select className="input" value={editing.status} onChange={(event) => setEditing({ ...editing, status: event.target.value })}><option value="active">Active</option><option value="paused">Paused</option><option value="closed">Closed</option></select></div>
          </div>
          <div className="form-group"><label>Staff Notes (Optional)</label><textarea className="input" rows={3} disabled={editing.was_closed} value={editing.staff_notes || ''} onChange={(event) => setEditing({ ...editing, staff_notes: event.target.value })} /></div>
          {editing.was_closed && <div className="form-alert info compact" role="note">This queue line is closed. Only its status can be changed.</div>}
          <div className="modal-actions queue-manage-actions"><button className="btn btn-outline" onClick={() => setEditing(null)}>Close</button><button className="btn btn-primary" disabled={busyId === editing.id} onClick={saveLine}>{busyId === editing.id ? 'Saving…' : 'Save Queue Information'}</button></div>
        </div>
      </div>}
    </div>
  )
}
