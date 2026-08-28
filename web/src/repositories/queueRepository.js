import { supabase } from '../lib/supabase'

const lineSelect = '*, queue_numbers(id, number, status, traveler_id, called_at, completed_at)'

function queueNumberCandidates(number, prefix = '') {
  const raw = number.trim().toUpperCase()
  const compact = raw.replace(/[\s-]/g, '')
  const cleanPrefix = prefix.trim().toUpperCase().replace(/[\s-]/g, '')
  const candidates = new Set([raw, compact])
  let numberPart = compact
  let resolvedPrefix = cleanPrefix

  if (cleanPrefix && compact.startsWith(cleanPrefix)) numberPart = compact.slice(cleanPrefix.length)
  if (!cleanPrefix) {
    const match = compact.match(/^([A-Z]+)(\d+)$/)
    if (match) [, resolvedPrefix, numberPart] = match
  }
  if (resolvedPrefix && /^\d+$/.test(numberPart)) {
    const padded = numberPart.padStart(3, '0')
    candidates.add(`${resolvedPrefix}-${padded}`)
    candidates.add(`${resolvedPrefix}${padded}`)
    candidates.add(`${resolvedPrefix}-${numberPart}`)
  }
  return [...candidates].filter(Boolean)
}

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
    const { data, error } = await supabase.functions.invoke('create-queue-line', {
      body: { queueLine: payload },
    })
    if (error) throw await functionError(error, 'Unable to create the queue line.')
    return data.queueLine
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

  async deleteQueueLine(id, institutionId) {
    const { data, error } = await supabase.functions.invoke('delete-queue-line', {
      body: { queueLineId: id, institutionId },
    })
    if (error) {
      let message = error.message
      const response = error.context
      if (response && typeof response.clone === 'function') {
        try {
          const payload = await response.clone().json()
          message = payload?.error || payload?.message || message
        } catch {
          // Keep the SDK error if the function response is not JSON.
        }
      }
      throw new Error(message)
    }
    return data
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
    if (status === 'completed') {
      const { data, error } = await supabase
        .from('queue_numbers')
        .update({ status: 'completed', completed_at: new Date().toISOString() })
        .eq('queue_line_id', queueLineId)
        .eq('number', number.trim())
        .select()
        .single()
      if (error) throw error
      return { number: data, line: null }
    }

    const { data, error } = await supabase.rpc('queue_mark_number_and_call_next', {
      p_queue_line_id: queueLineId,
      p_number: number.trim(),
      p_status: status,
    })
    if (error) throw error
    return data
  },

  async findQueueNumber(institutionId, number, queueLine = null) {
    let query = supabase
      .from('queue_numbers')
      .select('*, queue_lines!inner(id, name, service_area, counter, prefix, current_number, upcoming_number, status)')
      .eq('institution_id', institutionId)
      .in('number', queueNumberCandidates(number, queueLine?.prefix))
      .order('updated_at', { ascending: false })
      .limit(1)
    if (queueLine?.id) query = query.eq('queue_line_id', queueLine.id)
    const { data, error } = await query
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

async function functionError(error, fallback) {
  let message = error.message || fallback
  const response = error.context
  if (response && typeof response.clone === 'function') {
    try {
      const payload = await response.clone().json()
      message = payload?.error || payload?.message || message
    } catch {
      // Keep the SDK error when the response is not JSON.
    }
  }
  return new Error(message)
}
