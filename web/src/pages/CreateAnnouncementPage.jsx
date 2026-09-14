import React, { useEffect, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'
import { announcementRepository } from '../repositories/announcementRepository'
import { useAutoDismiss } from '../hooks/useAutoDismiss'

const languageOptions = [
  { code: 'ms', label: 'Bahasa Melayu' },
  { code: 'zh', label: 'Chinese (Simplified)' },
]

const initialForm = {
  title: '', serviceAreaId: 'all', type: '', priority: 'normal',
  messageEn: '', messageMs: '', messageZh: '', scheduledAt: '', autoTranslate: false,
  targetLanguages: ['ms'], status: 'active',
}

const emptyTranslations = {
  ms: { title: '', message: '' },
  zh: { title: '', message: '' },
}

function toLocalDateTime(value) {
  if (!value) return ''
  const date = new Date(value)
  const offset = date.getTimezoneOffset() * 60000
  return new Date(date.getTime() - offset).toISOString().slice(0, 16)
}

export default function CreateAnnouncementPage() {
  const { id } = useParams()
  const isEditing = Boolean(id)
  const navigate = useNavigate()
  const { session, staffContext } = useAuth()
  const [form, setForm] = useState(initialForm)
  const [serviceAreas, setServiceAreas] = useState([])
  const [fieldErrors, setFieldErrors] = useState({})
  const [loading, setLoading] = useState(true)
  const [publishLocked, setPublishLocked] = useState(false)
  const [submitting, setSubmitting] = useState(false)
  const [translating, setTranslating] = useState(false)
  const [translations, setTranslations] = useState(emptyTranslations)
  const [error, setError] = useState('')
  useAutoDismiss(error, () => setError(''))

  useEffect(() => {
    const load = async () => {
      try {
        const serviceAreaData = await announcementRepository.getServiceAreas(staffContext.institution_id)
        setServiceAreas(serviceAreaData)
        if (isEditing) {
          const item = await announcementRepository.getAnnouncement(id, staffContext.institution_id)
          setForm({
            title: item.title,
            serviceAreaId: item.service_area_id || 'all',
            type: item.announcement_type,
            priority: item.priority,
            messageEn: item.message_en,
            messageMs: item.translations?.ms?.message || '',
            messageZh: item.translations?.zh?.message || '',
            scheduledAt: toLocalDateTime(item.published_at),
            autoTranslate: item.auto_translated || false,
            targetLanguages: Object.keys(item.translations || {}).length ? Object.keys(item.translations) : ['ms'],
            status: item.status,
          })
          setPublishLocked(Boolean(item.published_at) && new Date(item.published_at) <= new Date())
          setTranslations({
            ms: {
              title: item.translations?.ms?.title || '',
              message: item.translations?.ms?.message || '',
            },
            zh: {
              title: item.translations?.zh?.title || '',
              message: item.translations?.zh?.message || '',
            },
          })
        }
      } catch (loadError) {
        setError(loadError.message || 'Unable to load the announcement form.')
      } finally {
        setLoading(false)
      }
    }
    load()
  }, [id, isEditing, staffContext.institution_id])

  const update = (field) => (event) => {
    const value = event.target.value
    setForm((current) => ({ ...current, [field]: value }))
    setFieldErrors((current) => ({ ...current, [field]: '' }))
  }

  const toggleLanguage = (code) => {
    setForm((current) => ({
      ...current,
      targetLanguages: current.targetLanguages.includes(code)
        ? current.targetLanguages.filter((item) => item !== code)
        : [...current.targetLanguages, code],
    }))
    setFieldErrors((current) => ({ ...current, targetLanguages: '' }))
  }

  const updateTranslation = (code, field) => (event) => {
    const value = event.target.value
    setTranslations((current) => ({
      ...current,
      [code]: { ...current[code], [field]: value },
    }))
  }

  const generateTranslations = async () => {
    const next = {}
    if (!form.title.trim()) next.title = 'Title / Subject is required before translating.'
    if (!form.messageEn.trim()) next.messageEn = 'English message content is required before translating.'
    if (form.targetLanguages.length === 0) next.targetLanguages = 'Choose at least one translation language.'
    setFieldErrors((current) => ({ ...current, ...next }))
    if (Object.keys(next).length) return

    setTranslating(true)
    setError('')
    try {
      const generated = await announcementRepository.translateAnnouncement({
        title: form.title.trim(),
        message: form.messageEn.trim(),
        targetLanguages: form.targetLanguages,
      })
      setTranslations((current) => ({ ...current, ...generated }))
    } catch (translationError) {
      setError(translationError.message || 'Unable to generate translations.')
    } finally {
      setTranslating(false)
    }
  }

  const validate = () => {
    const next = {}
    if (!form.title.trim()) next.title = 'Title / Subject is required.'
    if (!form.serviceAreaId) next.serviceAreaId = 'Target service area is required.'
    if (!form.priority) next.priority = 'Priority is required.'
    if (isEditing && !form.status) next.status = 'Status is required.'
    if (!form.messageEn.trim()) next.messageEn = 'English message content is required.'
    if (form.autoTranslate && form.targetLanguages.length === 0) next.targetLanguages = 'Choose at least one translation language.'
    // A published announcement keeps its original (past) publish time in the
    // disabled schedule field — that must not fail validation.
    if (!publishLocked && form.scheduledAt && new Date(form.scheduledAt) <= new Date()) next.scheduledAt = 'Schedule publish time must be in the future.'
    setFieldErrors(next)
    return Object.keys(next).length === 0
  }

  const handleSubmit = async (event) => {
    event.preventDefault()
    if (!validate()) return
    setSubmitting(true)
    setError('')
    try {
      let translationsPayload = {}
      if (form.autoTranslate) {
        const incompleteLanguages = form.targetLanguages.filter((code) => (
          !translations[code]?.title.trim() || !translations[code]?.message.trim()
        ))
        let generated = {}
        if (incompleteLanguages.length) {
          generated = await announcementRepository.translateAnnouncement({
            title: form.title.trim(), message: form.messageEn.trim(), targetLanguages: incompleteLanguages,
          })
        }
        translationsPayload = Object.fromEntries(form.targetLanguages.map((code) => [code, {
          title: translations[code]?.title.trim() || generated[code]?.title || '',
          message: translations[code]?.message.trim() || generated[code]?.message || '',
        }]))
        setTranslations((current) => ({ ...current, ...translationsPayload }))
      } else {
        if (form.messageMs.trim()) translationsPayload.ms = { title: form.title.trim(), message: form.messageMs.trim() }
        if (form.messageZh.trim()) translationsPayload.zh = { title: form.title.trim(), message: form.messageZh.trim() }
      }

      const scheduledFor = form.scheduledAt ? new Date(form.scheduledAt) : null
      const isScheduled = Boolean(scheduledFor) && scheduledFor > new Date()
      const payload = {
        service_area_id: form.serviceAreaId === 'all' ? null : form.serviceAreaId,
        title: form.title.trim(),
        message_en: form.messageEn.trim(),
        announcement_type: form.type,
        priority: form.priority,
        status: form.status,
        translations: translationsPayload,
        auto_translated: form.autoTranslate,
      }
      // A future schedule time becomes the publish time: mobile apps already
      // hide announcements whose published_at is in the future. Clearing the
      // schedule on an editable announcement publishes it immediately; a
      // published announcement keeps its original publish time.
      if (isScheduled) {
        payload.published_at = scheduledFor.toISOString()
      } else if (!isEditing || !publishLocked) {
        payload.published_at = new Date().toISOString()
      }

      if (isEditing) {
        await announcementRepository.updateAnnouncement(id, payload)
      } else {
        await announcementRepository.createAnnouncement({
          ...payload,
          institution_id: staffContext.institution_id,
          created_by: session.user.id,
        })
      }
      navigate('/announcements', { replace: true })
    } catch (submitError) {
      setError(submitError.message || `Unable to ${isEditing ? 'update' : 'broadcast'} the announcement.`)
    } finally {
      setSubmitting(false)
    }
  }

  const fieldError = (name) => fieldErrors[name] && <div className="field-error" role="alert">{fieldErrors[name]}</div>

  return (
    <div>
      <div className="page-header">
        <div><h2>{isEditing ? 'Edit Announcement' : 'Create Announcement'}</h2><div className="header-subtitle">{isEditing ? 'Update the official announcement information.' : 'Broadcast an official visual announcement to travellers at your institution.'}</div></div>
        <Link to="/announcements" className="btn btn-outline">Back to Announcements</Link>
      </div>

      <div className="page-body">
        <form className="card full-width-form" onSubmit={handleSubmit} noValidate>
          {error && <div className="form-alert error" role="alert">{error}</div>}
          {loading ? <div className="table-message">Loading announcement…</div> : <>
            <div className="form-group"><label htmlFor="announcement-title">Title / Subject <span className="required-mark">*</span></label><input id="announcement-title" className={`input ${fieldErrors.title ? 'invalid' : ''}`} value={form.title} onChange={update('title')} maxLength={160} placeholder="e.g. Gate Change — MH370" />{fieldError('title')}</div>
            <div className="form-grid">
              <div className="form-group"><label htmlFor="announcement-service-area">Target Service Area <span className="required-mark">*</span></label><select id="announcement-service-area" className={`input ${fieldErrors.serviceAreaId ? 'invalid' : ''}`} value={form.serviceAreaId} onChange={update('serviceAreaId')}><option value="all">All service areas (entire institution)</option>{serviceAreas.map((area) => <option key={area.id} value={area.id}>{area.name}</option>)}</select>{fieldError('serviceAreaId')}</div>
              <div className="form-group"><label htmlFor="announcement-type">Announcement Type </label><input id="announcement-type" className={`input ${fieldErrors.type ? 'invalid' : ''}`} value={form.type} onChange={update('type')} maxLength={160} placeholder="e.g. General Information" />{fieldError('type')}</div>
              <div className="form-group"><label htmlFor="announcement-priority">Priority <span className="required-mark">*</span></label><select id="announcement-priority" className={`input ${fieldErrors.priority ? 'invalid' : ''}`} value={form.priority} onChange={update('priority')}><option value="low">Low</option><option value="normal">Normal</option><option value="high">High</option><option value="urgent">Urgent</option></select>{fieldError('priority')}</div>
              <div className="form-group"><label htmlFor="announcement-schedule">Schedule Publish Time (Optional)</label><input id="announcement-schedule" type="datetime-local" className={`input ${fieldErrors.scheduledAt ? 'invalid' : ''}`} value={form.scheduledAt} min={new Date().toISOString().slice(0, 16)} disabled={publishLocked} onChange={update('scheduledAt')} />{fieldError('scheduledAt')}{publishLocked && <div className="field-note">Already published — the schedule can no longer be changed.</div>}</div>
              {isEditing && <div className="form-group"><label htmlFor="announcement-status">Status <span className="required-mark">*</span></label><select id="announcement-status" className={`input ${fieldErrors.status ? 'invalid' : ''}`} value={form.status} onChange={update('status')}><option value="active">Active</option><option value="draft">Draft</option><option value="cancelled">Cancelled</option></select>{fieldError('status')}</div>}
            </div>
            <div className="form-group"><label htmlFor="message-en">Message Content (English) <span className="required-mark">*</span></label><textarea id="message-en" className={`input ${fieldErrors.messageEn ? 'invalid' : ''}`} rows={5} value={form.messageEn} onChange={update('messageEn')} maxLength={2000} placeholder="Type the official announcement in English..." />{fieldError('messageEn')}</div>

            <div className="translation-panel">
              <label className="translation-toggle"><input type="checkbox" checked={form.autoTranslate} onChange={(event) => setForm((current) => ({ ...current, autoTranslate: event.target.checked }))} /><span><strong>Automatically translate this announcement</strong><small>Generate selected translations from the English title and message.</small></span></label>
              {form.autoTranslate ? <>
                <div className="language-options"><div className="language-options-title">Translation languages <span className="required-mark">*</span></div>{languageOptions.map((language) => <label key={language.code}><input type="checkbox" checked={form.targetLanguages.includes(language.code)} onChange={() => toggleLanguage(language.code)} /> {language.label}</label>)}{fieldError('targetLanguages')}</div>
                <button type="button" className="btn btn-outline translation-generate" onClick={generateTranslations} disabled={translating || submitting}>{translating ? 'Generating Translations…' : 'Generate & Preview Translations'}</button>
                <div className="translation-previews">
                  {languageOptions.filter((language) => form.targetLanguages.includes(language.code)).map((language) => <div className="translation-preview" key={language.code}>
                    <div className="translation-preview-heading"><strong>{language.label}</strong><span>Editable translation</span></div>
                    <div className="form-group"><label htmlFor={`translation-${language.code}-title`}>Translated Title</label><input id={`translation-${language.code}-title`} className="input" value={translations[language.code]?.title || ''} onChange={updateTranslation(language.code, 'title')} maxLength={160} placeholder={`Enter or generate the ${language.label} title...`} /></div>
                    <div className="form-group"><label htmlFor={`translation-${language.code}-message`}>Translated Message</label><textarea id={`translation-${language.code}-message`} className="input" rows={4} value={translations[language.code]?.message || ''} onChange={updateTranslation(language.code, 'message')} maxLength={2000} placeholder={`Enter or generate the ${language.label} message...`} /></div>
                  </div>)}
                </div>
              </> : <div className="manual-translation">
                <div className="manual-translation-intro"><strong>Manual translations</strong><span>Automatic translation is off. Both translations below are optional—enter either or both if you want travellers to see the announcement in another language.</span></div>
                <div className="manual-translation-grid">
                  <div className="form-group"><label htmlFor="message-ms">Bahasa Melayu <span className="optional-label">Optional</span></label><textarea id="message-ms" className="input" rows={5} value={form.messageMs} onChange={update('messageMs')} maxLength={2000} placeholder="Enter the complete announcement in Bahasa Melayu..." /><div className="field-note">Leave blank if a Malay translation is not required.</div></div>
                  <div className="form-group"><label htmlFor="message-zh">Simplified Chinese <span className="optional-label">Optional</span></label><textarea id="message-zh" className="input" rows={5} value={form.messageZh} onChange={update('messageZh')} maxLength={2000} placeholder="Enter the complete announcement in Simplified Chinese..." /><div className="field-note">Leave blank if a Chinese translation is not required.</div></div>
                </div>
              </div>}
            </div>

            <button type="submit" className="btn btn-primary" disabled={submitting} style={{ width: '100%', justifyContent: 'center' }}>{submitting ? (form.autoTranslate ? 'Translating & Saving…' : 'Saving…') : (isEditing ? 'Save Changes' : (form.scheduledAt && new Date(form.scheduledAt) > new Date() ? 'Schedule Broadcast' : 'Broadcast Instantly'))}</button>
          </>}
        </form>
      </div>
    </div>
  )
}
