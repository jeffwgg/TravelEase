import React, { useCallback, useEffect, useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import { Ban, Eye, Globe2, MapPin, Megaphone, Pencil, Radio } from 'lucide-react'
import { useAuth } from '../context/AuthContext'
import { announcementRepository } from '../repositories/announcementRepository'
import { serviceAreaRepository } from '../repositories/serviceAreaRepository'
import { useAutoDismiss } from '../hooks/useAutoDismiss'
import ListPagination, { ListFilterSearchField } from '../components/ListPagination'

const statusClass = { active: 'success', scheduled: 'secondary', withdrawn: 'emergency', expired: 'muted' }
const announcementPriorityClass = { low: 'muted', normal: 'primary', high: 'secondary', urgent: 'emergency' }
const pageSize = 10

function announcementPriorityLabel(priority) {
  if (priority === 'high') return 'High priority'
  if (priority === 'urgent') return 'Urgent'
  if (priority === 'normal') return 'Normal'
  if (priority === 'low') return 'Low'
  return priority || 'Normal'
}

function formatDate(value) {
  if (!value) return 'Not published'
  return new Intl.DateTimeFormat('en-MY', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))
}

// Scheduled = active row whose publish time is still in the future.
function isScheduled(item) {
  return item.status === 'scheduled'
    || (item.status === 'active' && Boolean(item.published_at) && new Date(item.published_at) > new Date())
}

function isExpired(item) {
  return item.status === 'expired'
    || (item.status === 'active' && Boolean(item.expires_at) && new Date(item.expires_at) <= new Date())
}

function displayStatus(item) {
  return item.status
}

