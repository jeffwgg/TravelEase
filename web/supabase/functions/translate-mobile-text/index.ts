import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const supportedLanguages = new Set(['en', 'ms', 'zh'])
const maxTextLength = 2000

// This proxy lets authenticated mobile users use the self-hosted service
// without exposing LIBRETRANSLATE_API_KEY in the Flutter application.
Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (request.method !== 'POST') return json({ error: 'Method not allowed.' }, 405)

  try {
    const authorization = request.headers.get('Authorization')
    if (!authorization) return json({ error: 'Authentication is required.' }, 401)

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authorization } },
    })
    const { data: userData, error: userError } = await userClient.auth.getUser()
    if (userError || !userData.user) return json({ error: 'Invalid user session.' }, 401)

    const body = await request.json()
    const text = typeof body.text === 'string' ? body.text.trim() : ''
    const source = typeof body.source === 'string' ? body.source.toLowerCase() : ''
    const target = typeof body.target === 'string' ? body.target.toLowerCase() : ''
    if (!text || !supportedLanguages.has(source) || !supportedLanguages.has(target)) {
      return json({ error: 'Text and supported source/target languages are required.' }, 400)
    }
    if (text.length > maxTextLength) {
      return json({ error: `Text must not exceed ${maxTextLength} characters.` }, 400)
    }
    if (source === target) return json({ translatedText: text })

    const configuredUrl = Deno.env.get('LIBRETRANSLATE_URL')
    const apiKey = Deno.env.get('LIBRETRANSLATE_API_KEY')
    if (!configuredUrl || !apiKey) return json({ error: 'Translation service is not configured.' }, 503)

    let response: Response
    try {
      response = await fetch(`${configuredUrl.replace(/\/$/, '')}/translate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        signal: AbortSignal.timeout(30000),
        body: JSON.stringify({ q: text, source, target, format: 'text', api_key: apiKey }),
      })
    } catch {
      return json({ error: 'Translation service is unavailable.' }, 503)
    }

    const result = await response.json().catch(() => null) as { translatedText?: unknown; error?: unknown } | null
    if (!response.ok) return json({ error: String(result?.error || 'Translation failed.') }, 502)
    const translatedText = typeof result?.translatedText === 'string' ? result.translatedText.trim() : ''
    if (!translatedText) return json({ error: 'Translation service returned an invalid response.' }, 502)
    return json({ translatedText })
  } catch (error) {
    console.error('translate-mobile-text failed', error)
    return json({ error: 'Translation failed.' }, 500)
  }
})

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
