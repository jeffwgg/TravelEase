import { useCallback, useEffect, useMemo, useState } from 'react'
import { CircleMarker, MapContainer, TileLayer } from 'react-leaflet'
import { AlertTriangle, CheckCircle2, Clock3, MapPin, RefreshCw, ShieldCheck, X } from 'lucide-react'
import 'leaflet/dist/leaflet.css'
import { useAuth } from '../context/AuthContext'
import { sosRequestRepository } from '../repositories/sosRequestRepository'

export default function SosRequestsPage() {
  const { staffContext } = useAuth()
  const institutionId = staffContext?.institutions?.id
  const [requests, setRequests] = useState([])
  const [loading, setLoading] = useState(true)
  const [refreshing, setRefreshing] = useState(false)
  const [busyId, setBusyId] = useState('')
  const [error, setError] = useState('')
  const [selectedLocation, setSelectedLocation] = useState(null)

  const load = useCallback(async ({ quiet = false } = {}) => {
    if (!institutionId) return
    if (quiet) setRefreshing(true)
    else setLoading(true)
    setError('')
    try {
      setRequests(await sosRequestRepository.listForInstitution(institutionId))
    } catch (loadError) {
      setError(friendlyError(loadError))
    } finally {
      setLoading(false)
      setRefreshing(false)
    }
  }, [institutionId])

  useEffect(() => {
    if (!institutionId) return undefined
    load()
    return sosRequestRepository.subscribe(institutionId, () => load({ quiet: true }))
  }, [institutionId, load])

  const activeRequests = useMemo(
    () => requests.filter((request) => request.status === 'sent' || request.status === 'acknowledged'),
    [requests],
  )
  const resolvedRequests = useMemo(
    () => requests.filter((request) => request.status === 'resolved'),
    [requests],
  )

  const updateStatus = async (request, status) => {
    setBusyId(request.id)
    setError('')
    try {
      const updated = await sosRequestRepository.updateStatus(
        institutionId,
        request.id,
        request.status,
        status,
      )
      setRequests((current) => current.map((item) => item.id === updated.id ? updated : item))
    } catch (updateError) {
      setError(friendlyError(updateError))
    } finally {
      setBusyId('')
    }
  }

  const resolveRequest = (request) => {
    const confirmed = window.confirm(
      'Resolve this SOS request?\n\nThis marks the emergency as completed.',
    )
    if (confirmed) updateStatus(request, 'resolved')
  }

  return <div className="page sos-page">
    <div className="page-header sos-page-header">
      <div>
        <h1>SOS / Emergency</h1>
        <p>Emergency alerts matched to your institution’s active Service Areas.</p>
      </div>
      <button className="btn btn-outline" onClick={() => load({ quiet: true })} disabled={refreshing}>
        <RefreshCw size={16} className={refreshing ? 'spin' : ''} />
        {refreshing ? 'Refreshing…' : 'Refresh'}
      </button>
    </div>

    {error && <div className="form-alert error" role="alert">{error}</div>}
    {loading ? <div className="card sos-empty">Loading SOS requests…</div> : <>
      <section className="sos-section" aria-labelledby="active-sos-title">
        <div className="sos-section-heading emergency">
          <div>
            <span className="sos-heading-icon"><AlertTriangle size={20} /></span>
            <div><h2 id="active-sos-title">Active SOS Requests</h2><p>Sent and acknowledged emergencies requiring attention.</p></div>
          </div>
          <span className="sos-count">{activeRequests.length}</span>
        </div>
        {activeRequests.length === 0
          ? <div className="card sos-empty"><ShieldCheck size={30} /><strong>No active SOS requests</strong><span>New institution-linked alerts will appear here automatically.</span></div>
          : <div className="sos-grid">{activeRequests.map((request) =>
            <SosRequestCard
              key={request.id}
              request={request}
              busy={busyId === request.id}
              onView={() => setSelectedLocation(request)}
              onAcknowledge={() => updateStatus(request, 'acknowledged')}
              onResolve={() => resolveRequest(request)}
            />,
          )}</div>}
      </section>

      <section className="sos-section" aria-labelledby="resolved-sos-title">
        <div className="sos-section-heading">
          <div>
            <span className="sos-heading-icon resolved"><CheckCircle2 size={20} /></span>
            <div><h2 id="resolved-sos-title">Resolved Requests</h2><p>Completed SOS requests, newest first.</p></div>
          </div>
          <span className="sos-count muted">{resolvedRequests.length}</span>
        </div>
        {resolvedRequests.length === 0
          ? <div className="card sos-empty compact"><span>No resolved SOS requests yet.</span></div>
          : <div className="sos-grid">{resolvedRequests.map((request) =>
            <SosRequestCard
              key={request.id}
              request={request}
              busy={false}
              onView={() => setSelectedLocation(request)}
            />,
          )}</div>}
      </section>
    </>}

    {selectedLocation && <LocationModal request={selectedLocation} onClose={() => setSelectedLocation(null)} />}
  </div>
}

