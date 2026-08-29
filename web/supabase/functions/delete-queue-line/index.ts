import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (request.method !== 'POST') return json({ error: 'Method not allowed.' }, 405)

  try {
    const authorization = request.headers.get('Authorization')
    if (!authorization) return json({ error: 'Authentication is required.' }, 401)

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authorization } },
    })
    const adminClient = createClient(supabaseUrl, serviceRoleKey)

    const { data: userData, error: userError } = await userClient.auth.getUser()
    if (userError || !userData.user) return json({ error: 'Invalid institution session.' }, 401)

    const body = await request.json()
    const queueLineId = typeof body.queueLineId === 'string' ? body.queueLineId : ''
    const institutionId = typeof body.institutionId === 'string' ? body.institutionId : ''
    if (!queueLineId || !institutionId) return json({ error: 'Queue line and institution are required.' }, 400)

    const { data: institution, error: institutionError } = await adminClient
      .from('institutions')
      .select('id')
      .eq('id', institutionId)
      .eq('account_user_id', userData.user.id)
      .eq('active', true)
      .maybeSingle()
    if (institutionError) throw institutionError
    if (!institution) return json({ error: 'You are not authorized to delete this queue line.' }, 403)

    const { data: line, error: lineError } = await adminClient
      .from('queue_lines')
      .select('id, name, current_number, status')
      .eq('id', queueLineId)
      .eq('institution_id', institutionId)
      .maybeSingle()
    if (lineError) throw lineError
    if (!line) return json({ error: 'Queue line not found.' }, 404)

    const { error: archiveError } = await adminClient
      .from('queue_lines')
      .update({ status: 'closed' })
      .eq('id', queueLineId)
      .eq('institution_id', institutionId)
    if (archiveError) throw archiveError

    const { error: eventError } = await adminClient.from('queue_events').insert({
      institution_id: institutionId,
      queue_line_id: queueLineId,
      event_type: 'updated',
      event_number: line.current_number,
      created_by: userData.user.id,
      details: { soft_deleted: true, previous_status: line.status },
    })
    if (eventError) console.error('Unable to record queue archive event', eventError)

    return json({ archived: true, queueLine: line })
  } catch (error) {
    console.error('delete-queue-line failed', error)
    return json({ error: error instanceof Error ? error.message : 'Unable to delete the queue line.' }, 500)
  }
})

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
