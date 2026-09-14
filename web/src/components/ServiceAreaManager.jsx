import React, { useCallback, useEffect, useState } from 'react'
import { Circle, MapContainer, Marker, TileLayer, Tooltip, useMap, useMapEvents } from 'react-leaflet'
import L from 'leaflet'
import { Crosshair, MapPin, Pencil, Plus, Search, Trash2, X } from 'lucide-react'
import 'leaflet/dist/leaflet.css'
import { useAuth } from '../context/AuthContext'
import { serviceAreaRepository } from '../repositories/serviceAreaRepository'
import { geocodingService } from '../services/geocodingService'

const defaultCentre = { latitude: 3.139, longitude: 101.6869 }
const emptyArea = { name: '', address: '', ...defaultCentre, radius_m: 500, active: true }
const markerIcon = L.divIcon({ className: 'service-area-marker', html: '<span></span>', iconSize: [24, 24], iconAnchor: [12, 12] })

function overviewMarkerIcon(area, selected) {
  const classes = ['service-area-marker', 'overview', area.active ? 'active' : 'inactive']
  if (selected) classes.push('selected')
  return L.divIcon({
    className: classes.join(' '),
    html: '<span></span>',
    iconSize: [24, 24],
    iconAnchor: [12, 12],
  })
}

function OverviewMapController({ areas, selectedId }) {
  const map = useMap()

  useEffect(() => {
    const selected = areas.find((area) => area.id === selectedId)
    if (selected) {
      map.flyTo([selected.latitude, selected.longitude], Math.max(map.getZoom(), 15), { duration: 0.6 })
      return
    }
    if (!areas.length) return
    const bounds = L.latLngBounds()
    areas.forEach((area) => {
      bounds.extend(L.latLng(area.latitude, area.longitude).toBounds(Math.max(Number(area.radius_m) * 2, 100)))
    })
    map.fitBounds(bounds, { padding: [36, 36], maxZoom: 16 })
  }, [areas, selectedId, map])

  return null
}

function ServiceAreaOverviewMap({ areas, selectedId, onSelect }) {
  const selected = areas.find((area) => area.id === selectedId)
  return <div className="service-area-overview">
    <div className="service-area-overview-heading">
      <div><strong>Total Coverage Overview</strong><span>{areas.length} saved service {areas.length === 1 ? 'area' : 'areas'}</span></div>
      <div className="service-area-legend"><span><i className="active" /> Active</span><span><i /> Inactive</span></div>
    </div>
    <div className="service-area-overview-map">
      <MapContainer center={[areas[0].latitude, areas[0].longitude]} zoom={13} scrollWheelZoom>
        <TileLayer attribution='&copy; Google Maps' url="https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}" maxZoom={20} />
        <OverviewMapController areas={areas} selectedId={selectedId} />
        {areas.map((area) => {
          const isSelected = area.id === selectedId
          const color = area.active ? '#0d9488' : '#94a3b8'
          const position = [area.latitude, area.longitude]
          const select = () => onSelect(area.id)
          return <React.Fragment key={area.id}>
            <Circle className={`service-area-radius ${area.active ? 'active' : 'inactive'} ${isSelected ? 'selected' : ''}`} center={position} radius={area.radius_m} eventHandlers={{ click: select }} pathOptions={{ color, weight: isSelected ? 4 : 2, fillColor: color, fillOpacity: area.active ? (isSelected ? 0.26 : 0.16) : (isSelected ? 0.14 : 0.07), opacity: area.active ? 0.9 : 0.55 }} />
            <Marker position={position} icon={overviewMarkerIcon(area, isSelected)} eventHandlers={{ click: select }}>
              <Tooltip permanent={isSelected} direction="top" offset={[0, -12]}><strong>{area.name}</strong><br />{area.active ? 'Active' : 'Inactive'} · {area.radius_m.toLocaleString()} m</Tooltip>
            </Marker>
          </React.Fragment>
        })}
      </MapContainer>
    </div>
    {selected && <div className="service-area-map-detail" role="status">
      <MapPin size={17} />
      <div><strong>{selected.name}</strong><span>{selected.address || `${Number(selected.latitude).toFixed(5)}, ${Number(selected.longitude).toFixed(5)}`}</span></div>
      <span className={`badge ${selected.active ? 'success' : 'muted'}`}>{selected.active ? 'Active' : 'Inactive'}</span>
      <small>{selected.radius_m.toLocaleString()} m radius</small>
    </div>}
  </div>
}

function MapEditor({ value, onChange }) {
  const position = [value.latitude, value.longitude]
  useMapEvents({
    click(event) { onChange(event.latlng.lat, event.latlng.lng, true) },
  })
  const map = useMap()
  useEffect(() => { map.flyTo(position, Math.max(map.getZoom(), 15)) }, [map, value.latitude, value.longitude])
  return <>
    <TileLayer attribution='&copy; Google Maps' url="https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}" maxZoom={20} />
    <Circle center={position} radius={Number(value.radius_m) || 1} pathOptions={{ color: '#0d9488', fillColor: '#14b8a6', fillOpacity: 0.18 }} />
    <Marker draggable position={position} icon={markerIcon} eventHandlers={{ dragend: (event) => {
      const point = event.target.getLatLng()
      onChange(point.lat, point.lng, true)
    } }} />
  </>
}

