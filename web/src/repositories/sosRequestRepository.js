import { supabase } from '../lib/supabase'

const requestSelect = `
  id,
  traveller_id,
  latitude,
  longitude,
  triggered_at,
  status,
  acknowledged_at,
  resolved_at,
  institution_id,
  service_area_id,
  assigned_staff_id,
  assigned_staff:institution_staff!assigned_staff_id(name, contact_number),
  traveller:user_profiles!sos_requests_traveller_profile_fkey(full_name),
  service_area:service_areas!sos_requests_service_area_id_fkey(name)
`

export function availableSosStaff(staff, requests, institutionId) {
  const occupied = new Set(requests.filter((request) => ['assigned', 'en_route'].includes(request.status))
    .map((request) => request.assigned_staff_id))
  return staff.filter((member) => member.institution_id === institutionId && member.role === 'staff'
    && member.active && member.status === 'free' && member.auth_user_id && !occupied.has(member.id))
}

async function withTravellerNames(requests) {
  const ids = requests.map(request => request.id).filter(Boolean)
  if (!ids.length) return requests
  const { data, error } = await supabase.rpc('get_sos_traveller_names', { p_request_ids: ids })
  if (error) throw error
  const names = new Map((data || []).map(row => [row.request_id, row.full_name]))
  return requests.map(request => ({
    ...request,
    traveller: { ...request.traveller, full_name: names.get(request.id) || request.traveller?.full_name || null },
  }))
}

export const sosRequestRepository = {
  async listForInstitution(institutionId, assignedStaffId = null) {
    if (!institutionId) return []
    let query = supabase
      .from('sos_requests')
      .select(requestSelect)
      .eq('institution_id', institutionId)
      .order('triggered_at', { ascending: false })
    if (assignedStaffId) query = query.eq('assigned_staff_id', assignedStaffId)
    const { data, error } = await query
    if (error) throw error
    return withTravellerNames(data ?? [])
  },

  async updateStatus(institutionId, requestId, currentStatus, status, staffId = null) {
    if (!['acknowledged', 'assigned', 'en_route', 'resolved'].includes(status)) {
      throw new Error('Unsupported SOS status update.')
    }
    const validTransition =
      (currentStatus === 'sent' && status === 'acknowledged') ||
      (currentStatus === 'acknowledged' && status === 'assigned') ||
      (currentStatus === 'assigned' && status === 'en_route') ||
      (currentStatus === 'en_route' && status === 'resolved')
    if (!validTransition) {
      throw new Error(`Invalid SOS workflow transition from ${currentStatus} to ${status}.`)
    }
    if (status === 'assigned' && !staffId) throw new Error('Choose an active staff member.')
    const { data, error } = await supabase
      .from('sos_requests')
      .update({ status, ...(status === 'assigned' ? { assigned_staff_id: staffId } : {}) })
      .eq('id', requestId)
      .eq('institution_id', institutionId)
      .eq('status', currentStatus)
      .select(requestSelect)
      .single()
    if (error) throw error

    // Synchronize institution_staff status column
    if (status === 'assigned' && staffId) {
      await supabase.from('institution_staff').update({ status: 'assigned' }).eq('id', staffId)
    } else if (status === 'resolved' && data.assigned_staff_id) {
      const { data: activeAssistance } = await supabase
        .from('assistance_requests')
        .select('id')
        .eq('assigned_staff_id', data.assigned_staff_id)
        .eq('status', 'in_progress')
        .limit(1)

      if (!activeAssistance || activeAssistance.length === 0) {
        await supabase.from('institution_staff').update({ status: 'free' }).eq('id', data.assigned_staff_id)
      }
    }

    return (await withTravellerNames([data]))[0]
  },

  subscribe(institutionId, callback, assignedStaffId = null) {
    const channel = supabase
      .channel(`institution-sos:${institutionId}:${assignedStaffId || 'manager'}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'sos_requests',
          filter: assignedStaffId ? `assigned_staff_id=eq.${assignedStaffId}` : `institution_id=eq.${institutionId}`,
        },
        callback,
      )
      .subscribe()
    return () => supabase.removeChannel(channel)
  },
}
