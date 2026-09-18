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

    const supabaseUrl = Deno.env.get('SUPABASE_URL')
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY')
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
    const resendApiKey = Deno.env.get('RESEND_API_KEY')
    const fromEmail = Deno.env.get('SOS_FROM_EMAIL')
    if (!supabaseUrl || !supabaseAnonKey || !serviceRoleKey) {
      return json({ error: 'Supabase function environment is incomplete.' }, 503)
    }
    if (!resendApiKey || !fromEmail) {
      return json({ error: 'SOS email delivery is not configured.' }, 503)
    }

    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authorization } },
    })
    const { data: userData, error: userError } = await userClient.auth.getUser()
    const user = userData.user
    if (userError || !user) return json({ error: 'Invalid traveller session.' }, 401)

    const body = await request.json()
    const contactId = typeof body.contact_id === 'string' ? body.contact_id.trim() : ''
    const triggeredAt = parseTriggeredAt(body.triggered_at)
    const latitude = parseCoordinate(body.latitude, -90, 90)
    const longitude = parseCoordinate(body.longitude, -180, 180)
    if (!contactId || !triggeredAt) {
      return json({ error: 'Contact and triggered time are required.' }, 400)
    }

    const adminClient = createClient(supabaseUrl, serviceRoleKey)
    const { data: contact, error: contactError } = await adminClient
      .from('emergency_contacts')
      .select('id, name, email')
      .eq('id', contactId)
      .eq('user_id', user.id)
      .eq('is_verified', true)
      .limit(1)
      .maybeSingle()
    if (contactError) throw contactError
    if (!contact?.email) {
      return json({ error: 'A verified emergency contact was not found.' }, 404)
    }

    const { data: profile, error: profileError } = await adminClient
      .from('user_profiles')
      .select('full_name')
      .eq('id', user.id)
      .limit(1)
      .maybeSingle()
    if (profileError) throw profileError

    const travellerName = cleanText(
      profile?.full_name ?? user.user_metadata?.full_name ?? 'TravelEase traveller',
    )
    const localTime = new Intl.DateTimeFormat('en-MY', {
      timeZone: 'Asia/Kuala_Lumpur',
      day: 'numeric', month: 'long', year: 'numeric',
      hour: 'numeric', minute: '2-digit', second: '2-digit', hour12: true,
    }).format(triggeredAt) + ' MYT (UTC+8)'
    const location = latitude === null || longitude === null
      ? 'Location unavailable'
      : `${latitude.toFixed(6)}, ${longitude.toFixed(6)}`
    const mapUrl = latitude === null || longitude === null
      ? null
      : `https://www.google.com/maps/search/?api=1&query=${latitude},${longitude}`
    const emergencyMessage = `${travellerName} has triggered an SOS alert through TravelEase and may need urgent assistance. Please contact them as soon as possible to check on their safety and offer help.`
    const message = [
      'TravelEase Emergency Alert',
      '',
      "You are receiving this alert as the traveller's verified emergency contact.",
      '',
      emergencyMessage,
      '',
      `Traveller: ${travellerName}`,
      `Triggered time: ${localTime}`,
      `Current location (recorded when the SOS was triggered): ${location}`,
      ...(mapUrl ? [`View location on Google Maps: ${mapUrl}`] : []),
      '',
      'Please respond directly to the traveller using your usual contact method.',
      '',
      'TravelEase',
    ].join('\n')
    const htmlMessage = `
      <div style="padding:24px;background:#f3f4f6;font-family:Arial,sans-serif;color:#1f2937;line-height:1.6">
        <div style="max-width:600px;margin:auto;padding:28px;background:#fff;border:1px solid #e5e7eb;border-radius:12px">
          <h1 style="margin:0 0 16px;font-size:24px;line-height:1.3;color:#b91c1c">TravelEase Emergency Alert</h1>
          <p>You are receiving this alert as the traveller's verified emergency contact.</p>
          <p>${escapeHtml(emergencyMessage)}</p>
          <div style="margin:24px 0;padding:16px;background:#f9fafb;border:1px solid #e5e7eb;border-radius:8px">
            <p style="margin:0 0 16px"><strong>Traveller</strong><br>${escapeHtml(travellerName)}</p>
            <p style="margin:0 0 16px"><strong>Triggered time</strong><br>${escapeHtml(localTime)}</p>
            <p style="margin:0"><strong>Current location</strong><br>${escapeHtml(location)}<br><span style="font-size:13px;color:#4b5563">Recorded when the SOS was triggered.</span></p>
          </div>
          ${mapUrl ? `<p><a href="${escapeHtml(mapUrl)}" style="color:#b91c1c;font-weight:bold;text-decoration:underline">View location on Google Maps</a></p>` : ''}
          <p>Please respond directly to the traveller using your usual contact method.</p>
          <p style="margin-top:24px;padding-top:16px;border-top:1px solid #e5e7eb;font-size:13px;color:#4b5563">TravelEase</p>
        </div>
      </div>`

    const resendResponse = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${resendApiKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        from: fromEmail,
        to: [contact.email],
        subject: 'TravelEase Emergency Alert',
        text: message,
        html: htmlMessage,
      }),
    })
    const resendBody = await resendResponse.json().catch(() => null)
    if (!resendResponse.ok || typeof resendBody?.id !== 'string') {
      console.error('Resend SOS delivery failed', resendResponse.status, resendBody)
      return json({ error: 'Emergency contact notification failed.' }, 502)
    }

    return json({ success: true, message_id: resendBody.id })
  } catch (error) {
    console.error('send-sos-contact failed', error)
    return json({ error: 'Emergency contact notification failed.' }, 500)
  }
})

function parseTriggeredAt(value: unknown): Date | null {
  if (typeof value !== 'string') return null
  const date = new Date(value)
  return Number.isNaN(date.getTime()) ? null : date
}

function parseCoordinate(value: unknown, minimum: number, maximum: number): number | null {
  if (value === null || value === undefined) return null
  if (typeof value !== 'number' || !Number.isFinite(value)) return null
  return value >= minimum && value <= maximum ? value : null
}

function cleanText(value: unknown): string {
  return String(value).replace(/[\r\n]+/g, ' ').trim() || 'TravelEase traveller'
}

function escapeHtml(value: string): string {
  return value.replace(/[&<>"']/g, (character) => ({
    '&': '&amp;',
    '<': '&lt;',
    '>': '&gt;',
    '"': '&quot;',
    "'": '&#39;',
  })[character]!)
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