export default function ServiceAreaManager() {
  const { staffContext } = useAuth()
  const [areas, setAreas] = useState([])
  const [loading, setLoading] = useState(true)
  const [busyId, setBusyId] = useState('')
  const [editing, setEditing] = useState(null)
  const [selectedId, setSelectedId] = useState('')
  const [error, setError] = useState('')
  const [success, setSuccess] = useState('')

  const load = useCallback(async () => {
    setLoading(true); setError('')
    try { setAreas(await serviceAreaRepository.list(staffContext)) }
    catch (e) { setError(friendlyError(e)) }
    finally { setLoading(false) }
  }, [staffContext])

  useEffect(() => { load() }, [load])

  const toggle = async (area) => {
    setBusyId(area.id); setError(''); setSuccess('')
    try {
      const saved = await serviceAreaRepository.setActive(staffContext, area, !area.active)
      setAreas((current) => current.map((item) => item.id === saved.id ? saved : item))
      setSuccess(`${saved.name} is now ${saved.active ? 'active' : 'inactive'}.`)
    } catch (e) { setError(friendlyError(e)) }
    finally { setBusyId('') }
  }

  const remove = async (area) => {
    if (!window.confirm(`Delete “${area.name}”? This cannot be undone.`)) return
    setBusyId(area.id); setError(''); setSuccess('')
    try {
      await serviceAreaRepository.remove(staffContext, area.id)
      setAreas((current) => current.filter((item) => item.id !== area.id))
      if (selectedId === area.id) setSelectedId('')
      setSuccess('Service area deleted.')
    } catch (e) { setError(friendlyError(e)) }
    finally { setBusyId('') }
  }

  return <div className="card service-area-card">
    <div className="card-header">
      <div><h3>Service Areas</h3><div className="service-area-help">Geographic coverage where travellers can access your services.</div></div>
      <button className="btn btn-outline btn-sm" onClick={() => setEditing({ ...emptyArea })}><Plus size={15} /> Add Area</button>
    </div>
    {loading && <div className="form-alert info">Loading service areas…</div>}
    {error && <div className="form-alert error" role="alert">{error}</div>}
    {success && <div className="form-alert success" role="status">{success}</div>}
    {!loading && areas.length === 0 && <div className="service-area-overview"><div className="service-area-overview-heading"><div><strong>Total Coverage Overview</strong><span>0 saved service areas</span></div></div><div className="service-area-empty"><MapPin size={28} /><strong>No service areas to display on the map</strong><span>Add the real-world area covered by this institution.</span></div></div>}
    {areas.length > 0 && <ServiceAreaOverviewMap areas={areas} selectedId={selectedId} onSelect={setSelectedId} />}
    {areas.length > 0 && <div className="service-area-list">{areas.map((area) => <div className={`service-area-row ${area.active ? 'active' : 'inactive'} ${selectedId === area.id ? 'selected' : ''}`} key={area.id} role="button" tabIndex={0} onClick={() => setSelectedId(area.id)} onKeyDown={(event) => { if (event.key === 'Enter' || event.key === ' ') setSelectedId(area.id) }}>
      <div className="service-area-row-main"><strong>{area.name}</strong><span>{area.address || `${Number(area.latitude).toFixed(5)}, ${Number(area.longitude).toFixed(5)}`}</span><small>{area.radius_m.toLocaleString()} m radius</small></div>
      <button className={`service-area-status ${area.active ? 'active' : ''}`} disabled={busyId === area.id} onClick={() => toggle(area)} aria-label={`Mark ${area.name} ${area.active ? 'inactive' : 'active'}`}><span />{area.active ? 'Active' : 'Inactive'}</button>
      <button className="icon-button" onClick={() => setEditing({ ...area })} title="Edit"><Pencil size={16} /></button>
      <button className="icon-button danger" disabled={busyId === area.id} onClick={() => remove(area)} title="Delete"><Trash2 size={16} /></button>
    </div>)}</div>}
    {editing && <ServiceAreaDialog value={editing} staffContext={staffContext} onClose={() => setEditing(null)} onSaved={(saved) => {
      setAreas((current) => current.some((item) => item.id === saved.id) ? current.map((item) => item.id === saved.id ? saved : item) : [...current, saved])
      setSelectedId(saved.id)
      setEditing(null); setError(''); setSuccess(`Service area ${editing.id ? 'updated' : 'created'} successfully.`)
    }} />}
  </div>
}

