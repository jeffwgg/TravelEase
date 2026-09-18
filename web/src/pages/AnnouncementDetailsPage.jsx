import { useEffect, useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { CalendarClock, Globe2, MapPin } from 'lucide-react'
import { useAuth } from '../context/AuthContext'
import { announcementRepository } from '../repositories/announcementRepository'

const statusClass = { active: 'success', scheduled: 'secondary', withdrawn: 'emergency', expired: 'muted' }
const announcementPriorityClass = { low: 'muted', normal: 'primary', high: 'secondary', urgent: 'emergency' }

function announcementPriorityLabel(priority) {
  if (priority === 'high') return 'High priority'
  if (priority === 'urgent') return 'Urgent'
  if (priority === 'normal') return 'Normal'
  if (priority === 'low') return 'Low'
  return priority || 'Normal'
}

function formatDate(value) {
  if (!value) return 'Not set'
  return new Intl.DateTimeFormat('en-MY', { dateStyle: 'medium', timeStyle: 'short' }).format(new Date(value))
}

function displayStatus(item) {
  return item.status
}

export default function AnnouncementDetailsPage() {
  const { id } = useParams()
  const { staffContext } = useAuth()
  const [announcement, setAnnouncement] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  useEffect(() => {
    let active = true
    announcementRepository.getAnnouncement(id, staffContext.institution_id)
      .then((item) => { if (active) setAnnouncement(item) })
      .catch((loadError) => { if (active) setError(loadError.message || 'Unable to load this announcement.') })
      .finally(() => { if (active) setLoading(false) })
    return () => { active = false }
  }, [id, staffContext.institution_id])

  if (loading) return <div className="page-body"><div className="table-message">Loading announcement…</div></div>
  if (error || !announcement) return <div className="page-body"><div className="form-alert error">{error || 'Announcement not found.'}</div><Link to="/announcements" className="btn btn-outline">Back to Announcements</Link></div>

  const status = displayStatus(announcement)
  const translations = Object.entries(announcement.translations || {})

  return (
    <div>
      <div className="page-header">
        <div><h2>Announcement Details</h2><div className="header-subtitle">Review the complete broadcast before editing it.</div></div>
        <div className="table-actions"><Link to="/announcements" className="btn btn-outline">Back to Announcements</Link><Link to={`/announcements/${announcement.id}/edit`} className="btn btn-primary">Edit Announcement</Link></div>
      </div>
      <div className="page-body">
        <article className="card announcement-detail-card">
          <div className="announcement-detail-heading">
            <div><div className="announcement-badges"><span className={`badge ${statusClass[status] || 'muted'}`}>{status}</span><span className={`badge ${announcementPriorityClass[announcement.priority] || 'muted'}`}>{announcementPriorityLabel(announcement.priority)}</span></div><h3>{announcement.title}</h3></div>
          </div>
          <div className="announcement-detail-meta">
            <span><MapPin size={15} />{announcement.service_areas?.name || 'All service areas'}</span>
            <span><CalendarClock size={15} />Published: {formatDate(announcement.published_at)}</span>
            <span><CalendarClock size={15} />Expires: {formatDate(announcement.expires_at)}</span>
            <span><Globe2 size={15} />{translations.length ? `${translations.length + 1} languages` : 'English only'}</span>
          </div>
          <div className="announcement-detail-message"><h4>English announcement</h4><p>{announcement.message_en}</p></div>
          {translations.map(([language, translation]) => <div className="announcement-detail-message" key={language}><h4>{language === 'ms' ? 'Bahasa Melayu' : language === 'zh' ? 'Chinese (Simplified)' : language}</h4><strong>{translation.title || announcement.title}</strong><p>{translation.message}</p></div>)}
        </article>
      </div>
    </div>
  )
}
