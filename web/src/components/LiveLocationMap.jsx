import React, { useEffect, useState, useRef, useMemo } from 'react'
import { MapContainer, TileLayer, Marker, Circle, useMap } from 'react-leaflet'
import L from 'leaflet'
import 'leaflet/dist/leaflet.css'
import { 
  Navigation, 
  Radio, 
  ExternalLink, 
  MapPin, 
  Crosshair, 
  AlertTriangle,
  Clock,
  ShieldAlert,
  Loader2
} from 'lucide-react'
import { liveLocationRepository } from '../repositories/liveLocationRepository'

// Smoothly pans the map when coordinates update
function MapController({ center, autoCenter, onMapMoved }) {
  const map = useMap()
  const prevCenterRef = useRef(center)

  useEffect(() => {
    if (!center || !center[0] || !center[1]) return
    if (autoCenter) {
      map.flyTo(center, Math.max(map.getZoom(), 16), {
        animate: true,
        duration: 0.8,
      })
    }
    prevCenterRef.current = center
  }, [center, autoCenter, map])

  useEffect(() => {
    const handleDragStart = () => {
      if (onMapMoved) onMapMoved()
    }
    map.on('dragstart', handleDragStart)
    return () => {
      map.off('dragstart', handleDragStart)
    }
  }, [map, onMapMoved])

  return null
}

