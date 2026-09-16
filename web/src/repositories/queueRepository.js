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

const DEFAULT_MAX_TRACKING_NUMBER = 100
const MAX_GENERATED_PER_RUN = 500

function parseQueueNumber(value) {
  const match = String(value || '').trim().toUpperCase().match(/^([A-Z]*)[-\s]?(\d+)$/)
  if (!match) return null
  return { prefix: match[1], value: parseInt(match[2], 10), width: match[2].length }
}

function formatQueueNumber(info) {
  const digits = String(info.value).padStart(Math.max(info.width, 3), '0')
  return info.prefix ? `${info.prefix}-${digits}` : digits
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
    // Fail fast on duplicates so staff always get the specific message, even
    // before the edge function re-validates both server-side.
    const { data: duplicate, error: duplicateError } = await supabase
      .from('queue_lines')
      .select('name')
      .eq('institution_id', payload.institution_id)
      .neq('status', 'reset')
      .ilike('name', payload.name)
      .limit(1)
      .maybeSingle()
    if (duplicateError) throw duplicateError
    if (duplicate) {
      throw new Error(`A queue line named "${payload.name}" already exists for this institution. Choose a different name.`)
    }

    const { data: duplicatePrefix, error: duplicatePrefixError } = await supabase
      .from('queue_lines')
      .select('prefix')
      .eq('institution_id', payload.institution_id)
      .neq('status', 'reset')
      .ilike('prefix', payload.prefix)
      .limit(1)
      .maybeSingle()
    if (duplicatePrefixError) throw duplicatePrefixError
    if (duplicatePrefix) {
      throw new Error(`A queue line with the prefix "${payload.prefix}" already exists for this institution. Choose a different prefix.`)
    }

    const { data, error } = await supabase.functions.invoke('create-queue-line', {
      body: { queueLine: payload },
    })
    if (error) throw await functionError(error, 'Unable to create the queue line.')
    // await ensureTraceableNumbers(data.queueLine)
    return data.queueLine
  },

  async updateQueueLine(id, payload, userId) {
    const { data: existing, error: existingError } = await supabase
      .from('queue_lines')
      .select('current_number, max_tracking_number')
      .eq('id', id)
      .single()
    if (existingError) throw existingError
    const currentValue = parseQueueNumber(existing.current_number)?.value
    const requestedMaximum = Number(payload.max_tracking_number)
    if (Number.isFinite(requestedMaximum) && currentValue != null && requestedMaximum < currentValue) {
      throw new Error(`Maximum queue number cannot be lower than ${existing.current_number}, which has already been called.`)
    }
    const { data: line, error } = await supabase
      .from('queue_lines')
      .update(payload)
      .eq('id', id)
      .select()
      .single()
    if (error) throw error

    await this.logEvent(line.id, line.current_number, 'updated', {
      status: line.status,
      service_area: line.service_area,
      service_area_id: line.service_area_id,
    })
    // await ensureTraceableNumbers(line)
    return line
  },

  /// Archives the old queue line as reset and starts an independent new line.
  /// The new UUID keeps historical queue numbers unambiguous.
  async resetQueueLineNumbers(queueLineId, userId = null) {
    const { data: line, error: lineError } = await supabase
      .from('queue_lines')
      .select('institution_id, name, prefix, current_number, upcoming_number, max_tracking_number, status, service_area_id, service_area, estimated_service_minutes, operating_hours, staff_notes')
      .eq('id', queueLineId)
      .single()
    if (lineError) throw lineError
    if (['closed', 'reset'].includes(line.status)) {
      throw new Error('This queue line cannot be reset.')
    }
    const parsed = parseQueueNumber(line.current_number)
    if (!parsed) throw new Error('Unable to parse the current queue number for this line.')
    const first = formatQueueNumber({ prefix: parsed.prefix, value: 1, width: parsed.width })
    const second = formatQueueNumber({ prefix: parsed.prefix, value: 2, width: parsed.width })

    const { error: updateError } = await supabase
      .from('queue_lines')
      .update({ status: 'reset' })
      .eq('id', queueLineId)
    if (updateError) throw updateError

    try {
      return await this.createQueueLine({
        institution_id: line.institution_id,
        name: line.name,
        prefix: line.prefix,
        service_area_id: line.service_area_id,
        service_area: line.service_area,
        current_number: first,
        upcoming_number: second,
        status: 'active',
        max_tracking_number: line.max_tracking_number,
        estimated_service_minutes: line.estimated_service_minutes,
        operating_hours: line.operating_hours,
        staff_notes: line.staff_notes,
        created_by: userId,
      })
    } catch (error) {
      // Do not silently leave staff with a reset line and no replacement.
      await supabase.from('queue_lines').update({ status: line.status }).eq('id', queueLineId)
      throw error
    }
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
    await enforceMaximumQueueNumber(queueLineId)
    const { data, error } = await supabase.rpc('queue_call_next', { p_queue_line_id: queueLineId })
    if (error) throw error
    // await ensureTraceableNumbers(data)
    return data
  },

  async notifyNumber(queueLineId, number) {
    const requestedNumber = number.trim()
    await enforceMaximumQueueNumber(queueLineId, requestedNumber)
    // This RPC records a status-neutral event under a security-definer
    // function. Browser clients must not insert directly into queue_events.
    const { data, error } = await supabase.rpc('queue_notify_number', {
      p_queue_line_id: queueLineId,
      p_number: requestedNumber,
    })
    if (error) throw error
    return data
  },

  async logEvent(queueLineId, number, eventType, details = {}) {
    const { error } = await supabase.rpc('queue_log_event', {
      p_queue_line_id: queueLineId,
      p_number: number,
      p_event_type: eventType,
      p_details: details,
    })
    if (error) throw error
  },

  async markNumber(queueLineId, number, status) {
    // Closed lines are read-only: staff may look numbers up but not change
    // them. Migration 006 enforces the same rule in the database itself.
    const { data: line, error: lineError } = await supabase
      .from('queue_lines')
      .select('status')
      .eq('id', queueLineId)
      .maybeSingle()
    if (lineError) throw lineError
    if (line?.status === 'closed') {
      throw new Error('This queue line is closed. Reopen it before updating queue number statuses.')
    }

    if (status === 'completed' || status === 'cancelled') {
      const { data, error } = await supabase
        .from('queue_numbers')
        .update({
          status,
          ...(status === 'completed' ? { completed_at: new Date().toISOString() } : {}),
        })
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
    // if (data?.line) await ensureTraceableNumbers(data.line)
    return data
  },

  async findQueueNumber(institutionId, number, queueLine = null) {
    let query = supabase
      .from('queue_numbers')
      .select('*, queue_lines!inner(id, name, service_area, prefix, current_number, upcoming_number, status)')
      .eq('institution_id', institutionId)
      .neq('queue_lines.status', 'reset')
      .in('number', queueNumberCandidates(number, queueLine?.prefix))
      .order('updated_at', { ascending: false })
      .limit(1)
    if (queueLine?.id) query = query.eq('queue_line_id', queueLine.id)
    const { data, error } = await query
      .maybeSingle()
    if (error) throw error
    if (data) return data

    // Waiting queue numbers are virtual until they are called or claimed by a
    // traveller. This avoids pre-creating up to the maximum in Supabase while
    // keeping valid numbers searchable as Waiting.
    const requested = parseQueueNumber(number)
    if (!requested) return null
    let lines = queueLine ? [queueLine] : await this.getQueueLines(institutionId)
    lines = lines.filter((line) => line.status !== 'reset')
    const line = lines.find((candidate) => {
      const prefix = String(candidate.prefix || '').replace(/[\s-]/g, '').toUpperCase()
      return prefix === requested.prefix && requested.value >= 1 && requested.value <= Number(candidate.max_tracking_number || DEFAULT_MAX_TRACKING_NUMBER)
    })
    if (!line) return null
    return {
      id: `virtual-${line.id}-${requested.value}`,
      queue_line_id: line.id,
      institution_id: institutionId,
      number: formatQueueNumber({ prefix: line.prefix, value: requested.value, width: Math.max(requested.width, 3) }),
      status: 'waiting',
      virtual: true,
      queue_lines: line,
    }
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
      // Keep the SDK error when the function response is not JSON.
    }
  }
  return new Error(message)
}

