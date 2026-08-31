import { supabase } from '../lib/supabase'

export const announcementRepository = {
  async getAnnouncements(institutionId) {
    const { data, error } = await supabase
      .from('announcements')
      .select('*, venue_zones(id, name, code)')
      .eq('institution_id', institutionId)
      .order('created_at', { ascending: false })

    if (error) throw error
    return data ?? []
  },

  async getZones(institutionId) {
    const { data, error } = await supabase
      .from('venue_zones')
      .select('id, name, code, zone_type, map_x, map_y')
      .eq('institution_id', institutionId)
      .eq('active', true)
      .order('name')

    if (error) throw error
    return data ?? []
  },

  async getAnnouncement(id, institutionId) {
    const { data, error } = await supabase
      .from('announcements')
      .select('*, venue_zones(id, name, code)')
      .eq('id', id)
      .eq('institution_id', institutionId)
      .single()

    if (error) throw error
    return data
  },

  async createAnnouncement(payload) {
    const { data, error } = await supabase
      .from('announcements')
      .insert(payload)
      .select('*, venue_zones(id, name, code)')
      .single()

    if (error) throw error
    return data
  },

  async updateAnnouncement(id, payload) {
    const { data, error } = await supabase
      .from('announcements')
      .update(payload)
      .eq('id', id)
      .select('*, venue_zones(id, name, code)')
      .single()

    if (error) throw error
    return data
  },

  async translateAnnouncement({ title, message, targetLanguages }) {
    const { data, error } = await supabase.functions.invoke('translate-announcement', {
      body: { title, message, targetLanguages },
    })

    if (error) {
      let message = error.message
      const response = error.context
      if (response && typeof response.clone === 'function') {
        try {
          const payload = await response.clone().json()
          message = payload?.error || payload?.message || message
        } catch {
          // Keep the SDK error when the response is not JSON.
        }
      }
      throw new Error(message)
    }
    return data.translations
  },

  async cancelAnnouncement(id) {
    const { data, error } = await supabase
      .from('announcements')
      .update({ status: 'cancelled' })
      .eq('id', id)
      .select()
      .single()

    if (error) throw error
    return data
  },

  subscribeToAnnouncements(institutionId, callback) {
    const channel = supabase
      .channel(`official-announcements:${institutionId}`)
      .on(
        'postgres_changes',
        {
          event: '*',
          schema: 'public',
          table: 'announcements',
          filter: `institution_id=eq.${institutionId}`,
        },
        callback,
      )
      .subscribe()

    return () => supabase.removeChannel(channel)
  },
}
