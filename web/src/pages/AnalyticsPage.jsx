import React, { useEffect, useMemo, useState } from 'react'
import { BarChart3, MapPin, LifeBuoy, Zap, RefreshCw, AlertTriangle, CheckCircle2, Download, FileDown } from 'lucide-react'
import { assistanceRepository } from '../repositories/assistanceRepository'
import { serviceAreaRepository } from '../repositories/serviceAreaRepository'
import { useAuth } from '../context/AuthContext'
import Tabs from '../components/Tabs'
import { KpiCard, HBars, HourBars, LineTrend, ServiceAreaHeatmap, ChartSkeleton } from '../components/charts'
import { downloadCsv, downloadPdf } from '../lib/exporter'
import {
  PERIODS, periodStart, inPeriod, withDerivedTimes, assistanceKpis,
  countBy, toList, hourlyTrend, dailyTrend, serviceAreaStats, hotspotFlags,
  fmtDuration, pct, ISSUE_TYPE_LABELS, LOW_SAMPLE_MIN
} from '../lib/analytics'

const TABS = [
  { key: 'overview', label: 'Overview' },
  { key: 'trends', label: 'Categories & Trends' },
  { key: 'hotspots', label: 'Area Hotspots' }
]

export default function AnalyticsPage() {
  const { staffContext } = useAuth()
  const [period, setPeriod] = useState('30d')
  const [tab, setTab] = useState('overview')
  const [requests, setRequests] = useState([])
  const [issues, setIssues] = useState([])
  const [areas, setAreas] = useState([])
  const [selectedArea, setSelectedArea] = useState(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    loadAnalyticsData()
  }, [staffContext?.institution_id])

  async function loadAnalyticsData() {
    setLoading(true)
    const [requestsData, issuesData, areasData] = await Promise.all([
      assistanceRepository.getAssistanceRequests(),
      assistanceRepository.getAccessibilityIssueReports(),
      staffContext
        ? serviceAreaRepository.list(staffContext).catch(() => [])
        : Promise.resolve([])
    ])
    setRequests(withDerivedTimes(requestsData || []))
    setIssues(issuesData || [])
    setAreas((areasData || []).filter((a) => a.active))
    setLoading(false)
  }

  // FR-M7-07: institution-facing analytics count confirmed issue data and
  // consented assistance data only, scoped to this institution's venue.
  const venueName = staffContext?.institutions?.name
  const scopedRequests = useMemo(
    () => requests.filter((r) => !venueName || r.venue_name === venueName),
    [requests, venueName]
  )
  const scopedIssues = useMemo(
    () => issues.filter((i) => !venueName || i.venue_name === venueName),
    [issues, venueName]
  )

  const start = periodStart(period)
  const periodRequests = useMemo(
    () => scopedRequests.filter((r) => inPeriod(r, 'created_at', start) && r.analytics_consent !== false),
    [scopedRequests, start]
  )
  const periodIssues = useMemo(
    () => scopedIssues.filter((i) => inPeriod(i, 'created_at', start) && i.analytics_consent !== false),
    [scopedIssues, start]
  )

  const kpis = useMemo(() => assistanceKpis(periodRequests), [periodRequests])
  const categoryMix = useMemo(
    () => toList(countBy(periodIssues, (i) => i.issue_type), (k) => ISSUE_TYPE_LABELS[k] || k),
    [periodIssues]
  )
  const areaList = useMemo(() => serviceAreaStats(areas, periodIssues, periodRequests), [areas, periodIssues, periodRequests])
  const hotspots = useMemo(() => hotspotFlags(areaList), [areaList])
  const hours = useMemo(() => hourlyTrend(periodIssues), [periodIssues])
  const daily = useMemo(() => dailyTrend(periodIssues, 'created_at', 30), [periodIssues])
  // FR-M7-20: preferred contact method across assistance requests
  const contactMix = useMemo(
    () => toList(
      countBy(periodRequests, (r) => r.preferred_communication),
      (k) => (k === 'chat' ? 'In-app Chat' : k === 'location' ? 'Staff Comes to Location' : k)
    ),
    [periodRequests]
  )

  const topCategory = categoryMix[0]
  const periodLabel = PERIODS.find((p) => p.key === period)?.label

  // ------------------------------------------------- per-tab export builders
  function exportCurrentTab(format) {
    const base = {
      title: 'Accessibility Analytics Export',
      metaLines: [
        ['Venue', venueName || 'All Venues'],
        ['Period', periodLabel],
        ['Generated', new Date().toISOString()],
        ['Note', 'Confirmed issue reports; assistance data limited to consented rows.']
      ]
    }
    let spec
    if (tab === 'overview') {
      spec = {
        ...base,
        kpis: [
          { label: 'Total confirmed barriers', value: periodIssues.length },
          { label: 'Assistance requests', value: kpis.total },
          { label: 'Avg first response time', value: fmtDuration(kpis.avgFirstResponseSec) },
          { label: 'Resolution rate', value: `${kpis.resolutionRatePct}% (n=${kpis.serviceable})` }
        ],
        tables: [{
          title: 'Service area summary',
          headers: ['Service area', 'Barriers', 'Assistance requests', 'Top category'],
          rows: areaList.map((a) => [a.name, a.issueCount, a.requestCount, a.categories[0]?.label || '—'])
        }]
      }
    } else if (tab === 'trends') {
      spec = {
        ...base,
        kpis: [{ label: 'Confirmed barriers in period', value: periodIssues.length }],
        tables: [
          { title: 'Barrier category distribution', headers: ['Category', 'Count'], rows: categoryMix.map((c) => [c.label, c.count]) },
          { title: 'Barrier reports by hour of day', headers: ['Hour', 'Reports'], rows: hours.map((c, h) => [`${String(h).padStart(2, '0')}:00`, c]) },
          { title: 'Barrier reports by day', headers: ['Date', 'Reports'], rows: daily.map((d) => [d.key, d.count]) },
          { title: 'Preferred contact method', headers: ['Method', 'Requests'], rows: contactMix.map((c) => [c.label, c.count]) }
        ]
      }
    } else {
      spec = {
        ...base,
        kpis: [{ label: 'Double-jeopardy hotspots flagged', value: hotspots.filter((z) => z.doubleJeopardy).length }],
        tables: [{
          title: 'Service area hotspot correlation',
          headers: ['Service area', 'Barriers', 'Assistance requests', 'Top category', 'Priority'],
          rows: hotspots.map((z) => [
            z.name, z.issueCount, z.requestCount, z.categories[0]?.label || '—',
            z.doubleJeopardy ? 'Fix first' : z.issueCount + z.requestCount > 0 ? 'Monitor' : 'Clear'
          ])
        }]
      }
    }
    const filename = `travelease_accessibility_${tab}_${period}_${new Date().toISOString().slice(0, 10)}`
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
          <h2>Accessibility Analytics & Heatmaps</h2>
          <div className="header-subtitle">
            Analyze confirmed accessibility barriers, problem locations, and recurring service gaps across your facility.
          </div>
        </div>
        <div className="header-actions">
          <label className="sr-only" htmlFor="analytics-period">Analytics period</label>
          <select id="analytics-period" className="input filter-select" value={period} onChange={(e) => setPeriod(e.target.value)}>
            {PERIODS.map((p) => (
              <option key={p.key} value={p.key}>{p.label}</option>
            ))}
          </select>
          <button className="btn btn-outline" onClick={loadAnalyticsData}>
            <RefreshCw size={16} /> Refresh Analytics
          </button>
        </div>
      </div>

      <div className="page-body">
        <Tabs tabs={TABS} active={tab} onChange={setTab} actions={tabActions} />

        {tab === 'overview' && (
          <>
            <div className="stats-grid">
              <KpiCard
                loading={loading}
                icon={<BarChart3 size={22} />}
                tone="primary"
                label="Total Confirmed Barriers"
                value={periodIssues.length}
                sub={periodIssues.length ? `n = ${periodIssues.length} confirmed issue reports` : 'No confirmed reports in this period'}
              />
              <KpiCard
                loading={loading}
                icon={<LifeBuoy size={22} />}
                tone="secondary"
                label="Assistance Requests"
                value={kpis.total}
                sub={kpis.total ? `${kpis.pending + kpis.inProgress} active now • n = ${kpis.total}` : 'No assistance requests in this period'}
              />
              <KpiCard
                loading={loading}
                icon={<Zap size={22} />}
                tone="accent"
                label="Avg. First Response Time"
                value={fmtDuration(kpis.avgFirstResponseSec)}
                sub={kpis.responseSampleCount ? `from first staff action • n = ${kpis.responseSampleCount}` : 'No staff responses recorded yet'}
              />
              <KpiCard
                loading={loading}
                icon={<CheckCircle2 size={22} />}
                tone="success"
                label="Resolution Rate"
                value={`${kpis.resolutionRatePct}%`}
                sub={kpis.serviceable ? `requests resolved • n = ${kpis.serviceable}` : 'No completed requests yet'}
              />
            </div>

            <div className="grid-2 section-gap">
              <div className="card">
                <div className="card-header">
                  <h3>Service Area Barrier Heatmap</h3>
                  <span className="badge secondary">{venueName || 'All Venues'}</span>
                </div>
                {loading
                  ? <ChartSkeleton height={240} />
                  : <ServiceAreaHeatmap areas={areaList} selected={selectedArea} onSelect={(a) => setSelectedArea(a)} />}
              </div>

              <div className="card">
                <div className="card-header">
                  <h3>{selectedArea ? `Area Breakdown — ${selectedArea.name}` : 'Area Breakdown'}</h3>
                  {selectedArea && (
                    <button className="btn btn-outline btn-sm" onClick={() => setSelectedArea(null)}>Clear</button>
                  )}
                </div>
                {!selectedArea ? (
                  <div className="chart-placeholder">
                    Select a service area on the heatmap to see its barrier categories, exact sample sizes and time-of-day trend.
                  </div>
                ) : (
                  <div className="chart-groups">
                    <div className="badge-strip">
                      <span className="badge primary">Barriers: {selectedArea.issueCount}</span>
                      <span className="badge secondary">Assistance requests: {selectedArea.requestCount}</span>
                      {selectedArea.issueCount > 0 && selectedArea.issueCount < LOW_SAMPLE_MIN && (
                        <span className="badge emergency" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
                          <AlertTriangle size={12} /> Low sample size (n = {selectedArea.issueCount}) — percentages hidden
                        </span>
                      )}
                    </div>
                    {selectedArea.issueCount === 0 ? (
                      <div className="chart-placeholder">No data available for the selected period.</div>
                    ) : (
                      <>
                        <div className="chart-block">
                          <div className="chart-group-title">Barrier categories</div>
                          <HBars
                            items={selectedArea.categories}
                            total={selectedArea.issueCount}
                            showPct={selectedArea.issueCount >= LOW_SAMPLE_MIN}
                          />
                        </div>
                        <div className="chart-block">
                          <div className="chart-group-title">Time-of-day trend</div>
                          <HourBars counts={selectedArea.hourly} label="Barrier reports by hour of day for this service area" />
                        </div>
                      </>
                    )}
                  </div>
                )}
              </div>
            </div>
          </>
        )}

        {tab === 'trends' && (
          <>
            <div className="grid-2 section-gap">
              <div className="card">
                <div className="card-header">
                  <h3>Barrier Category Distribution</h3>
                  {periodIssues.length > 0 && <span className="badge secondary">n = {periodIssues.length}</span>}
                </div>
                {loading
                  ? <ChartSkeleton />
                  : (
                    <>
                      {topCategory && (
                        <div className="panel-footnote" style={{ marginTop: 0, marginBottom: '12px' }}>
                          Most reported: <strong>{topCategory.label}</strong>
                          {periodIssues.length >= LOW_SAMPLE_MIN
                            ? ` — ${pct(topCategory.count, periodIssues.length)}% of all reports (n = ${periodIssues.length})`
                            : ` (n = ${periodIssues.length})`}
                        </div>
                      )}
                      <HBars items={categoryMix} total={periodIssues.length} showPct={periodIssues.length >= LOW_SAMPLE_MIN} />
                    </>
                  )}
              </div>

              <div className="card">
                <div className="card-header">
                  <h3>Barrier Reports by Time of Day</h3>
                </div>
                {loading
                  ? <ChartSkeleton height={170} />
                  : <HourBars counts={hours} label="Barrier reports by hour of day" />}
              </div>
            </div>

            <div className="grid-2">
              <div className="card">
                <div className="card-header">
                  <h3>Barrier Reports — Daily Trend (last 30 days)</h3>
                </div>
                {loading
                  ? <ChartSkeleton height={150} />
                  : <LineTrend points={daily} height={140} />}
              </div>

              <div className="card">
                <div className="card-header">
                  <h3>Preferred Contact Method</h3>
                  {periodRequests.length > 0 && <span className="badge muted">n = {periodRequests.length}</span>}
                </div>
                {loading
                  ? <ChartSkeleton />
                  : <HBars items={contactMix} total={periodRequests.length} showPct={periodRequests.length >= LOW_SAMPLE_MIN} />}
              </div>
            </div>
          </>
        )}

        {tab === 'hotspots' && (
          <>
            <div className="stats-grid section-gap">
              <KpiCard
                loading={loading}
                icon={<MapPin size={22} />}
                tone="primary"
                label="Double-Jeopardy Hotspots"
                value={hotspots.filter((z) => z.doubleJeopardy).length}
                sub="areas above median on both barriers & demand"
              />
              <KpiCard
                loading={loading}
                icon={<BarChart3 size={22} />}
                tone="secondary"
                label="Service Areas Analysed"
                value={hotspots.filter((z) => z.id !== 'unmapped').length}
                sub="active service areas with coordinates"
              />
              <KpiCard
                loading={loading}
                icon={<CheckCircle2 size={22} />}
                tone="success"
                label="Clear Areas"
                value={hotspots.filter((z) => z.id !== 'unmapped' && z.issueCount + z.requestCount === 0).length}
                sub="no reports in the selected period"
              />
            </div>

            <div className="card">
              <div className="card-header">
                <h3>High-Frequency Problem Areas — Hotspot Correlation</h3>
                <span className="badge muted">Barriers vs live assistance demand</span>
              </div>
              <table className="data-table">
                <thead>
                  <tr>
                    <th>Service Area</th>
                    <th>Confirmed Barriers</th>
                    <th>Assistance Requests</th>
                    <th>Top Category</th>
                    <th>Priority</th>
                  </tr>
                </thead>
                <tbody>
                  {loading ? (
                    <tr><td colSpan={5} className="table-message">Loading reports from Supabase…</td></tr>
                  ) : hotspots.length === 0 ? (
                    <tr><td colSpan={5} className="table-message">No data available for the selected period.</td></tr>
                  ) : (
                    hotspots.map((z) => (
                      <tr
                        key={z.id}
                        tabIndex={0}
                        aria-label={`${z.name}: view breakdown`}
                        onClick={() => { setTab('overview'); setSelectedArea(z) }}
                        onKeyDown={(e) => {
                          if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); setTab('overview'); setSelectedArea(z) }
                        }}
                        style={{ cursor: 'pointer' }}
                      >
                        <td><strong>{z.name}</strong></td>
                        <td>{z.issueCount}</td>
                        <td>{z.requestCount}</td>
                        <td>{z.categories[0]?.label || '—'}</td>
                        <td>
                          {z.doubleJeopardy ? (
                            <span className="badge emergency" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
                              <MapPin size={12} /> Fix first — high barriers & demand
                            </span>
                          ) : z.issueCount + z.requestCount > 0 ? (
                            <span className="badge secondary">Monitor</span>
                          ) : (
                            <span className="badge muted">Clear</span>
                          )}
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
              <div className="panel-footnote">
                "Fix first" flags service areas that are above the median for both confirmed barriers and live
                assistance demand — resolving these improves the most travellers. Click a row to open its breakdown.
                "Unmapped" collects reports without usable coordinates (travellers who didn't share their location).
              </div>
            </div>
          </>
        )}
      </div>
    </div>
  )
}