/**
 * The maximum tracking number is a hard cap on issued queue numbers: no
 * number beyond it may be called or notified. Throws a specific error when
 * the line is exhausted, or when a directly requested number exceeds the cap.
 */
async function enforceMaximumQueueNumber(queueLineId, requestedNumber = null) {
  const { data: line, error } = await supabase
    .from('queue_lines')
    .select('name, upcoming_number, max_tracking_number')
    .eq('id', queueLineId)
    .single()
  if (error) throw error
  const cap = Number(line.max_tracking_number)
  if (!Number.isFinite(cap) || cap <= 0) return

  const capLabel = formatQueueNumber({ prefix: parseQueueNumber(line.upcoming_number)?.prefix ?? '', value: cap, width: 3 })
  if (requestedNumber != null) {
    const requested = parseQueueNumber(requestedNumber)
    if (requested && requested.value > cap) {
      throw new Error(`Queue number ${String(requestedNumber).trim().toUpperCase()} exceeds the maximum queue number (${capLabel}) for "${line.name}".`)
    }
    return
  }
  const upcoming = parseQueueNumber(line.upcoming_number)
  if (upcoming && upcoming.value > cap) {
    throw new Error(`"${line.name}" has reached its maximum queue number (${capLabel}). No further numbers can be called.`)
  }
}

