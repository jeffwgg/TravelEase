import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (request.method !== 'POST') return json({ error: 'Method not allowed.' }, 405)

  let createdLineId: string | null = null
  try {
    const authorization = request.headers.get('Authorization')
    if (!authorization) return json({ error: 'Authentication is required.' }, 401)
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authorization } } })
    const adminClient = createClient(supabaseUrl, serviceRoleKey)
    const { data: userData, error: userError } = await userClient.auth.getUser()
    if (userError || !userData.user) return json({ error: 'Invalid institution session.' }, 401)

    const body = await request.json()
    const input = body.queueLine
    if (!input || typeof input !== 'object') return json({ error: 'Queue-line information is required.' }, 400)
    const institutionId = typeof input.institution_id === 'string' ? input.institution_id : ''
    const { data: institution, error: institutionError } = await adminClient
      .from('institutions').select('id').eq('id', institutionId)
      .eq('account_user_id', userData.user.id).eq('active', true).maybeSingle()
    if (institutionError) throw institutionError
    if (!institution) return json({ error: 'Active institution account access is required.' }, 403)

    const name = String(input.name || '').trim()
    if (!name) return json({ error: 'Queue line name is required.' }, 400)
    const { data: duplicate, error: duplicateError } = await adminClient
      .from('queue_lines')
      .select('id')
      .eq('institution_id', institutionId)
      .ilike('name', name)
      .limit(1)
      .maybeSingle()
    if (duplicateError) throw duplicateError
    if (duplicate) {
      return json({ error: `A queue line named "${name}" already exists for this institution. Choose a different name.` }, 409)
    }

    const linePayload = {
      institution_id: institutionId,
      name: String(input.name || '').trim(),
      service_area: String(input.service_area || '').trim(),
      counter: String(input.counter || '').trim(),
      prefix: String(input.prefix || '').trim().toUpperCase(),
      current_number: String(input.current_number || '').trim().toUpperCase(),
      upcoming_number: String(input.upcoming_number || '').trim().toUpperCase(),
      status: input.status,
      estimated_service_minutes: input.estimated_service_minutes,
      operating_hours: input.operating_hours || null,
      staff_notes: input.staff_notes || null,
      max_tracking_number: resolveMaxTrackingNumber(input.max_tracking_number),
      created_by: userData.user.id,
    }
    const { data: line, error: lineError } = await adminClient.from('queue_lines').insert(linePayload).select().single()
    if (lineError) throw lineError
    createdLineId = line.id

    const { error: numbersError } = await adminClient.from('queue_numbers').insert([
      { queue_line_id: line.id, institution_id: institutionId, number: line.current_number, status: 'called', called_at: new Date().toISOString() },
      { queue_line_id: line.id, institution_id: institutionId, number: line.upcoming_number, status: 'waiting' },
    ])
    if (numbersError) throw numbersError
    await ensureTraceableNumbers(adminClient, line)

    const { error: eventError } = await adminClient.from('queue_events').insert({
      institution_id: institutionId,
      queue_line_id: line.id,
      event_type: 'created',
      event_number: line.current_number,
      created_by: userData.user.id,
    })
    if (eventError) throw eventError
    return json({ queueLine: line }, 201)
  } catch (error) {
    if (createdLineId) {
      const adminClient = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!)
      await adminClient.from('queue_lines').delete().eq('id', createdLineId)
    }
    console.error('create-queue-line failed', error)
    const code = (error as { code?: string }).code
    if (code === '23505') {
      return json({ error: 'A queue line with this name or prefix already exists for your institution. Choose a different name or prefix.' }, 409)
    }
    return json({ error: error instanceof Error ? error.message : 'Unable to create the queue line.' }, 500)
  }
})

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } })
}

const DEFAULT_MAX_TRACKING_NUMBER = 100
const MAX_GENERATED_PER_RUN = 500

function resolveMaxTrackingNumber(value: unknown): number | null {
  const parsed = Number(value)
  if (!Number.isFinite(parsed) || parsed <= 0) return null
  return Math.floor(parsed)
}

function parseQueueNumber(value: string) {
  const match = value.trim().toUpperCase().match(/^([A-Z]*)[-\s]?(\d+)$/)
  if (!match) return null
  return { prefix: match[1], value: parseInt(match[2], 10), width: match[2].length }
}

function formatQueueNumber(info: { prefix: string; value: number; width: number }) {
  const digits = String(info.value).padStart(Math.max(info.width, 3), '0')
  return info.prefix ? `${info.prefix}-${digits}` : digits
}

/**
 * Creates queue_numbers rows for the traceable window ahead of the current
 * number (current+1 .. current+max_tracking_number, default 100) so that
 * travellers can track any number inside the window from day one. When a
 * max_tracking_number is configured it is a hard cap on issued numbers.
 */
async function ensureTraceableNumbers(adminClient: any, line: any) {
  try {
    const current = parseQueueNumber(line.current_number)
    if (!current) return
    const max = Number(line.max_tracking_number) > 0
      ? Number(line.max_tracking_number)
      : DEFAULT_MAX_TRACKING_NUMBER
    const hardCap = Number(line.max_tracking_number) > 0 ? max : null
    const end = hardCap != null
      ? hardCap
      : current.value + Math.min(max, MAX_GENERATED_PER_RUN)
    const { data: existing, error } = await adminClient
      .from('queue_numbers')
      .select('number')
      .eq('queue_line_id', line.id)
    if (error) throw error
    const have = new Set((existing ?? []).map((row: any) => String(row.number).trim().toUpperCase()))
    const rows: any[] = []
    for (let value = current.value + 1; value <= end; value += 1) {
      const formatted = formatQueueNumber({ ...current, value })
      if (have.has(formatted)) continue
      rows.push({
        queue_line_id: line.id,
        institution_id: line.institution_id,
        number: formatted,
        status: 'waiting',
      })
    }
    if (!rows.length) return
    const { error: insertError } = await adminClient.from('queue_numbers').insert(rows)
    if (insertError) throw insertError
  } catch (error) {
    // Traceability backfill is best-effort; the line creation must not fail.
    console.error('ensureTraceableNumbers failed', error)
  }
}
