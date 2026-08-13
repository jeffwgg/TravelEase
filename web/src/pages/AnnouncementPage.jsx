import React, { useCallback, useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'
import { announcementRepository } from '../repositories/announcementRepository'

const priorityClass = { low: 'muted', normal: 'primary', high: 'secondary', urgent: 'emergency' }
const statusClass = { active: 'success', draft: 'muted', expired: 'secondary', cancelled: 'emergency' }

function formatDate(value) {
  if (!value) return 'Not published'
  return new Intl.DateTimeFormat('en-MY', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))
}

export default function AnnouncementPage() {
  const { staffContext } = useAuth()
  const institutionId = staffContext.institution_id
  const [announcements, setAnnouncements] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [search, setSearch] = useState('')
  const [cancellingId, setCancellingId] = useState(null)

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
    if (!query) return announcements
    return announcements.filter((item) => [item.title, item.message_en, item.message_ms, item.venue_zones?.name].some((value) => value?.toLowerCase().includes(query)))
  }, [announcements, search])

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
        <div className="card">
          <div className="card-header">
            <h3>Active &amp; Recent Announcements</h3>
            <input type="search" className="input" value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search broadcasts..." style={{ width: '240px' }} />
          </div>
          <div className="table-scroll">
            <table className="data-table">
              <thead><tr><th>Title / Message</th><th>Target Zone</th><th>Priority</th><th>Status</th><th>Published</th><th>Reach</th><th>Action</th></tr></thead>
              <tbody>
                {loading && <tr><td colSpan="7" className="table-message">Loading announcements…</td></tr>}
                {!loading && filtered.length === 0 && <tr><td colSpan="7" className="table-message">No announcements found.</td></tr>}
                {!loading && filtered.map((item) => (
                  <tr key={item.id}>
                    <td><strong>{item.title}</strong><br/><span className="table-secondary">{item.message_en}</span></td>
                    <td>{item.venue_zones?.name || 'All Zones'}</td>
                    <td><span className={`badge ${priorityClass[item.priority] || 'muted'}`}>{item.priority}</span></td>
                    <td><span className={`badge ${statusClass[item.status] || 'muted'}`}>{item.status}</span></td>
                    <td>{formatDate(item.published_at || item.created_at)}</td>
                    <td>{item.reach_count ?? 0}</td>
                    <td><div className="table-actions"><Link className="btn btn-outline btn-sm" to={`/announcements/${item.id}/edit`}>Edit</Link>{item.status === 'active' && <button className="btn btn-outline btn-sm" disabled={cancellingId === item.id} onClick={() => cancelAnnouncement(item.id)}>{cancellingId === item.id ? 'Cancelling…' : 'Cancel'}</button>}</div></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </div>
      </div>
    </div>
  )
}