/**
 * Ensures queue_numbers rows exist for the whole traceable window ahead of
 * the currently served number: current+1 .. current+max_tracking_number
 * (default 100 when the line does not define one). Travellers can only track
 * numbers that exist as rows, so this keeps every number inside the window
 * traceable. Best-effort: the triggering action must never fail because of it.
 */
// async function ensureTraceableNumbers(line) {
//   try {
//     if (!line?.id || !line.institution_id) return 0
//     const current = parseQueueNumber(line.current_number)
//     if (!current) return 0
//     const max = Number(line.max_tracking_number) > 0
//       ? Number(line.max_tracking_number)
//       : DEFAULT_MAX_TRACKING_NUMBER
//     // When a maximum queue number is configured it is a hard cap on issued
//     // numbers; otherwise the window slides ahead of the current number.
//     const hardCap = Number(line.max_tracking_number) > 0 ? max : null
//     const end = hardCap != null
//       ? hardCap
//       : current.value + Math.min(max, MAX_GENERATED_PER_RUN)
//     if (end <= current.value) return 0

//     const { data: existing, error } = await supabase
//       .from('queue_numbers')
//       .select('number')
//       .eq('queue_line_id', line.id)
//     if (error) throw error
//     const have = new Set((existing ?? []).map((row) => String(row.number).trim().toUpperCase()))

//     const rows = []
//     for (let value = current.value + 1; value <= end; value += 1) {
//       const formatted = formatQueueNumber({ ...current, value })
//       if (have.has(formatted)) continue
//       rows.push({
//         queue_line_id: line.id,
//         institution_id: line.institution_id,
//         number: formatted,
//         status: 'waiting',
//       })
//     }
//     if (!rows.length) return 0
//     const { error: insertError } = await supabase.from('queue_numbers').insert(rows)
//     if (insertError) throw insertError
//     return rows.length
//   } catch (error) {
//     console.error('ensureTraceableNumbers failed', error)
//     return 0
//   }
// }
