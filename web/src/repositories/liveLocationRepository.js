import { supabase } from '../lib/supabase'

export const liveLocationRepository = {
  async getLiveLocation(sessionId) {
    if (!sessionId) return null
    try {
      const { data, error } = await supabase
        .from('traveler_live_locations')
        .select('*')
        .eq('session_id', sessionId)
        .maybeSingle()

      if (error) {
        console.error('Error fetching live location:', error)
        return null
      }
      return data
    } catch (err) {
      console.error('Unexpected error fetching live location:', err)
      return null
    }
  },

  subscribeToLiveLocation(sessionId, onUpdate, onDelete) {
    if (!sessionId) return () => {}

    const channel = supabase
      .channel(`live_loc_${sessionId}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'traveler_live_locations',
          filter: `session_id=eq.${sessionId}`,
        },
        (payload) => {
          if (payload.eventType === 'DELETE') {
            if (onDelete) onDelete(payload.old)
          } else if (payload.new) {
            if (onUpdate) onUpdate(payload.new)
          }
        }
      )
      .subscribe()

    return () => {
      supabase.removeChannel(channel)
    }
  },

  async deleteLiveLocation(sessionId) {
    if (!sessionId) return
    try {
      const { error } = await supabase
        .from('traveler_live_locations')
        .delete()
        .eq('session_id', sessionId)

      if (error) {
        console.error('Error deleting live location:', error)
      }
    } catch (err) {
      console.error('Unexpected error deleting live location:', err)
    }
  },
}
