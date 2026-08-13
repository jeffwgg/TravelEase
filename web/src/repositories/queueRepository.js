import { supabase } from '../lib/supabase'

const lineSelect = '*, queue_numbers(id, number, status, traveler_id, called_at, completed_at)'

export const queueRepository = {
  async getQueueLines(institutionId) {
    const { data, error } = await supabase
      .from('queue_lines')
      .select(lineSelect)
      .eq('institution_id', institutionId)
      .order('name')

    if (error) throw error
    return data ?? []
  },

  async createQueueLine(payload) {
    const { data: line, error } = await supabase
      .from('queue_lines')
      .insert(payload)
      .select()
      .single()
    if (error) throw error

    const numbers = [...new Set([payload.current_number, payload.upcoming_number])]
      .map((number) => ({
        queue_line_id: line.id,
        institution_id: line.institution_id,
        number,
        status: number === payload.current_number ? 'serving' : 'waiting',
        called_at: number === payload.current_number ? new Date().toISOString() : null,
      }))
    const { error: numbersError } = await supabase.from('queue_numbers').insert(numbers)
    if (numbersError) throw numbersError

    const { error: eventError } = await supabase.from('queue_events').insert({
      institution_id: line.institution_id,
      queue_line_id: line.id,
      event_type: 'created',
      event_number: line.current_number,
      created_by: payload.created_by,
    })
    if (eventError) throw eventError
    return line
  },

  async updateQueueLine(id, payload, userId) {
    const { data: line, error } = await supabase
      .from('queue_lines')
      .update(payload)
      .eq('id', id)
      .select()
      .single()
    if (error) throw error

    const { error: eventError } = await supabase.from('queue_events').insert({
      institution_id: line.institution_id,
      queue_line_id: line.id,
      event_type: 'updated',
      event_number: line.current_number,
      created_by: userId,
      details: { status: line.status, counter: line.counter, service_area: line.service_area },
    })
    if (eventError) throw eventError
    return line
  },

  async callNext(queueLineId) {
    const { data, error } = await supabase.rpc('queue_call_next', { p_queue_line_id: queueLineId })
    if (error) throw error
    return data
  },

  async notifyNumber(queueLineId, number) {
    const { data, error } = await supabase.rpc('queue_notify_number', {
      p_queue_line_id: queueLineId,
      p_number: number.trim(),
    })
    if (error) throw error
    return data
  },

  async markNumber(queueLineId, number, status) {
    const { data, error } = await supabase.rpc('queue_mark_number_and_call_next', {
      p_queue_line_id: queueLineId,
      p_number: number.trim(),
      p_status: status,
    })
    if (error) throw error
    return data
  },

  async findQueueNumber(institutionId, number) {
    const { data, error } = await supabase
      .from('queue_numbers')
      .select('*, queue_lines!inner(id, name, service_area, counter, current_number, upcoming_number, status)')
      .eq('institution_id', institutionId)
      .eq('number', number.trim().toUpperCase())
      .order('updated_at', { ascending: false })
      .limit(1)
      .maybeSingle()
    if (error) throw error
    return data
  },

  subscribe(institutionId, callback) {
    const channel = supabase
      .channel(`queue-management:${institutionId}`)
      .on('postgres_changes', {
        event: '*', schema: 'public', table: 'queue_lines',
        filter: `institution_id=eq.${institutionId}`,
      }, callback)
      .on('postgres_changes', {
        event: '*', schema: 'public', table: 'queue_numbers',
        filter: `institution_id=eq.${institutionId}`,
      }, callback)
      .subscribe()

    return () => supabase.removeChannel(channel)
  },
}