export default function LiveLocationMap({
  sessionId,
  sessionType = 'assistance',
  initialLat = null,
  initialLng = null,
  travelerName = 'Traveler',
  locationZone = '',
  height = '380px',
  compact = false,
}) {
  const [liveData, setLiveData] = useState(null)
  const [loading, setLoading] = useState(true)
  const [sharingStopped, setSharingStopped] = useState(false)
  const [autoCenter, setAutoCenter] = useState(true)
  const [secondsAgo, setSecondsAgo] = useState(0)

  // Fetch initial location from DB
  useEffect(() => {
    let isMounted = true

    async function fetchInitial() {
      if (!sessionId) {
        setLoading(false)
        return
      }
      setLoading(true)
      const data = await liveLocationRepository.getLiveLocation(sessionId)
      if (isMounted) {
        if (data) {
          setLiveData(data)
          setSharingStopped(false)
        } else if (initialLat && initialLng) {
          // Fallback to trigger-time coordinates
          setLiveData({
            latitude: Number(initialLat),
            longitude: Number(initialLng),
            accuracy_m: null,
            updated_at: null,
          })
        }
        setLoading(false)
      }
    }

    fetchInitial()

    // Subscribe to realtime changes
    const unsubscribe = liveLocationRepository.subscribeToLiveLocation(
      sessionId,
      (newRecord) => {
        if (!isMounted) return
        setLiveData(newRecord)
        setSharingStopped(false)
        setSecondsAgo(0)
      },
      () => {
        if (!isMounted) return
        setSharingStopped(true)
      }
    )

    return () => {
      isMounted = false
      if (unsubscribe) unsubscribe()
    }
  }, [sessionId, initialLat, initialLng])

  // Timer to update "seconds ago" display
  useEffect(() => {
    if (!liveData?.updated_at) return

    const interval = setInterval(() => {
      const updatedTime = new Date(liveData.updated_at).getTime()
      const now = Date.now()
      const diffSec = Math.max(0, Math.floor((now - updatedTime) / 1000))
      setSecondsAgo(diffSec)
    }, 1000)

    return () => clearInterval(interval)
  }, [liveData?.updated_at])

  // Current coordinates
  const lat = liveData?.latitude ?? (initialLat ? Number(initialLat) : null)
  const lng = liveData?.longitude ?? (initialLng ? Number(initialLng) : null)
  const accuracy = liveData?.accuracy_m ?? null
  const hasCoordinates = lat != null && lng != null && !Number.isNaN(lat) && !Number.isNaN(lng)

  const isSos = sessionType === 'sos'
  const isStationary = secondsAgo > 25 && !sharingStopped
  const isActivelyStreaming = !sharingStopped && liveData?.updated_at && secondsAgo <= 25

  // Custom FindMy Pulsing Marker Icon
  const findMyIcon = useMemo(() => {
    const pulseColor = isSos ? 'rgba(239, 68, 68, 0.35)' : 'rgba(0, 122, 255, 0.3)'
    const coreColor = isSos ? '#ef4444' : '#007aff'
    const glowColor = isSos ? 'rgba(239, 68, 68, 0.6)' : 'rgba(0, 122, 255, 0.6)'

    return L.divIcon({
      className: 'findmy-custom-marker',
      html: `
        <div style="position: relative; width: 36px; height: 36px; display: flex; align-items: center; justify-content: center;">
          <div style="
            position: absolute;
            width: 36px;
            height: 36px;
            border-radius: 50%;
            background: ${pulseColor};
            animation: findmy-pulse 2s cubic-bezier(0.24, 0, 0.38, 1) infinite;
          "></div>
          <div style="
            position: relative;
            width: 16px;
            height: 16px;
            border-radius: 50%;
            background: ${coreColor};
            border: 2.5px solid #ffffff;
            box-shadow: 0 0 8px ${glowColor}, 0 2px 4px rgba(0,0,0,0.3);
            z-index: 2;
          "></div>
        </div>
      `,
      iconSize: [36, 36],
      iconAnchor: [18, 18],
    })
  }, [isSos])

  if (loading) {
    return (
      <div style={{
        height,
        width: '100%',
        background: 'var(--surface-variant, #f8fafc)',
        borderRadius: compact ? '8px' : '14px',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        gap: '12px',
        color: 'var(--text-secondary, #64748b)',
        fontSize: '13px'
      }}>
        <Loader2 size={24} className="spin" color="var(--primary, #3b82f6)" />
        <span>Connecting to real-time traveler stream...</span>
      </div>
    )
  }

  if (!hasCoordinates) {
    return (
      <div style={{
        height,
        width: '100%',
        background: 'var(--surface-variant, #f8fafc)',
        borderRadius: compact ? '8px' : '14px',
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        padding: '24px',
        textAlign: 'center',
        border: '1px dashed var(--divider, #cbd5e1)',
        color: 'var(--text-secondary, #64748b)'
      }}>
        <MapPin size={32} color="#94a3b8" style={{ marginBottom: '8px' }} />
        <strong style={{ fontSize: '14px', color: 'var(--text-main, #1e293b)' }}>
          Location Tracking Unavailable
        </strong>
        <p style={{ fontSize: '12px', marginTop: '4px', maxWidth: '320px', lineHeight: 1.5 }}>
          The traveler has not shared live coordinates, or location permission is currently disabled on their device.
        </p>
        {locationZone && (
          <div style={{
            marginTop: '12px',
            padding: '6px 12px',
            background: 'rgba(59, 130, 246, 0.08)',
            borderRadius: '20px',
            fontSize: '12px',
            color: 'var(--primary, #3b82f6)',
            fontWeight: 500
          }}>
            Reported Zone: {locationZone}
          </div>
        )}
      </div>
    )
  }

  const center = [lat, lng]

  return (
    <div style={{
      position: 'relative',
      height,
      width: '100%',
      borderRadius: compact ? '8px' : '14px',
      overflow: 'hidden',
      border: '1px solid var(--card-border, #e2e8f0)',
      boxShadow: '0 4px 20px rgba(0,0,0,0.06)',
      display: 'flex',
      flexDirection: 'column',
      background: '#f8fafc'
    }}>
      {/* CSS Animation Keyframes for FindMy pulse */}
      <style>{`
        @keyframes findmy-pulse {
          0% {
            transform: scale(0.6);
            opacity: 0.9;
          }
          70% {
            transform: scale(1.8);
            opacity: 0;
          }
          100% {
            transform: scale(2.0);
            opacity: 0;
          }
        }
      `}</style>

      {/* Floating Status Bar Overlay (FindMy style) */}
      <div style={{
        position: 'absolute',
        top: '12px',
        left: '12px',
        right: '12px',
        zIndex: 1000,
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        gap: '8px',
        pointerEvents: 'none'
      }}>
        {/* Live Status Pill */}
        <div style={{
          pointerEvents: 'auto',
          background: 'rgba(255, 255, 255, 0.92)',
          backdropFilter: 'blur(10px)',
          WebkitBackdropFilter: 'blur(10px)',
          padding: '6px 12px',
          borderRadius: '30px',
          boxShadow: '0 2px 10px rgba(0,0,0,0.12)',
          display: 'flex',
          alignItems: 'center',
          gap: '8px',
          fontSize: '12px',
          fontWeight: 600,
          border: '1px solid rgba(226, 232, 240, 0.8)'
        }}>
          {isSos ? (
            <span style={{
              display: 'flex',
              alignItems: 'center',
              gap: '5px',
              color: '#dc2626'
            }}>
              <span style={{
                width: '8px',
                height: '8px',
                borderRadius: '50%',
                background: '#dc2626',
                boxShadow: '0 0 6px #dc2626'
              }}></span>
              Emergency Live Tracking
            </span>
          ) : sharingStopped ? (
            <span style={{
              display: 'flex',
              alignItems: 'center',
              gap: '5px',
              color: '#64748b'
            }}>
              <span style={{ width: '8px', height: '8px', borderRadius: '50%', background: '#94a3b8' }}></span>
              Sharing Stopped
            </span>
          ) : isStationary ? (
            <span style={{
              display: 'flex',
              alignItems: 'center',
              gap: '5px',
              color: '#d97706'
            }}>
              <span style={{ width: '8px', height: '8px', borderRadius: '50%', background: '#d97706' }}></span>
              Stationary (Location Unchanged)
            </span>
          ) : (
            <span style={{
              display: 'flex',
              alignItems: 'center',
              gap: '5px',
              color: '#16a34a'
            }}>
              <Radio size={14} color="#16a34a" />
              Live Stream Active
            </span>
          )}

          {/* Time Counter */}
          {liveData?.updated_at && !sharingStopped && (
            <span style={{
              color: '#64748b',
              fontWeight: 400,
              fontSize: '11px',
              borderLeft: '1px solid #e2e8f0',
              paddingLeft: '8px'
            }}>
              {secondsAgo < 5 ? 'Just now' : `${secondsAgo}s ago`}
            </span>
          )}
        </div>

        {/* Map Control Buttons */}
        <div style={{ pointerEvents: 'auto', display: 'flex', gap: '6px' }}>
          <button
            type="button"
            onClick={() => setAutoCenter(true)}
            style={{
              background: autoCenter ? 'var(--primary, #007aff)' : 'rgba(255, 255, 255, 0.92)',
              color: autoCenter ? '#ffffff' : '#334155',
              border: '1px solid rgba(226, 232, 240, 0.8)',
              borderRadius: '30px',
              padding: '6px 12px',
              fontSize: '11px',
              fontWeight: 600,
              cursor: 'pointer',
              display: 'flex',
              alignItems: 'center',
              gap: '5px',
              boxShadow: '0 2px 10px rgba(0,0,0,0.12)',
              backdropFilter: 'blur(8px)',
              transition: 'all 0.15s ease'
            }}
            title="Recenter on traveler"
          >
            <Crosshair size={13} />
            <span>Recenter</span>
          </button>

          <a
            href={`https://www.google.com/maps/search/?api=1&query=${lat},${lng}`}
            target="_blank"
            rel="noopener noreferrer"
            style={{
              background: 'rgba(255, 255, 255, 0.92)',
              color: '#334155',
              border: '1px solid rgba(226, 232, 240, 0.8)',
              borderRadius: '30px',
              padding: '6px 12px',
              fontSize: '11px',
              fontWeight: 600,
              textDecoration: 'none',
              display: 'flex',
              alignItems: 'center',
              gap: '5px',
              boxShadow: '0 2px 10px rgba(0,0,0,0.12)',
              backdropFilter: 'blur(8px)'
            }}
            title="Open in Google Maps"
          >
            <ExternalLink size={13} />
            <span>Open Maps</span>
          </a>
        </div>
      </div>

      {/* Leaflet Map */}
      <div style={{ flex: 1, width: '100%', position: 'relative' }}>
        <MapContainer
          center={center}
          zoom={17}
          scrollWheelZoom
          style={{ height: '100%', width: '100%' }}
        >
          <TileLayer
            attribution='&copy; Google Maps'
            url="https://mt1.google.com/vt/lyrs=m&x={x}&y={y}&z={z}"
            maxZoom={20}
          />

          <MapController
            center={center}
            autoCenter={autoCenter}
            onMapMoved={() => setAutoCenter(false)}
          />

          {/* Accuracy Halo (like Apple FindMy) */}
          {accuracy && accuracy > 0 && (
            <Circle
              center={center}
              radius={Math.min(accuracy, 100)}
              pathOptions={{
                color: isSos ? '#ef4444' : '#007aff',
                fillColor: isSos ? '#ef4444' : '#007aff',
                fillOpacity: 0.08,
                weight: 1,
                dashArray: '4, 4',
              }}
            />
          )}

          {/* FindMy Pulsing Marker */}
          <Marker position={center} icon={findMyIcon} />
        </MapContainer>
      </div>

      {/* Bottom Info Bar */}
      <div style={{
        padding: '10px 16px',
        background: '#ffffff',
        borderTop: '1px solid var(--divider, #e2e8f0)',
        display: 'flex',
        justifyContent: 'space-between',
        alignItems: 'center',
        fontSize: '12px',
        color: 'var(--text-secondary, #64748b)'
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
          <Navigation size={14} color="var(--primary, #007aff)" />
          <span style={{ fontWeight: 600, color: 'var(--text-main, #1e293b)' }}>
            {travelerName}
          </span>
          {locationZone && <span>({locationZone})</span>}
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: '14px', fontSize: '11px', color: '#64748b' }}>
          <span>
            {lat.toFixed(6)}, {lng.toFixed(6)}
          </span>
          {accuracy && (
            <span style={{
              background: '#f1f5f9',
              padding: '2px 6px',
              borderRadius: '4px',
              fontWeight: 500
            }}>
              Precision: ±{Math.round(accuracy)}m
            </span>
          )}
        </div>
      </div>
    </div>
  )
}
