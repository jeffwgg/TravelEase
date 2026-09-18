import React, { useEffect, useMemo, useState } from 'react'
import {
  ListOrdered, MessageSquareText, RefreshCw, Hourglass, UserX,
  Download, FileDown, Zap, Clock, Star, ThumbsUp, ShieldAlert
} from 'lucide-react'
import { analyticsRepository } from '../repositories/analyticsRepository'
import { assistanceRepository } from '../repositories/assistanceRepository'
import { serviceAreaRepository } from '../repositories/serviceAreaRepository'
import { useAuth } from '../context/AuthContext'
import Tabs from '../components/Tabs'
import { KpiCard, HBars, HourBars, LineTrend, ChartSkeleton } from '../components/charts'
import { downloadCsv, downloadPdf } from '../lib/exporter'
import {
  PERIODS, periodStart, inPeriod, withDerivedTimes, assistanceKpis,
  queueStats, communicationStats, ratingDistribution, assignServiceArea,
  fmtDuration, LOW_SAMPLE_MIN
} from '../lib/analytics'

// Consolidated operational analytics page (formerly Usage Insights + Service
// Performance). Users & adoption analysis lives in the Reports page's "Users"
// report type instead — its numbers are platform-wide and not actionable for
// a single venue manager.
const TABS = [
  { key: 'performance', label: 'Service Performance' },
  { key: 'queue', label: 'Queue Analytics' },
  { key: 'communication', label: 'Communication Usage' }
]