export default function AnnouncementPage() {
  const { staffContext } = useAuth()
  const institutionId = staffContext.institution_id
  const [announcements, setAnnouncements] = useState([])
  const [serviceAreas, setServiceAreas] = useState([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')
  const [search, setSearch] = useState('')
  const [statusFilter, setStatusFilter] = useState('current')
  const [priorityFilter, setPriorityFilter] = useState('all')
  const [serviceAreaFilter, setServiceAreaFilter] = useState('all')
  const [dateFrom, setDateFrom] = useState('')
  const [dateTo, setDateTo] = useState('')
  const [page, setPage] = useState(1)
  const [deletingId, setDeletingId] = useState(null)
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

  useEffect(() => {
    let active = true
    serviceAreaRepository.list(staffContext)
      .then((areas) => { if (active) setServiceAreas(areas) })
      .catch((loadError) => { if (active) setError(loadError.message || 'Unable to load service areas.') })
    return () => { active = false }
  }, [staffContext])

  const scopedAnnouncements = useMemo(() => serviceAreaFilter === 'all'
    ? announcements
    : announcements.filter((item) => item.service_area_id === serviceAreaFilter), [announcements, serviceAreaFilter])

  const filtered = useMemo(() => {
    const query = search.trim().toLowerCase()
    const priorityRank = { urgent: 4, high: 3, normal: 2, low: 1 }
    return scopedAnnouncements.filter((item) => {
      const status = displayStatus(item)
      const matchesStatus = statusFilter === 'all'
        || (statusFilter === 'current'
          ? status === 'active' || status === 'scheduled'
          : status === statusFilter)
      const matchesPriority = priorityFilter === 'all' || item.priority === priorityFilter
      const published = new Date(item.published_at || item.created_at)
      const matchesDateFrom = !dateFrom || published >= new Date(`${dateFrom}T00:00:00`)
      const matchesDateTo = !dateTo || published <= new Date(`${dateTo}T23:59:59.999`)
      const matchesSearch = !query || [item.title, item.message_en, item.service_areas?.name]
        .some((value) => value?.toLowerCase().includes(query))
      return matchesStatus && matchesPriority && matchesDateFrom && matchesDateTo && matchesSearch
    }).sort((left, right) => {
      const priorityDifference = (priorityRank[right.priority] || 0) - (priorityRank[left.priority] || 0)
      if (priorityDifference) return priorityDifference
      return new Date(right.published_at || right.created_at) - new Date(left.published_at || left.created_at)
    })
  }, [scopedAnnouncements, dateFrom, dateTo, priorityFilter, search, statusFilter])

  useEffect(() => { setPage(1) }, [search, statusFilter, priorityFilter, serviceAreaFilter, dateFrom, dateTo])
  const totalPages = Math.max(1, Math.ceil(filtered.length / pageSize))
  const currentPage = Math.min(page, totalPages)
  const pageItems = filtered.slice((currentPage - 1) * pageSize, currentPage * pageSize)

  const summary = useMemo(() => ({
    total: scopedAnnouncements.length,
    active: scopedAnnouncements.filter((item) => displayStatus(item) === 'active').length,
    scheduled: scopedAnnouncements.filter((item) => isScheduled(item)).length,
    urgent: scopedAnnouncements.filter((item) => item.priority === 'urgent' && item.status === 'active').length,
  }), [scopedAnnouncements])

  const deleteAnnouncement = async (id, title) => {
    const confirmed = window.confirm(
      `Withdraw "${title}"? It will be removed from active announcements.`,
    )
    if (!confirmed) return
    setDeletingId(id)
    setError('')
    try {
      await announcementRepository.deleteAnnouncement(id)
      await loadAnnouncements()
    } catch (deleteError) {
      setError(deleteError.message || 'Unable to withdraw this announcement.')
    } finally {
      setDeletingId(null)
    }
  }

  return (
    <div>
      <div className="page-header">
        <div>
          <h2>Announcement Management</h2>
          <div className="header-subtitle">Official broadcasts for {staffContext.institutions?.name} — {staffContext.institutions?.branch}.</div>
        </div>
        <div className="page-header-actions"><select className="input page-service-area-filter" value={serviceAreaFilter} onChange={(event) => setServiceAreaFilter(event.target.value)} aria-label="Filter the page by service area"><option value="all">All service areas</option>{serviceAreas.map((area) => <option key={area.id} value={area.id}>{area.name}</option>)}</select><Link to="/announcements/create" className="btn btn-primary">+ Create Announcement</Link></div>
      </div>

      <div className="page-body">
        {error && <div className="form-alert error" role="alert">{error}</div>}
        <div className="announcement-summary" aria-label="Announcement summary">
          <div className="announcement-stat"><span className="announcement-stat-icon primary"><Megaphone size={20} /></span><div><strong>{summary.total}</strong><span>Total broadcasts</span></div></div>
          <div className="announcement-stat"><span className="announcement-stat-icon success"><Radio size={20} /></span><div><strong>{summary.active}</strong><span>Currently active</span></div></div>
          <div className="announcement-stat"><span className="announcement-stat-icon secondary"><Megaphone size={20} /></span><div><strong>{summary.scheduled}</strong><span>Scheduled</span></div></div>
          <div className="announcement-stat"><span className="announcement-stat-icon emergency"><Ban size={20} /></span><div><strong>{summary.urgent}</strong><span>Urgent</span></div></div>
        </div>

        <div className="announcement-list-card card">
          <div className="announcement-list-header">
            <div><h3>Official Announcements</h3><p>Review, edit and manage broadcasts sent to travellers.</p></div>
            <div className="announcement-filters">
              <ListFilterSearchField className="announcement-filter-search" value={search} onChange={setSearch} placeholder="Search announcements…" label="Search announcements" />
              <select className="input announcement-status-filter" value={statusFilter} onChange={(event) => setStatusFilter(event.target.value)} aria-label="Filter by status"><option value="current">Active &amp; scheduled</option><option value="all">All statuses</option><option value="active">Active</option><option value="scheduled">Scheduled</option><option value="expired">Expired</option><option value="withdrawn">Withdrawn</option></select>
              <select className="input announcement-priority-filter" value={priorityFilter} onChange={(event) => setPriorityFilter(event.target.value)} aria-label="Filter by priority"><option value="all">All priorities</option><option value="low">Low</option><option value="normal">Normal</option><option value="high">High priority</option><option value="urgent">Urgent</option></select>
              <label className="announcement-date-filter">From<input className="input" type="date" value={dateFrom} onChange={(event) => setDateFrom(event.target.value)} aria-label="Published from" /></label>
              <label className="announcement-date-filter">To<input className="input" type="date" value={dateTo} min={dateFrom || undefined} onChange={(event) => setDateTo(event.target.value)} aria-label="Published to" /></label>
            </div>
          </div>
          {loading && <div className="announcement-empty">Loading announcements…</div>}
          {!loading && filtered.length === 0 && <div className="announcement-empty"><Megaphone size={28} /><strong>No announcements found</strong><span>Try changing the search or status filter.</span></div>}
          {!loading && filtered.length > 0 && <div className="table-scroll"><table className="data-table announcement-table">
            <thead><tr><th>Announcement</th><th>Priority</th><th>Status</th><th>Target</th><th>Languages</th><th>Published</th><th>Actions</th></tr></thead>
            <tbody>{pageItems.map((item) => {
              const translationCount = Object.keys(item.translations || {}).length
              const status = displayStatus(item)
              return <tr key={item.id} className={`announcement-table-row status-${status}`}>
                <td><Link className="announcement-table-title" to={`/announcements/${item.id}`}>{item.title}</Link></td>
                <td><span className={`badge ${announcementPriorityClass[item.priority] || 'muted'}`}>{announcementPriorityLabel(item.priority)}</span></td>
                <td><span className={`badge ${statusClass[status] || 'muted'}`}>{status}</span></td>
                <td><span className="announcement-table-meta"><MapPin size={14} />{item.service_areas?.name || 'All service areas'}</span></td>
                <td><span className="announcement-table-meta"><Globe2 size={14} />{translationCount ? `${translationCount + 1} languages` : 'English only'}</span></td>
                <td>{status === 'scheduled' ? <span className="badge secondary">Scheduled — {formatDate(item.published_at)}</span> : formatDate(item.published_at || item.created_at)}</td>
                <td><div className="table-actions"><Link className="btn btn-outline btn-sm" to={`/announcements/${item.id}`}><Eye size={14} /> View</Link><Link className="btn btn-outline btn-sm" to={`/announcements/${item.id}/edit`}><Pencil size={14} /> Edit</Link>{status !== 'withdrawn' && <button className="btn btn-danger btn-sm" disabled={deletingId === item.id} onClick={() => deleteAnnouncement(item.id, item.title)}>{deletingId === item.id ? 'Withdrawing…' : 'Withdraw'}</button>}</div></td>
              </tr>
            })}</tbody>
          </table></div>}
          {!loading && <ListPagination page={currentPage} totalItems={filtered.length} pageSize={pageSize} onPageChange={setPage} label="Announcement list" />}
        </div>
      </div>
    </div>
  )
}
