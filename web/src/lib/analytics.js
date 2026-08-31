// Shared aggregation helpers for Module 7 analytics (FR-M7-*).
// Pure functions: raw Supabase rows in, display models out. No Supabase imports
// here so report generation can reuse the same numbers the dashboards show.

export const ISSUE_TYPE_LABELS = {
  visual: 'No Visual Announcement',
  queue: 'Sound-Only Queue',
  sign: 'No Sign Language Support',
  alert: 'Missing Visual Alert',
  access: 'Inaccessible Area',
  other: 'Other'
}

export const CATEGORY_LABELS = {
  communication: 'Communication',
  location: 'Finding Location',
  checkin: 'Check-in / Boarding',
  luggage: 'Luggage Issue',
  accessibility: 'Accessibility',
  emergency: 'Emergency Info',
  general: 'General Help'
}

export const MODALITY_LABELS = {
  sign_to_text: 'Sign → Text',
  speech_to_text: 'Speech → Text',
  typed_text: 'Typed Text',
  quick_phrase: 'Quick Phrase'
}

export const LANG_LABELS = {
  en: 'English',
  ms: 'Bahasa Melayu',
  zh: 'Chinese',
  ta: 'Tamil',
  unknown: 'Unspecified'
}

export const COMM_PREF_LABELS = {
  in_app_chat: 'In-app Chat',
  sign_language: 'Sign Language',
  text: 'Text',
  voice: 'Voice Call',
  unspecified: 'Unspecified'
}

export const PERIODS = [
  { key: '7d', label: 'Last 7 Days', days: 7 },
  { key: '30d', label: 'Last 30 Days', days: 30 },
  { key: '90d', label: 'This Quarter', days: 90 },
  { key: 'ytd', label: 'Year to Date', days: null }
]

// FR-M7-06: below this sample size percentages are hidden to avoid
// misinterpretation, and a warning is shown instead.
export const LOW_SAMPLE_MIN = 5

export function periodStart(periodKey) {
  const period = PERIODS.find((p) => p.key === periodKey)
  if (!period) return null
  if (period.days == null) {
    const now = new Date()
    return new Date(now.getFullYear(), 0, 1)
  }
  return new Date(Date.now() - period.days * 86400000)
}

export function inPeriod(row, field, start) {
  if (!start) return true
  const t = new Date(row[field]).getTime()
  return t >= start.getTime()
}

export function pct(part, whole) {
  return whole > 0 ? Math.round((part / whole) * 1000) / 10 : 0
}

export function fmtDuration(seconds) {
  if (seconds == null || Number.isNaN(seconds)) return '—'
  const s = Math.round(seconds)
  if (s < 60) return `${s}s`
  const m = Math.floor(s / 60)
  if (m < 60) return `${m} min ${s % 60}s`
  const h = Math.floor(m / 60)
  return `${h} h ${m % 60} min`
}

export function countBy(rows, keyFn) {
  const map = new Map()
  for (const r of rows) {
    const k = keyFn(r)
    if (k == null) continue
    map.set(k, (map.get(k) || 0) + 1)
  }
  return map
}

export function toList(map, labelFn) {
  return [...map.entries()]
    .map(([key, count]) => ({ key, label: labelFn ? labelFn(key) : key, count }))
    .sort((a, b) => b.count - a.count)
}

// FR-M7-08/15: prefer the explicit *_seconds columns; derive from
// acknowledged_at / resolved_at timestamps when they are absent.
export function withDerivedTimes(requests) {
  return requests.map((r) => {
    const out = { ...r }
    if (out.response_time_seconds == null && out.acknowledged_at) {
      out.response_time_seconds = Math.max(0, (new Date(out.acknowledged_at) - new Date(out.created_at)) / 1000)
    }
    if (out.resolution_time_seconds == null && out.resolved_at) {
      out.resolution_time_seconds = Math.max(0, (new Date(out.resolved_at) - new Date(out.created_at)) / 1000)
    }
    return out
  })
}