export default function UsageInsightsPage() {
  const { staffContext } = useAuth()
  const [period, setPeriod] = useState('30d')
  const [tab, setTab] = useState('performance')
  const [loading, setLoading] = useState(true)
  const [queueLines, setQueueLines] = useState([])
  const [queueNumbers, setQueueNumbers] = useState([])
  const [sessions, setSessions] = useState([])
  const [messages, setMessages] = useState([])
  const [requests, setRequests] = useState([])
  const [areas, setAreas] = useState([])
  const [slaConfigs, setSlaConfigs] = useState([])

  useEffect(() => {
    loadData()
  }, [staffContext?.institution_id])

  async function loadData() {
    setLoading(true)
    const institutionId = staffContext?.institution_id
    const [lines, numbers, sess, msgs, requestsData, areasData, slaData] = await Promise.all([
      institutionId ? analyticsRepository.getQueueLines(institutionId) : Promise.resolve([]),
      institutionId ? analyticsRepository.getQueueNumbers(institutionId) : Promise.resolve([]),
      analyticsRepository.getDialogueSessions(),
      analyticsRepository.getDialogueMessages(),
      assistanceRepository.getAssistanceRequests(),
      staffContext ? serviceAreaRepository.list(staffContext).catch(() => []) : Promise.resolve([]),
      institutionId ? analyticsRepository.getSlaConfigs(institutionId) : Promise.resolve([])
    ])
    setQueueLines(lines)
    setQueueNumbers(numbers)
    setSessions(sess)
    setMessages(msgs)
    setRequests(withDerivedTimes(requestsData || []))
    setAreas((areasData || []).filter((a) => a.active))
    setSlaConfigs(slaData || [])
    setLoading(false)
  }

  const start = periodStart(period)
  const venueName = staffContext?.institutions?.name
  const venueLabel = venueName || 'All Venues'

  // ------------------------------------------------ service performance
  const periodRequests = useMemo(
    () => requests.filter(
      (r) => (!venueName || r.venue_name === venueName) && inPeriod(r, 'created_at', start) && r.analytics_consent !== false
    ),
    [requests, venueName, start]
  )

  // FR-M7-15: institution-wide default limit first, zone rows are overrides.
  const defaultSla = useMemo(() => {
    const row = slaConfigs.find((s) => s.zone_id == null)
    return {
      responseMinutes: row?.response_limit_minutes ?? 5,
      resolutionMinutes: row?.resolution_limit_minutes ?? 60
    }
  }, [slaConfigs])

  const kpis = useMemo(
    () => assistanceKpis(periodRequests, {
      response: defaultSla.responseMinutes * 60,
      resolution: defaultSla.resolutionMinutes * 60
    }),
    [periodRequests, defaultSla]
  )

  const satisfactionTrend = useMemo(() => {
    const rated = periodRequests.filter((r) => r.user_rating != null)
    const buckets = new Map()
    for (const r of rated) {
      const d = new Date(r.created_at)
      const k = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`
      const cur = buckets.get(k) || { sum: 0, n: 0 }
      cur.sum += Number(r.user_rating)
      cur.n += 1
      buckets.set(k, cur)
    }
    return [...buckets.entries()]
      .sort((a, b) => a[0].localeCompare(b[0]))
      .map(([key, v]) => ({ key, count: Math.round((v.sum / v.n) * 100) / 100 }))
  }, [periodRequests])

  const ratingDist = useMemo(() => ratingDistribution(periodRequests), [periodRequests])

  // FR-M7-10: compare service performance across service areas. Rows are
  // attributed by shared coordinates (circle containment), with a text-match
  // fallback; anything left over is bucketed as "Unmapped".
  const areaComparison = useMemo(() => {
    const buckets = new Map()
    for (const r of periodRequests) {
      const area = assignServiceArea(areas, r)
      const key = area ? area.id : 'unmapped'
      const label = area ? area.name : 'Unmapped'
      if (!buckets.has(key)) buckets.set(key, { name: label, rows: [] })
      buckets.get(key).rows.push(r)
    }
    return [...buckets.values()].map(({ name, rows }) => {
      const k = assistanceKpis(rows, {
        response: defaultSla.responseMinutes * 60,
        resolution: defaultSla.resolutionMinutes * 60
      })
      return { name, ...k }
    }).sort((a, b) => b.total - a.total)
  }, [periodRequests, areas, defaultSla])

  // ------------------------------------------------ queue & communication
  const periodQueue = useMemo(() => queueNumbers.filter((n) => inPeriod(n, 'created_at', start)), [queueNumbers, start])
  const periodSessions = useMemo(() => sessions.filter((s) => inPeriod(s, 'created_at', start)), [sessions, start])
  const periodSessionIds = useMemo(() => new Set(periodSessions.map((s) => s.id)), [periodSessions])
  const periodMessages = useMemo(() => messages.filter((m) => periodSessionIds.has(m.session_id)), [messages, periodSessionIds])

  const queue = useMemo(() => queueStats(queueLines, periodQueue), [queueLines, periodQueue])
  const comm = useMemo(() => communicationStats(periodSessions, periodMessages), [periodSessions, periodMessages])

  const periodLabel = PERIODS.find((p) => p.key === period)?.label

  // ------------------------------------------------- per-tab export builders
  function exportCurrentTab(format) {
    const base = {
      title: 'Service Analytics Export',
      metaLines: [
        ['Venue', venueLabel],
        ['Period', periodLabel],
        ['Generated', new Date().toISOString()]
      ]
    }
    let spec
    if (tab === 'performance') {
      spec = {
        ...base,
        title: 'Service Performance Export',
        metaLines: [...base.metaLines, ['Note', 'Assistance data limited to consented rows. SLA limits: ' + defaultSla.responseMinutes + ' min response / ' + defaultSla.resolutionMinutes + ' min resolution.']],
        kpis: [
          { label: 'Avg first response time', value: fmtDuration(kpis.avgFirstResponseSec) },
          { label: 'Avg resolution time', value: fmtDuration(kpis.avgResolutionSec) },
          { label: 'User satisfaction', value: kpis.avgRating != null ? `${kpis.avgRating.toFixed(2)} / 5 (n=${kpis.ratingCount})` : '—' },
          { label: 'Resolution rate', value: `${kpis.resolutionRatePct}% (n=${kpis.serviceable})` },
          { label: 'Response SLA breaches', value: `${kpis.respBreaches} (${kpis.respBreachPct}%)` },
          { label: 'Resolution SLA breaches', value: `${kpis.resolBreaches} (${kpis.resolBreachPct}%)` }
        ],
        tables: [{
          title: 'Service area performance comparison',
          headers: ['Service area', 'Requests', 'Avg first response', 'Avg resolution', 'Avg rating', 'Ratings (n)'],
          rows: areaComparison.map((z) => [
            z.name, z.total, fmtDuration(z.avgFirstResponseSec), fmtDuration(z.avgResolutionSec),
            z.avgRating != null ? z.avgRating.toFixed(2) : '—', z.ratingCount
          ])
        }]
      }
    } else if (tab === 'queue') {
      spec = {
        ...base,
        title: 'Queue Service Analytics Export',
        metaLines: [...base.metaLines, ['Note', 'Aggregate counts only — no personal data.']],
        kpis: [
          { label: 'Queue numbers issued', value: queue.total },
          { label: 'Completed', value: queue.completed },
          { label: 'Median wait before call', value: fmtDuration(queue.medianWaitSec) },
          { label: 'Abandonment rate', value: `${queue.abandonmentPct}% (${queue.cancelled})` }
        ],
        tables: [
          {
            title: 'Queue line performance',
            headers: ['Line', 'Issued', 'Completed', 'Median wait', 'P95 wait', 'Abandoned'],
            rows: queue.perLine.map((l) => [l.name, l.total, l.completed, fmtDuration(l.medianWaitSec), fmtDuration(l.p95WaitSec), `${l.cancelled} (${l.abandonmentPct}%)`])
          },
          { title: 'Queue arrivals by hour of day', headers: ['Hour', 'Arrivals'], rows: queue.hourly.map((c, h) => [`${String(h).padStart(2, '0')}:00`, c]) }
        ]
      }
    } else {
      spec = {
        ...base,
        title: 'Accessible Communication Usage Export',
        metaLines: [...base.metaLines, ['Note', 'Aggregate counts only — no personal data.']],
        kpis: [
          { label: 'Dialogue sessions', value: comm.total },
          { label: 'Completed sessions', value: comm.completed },
          { label: 'Avg session duration', value: fmtDuration(comm.avgDurationSec) },
          { label: 'Top input modality', value: comm.modalityMix[0]?.label || '—' }
        ],
        tables: [
          { title: 'Traveller input modality mix', headers: ['Modality', 'Messages'], rows: comm.modalityMix.map((s) => [s.label, s.count]) },
          { title: 'Translation direction (EN → ?)', headers: ['Target language', 'Sessions'], rows: comm.targetMix.map((s) => [s.label, s.count]) },
          { title: 'Sessions per month', headers: ['Month', 'Sessions'], rows: comm.monthly.map((s) => [s.key, s.count]) }
        ]
      }
    }
    const filename = `travelease_analytics_${tab}_${period}_${new Date().toISOString().slice(0, 10)}`
    if (format === 'pdf') downloadPdf(`${filename}.pdf`, spec)
    else downloadCsv(`${filename}.csv`, spec)
  }

  const tabActions = (
    <>
      <button className="btn btn-outline btn-sm" onClick={() => exportCurrentTab('csv')}>
        <Download size={14} /> Export CSV
      </button>
      <button className="btn btn-outline btn-sm" onClick={() => exportCurrentTab('pdf')}>
        <FileDown size={14} /> Export PDF
      </button>
    </>
  )

  return (
    <div>
      <div className="page-header">
        <div>
          <h2>Service Analytics</h2>
          <div className="header-subtitle">
            Operational analytics across assistance service (SLA &amp; satisfaction), queue service
            and accessible communication usage.
          </div>
        </div>
        <div className="header-actions">
          <label className="sr-only" htmlFor="analytics-period">Analytics period</label>
          <select id="analytics-period" className="input filter-select" value={period} onChange={(e) => setPeriod(e.target.value)}>
            {PERIODS.map((p) => (
              <option key={p.key} value={p.key}>{p.label}</option>
            ))}
          </select>
          <button className="btn btn-outline" onClick={loadData}>
            <RefreshCw size={16} /> Refresh
          </button>
        </div>
      </div>

      <div className="page-body">
        <Tabs tabs={TABS} active={tab} onChange={setTab} actions={tabActions} />

        {/* ----------------------------------------------- service performance */}
        {tab === 'performance' && (
          <>
            <div className="stats-grid">
              <KpiCard
                loading={loading}
                icon={<Zap size={22} />}
                tone="primary"
                label="Avg. First Response Time"
                value={fmtDuration(kpis.avgFirstResponseSec)}
                sub={kpis.responseSampleCount ? `n = ${kpis.responseSampleCount}` : 'No responses recorded yet'}
              />
              <KpiCard
                loading={loading}
                icon={<Clock size={22} />}
                tone="accent"
                label="Avg. Resolution Time"
                value={fmtDuration(kpis.avgResolutionSec)}
                sub={kpis.resolutionSampleCount ? `n = ${kpis.resolutionSampleCount}` : 'No resolutions recorded yet'}
              />
              <KpiCard
                loading={loading}
                icon={<Star size={22} />}
                tone="secondary"
                label="User Satisfaction"
                value={kpis.avgRating != null ? `${kpis.avgRating.toFixed(2)} / 5` : '—'}
                sub={kpis.ratingCount ? `based on ${kpis.ratingCount} ratings` : 'No ratings yet'}
              />
              <KpiCard
                loading={loading}
                icon={<ThumbsUp size={22} />}
                tone="success"
                label="Resolution Rate"
                value={`${kpis.resolutionRatePct}%`}
                sub={kpis.serviceable ? `unresolved: ${kpis.unresolvedRatePct}% • repeated: ${kpis.repeatedRatePct}% • n = ${kpis.serviceable}` : 'No completed requests yet'}
              />
            </div>

            <div className="grid-2 section-gap">
              <div className="card">
                <div className="card-header">
                  <h3>SLA Compliance</h3>
                  <span className="badge secondary">
                    Limits: {defaultSla.responseMinutes} min response / {defaultSla.resolutionMinutes} min resolution
                  </span>
                </div>
                {loading ? (
                  <ChartSkeleton height={140} />
                ) : (
                  <>
                    <div className="breach-grid">
                      <div className="breach-tile danger">
                        <div className="breach-tile-label">
                          <ShieldAlert size={14} color="#ef4444" /> Response SLA breaches
                        </div>
                        <div className="breach-tile-value">
                          {kpis.respBreaches}
                          {kpis.responseSampleCount > 0 && <small> of {kpis.responseSampleCount}</small>}
                        </div>
                        <div className="breach-tile-note">
                          {kpis.responseSampleCount > 0
                            ? `${kpis.respBreachPct}% exceeded the ${defaultSla.responseMinutes}-minute limit`
                            : 'No responses sampled in this period'}
                        </div>
                      </div>
                      <div className="breach-tile warn">
                        <div className="breach-tile-label">
                          <ShieldAlert size={14} color="#f59e0b" /> Resolution SLA breaches
                        </div>
                        <div className="breach-tile-value">
                          {kpis.resolBreaches}
                          {kpis.resolutionSampleCount > 0 && <small> of {kpis.resolutionSampleCount}</small>}
                        </div>
                        <div className="breach-tile-note">
                          {kpis.resolutionSampleCount > 0
                            ? `${kpis.resolBreachPct}% exceeded the ${defaultSla.resolutionMinutes}-minute limit`
                            : 'No resolutions sampled in this period'}
                        </div>
                      </div>
                    </div>
                    <div className="panel-footnote">
                      Total assistance requests exceeding the institution's predefined response or resolution limits.
                    </div>
                  </>
                )}
              </div>

              <div className="card">
                <div className="card-header">
                  <h3>Satisfaction Rating Distribution</h3>
                  {kpis.ratingCount > 0 && <span className="badge secondary">n = {kpis.ratingCount}</span>}
                </div>
                {loading
                  ? <ChartSkeleton />
                  : <HBars items={ratingDist} total={kpis.ratingCount} color="#d97706" showPct={kpis.ratingCount >= LOW_SAMPLE_MIN} />}
              </div>
            </div>

            <div className="card section-gap">
              <div className="card-header">
                <h3>Satisfaction Trend</h3>
                <span className="badge muted">unresolved {kpis.unresolvedCount} ({kpis.unresolvedRatePct}%) • cancelled {kpis.cancelled} • repeated {kpis.repeatedRatePct}%</span>
              </div>
              {loading ? (
                <ChartSkeleton height={150} />
              ) : satisfactionTrend.length < 2 ? (
                <div className="chart-placeholder">Not enough rated months to draw a trend yet.</div>
              ) : (
                <LineTrend points={satisfactionTrend} color="#8b5cf6" suffix=" stars" />
              )}
            </div>

            <div className="card">
              <div className="card-header">
                <h3>Service Area Performance Comparison</h3>
                <span className="badge muted">{venueLabel}</span>
              </div>
              <table className="data-table">
                <thead>
                  <tr>
                    <th>Service Area</th>
                    <th>Requests</th>
                    <th>Avg. First Response</th>
                    <th>Avg. Resolution</th>
                    <th>Avg. Rating</th>
                    <th>Ratings (n)</th>
                  </tr>
                </thead>
                <tbody>
                  {loading ? (
                    <tr><td colSpan={6} className="table-message">Loading…</td></tr>
                  ) : areaComparison.length === 0 ? (
                    <tr><td colSpan={6} className="table-message">No data available for the selected period.</td></tr>
                  ) : (
                    areaComparison.map((z) => (
                      <tr key={z.name}>
                        <td><strong>{z.name}</strong></td>
                        <td>{z.total}</td>
                        <td>{fmtDuration(z.avgFirstResponseSec)}</td>
                        <td>{fmtDuration(z.avgResolutionSec)}</td>
                        <td>
                          {z.avgRating != null ? (
                            <span className="badge success" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
                              <Star size={12} fill="currentColor" /> {z.avgRating.toFixed(2)}
                            </span>
                          ) : '—'}
                        </td>
                        <td>{z.ratingCount}</td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </>
        )}

        {/* ------------------------------------------------- queue analytics */}
        {tab === 'queue' && (
          <div className="card">
            <div className="card-header">
              <h3><ListOrdered size={18} /> Queue Service Analytics</h3>
              <span className="badge muted">{venueLabel}</span>
            </div>
            <div className="stats-grid">
              <KpiCard
                loading={loading}
                icon={<ListOrdered size={22} />}
                tone="primary"
                label="Queue Numbers Issued"
                value={queue.total}
                sub={queue.total ? `${queue.completed} completed • n = ${queue.total}` : 'No numbers issued in this period'}
              />
              <KpiCard
                loading={loading}
                icon={<Hourglass size={22} />}
                tone="accent"
                label="Median Wait Before Call"
                value={fmtDuration(queue.medianWaitSec)}
                sub="issued → called"
              />
              <KpiCard
                loading={loading}
                icon={<UserX size={22} />}
                tone="secondary"
                label="Abandonment Rate"
                value={`${queue.abandonmentPct}%`}
                sub={`${queue.cancelled} cancelled without service`}
              />
            </div>
            <div className="grid-2">
              <div className="chart-block">
                <div className="chart-group-title">Queue arrivals by time of day</div>
                {loading ? <ChartSkeleton height={170} /> : <HourBars counts={queue.hourly} color="#8b5cf6" label="Queue arrivals by hour of day" />}
              </div>
              <table className="data-table">
                <thead>
                  <tr>
                    <th>Queue Line</th>
                    <th>Issued</th>
                    <th>Completed</th>
                    <th>Median Wait</th>
                    <th>Abandonment</th>
                  </tr>
                </thead>
                <tbody>
                  {loading ? (
                    <tr><td colSpan={5} className="table-message">Loading…</td></tr>
                  ) : queue.perLine.length === 0 ? (
                    <tr><td colSpan={5} className="table-message">No data available for the selected period.</td></tr>
                  ) : (
                    queue.perLine.map((l) => (
                      <tr key={l.id}>
                        <td><strong>{l.name}</strong></td>
                        <td>{l.total}</td>
                        <td>{l.completed}</td>
                        <td>{fmtDuration(l.medianWaitSec)}</td>
                        <td>{l.abandonmentPct}% ({l.cancelled})</td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </div>
        )}

        {/* -------------------------------------------- communication usage */}
        {tab === 'communication' && (
          <div className="card">
            <div className="card-header">
              <h3><MessageSquareText size={18} /> Accessible Communication Usage</h3>
              <span className="badge muted">Two-way traveller dialogue</span>
            </div>
            <div className="stats-grid">
              <KpiCard
                loading={loading}
                icon={<MessageSquareText size={22} />}
                tone="primary"
                label="Dialogue Sessions"
                value={comm.total}
                sub={comm.total ? `n = ${comm.total}` : 'No sessions in this period'}
              />
              <KpiCard
                loading={loading}
                icon={<Hourglass size={22} />}
                tone="accent"
                label="Avg. Session Duration"
                value={fmtDuration(comm.avgDurationSec)}
                sub={`${comm.completed} completed`}
              />
            </div>
            <div className="grid-2 section-gap">
              <div className="chart-block">
                <div className="chart-group-title">Traveller input modality mix</div>
                {loading
                  ? <ChartSkeleton />
                  : <HBars items={comm.modalityMix} showPct={comm.modalityMix.reduce((s, i) => s + i.count, 0) >= LOW_SAMPLE_MIN} />}
              </div>
              <div className="chart-block">
                <div className="chart-group-title">Translation direction (EN → ?)</div>
                {loading
                  ? <ChartSkeleton />
                  : <HBars items={comm.targetMix} total={comm.total} color="#10b981" />}
              </div>
            </div>
            <div className="chart-block">
              <div className="chart-group-title">Sessions per month</div>
              {loading ? <ChartSkeleton height={140} /> : <LineTrend points={comm.monthly} color="#10b981" />}
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
