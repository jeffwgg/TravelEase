import React, { useCallback, useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { Ban, Eye, Globe2, MapPin, Megaphone, Pencil, Radio, Search } from 'lucide-react'
import { useAuth } from '../context/AuthContext'
import { announcementRepository } from '../repositories/announcementRepository'
import { supabase } from '../lib/supabase'
import { useAutoDismiss } from '../hooks/useAutoDismiss'

const priorityClass = { low: 'muted', normal: 'primary', high: 'secondary', urgent: 'emergency' }
const statusClass = { active: 'success', draft: 'muted', expired: 'secondary', cancelled: 'emergency' }

function formatDate(value) {
  if (!value) return 'Not published'
  return new Intl.DateTimeFormat('en-MY', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))
}

// Scheduled = active row whose publish time is still in the future.
function isScheduled(item) {
  return item.status === 'active' && Boolean(item.published_at) && new Date(item.published_at) > new Date()
}

export default function AnnouncementPage() {
  const { staffContext } = useAuth()
  const institutionId = staffContext.institution_id
  const [announcements, setAnnouncements] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('all')
  const [cancellingId, setCancellingId] = useState(null)
  useAutoDismiss(error, () => setError(''))

  const loadAnnouncements = useCallback(async () => {
    try {
      setError('')
      setAnnouncements(await announcementRepository.getAnnouncements(institutionId))
    } catch (loadError) {
      setError(loadError.message || 'Unable to load announcements.')
    } finally {
      setLoading(false)
    }
  }, [institutionId])

  useEffect(() => {
    loadAnnouncements()
    return announcementRepository.subscribeToAnnouncements(institutionId, loadAnnouncements)
  }, [institutionId, loadAnnouncements])

  const filtered = useMemo(() => {
    const query = search.trim().toLowerCase()
    const priorityRank = { urgent: 4, high: 3, normal: 2, low: 1 }
    return announcements.filter((item) => {
      const matchesStatus = statusFilter === 'all'
        || (statusFilter === 'scheduled' ? isScheduled(item) : item.status === statusFilter)
      const matchesSearch = !query || [item.title, item.message_en, item.message_ms, item.venue_zones?.name]
        .some((value) => value?.toLowerCase().includes(query))
      return matchesStatus && matchesSearch
    }).sort((left, right) => {
      const priorityDifference = (priorityRank[right.priority] || 0) - (priorityRank[left.priority] || 0)
      if (priorityDifference) return priorityDifference
      return new Date(right.published_at || right.created_at) - new Date(left.published_at || left.created_at)
    })
  }, [announcements, search, statusFilter])

  const summary = useMemo(() => ({
    total: announcements.length,
    active: announcements.filter((item) => item.status === 'active' && !isScheduled(item)).length,
    scheduled: announcements.filter((item) => isScheduled(item)).length,
    urgent: announcements.filter((item) => item.priority === 'urgent' && item.status === 'active').length,
    translated: announcements.filter((item) => Object.keys(item.translations || {}).length > 0).length,
  }), [announcements])

  const cancelAnnouncement = async (id) => {
    setCancellingId(id)
    setError('')
    try {
      await announcementRepository.cancelAnnouncement(id)
      await loadAnnouncements()
    } catch (cancelError) {
      setError(cancelError.message || 'Unable to cancel this announcement.')
    } finally {
      setCancellingId(null)
    }
  }

  return (
    <div>
      <div className="page-header">
        <div>
          <h2>Announcement Management</h2>
          <div className="header-subtitle">Official broadcasts for {staffContext.institutions?.name} — {staffContext.institutions?.branch}.</div>
        </div>
        <Link to="/announcements/create" className="btn btn-primary">+ Create Announcement</Link>
      </div>

      <div className="page-body">
        {error && <div className="form-alert error" role="alert">{error}</div>}
        <div className="announcement-summary" aria-label="Announcement summary">
          <div className="announcement-stat"><span className="announcement-stat-icon primary"><Megaphone size={20} /></span><div><strong>{summary.total}</strong><span>Total broadcasts</span></div></div>
          <div className="announcement-stat"><span className="announcement-stat-icon success"><Radio size={20} /></span><div><strong>{summary.active}</strong><span>Currently active</span></div></div>
          <div className="announcement-stat"><span className="announcement-stat-icon secondary"><Megaphone size={20} /></span><div><strong>{summary.scheduled}</strong><span>Scheduled</span></div></div>
          <div className="announcement-stat"><span className="announcement-stat-icon emergency"><Ban size={20} /></span><div><strong>{summary.urgent}</strong><span>Urgent and active</span></div></div>
          <div className="announcement-stat"><span className="announcement-stat-icon secondary"><Globe2 size={20} /></span><div><strong>{summary.translated}</strong><span>With translations</span></div></div>
        </div>

        <div className="announcement-list-card card">
          <div className="announcement-list-header">
            <div><h3>Official Announcements</h3><p>Review, edit and manage broadcasts sent to travellers.</p></div>
            <div className="announcement-filters">
              <label className="announcement-search"><Search size={17} /><input type="search" value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search title, message or zone..." aria-label="Search announcements" /></label>
              <select className="input announcement-status-filter" value={statusFilter} onChange={(event) => setStatusFilter(event.target.value)} aria-label="Filter by status"><option value="all">All statuses</option><option value="active">Active</option><option value="scheduled">Scheduled</option><option value="draft">Draft</option><option value="expired">Expired</option><option value="cancelled">Cancelled</option></select>
            </div>
          </div>
          {loading && <div className="announcement-empty">Loading announcements…</div>}
          {!loading && filtered.length === 0 && <div className="announcement-empty"><Megaphone size={28} /><strong>No announcements found</strong><span>Try changing the search or status filter.</span></div>}
          {!loading && filtered.length > 0 && <div className="table-scroll"><table className="data-table announcement-table">
            <thead><tr><th>Announcement</th><th>Priority</th><th>Status</th><th>Target</th><th>Languages</th><th>Published</th><th>Reach</th><th>Actions</th></tr></thead>
            <tbody>{filtered.map((item) => {
              const translationCount = Object.keys(item.translations || {}).length
              return <tr key={item.id} className={`announcement-table-row priority-${item.priority}`}>
                <td><strong className="announcement-table-title">{item.title}</strong><span className="table-secondary">{item.message_en}</span></td>
                <td><span className={`badge ${priorityClass[item.priority] || 'muted'}`}>{item.priority}</span></td>
                <td><span className={`badge ${statusClass[item.status] || 'muted'}`}>{item.status}</span></td>
                <td><span className="announcement-table-meta"><MapPin size={14} />{item.venue_zones?.name || 'All Zones'}</span></td>
                <td><span className="announcement-table-meta"><Globe2 size={14} />{translationCount ? `${translationCount} translation${translationCount === 1 ? '' : 's'}` : 'English only'}</span></td>
                <td>{isScheduled(item) ? <span className="badge secondary">Scheduled — {formatDate(item.published_at)}</span> : formatDate(item.published_at || item.created_at)}</td>
                <td><span className="announcement-table-meta"><Eye size={14} />{item.reach_count ?? 0}</span></td>
                <td><div className="table-actions"><Link className="btn btn-outline btn-sm" to={`/announcements/${item.id}/edit`}><Pencil size={14} /> Edit</Link>{item.status === 'active' && <button className="btn btn-outline btn-sm announcement-cancel" disabled={cancellingId === item.id} onClick={() => cancelAnnouncement(item.id)}>{cancellingId === item.id ? 'Cancelling…' : 'Cancel'}</button>}</div></td>
              </tr>
            })}</tbody>
          </table></div>}
        </div>

        <InstitutionLocationTestSection institutionId={institutionId} institutionName={staffContext.institutions?.name || 'this institution'} />
      </div>
    </div>
  )
}