// FR-M7-08/09/14/15 KPI block for a filtered set of assistance requests.
export function assistanceKpis(requests, sla = { response: 300, resolution: 3600 }) {
  const total = requests.length
  const resolved = requests.filter((r) => r.status === 'resolved' || r.status === 'closed')
  const pending = requests.filter((r) => r.status === 'pending')
  const inProgress = requests.filter((r) => r.status === 'in_progress')
  const cancelled = requests.filter((r) => r.status === 'cancelled')
  const serviceable = total - cancelled.length
  const responseSamples = requests.filter((r) => r.response_time_seconds != null)
  const resolutionSamples = requests.filter((r) => r.resolution_time_seconds != null)
  const ratings = requests.filter((r) => r.user_rating != null)
  const avg = (rows, field) =>
    rows.length ? rows.reduce((s, r) => s + Number(r[field] || 0), 0) / rows.length : null
  const respBreaches = responseSamples.filter((r) => Number(r.response_time_seconds) > sla.response).length
  const resolBreaches = resolutionSamples.filter((r) => Number(r.resolution_time_seconds) > sla.resolution).length
  const byTraveler = countBy(requests, (r) => (r.traveler_name || '').trim() || null)
  const repeaters = [...byTraveler.values()].filter((c) => c > 1).length

  return {
    total,
    resolved: resolved.length,
    inProgress: inProgress.length,
    pending: pending.length,
    cancelled: cancelled.length,
    serviceable,
    responseSampleCount: responseSamples.length,
    resolutionSampleCount: resolutionSamples.length,
    resolutionRatePct: pct(resolved.length, serviceable),
    unresolvedCount: pending.length + inProgress.length,
    unresolvedRatePct: pct(pending.length + inProgress.length, serviceable),
    repeatedRatePct: pct(repeaters, total),
    avgFirstResponseSec: avg(responseSamples, 'response_time_seconds'),
    avgResolutionSec: avg(resolutionSamples, 'resolution_time_seconds'),
    respBreaches,
    resolBreaches,
    respBreachPct: pct(respBreaches, responseSamples.length),
    resolBreachPct: pct(resolBreaches, resolutionSamples.length),
    avgRating: ratings.length ? ratings.reduce((s, r) => s + Number(r.user_rating), 0) / ratings.length : null,
    ratingCount: ratings.length
  }
}

// FR-M7-13: counts per local hour of day (0-23).
export function hourlyTrend(rows, field = 'created_at') {
  const counts = Array(24).fill(0)
  for (const r of rows) {
    const d = new Date(r[field])
    if (!Number.isNaN(d.getTime())) counts[d.getHours()] += 1
  }
  return counts
}

function localDateKey(d) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
}

export function dailyTrend(rows, field, days = 30) {
  const base = new Date()
  base.setHours(0, 0, 0, 0)
  const buckets = new Map()
  for (let i = days - 1; i >= 0; i--) {
    const d = new Date(base.getTime() - i * 86400000)
    buckets.set(localDateKey(d), { key: localDateKey(d), count: 0 })
  }
  for (const r of rows) {
    const d = new Date(r[field])
    if (Number.isNaN(d.getTime())) continue
    const k = localDateKey(d)
    if (buckets.has(k)) buckets.get(k).count += 1
  }
  return [...buckets.values()]
}

export function monthlyTrend(rows, field, months = 6) {
  const now = new Date()
  const buckets = new Map()
  for (let i = months - 1; i >= 0; i--) {
    const d = new Date(now.getFullYear(), now.getMonth() - i, 1)
    const k = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`
    buckets.set(k, { key: k, count: 0 })
  }
  for (const r of rows) {
    const d = new Date(r[field])
    if (Number.isNaN(d.getTime())) continue
    const k = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`
    if (buckets.has(k)) buckets.get(k).count += 1
  }
  return [...buckets.values()]
}

// Spatial + category breakdown per mapped zone (FR-M7-04, FR-M7-19).
export function zoneStats(zones, issues, requests) {
  return zones
    .filter((z) => z.map_x != null && z.map_y != null)
    .map((z) => {
      const zIssues = issues.filter((i) => i.location_zone === z.name)
      const zRequests = requests.filter((r) => r.location_zone === z.name)
      return {
        id: z.id,
        name: z.name,
        code: z.code,
        x: Number(z.map_x),
        y: Number(z.map_y),
        issueCount: zIssues.length,
        requestCount: zRequests.length,
        categories: toList(countBy(zIssues, (i) => i.issue_type), (k) => ISSUE_TYPE_LABELS[k] || k),
        hourly: hourlyTrend(zIssues)
      }
    })
    .sort((a, b) => b.issueCount - a.issueCount)
}