function SosRequestCard({ request, busy, onView, onAcknowledge, onResolve }) {
  const isResolved = request.status === 'resolved'
  const travellerName = request.traveller?.full_name || 'Traveller'
  const serviceAreaName = request.service_area?.name || 'Unknown Service Area'
  return <article className={`card sos-request-card ${isResolved ? 'resolved' : 'active'}`}>
    <div className="sos-request-topline">
      <div><strong>{travellerName}</strong><span><Clock3 size={14} /> {formatTime(request.triggered_at)}</span></div>
      <span className={`sos-status ${request.status}`}>{statusLabel(request.status)}</span>
    </div>
    <dl className="sos-request-details">
      <div><dt>Service Area</dt><dd>{serviceAreaName}</dd></div>
      <div><dt>Latitude / Longitude</dt><dd>{formatCoordinate(request.latitude)}, {formatCoordinate(request.longitude)}</dd></div>
    </dl>
    <div className="sos-request-actions">
      <button className="btn btn-outline btn-sm" onClick={onView}><MapPin size={15} /> View Location</button>
      {request.status === 'sent' && <button className="btn btn-primary btn-sm" disabled={busy} onClick={onAcknowledge}>{busy ? 'Acknowledging…' : 'Acknowledge'}</button>}
      {request.status === 'acknowledged' && <button className="btn btn-primary btn-sm" disabled={busy} onClick={onResolve}>{busy ? 'Resolving…' : 'Resolve'}</button>}
    </div>
  </article>
}

function LocationModal({ request, onClose }) {
  const position = [Number(request.latitude), Number(request.longitude)]
  return <div className="sos-map-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose() }}>
    <div className="sos-map-dialog" role="dialog" aria-modal="true" aria-labelledby="sos-location-title">
      <div className="sos-map-header">
        <div><h2 id="sos-location-title">Traveller SOS Location</h2><p>{formatCoordinate(request.latitude)}, {formatCoordinate(request.longitude)}</p></div>
        <button className="icon-button" onClick={onClose} aria-label="Close location map"><X size={20} /></button>
      </div>
      <div className="sos-location-map">
        <MapContainer center={position} zoom={16} scrollWheelZoom>
          <TileLayer attribution='&copy; OpenStreetMap contributors' url="https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" />
          <CircleMarker center={position} radius={11} pathOptions={{ color: '#b91c1c', fillColor: '#ef4444', fillOpacity: 0.85, weight: 3 }} />
        </MapContainer>
      </div>
      <div className="sos-map-actions"><button className="btn btn-outline" onClick={onClose}>Close</button></div>
    </div>
  </div>
}

function statusLabel(status) {
  if (status === 'acknowledged') return 'Acknowledged'
  if (status === 'resolved') return 'Resolved'
  return 'Sent'
}

function formatTime(value) {
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? 'Unknown time' : date.toLocaleString()
}

function formatCoordinate(value) {
  const coordinate = Number(value)
  return Number.isFinite(coordinate) ? coordinate.toFixed(6) : 'Unavailable'
}

function friendlyError(error) {
  const message = String(error?.message || '')
  const lower = message.toLowerCase()
  if (lower.includes('sos_requests') && lower.includes('schema cache')) return 'SOS requests are not configured yet. Apply migrations 011 and 012 in Supabase.'
  if (lower.includes('permission') || lower.includes('row-level security')) return 'Supabase denied this SOS operation. Re-run migration 012 and confirm this login is linked through institutions.account_user_id.'
  return message || 'Unable to load SOS requests.'
}
