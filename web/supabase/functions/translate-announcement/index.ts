import { createClient } from 'npm:@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const allowedLanguages = new Set(['ms', 'zh'])
const libreTranslateLanguageCodes: Record<string, string> = {
  ms: 'ms',
  zh: 'zh',
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (request.method !== 'POST') return json({ error: 'Method not allowed.' }, 405)

  try {
    const authorization = request.headers.get('Authorization')
    if (!authorization) return json({ error: 'Authentication is required.' }, 401)

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const configuredUrl = Deno.env.get('LIBRETRANSLATE_URL')
    const libreTranslateApiKey = Deno.env.get('LIBRETRANSLATE_API_KEY')
    if (!configuredUrl) return json({ error: 'Self-hosted LibreTranslate URL is not configured.' }, 503)
    const libreTranslateUrl = configuredUrl.replace(/\/$/, '')

    const supabase = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authorization } },
    })
    const { data: userData, error: userError } = await supabase.auth.getUser()
    if (userError || !userData.user) return json({ error: 'Invalid institution session.' }, 401)

    const { data: institution, error: institutionError } = await supabase
      .from('institutions')
      .select('id')
      .eq('account_user_id', userData.user.id)
      .eq('active', true)
      .limit(1)
      .maybeSingle()
    if (institutionError || !institution) return json({ error: 'Active institution account access is required.' }, 403)

    const body = await request.json()
    const title = typeof body.title === 'string' ? body.title.trim() : ''
    const message = typeof body.message === 'string' ? body.message.trim() : ''
    const targetLanguages = Array.isArray(body.targetLanguages)
      ? [...new Set(body.targetLanguages.filter((code: unknown) => typeof code === 'string' && allowedLanguages.has(code)))]
      : []
    if (!title || !message || targetLanguages.length === 0) return json({ error: 'Title, message, and target languages are required.' }, 400)

    const translations: Record<string, { title: string; message: string }> = {}
    for (const target of targetLanguages) {
      const providerTarget = libreTranslateLanguageCodes[target]
      const response = await fetch(`${libreTranslateUrl}/translate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        signal: AbortSignal.timeout(30000),
        body: JSON.stringify({
          q: [title, message],
          source: 'en',
          target: providerTarget,
          format: 'text',
          ...(libreTranslateApiKey ? { api_key: libreTranslateApiKey } : {}),
        }),
      })
      const result = await response.json()
      if (!response.ok) throw new Error(result?.error || `Translation failed for ${target}.`)

      const translatedText = result.translatedText
      if (!Array.isArray(translatedText) || translatedText.length < 2) {
        throw new Error(`LibreTranslate returned an invalid response for ${target}.`)
      }
      translations[target] = {
        title: String(translatedText[0]),
        message: String(translatedText[1]),
      }
    }

    return json({ translations })
  } catch (error) {
    console.error('translate-announcement failed', error)
    return json({ error: error instanceof Error ? error.message : 'Translation failed.' }, 500)
  }
})

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