function ServiceAreaDialog({ value, staffContext, onClose, onSaved }) {
  const [form, setForm] = useState(value)
  const [query, setQuery] = useState(value.address || '')
  const [results, setResults] = useState([])
  const [searching, setSearching] = useState(false)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  const setPoint = async (latitude, longitude, reverse = false) => {
    setForm((current) => ({ ...current, latitude, longitude }))
    if (reverse) {
      const address = await geocodingService.reverse(latitude, longitude).catch(() => '')
      if (address) { setForm((current) => ({ ...current, address })); setQuery(address) }
    }
  }
  const search = async (event) => {
    event.preventDefault()
    if (query.trim().length < 3) return setError('Enter at least 3 characters to search.')
    setSearching(true); setError('')
    try { setResults(await geocodingService.search(query.trim())) }
    catch (e) { setError(e.message) }
    finally { setSearching(false) }
  }
  const currentLocation = () => {
    if (!navigator.geolocation) return setError('Current location is not supported by this browser.')
    navigator.geolocation.getCurrentPosition(
      ({ coords }) => setPoint(coords.latitude, coords.longitude, true),
      () => setError('Location access was denied or unavailable.'),
      { enableHighAccuracy: true, timeout: 10000 },
    )
  }
  const save = async () => {
    const validation = validateArea(form)
    if (validation) return setError(validation)
    setSaving(true); setError('')
    try { onSaved(await serviceAreaRepository.save(staffContext, form)) }
    catch (e) { setError(friendlyError(e)) }
    finally { setSaving(false) }
  }

  return <div className="service-area-backdrop" role="presentation"><div className="service-area-dialog" role="dialog" aria-modal="true" aria-labelledby="service-area-title">
    <div className="service-area-dialog-header"><div><h3 id="service-area-title">{form.id ? 'Edit' : 'Create'} Service Area</h3><p>Choose the authoritative centre point and coverage radius.</p></div><button className="icon-button" onClick={onClose}><X size={20} /></button></div>
    {error && <div className="form-alert error" role="alert">{error}</div>}
    <div className="form-group"><label>Service Area Name</label><input className="input" maxLength={120} value={form.name} onChange={(e) => setForm({ ...form, name: e.target.value })} placeholder="e.g. Terminal 1 Main Service Area" /></div>
    <form className="service-area-search" onSubmit={search}><div className="form-group"><label>Search Address</label><div className="service-area-search-row"><input className="input" value={query} onChange={(e) => setQuery(e.target.value)} placeholder="Search a venue or street address" /><button className="btn btn-outline" disabled={searching}><Search size={16} />{searching ? 'Searching…' : 'Search'}</button><button type="button" className="btn btn-outline" onClick={currentLocation} title="Use current location"><Crosshair size={16} /></button></div></div></form>
    {results.length > 0 && <div className="service-area-results">{results.map((result) => <button key={`${result.latitude}-${result.longitude}`} onClick={() => { setForm({ ...form, ...result }); setQuery(result.address); setResults([]) }}>{result.address}</button>)}</div>}
    <div className="service-area-map"><MapContainer center={[form.latitude, form.longitude]} zoom={14} scrollWheelZoom><MapEditor value={form} onChange={setPoint} /></MapContainer></div>
    <div className="service-area-coordinate-note"><MapPin size={14} /> {Number(form.latitude).toFixed(6)}, {Number(form.longitude).toFixed(6)} · Click the map or drag the marker to adjust.</div>
    <div className="form-group"><label>Selected Address</label><input className="input" value={form.address} onChange={(e) => setForm({ ...form, address: e.target.value })} placeholder="Address saved with this location" /></div>
    <div className="form-group"><label>Coverage Radius: <strong>{Number(form.radius_m).toLocaleString()} m</strong></label><input className="service-area-range" type="range" min="50" max="50000" step="50" value={form.radius_m} onChange={(e) => setForm({ ...form, radius_m: Number(e.target.value) })} /><div className="service-area-range-labels"><span>50 m</span><span>50 km</span></div></div>
    <label className="service-area-active"><input type="checkbox" checked={form.active} onChange={(e) => setForm({ ...form, active: e.target.checked })} /> Make this service area active</label>
    <div className="service-area-dialog-actions"><button className="btn btn-outline" onClick={onClose}>Cancel</button><button className="btn btn-primary" disabled={saving} onClick={save}>{saving ? 'Saving…' : 'Save Service Area'}</button></div>
  </div></div>
}

function validateArea(area) {
  if (area.name.trim().length < 2) return 'Service area name must be at least 2 characters.'
  if (!Number.isFinite(Number(area.latitude)) || Number(area.latitude) < -90 || Number(area.latitude) > 90) return 'Select a valid latitude on the map.'
  if (!Number.isFinite(Number(area.longitude)) || Number(area.longitude) < -180 || Number(area.longitude) > 180) return 'Select a valid longitude on the map.'
  if (!Number.isInteger(Number(area.radius_m)) || Number(area.radius_m) < 1 || Number(area.radius_m) > 50000) return 'Radius must be between 1 and 50,000 metres.'
  return ''
}

function friendlyError(error) {
  const message = String(error?.message || '')
  const lower = message.toLowerCase()
  if (lower.includes('service_areas') && lower.includes('schema cache')) return 'Service Areas are not configured yet. Run the service_areas SQL migration in Supabase.'
  if (lower.includes('row-level security') || lower.includes('permission')) return 'You do not have permission to manage this service area.'
  if (lower.includes('jwt')) return 'Your session has expired. Please sign in again.'
  return message || 'Unable to manage service areas.'
}
