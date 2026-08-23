import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (request.method !== 'POST') return json({ error: 'Method not allowed.' }, 405)
  try {
    const body = await request.json()
    const query = String(body.query || '').trim().replaceAll(/[,%()]/g, ' ').slice(0, 80)
    if (query.length < 2) return json({ venues: [] })
    const client = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )
    const { data, error } = await client
      .from('institutions')
      .select('id, name, branch')
      .eq('active', true)
      .or(`name.ilike.%${query}%,branch.ilike.%${query}%`)
      .order('name')
      .limit(8)
    if (error) throw error
    return json({ venues: data ?? [] })
  } catch (error) {
    console.error('search-venues failed', error)
    return json({ error: 'Unable to search participating institutions.' }, 500)
  }
})

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
