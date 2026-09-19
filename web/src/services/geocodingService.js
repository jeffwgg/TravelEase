const GOOGLE_MAPS_API_KEY = import.meta.env.VITE_GOOGLE_MAPS_API_KEY
const endpoint = 'https://maps.googleapis.com/maps/api'

function requireKey() {
  if (!GOOGLE_MAPS_API_KEY) {
    throw new Error('Missing VITE_GOOGLE_MAPS_API_KEY. Copy web/.env.example to web/.env and set your Google Maps API key.')
  }
}

export const geocodingService = {
  async search(query) {
    requireKey()
    const params = new URLSearchParams({ address: query, key: GOOGLE_MAPS_API_KEY })
    const response = await fetch(`${endpoint}/geocode/json?${params}`)
    if (!response.ok) throw new Error('Address search is temporarily unavailable.')
    const data = await response.json()
    if (data.status === 'ZERO_RESULTS') return []
    if (data.status !== 'OK') throw new Error('Address search is temporarily unavailable.')
    return data.results.slice(0, 5).map((item) => ({
      address: item.formatted_address,
      latitude: item.geometry.location.lat,
      longitude: item.geometry.location.lng,
    }))
  },

  async reverse(latitude, longitude) {
    requireKey()
    const params = new URLSearchParams({ latlng: `${latitude},${longitude}`, key: GOOGLE_MAPS_API_KEY })
    const response = await fetch(`${endpoint}/geocode/json?${params}`)
    if (!response.ok) return ''
    const data = await response.json()
    return data.results?.[0]?.formatted_address || ''
  },
}
