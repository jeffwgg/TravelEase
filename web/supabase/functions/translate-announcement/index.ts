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
const googleTranslateLanguageCodes: Record<string, string> = {
  ms: 'ms',
  zh: 'zh-CN',
}
const googleTranslateEndpoint = 'https://translate.googleapis.com/translate_a/single'

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (request.method !== 'POST') return json({ error: 'Method not allowed.' }, 405)

  try {
    const authorization = request.headers.get('Authorization')
    if (!authorization) return json({ error: 'Authentication is required.' }, 401)

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    // Google is the default provider so the web flow matches the current
    // mobile TranslationService. Set TRANSLATION_PROVIDER=libretranslate to
    // continue using the existing Docker-hosted implementation.
    const translationProvider = (Deno.env.get('TRANSLATION_PROVIDER') || 'google').toLowerCase()
    if (translationProvider !== 'google' && translationProvider !== 'libretranslate') {
      return json({ error: 'TRANSLATION_PROVIDER must be google or libretranslate.' }, 503)
    }
    const configuredUrl = Deno.env.get('LIBRETRANSLATE_URL')
    const libreTranslateApiKey = Deno.env.get('LIBRETRANSLATE_API_KEY')
    if (translationProvider === 'libretranslate' && !configuredUrl) {
      return json({ error: 'Self-hosted LibreTranslate URL is not configured.' }, 503)
    }
    const libreTranslateUrl = configuredUrl?.replace(/\/$/, '')

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
      if (translationProvider === 'google') {
        translations[target] = {
          title: await translateWithGoogle(title, target),
          message: await translateWithGoogle(message, target),
        }
        continue
      }

      const providerTarget = libreTranslateLanguageCodes[target]
      let response: Response
      try {
        response = await fetch(`${libreTranslateUrl!}/translate`, {
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
      } catch {
        throw new Error(
          `Could not reach the self-hosted LibreTranslate service at ${libreTranslateUrl}. The service is offline or its public URL changed; restart it and update the LIBRETRANSLATE_URL secret.`,
        )
      }
      const rawBody = await response.text()
      let result: { translatedText?: unknown; error?: string }
      try {
        result = JSON.parse(rawBody)
      } catch {
        throw new Error(
          `LibreTranslate returned a non-JSON response (HTTP ${response.status}). The service or its public tunnel is unhealthy.`,
        )
      }
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

async function translateWithGoogle(text: string, target: string): Promise<string> {
  const targetLanguage = googleTranslateLanguageCodes[target]
  const url = new URL(googleTranslateEndpoint)
  url.searchParams.set('client', 'gtx')
  url.searchParams.set('sl', 'en')
  url.searchParams.set('tl', targetLanguage)
  url.searchParams.set('dt', 't')
  url.searchParams.set('q', text)

  let response: Response
  try {
    response = await fetch(url, { signal: AbortSignal.timeout(30000) })
  } catch {
    throw new Error('Could not reach Google Translate. Check the internet connection and try again.')
  }
  if (!response.ok) throw new Error(`Google Translate failed for ${target} (HTTP ${response.status}).`)

  const result: unknown = await response.json()
  if (!Array.isArray(result) || !Array.isArray(result[0])) {
    throw new Error(`Google Translate returned an invalid response for ${target}.`)
  }
  const translated = result[0]
    .filter((segment: unknown) => Array.isArray(segment) && typeof segment[0] === 'string')
    .map((segment: unknown[]) => segment[0])
    .join('')
    .trim()
  if (!translated) throw new Error(`Google Translate returned an empty translation for ${target}.`)
  return translated
}
