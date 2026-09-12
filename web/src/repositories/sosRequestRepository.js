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
  traveller:user_profiles!sos_requests_traveller_profile_fkey(full_name),
  service_area:service_areas!sos_requests_service_area_id_fkey(name)
`

export const sosRequestRepository = {
  async listForInstitution(institutionId) {
    if (!institutionId) return []
    const { data, error } = await supabase
      .from('sos_requests')
      .select(requestSelect)
      .eq('institution_id', institutionId)
      .order('triggered_at', { ascending: false })
    if (error) throw error
    return data ?? []
  },

  async updateStatus(institutionId, requestId, currentStatus, status) {
    if (!['acknowledged', 'resolved'].includes(status)) {
      throw new Error('Unsupported SOS status update.')
    }
    const validTransition =
      (currentStatus === 'sent' && status === 'acknowledged') ||
      (currentStatus === 'acknowledged' && status === 'resolved')
    if (!validTransition) {
      throw new Error(`Invalid SOS workflow transition from ${currentStatus} to ${status}.`)
    }
    const { data, error } = await supabase
      .from('sos_requests')
      .update({ status })
      .eq('id', requestId)
      .eq('institution_id', institutionId)
      .eq('status', currentStatus)
      .select(requestSelect)
      .single()
    if (error) throw error
    return data
  },

  subscribe(institutionId, callback) {
    const channel = supabase
      .channel(`institution-sos:${institutionId}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'sos_requests',
          filter: `institution_id=eq.${institutionId}`,
        },
        callback,
      )
      .subscribe()
    return () => supabase.removeChannel(channel)
  },
}
