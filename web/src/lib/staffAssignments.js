// Adapt both sources to the existing dashboard without changing its layout.
export function mergeStaffAssignments(assistance, sos, staffId) {
  if (!staffId) return []
  return [
    ...assistance.filter(request => request.assigned_staff_id === staffId)
      .map(request => ({ ...request, request_type: 'assistance', destination: '/requests' })),
    ...sos.filter(request => request.assigned_staff_id === staffId).map(request => ({
      ...request,
      request_type: 'sos',
      request_code: `SOS · ${request.id.slice(0, 8)}`,
      traveler_name: request.traveller?.full_name || 'Traveller',
      request_category: 'emergency',
      location_zone: request.service_area?.name || '',
      created_at: request.triggered_at,
      urgency: request.status === 'resolved' ? 'normal' : 'urgent',
      destination: `/sos?task=${encodeURIComponent(request.id)}`,
    })),
  ]
}
