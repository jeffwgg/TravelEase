import React, { useEffect, useState } from 'react'
import { useAuth } from '../context/AuthContext'
import { institutionSettingsRepository } from '../repositories/institutionSettingsRepository'
import ServiceAreaManager from '../components/ServiceAreaManager'

const emptyProfile = {
  name: '',
  institution_type: '',
  official_contact: '',
  service_address: '',
}

export default function ProfilePage() {
  const { session, refreshStaffContext } = useAuth()
  const [profile, setProfile] = useState(emptyProfile)
  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')

  useEffect(() => {
    let active = true

    institutionSettingsRepository.getCurrentInstitution()
      .then((data) => {
        if (!active) return
        setProfile({
          ...data,
          name: data.name || '',
          institution_type: data.institution_type || '',
          official_contact: data.official_contact || '',
          service_address: data.service_address || '',
        })
      })
      .catch((loadError) => {
        if (active) setError(friendlySettingsError(loadError))
      })
      .finally(() => {
        if (active) setLoading(false)
      })

    return () => { active = false }
  }, [])

  const updateField = (field) => (event) => {
    setProfile((current) => ({ ...current, [field]: event.target.value }))
    setError('')
    setSuccess('')
  }

  const saveProfile = async () => {
    const validationError = validateProfile(profile)
    if (validationError) {
      setError(validationError)
      setSuccess('')
      return
    }

    setSaving(true)
    setError('')
    setSuccess('')
    try {
      const saved = await institutionSettingsRepository.updateCurrentInstitution(profile)
      setProfile({
        ...saved,
        name: saved.name || '',
        institution_type: saved.institution_type || '',
        official_contact: saved.official_contact || '',
        service_address: saved.service_address || '',
      })
      await refreshStaffContext()
      setSuccess('Institution details saved successfully.')
    } catch (saveError) {
      setError(friendlySettingsError(saveError))
    } finally {
      setSaving(false)
    }
  }

  const verified = profile.verification_status === 'email_verified'

  return (
    <div>
      <div className="page-header">
        <div>
          <h2>Organization Profile Management</h2>
          <div className="header-subtitle">Manage institution details and location-based service coverage.</div>
        </div>
        <button className="btn btn-primary" onClick={saveProfile} disabled={loading || saving}>
          {saving ? 'Saving…' : 'Save Changes'}
        </button>
      </div>

      <div className="page-body">
        <div className="grid-2">
          {/* Org details */}
          <div className="card">
            <div className="card-header">
              <h3>Institution Details</h3>
              <span className={`badge ${verified ? 'success' : 'muted'}`}>
                {verified ? 'Verified Institution' : 'Verification Pending'}
              </span>
            </div>
            {loading && <div className="form-alert info" role="status">Loading institution details…</div>}
            {error && <div className="form-alert error" role="alert">{error}</div>}
            {success && <div className="form-alert success" role="status">{success}</div>}
            <div className="form-group">
              <label>Organization Name</label>
              <input type="text" className="input" value={profile.name} onChange={updateField('name')} disabled={loading || saving} />
            </div>
            <div className="form-group">
              <label>Account Email</label>
              <input type="email" className="input" value={session?.user?.email || 'Loading account…'} readOnly aria-describedby="account-email-help" />
              <small id="account-email-help" className="field-help">Managed through your Supabase authentication account.</small>
            </div>
            <div className="form-group">
              <label>Category</label>
              <select className="input" value={profile.institution_type} onChange={updateField('institution_type')} disabled={loading || saving}>
                <option value="">Select institution type</option>
                <option value="airport_transport">Airport / Transportation Hub</option>
                <option value="hotel_hospitality">Hotel &amp; Hospitality</option>
                <option value="tourist_attraction">Tourist Attraction</option>
                <option value="healthcare">Healthcare Facility</option>
                <option value="government">Government Agency</option>
                <option value="other">Other</option>
              </select>
            </div>
            <div className="form-group">
              <label>Official Address</label>
              <textarea className="input" rows={3} value={profile.service_address} onChange={updateField('service_address')} disabled={loading || saving}></textarea>
            </div>
            <div className="form-group">
              <label>Support Contact Hotline (SMS/Text)</label>
              <input type="text" className="input" value={profile.official_contact} onChange={updateField('official_contact')} disabled={loading || saving} />
            </div>
          </div>

          {/* Service areas and existing staff summary */}
          <div style={{ display: 'flex', flexDirection: 'column', gap: '24px' }}>
            <ServiceAreaManager />
            {profile.showLegacyServiceZones && <div className="card">
              <div className="card-header">
                <h3>Active Service Zones / Branches</h3>
                <button className="btn btn-outline btn-sm">+ Add Zone</button>
              </div>
              <table className="data-table">
                <thead>
                  <tr>
                    <th>Zone Name</th>
                    <th>Staff On Duty</th>
                    <th>Status</th>
                  </tr>
                </thead>
                <tbody>
                  <tr>
                    <td>Terminal 1 â€” Main Terminal</td>
                    <td>14 staff</td>
                    <td><span className="badge success">Active</span></td>
                  </tr>
                  <tr>
                    <td>Terminal 1 â€” Satellite Building</td>
                    <td>8 staff</td>
                    <td><span className="badge success">Active</span></td>
                  </tr>
                  <tr>
                    <td>Terminal 2 â€” Budget Hub</td>
                    <td>12 staff</td>
                    <td><span className="badge success">Active</span></td>
                  </tr>
                </tbody>
              </table>
            </div>}

          </div>
        </div>
      </div>
    </div>
  )
}

function validateProfile(profile) {
  if (profile.name.trim().length < 2 || profile.name.trim().length > 120) {
    return 'Organization name must be between 2 and 120 characters.'
  }
  if (!profile.institution_type) return 'Select an institution category.'
  if (profile.service_address.trim().length < 10 || profile.service_address.trim().length > 500) {
    return 'Official address must be between 10 and 500 characters.'
  }
  if (profile.official_contact.trim().length < 5 || profile.official_contact.trim().length > 100) {
    return 'Enter a valid support contact.'
  }
  return ''
}

function friendlySettingsError(error) {
  const message = String(error?.message || '').toLowerCase()
  if (message.includes('jwt') || message.includes('session')) return 'Your session has expired. Please sign in again.'
  if (message.includes('row-level security') || message.includes('permission')) return 'You do not have permission to update this institution.'
  if (message.includes('multiple') || message.includes('no rows')) return 'The institution profile could not be found.'
  return error?.message || 'Unable to save institution settings.'
}
