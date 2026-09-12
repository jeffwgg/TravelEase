const endpoint = 'https://nominatim.openstreetmap.org'

export const geocodingService = {
  async search(query) {
    const params = new URLSearchParams({ format: 'jsonv2', q: query, limit: '5' })
    const response = await fetch(`${endpoint}/search?${params}`)
    if (!response.ok) throw new Error('Address search is temporarily unavailable.')
    return (await response.json()).map((item) => ({
      address: item.display_name,
      latitude: Number(item.lat),
      longitude: Number(item.lon),
    }))
  },

  async reverse(latitude, longitude) {
    const params = new URLSearchParams({ format: 'jsonv2', lat: String(latitude), lon: String(longitude) })
    const response = await fetch(`${endpoint}/reverse?${params}`)
    if (!response.ok) return ''
    const data = await response.json()
    return data.display_name || ''
  },
}
