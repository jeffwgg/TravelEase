import { supabase } from '../lib/supabase'

// Module 7 data access: cross-module reads (queue, communication, users, SLA)
// used by the analytics dashboards and the report generator.
export const analyticsRepository = {
  async getQueueLines(institutionId) {
    let query = supabase
      .from('queue_lines')
      .select('id, name, prefix, service_area, status')
    if (institutionId) query = query.eq('institution_id', institutionId)
    const { data, error } = await query

    if (error) {
      console.error('Error fetching queue lines:', error)
      return []
    }
    return data
  },

  async getQueueNumbers(institutionId) {
    let query = supabase
      .from('queue_numbers')
      .select('id, queue_line_id, number, status, called_at, completed_at, created_at')
    if (institutionId) query = query.eq('institution_id', institutionId)
    const { data, error } = await query

    if (error) {
      console.error('Error fetching queue numbers:', error)
      return []
    }
    return data
  },

  async getDialogueSessions() {
    const { data, error } = await supabase
      .from('communication_dialogue_sessions')
      .select('id, session_code, target_language, status, created_at, ended_at')

    if (error) {
      console.error('Error fetching dialogue sessions:', error)
      return []
    }
    return data
  },

  async getDialogueMessages() {
    const { data, error } = await supabase
      .from('communication_dialogue_messages')
      .select('id, session_id, sender_role, input_modality, created_at')

    if (error) {
      console.error('Error fetching dialogue messages:', error)
      return []
    }
    return data
  },

  // Aggregate-only user stats (FR-M7-23): SECURITY DEFINER function that
  // returns counts, never personal rows.
  async getUserAnalytics() {
    const { data, error } = await supabase.rpc('get_user_analytics')
    if (error) {
      console.error('Error fetching user analytics:', error)
      return null
    }
    return Array.isArray(data) ? data[0] : data
  },

  async getSlaConfigs(institutionId) {
    const { data, error } = await supabase
      .from('sla_configs')
      .select('*')
      .eq('institution_id', institutionId)

    if (error) {
      console.error('Error fetching SLA configs:', error)
      return []
    }
    return data
  },

  async saveGeneratedReport(payload) {
    const { data, error } = await supabase
      .from('generated_reports')
      .insert(payload)
      .select()
      .single()

    if (error) {
      console.error('Error saving generated report:', error)
      throw error
    }
    return data
  }
}