// FR-M7-19: zones that are hotspots for both confirmed barriers AND live
// assistance demand — the "double jeopardy" flag.
export function hotspotFlags(zoneList) {
  const issueVals = zoneList.map((z) => z.issueCount)
  const reqVals = zoneList.map((z) => z.requestCount)
  const median = (arr) => {
    if (!arr.length) return 0
    const s = [...arr].sort((a, b) => a - b)
    const mid = Math.floor(s.length / 2)
    return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2
  }
  const mi = median(issueVals)
  const mr = median(reqVals)
  return zoneList.map((z) => ({
    ...z,
    doubleJeopardy: z.issueCount > mi && z.requestCount > mr && z.issueCount + z.requestCount > 0
  }))
}

export function queueStats(lines, numbers) {
  const median = (arr) => {
    if (!arr.length) return null
    const s = [...arr].sort((a, b) => a - b)
    const mid = Math.floor(s.length / 2)
    return s.length % 2 ? s[mid] : (s[mid - 1] + s[mid]) / 2
  }
  const terminal = numbers.filter((n) => n.status === 'completed' || n.status === 'cancelled')
  const perLine = lines.map((l) => {
    const rows = terminal.filter((n) => n.queue_line_id === l.id)
    const completed = rows.filter((n) => n.status === 'completed' && n.called_at)
    const waits = completed.map((n) => (new Date(n.called_at) - new Date(n.created_at)) / 1000)
    const sorted = [...waits].sort((a, b) => a - b)
    const p95 = sorted.length ? sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * 0.95))] : null
    return {
      id: l.id,
      name: l.name,
      prefix: l.prefix,
      serviceArea: l.service_area,
      total: rows.length,
      completed: completed.length,
      cancelled: rows.length - completed.length,
      abandonmentPct: pct(rows.length - completed.length, rows.length),
      // median is robust to a few stale numbers with multi-hour/day gaps
      medianWaitSec: median(waits),
      p95WaitSec: p95
    }
  })
  const allWaits = terminal
    .filter((n) => n.status === 'completed' && n.called_at)
    .map((n) => (new Date(n.called_at) - new Date(n.created_at)) / 1000)
  return {
    perLine,
    total: terminal.length,
    cancelled: terminal.filter((n) => n.status === 'cancelled').length,
    abandonmentPct: pct(terminal.filter((n) => n.status === 'cancelled').length, terminal.length),
    medianWaitSec: median(allWaits),
    hourly: hourlyTrend(terminal, 'created_at')
  }
}

// FR-M7-22: Module 3 usage analytics.
export function communicationStats(sessions, messages) {
  const completed = sessions.filter((s) => s.ended_at)
  const durations = completed.map((s) => (new Date(s.ended_at) - new Date(s.created_at)) / 1000)
  const travelerMsgs = messages.filter((m) => m.sender_role === 'traveler')
  return {
    total: sessions.length,
    completed: completed.length,
    avgDurationSec: durations.length ? durations.reduce((a, b) => a + b, 0) / durations.length : null,
    targetMix: toList(countBy(sessions, (s) => s.target_language), (k) =>
      k === 'ms' ? 'Bahasa Melayu' : k === 'zh' ? 'Chinese' : k),
    modalityMix: toList(countBy(travelerMsgs, (m) => m.input_modality), (k) => MODALITY_LABELS[k] || k),
    monthly: monthlyTrend(sessions, 'created_at', 6)
  }
}

export function ratingDistribution(requests) {
  const dist = toList(countBy(requests.filter((r) => r.user_rating != null), (r) => Math.round(Number(r.user_rating))))
  return [5, 4, 3, 2, 1].map((star) => ({
    key: String(star),
    label: `${star} star${star > 1 ? 's' : ''}`,
    count: dist.find((d) => d.key === String(star))?.count || 0
  }))
}