// ============================================================================
// TEMPORARY TEST SECTION — DELETE AFTER TESTING
// Lets staff store the institution's real coordinates so the mobile app can
// match this record by GPS (venue session detection, FR-M2-01..FR-M2-04).
// Reads/writes institutions.latitude / longitude / location_match_radius_m.
// ============================================================================
function InstitutionLocationTestSection({ institutionId, institutionName }) {
  const [latitude, setLatitude] = useState('')
  const [longitude, setLongitude] = useState('')
  const [radius, setRadius] = useState('800')
  const [saving, setSaving] = useState(false)
  const [status, setStatus] = useState(null)
  useAutoDismiss(status?.text ?? '', () => setStatus(null))

  useEffect(() => {
    const load = async () => {
      const { data, error } = await supabase
        .from('institutions')
        .select('latitude, longitude, location_match_radius_m')
        .eq('id', institutionId)
        .single()
      if (error) return
      if (data?.latitude != null) setLatitude(String(data.latitude))
      if (data?.longitude != null) setLongitude(String(data.longitude))
      if (data?.location_match_radius_m != null) setRadius(String(data.location_match_radius_m))
    }
    load()
  }, [institutionId])

  const useCurrentPosition = () => {
    if (!navigator.geolocation) {
      setStatus({ type: 'error', text: 'This browser does not support geolocation.' })
      return
    }
    setStatus({ type: 'info', text: 'Detecting your position…' })
    navigator.geolocation.getCurrentPosition(
      (position) => {
        setLatitude(position.coords.latitude.toFixed(6))
        setLongitude(position.coords.longitude.toFixed(6))
        setStatus({ type: 'success', text: 'Position captured — review it and save.' })
      },
      (positionError) => setStatus({ type: 'error', text: `Position detection failed: ${positionError.message}` }),
      { enableHighAccuracy: true, timeout: 15000 },
    )
  }

  const saveLocation = async () => {
    const lat = Number(latitude)
    const lng = Number(longitude)
    const matchRadius = Number(radius)
    const problems = []
    if (!latitude || !Number.isFinite(lat) || lat < -90 || lat > 90) problems.push('latitude must be between -90 and 90')
    if (!longitude || !Number.isFinite(lng) || lng < -180 || lng > 180) problems.push('longitude must be between -180 and 180')
    if (!Number.isInteger(matchRadius) || matchRadius < 10 || matchRadius > 50000) problems.push('radius must be a whole number from 10 to 50000 metres')
    if (problems.length) {
      setStatus({ type: 'error', text: `${problems.join('; ')}.` })
      return
    }
    setSaving(true)
    setStatus(null)
    try {
      const { error } = await supabase
        .from('institutions')
        .update({ latitude: lat, longitude: lng, location_match_radius_m: matchRadius })
        .eq('id', institutionId)
      if (error) throw error
      setStatus({ type: 'success', text: 'Location saved — the mobile app can now match this venue by GPS.' })
    } catch (saveError) {
      const message = saveError.message || 'Unable to save the location.'
      const hint = /row-level security/i.test(message)
        ? ' Run migration 007_institution_location_update_policy.sql in the Supabase SQL editor first.'
        : ''
      setStatus({ type: 'error', text: message + hint })
    } finally {
      setSaving(false)
    }
  }

  const clearLocation = async () => {
    setSaving(true)
    setStatus(null)
    try {
      const { error } = await supabase
        .from('institutions')
        .update({ latitude: null, longitude: null })
        .eq('id', institutionId)
      if (error) throw error
      setLatitude('')
      setLongitude('')
      setStatus({ type: 'success', text: 'Stored location cleared.' })
    } catch (clearError) {
      setStatus({ type: 'error', text: clearError.message || 'Unable to clear the location.' })
    } finally {
      setSaving(false)
    }
  }

  const hasCoordinates = latitude !== '' && longitude !== '' && Number.isFinite(Number(latitude)) && Number.isFinite(Number(longitude))

  return (
    <div className="card" style={{ border: '2px dashed #f59e0b' }}>
      <div className="card-header"><div><h3>🧪 [TEST ONLY] Institution Location — {institutionName}</h3><div className="header-subtitle">Temporary helper: store the real location of this venue so the mobile app can detect it by GPS when starting a venue session. <strong>Delete this section after testing.</strong></div></div></div>
      <div className="form-grid">
        <div className="form-group"><label htmlFor="test-latitude">Latitude</label><input id="test-latitude" type="number" step="any" className="input" value={latitude} onChange={(event) => setLatitude(event.target.value)} placeholder="e.g. 2.745600" /></div>
        <div className="form-group"><label htmlFor="test-longitude">Longitude</label><input id="test-longitude" type="number" step="any" className="input" value={longitude} onChange={(event) => setLongitude(event.target.value)} placeholder="e.g. 101.709900" /></div>
        <div className="form-group"><label htmlFor="test-radius">Match Radius (Metres)</label><input id="test-radius" type="number" min="10" max="50000" step="1" className="input" value={radius} onChange={(event) => setRadius(event.target.value)} /><div className="field-note">Travellers within this distance of the stored point count as being at this venue.</div></div>
      </div>
      <div className="modal-actions" style={{ gap: 10, flexWrap: 'wrap' }}>
        <button type="button" className="btn btn-outline" onClick={useCurrentPosition}>Use My Current Position</button>
        {hasCoordinates && <a className="btn btn-outline" href={`https://www.google.com/maps?q=${Number(latitude)},${Number(longitude)}`} target="_blank" rel="noreferrer">Open in Google Maps</a>}
        <button type="button" className="btn btn-primary" disabled={saving} onClick={saveLocation}>{saving ? 'Saving…' : 'Save Location'}</button>
        <button type="button" className="btn btn-outline" disabled={saving} onClick={clearLocation}>Clear Location</button>
      </div>
      {status && <div className={`form-alert ${status.type} compact`} role="status">{status.text}</div>}
    </div>
  )
}
