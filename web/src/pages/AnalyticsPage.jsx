import React, { useEffect, useMemo, useState } from 'react'
import { BarChart3, MapPin, LifeBuoy, Zap, RefreshCw, AlertTriangle, CheckCircle2, Download, FileDown } from 'lucide-react'
import { assistanceRepository } from '../repositories/assistanceRepository'
import { announcementRepository } from '../repositories/announcementRepository'
import { useAuth } from '../context/AuthContext'
import Tabs from '../components/Tabs'
import { KpiCard, HBars, HourBars, LineTrend, ZoneHeatmap } from '../components/charts'
import { downloadCsv, downloadPdf } from '../lib/exporter'
import {
  PERIODS, periodStart, inPeriod, withDerivedTimes, assistanceKpis,
  countBy, toList, hourlyTrend, dailyTrend, zoneStats, hotspotFlags,
  fmtDuration, pct, ISSUE_TYPE_LABELS, LOW_SAMPLE_MIN
} from '../lib/analytics'

const TABS = [
  { key: 'overview', label: 'Overview' },
  { key: 'trends', label: 'Categories & Trends' },
  { key: 'hotspots', label: 'Zone Hotspots' }
]

export default function AnalyticsPage() {
  const { staffContext } = useAuth()
  const [period, setPeriod] = useState('30d')
  const [tab, setTab] = useState('overview')
  const [requests, setRequests] = useState([])
  const [issues, setIssues] = useState([])
  const [zones, setZones] = useState([])
  const [selectedZone, setSelectedZone] = useState(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    loadAnalyticsData()
  }, [staffContext?.institution_id])

  async function loadAnalyticsData() {
    setLoading(true)
    const institutionId = staffContext?.institution_id
    const [requestsData, issuesData, zonesData] = await Promise.all([
      assistanceRepository.getAssistanceRequests(),
      assistanceRepository.getAccessibilityIssueReports(),
      institutionId
        ? announcementRepository.getZones(institutionId)
        : Promise.resolve([])
    ])
    setRequests(withDerivedTimes(requestsData || []))
    setIssues(issuesData || [])
    setZones(zonesData || [])
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
    () => scopedIssues.filter((i) => inPeriod(i, 'created_at', start)),
    [scopedIssues, start]
  )

  const kpis = useMemo(() => assistanceKpis(periodRequests), [periodRequests])
  const categoryMix = useMemo(
    () => toList(countBy(periodIssues, (i) => i.issue_type), (k) => ISSUE_TYPE_LABELS[k] || k),
    [periodIssues]
  )
  const zoneList = useMemo(() => zoneStats(zones, periodIssues, periodRequests), [zones, periodIssues, periodRequests])
  const hotspots = useMemo(() => hotspotFlags(zoneList), [zoneList])
  const hours = useMemo(() => hourlyTrend(periodIssues), [periodIssues])
  const daily = useMemo(() => dailyTrend(periodIssues, 'created_at', 30), [periodIssues])

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
        ['Note', 'Confirmed issue reports; assistance data limited to consented rows (FR-M7-07).']
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
          title: 'Zone summary',
          headers: ['Zone', 'Barriers', 'Assistance requests', 'Top category'],
          rows: zoneList.map((z) => [z.name, z.issueCount, z.requestCount, z.categories[0]?.label || '—'])
        }]
      }
    } else if (tab === 'trends') {
      spec = {
        ...base,
        kpis: [{ label: 'Confirmed barriers in period', value: periodIssues.length }],
        tables: [
          { title: 'Barrier category distribution', headers: ['Category', 'Count'], rows: categoryMix.map((c) => [c.label, c.count]) },
          { title: 'Barrier reports by hour of day', headers: ['Hour', 'Reports'], rows: hours.map((c, h) => [`${String(h).padStart(2, '0')}:00`, c]) },
          { title: 'Barrier reports by day', headers: ['Date', 'Reports'], rows: daily.map((d) => [d.key, d.count]) }
        ]
      }
    } else {
      spec = {
        ...base,
        kpis: [{ label: 'Double-jeopardy hotspots flagged', value: hotspots.filter((z) => z.doubleJeopardy).length }],
        tables: [{
          title: 'Zone hotspot correlation',
          headers: ['Zone', 'Barriers', 'Assistance requests', 'Top category', 'Priority'],
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
        <div style={{ display: 'flex', gap: '8px' }}>
          <select className="input" style={{ width: '160px' }} value={period} onChange={(e) => setPeriod(e.target.value)}>
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
                icon={<BarChart3 size={22} />}
                tone="primary"
                label="Total Confirmed Barriers"
                value={loading ? '…' : periodIssues.length}
                sub={`n = ${periodIssues.length} confirmed issue reports`}
              />
              <KpiCard
                icon={<LifeBuoy size={22} />}
                tone="secondary"
                label="Assistance Requests"
                value={loading ? '…' : kpis.total}
                sub={`${kpis.pending + kpis.inProgress} active now • n = ${kpis.total}`}
              />
              <KpiCard
                icon={<Zap size={22} />}
                tone="accent"
                label="Avg. First Response Time"
                value={loading ? '…' : fmtDuration(kpis.avgFirstResponseSec)}
                sub={`from first staff action • n = ${kpis.responseSampleCount}`}
              />
              <KpiCard
                icon={<CheckCircle2 size={22} />}
                tone="success"
                label="Resolution Rate"
                value={loading ? '…' : `${kpis.resolutionRatePct}%`}
                sub={`requests resolved • n = ${kpis.serviceable}`}
              />
            </div>

            <div className="grid-2" style={{ marginBottom: '24px' }}>
              <div className="card">
                <div className="card-header">
                  <h3>Facility Barrier Heatmap</h3>
                  <span className="badge secondary">{venueName || 'All Venues'}</span>
                </div>
                {loading
                  ? <div className="chart-placeholder">Loading heatmap data…</div>
                  : <ZoneHeatmap zones={zoneList} selected={selectedZone} onSelect={(z) => setSelectedZone(z)} />}
              </div>

              <div className="card">
                <div className="card-header">
                  <h3>{selectedZone ? `Zone Breakdown — ${selectedZone.name}` : 'Zone Breakdown'}</h3>
                  {selectedZone && (
                    <button className="btn btn-outline btn-sm" onClick={() => setSelectedZone(null)}>Clear</button>
                  )}
                </div>
                {!selectedZone ? (
                  <div className="chart-placeholder">
                    Select a zone on the heatmap to see its barrier categories, exact sample sizes and time-of-day trend.
                  </div>
                ) : (
                  <div style={{ display: 'flex', flexDirection: 'column', gap: '18px' }}>
                    <div style={{ display: 'flex', gap: '10px', flexWrap: 'wrap' }}>
                      <span className="badge primary">Barriers: {selectedZone.issueCount}</span>
                      <span className="badge secondary">Assistance requests: {selectedZone.requestCount}</span>
                      {selectedZone.issueCount < LOW_SAMPLE_MIN && (
                        <span className="badge emergency" style={{ display: 'inline-flex', alignItems: 'center', gap: '4px' }}>
                          <AlertTriangle size={12} /> Low sample size (n = {selectedZone.issueCount}) — percentages hidden
                        </span>
                      )}
                    </div>
                    {selectedZone.issueCount === 0 ? (
                      <div className="chart-placeholder">No data available for the selected period.</div>
                    ) : (
                      <>
                        <div>
                          <div style={{ fontSize: '13px', fontWeight: 600, marginBottom: '8px' }}>Barrier categories</div>
                          <HBars
                            items={selectedZone.categories}
                            total={selectedZone.issueCount}
                            showPct={selectedZone.issueCount >= LOW_SAMPLE_MIN}
                          />
                        </div>
                        <div>
                          <div style={{ fontSize: '13px', fontWeight: 600, marginBottom: '8px' }}>Time-of-day trend</div>
                          <HourBars counts={selectedZone.hourly} />
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
            <div className="grid-2" style={{ marginBottom: '24px' }}>
              <div className="card">
                <div className="card-header">
                  <h3>Barrier Category Distribution</h3>
                  <span className="badge secondary">n = {periodIssues.length}</span>
                </div>
                {loading
                  ? <div className="chart-placeholder">Loading…</div>
                  : (
                    <>
                      {topCategory && (
                        <div style={{ marginBottom: '12px', fontSize: '13px' }}>
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
                  ? <div className="chart-placeholder">Loading…</div>
                  : <HourBars counts={hours} />}
              </div>
            </div>

            <div className="card">
              <div className="card-header">
                <h3>Barrier Reports — Daily Trend (last 30 days)</h3>
              </div>
              {loading
                ? <div className="chart-placeholder">Loading…</div>
                : <LineTrend points={daily} height={140} />}
            </div>
          </>
        )}

        {tab === 'hotspots' && (
          <>
            <div className="stats-grid" style={{ marginBottom: '24px' }}>
              <KpiCard
                icon={<MapPin size={22} />}
                tone="primary"
                label="Double-Jeopardy Hotspots"
                value={loading ? '…' : hotspots.filter((z) => z.doubleJeopardy).length}
                sub="zones above median on both barriers & demand"
              />
              <KpiCard
                icon={<BarChart3 size={22} />}
                tone="secondary"
                label="Zones Analysed"
                value={loading ? '…' : hotspots.length}
                sub="zones with layout coordinates"
              />
              <KpiCard
                icon={<CheckCircle2 size={22} />}
                tone="success"
                label="Clear Zones"
                value={loading ? '…' : hotspots.filter((z) => z.issueCount + z.requestCount === 0).length}
                sub="no reports in the selected period"
              />
            </div>

            <div className="card">
              <div className="card-header">
                <h3>High-Frequency Problem Areas — Hotspot Correlation</h3>
                <span className="badge muted">Barriers vs live assistance demand (FR-M7-19)</span>
              </div>
              <table className="data-table">
                <thead>
                  <tr>
                    <th>Location / Zone</th>
                    <th>Confirmed Barriers</th>
                    <th>Assistance Requests</th>
                    <th>Top Category</th>
                    <th>Priority</th>
                  </tr>
                </thead>
                <tbody>
                  {loading ? (
                    <tr><td colSpan="5" style={{ textAlign: 'center', padding: '32px' }}>Loading reports from Supabase…</td></tr>
                  ) : hotspots.length === 0 ? (
                    <tr><td colSpan="5" style={{ textAlign: 'center', padding: '32px' }}>No data available for the selected period.</td></tr>
                  ) : (
                    hotspots.map((z) => (
                      <tr key={z.id} onClick={() => { setTab('overview'); setSelectedZone(z) }} style={{ cursor: 'pointer' }}>
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
              <div style={{ padding: '12px 16px', fontSize: '12px', color: '#64748b' }}>
                "Fix first" flags zones that are above the median for both confirmed barriers and live assistance
                demand — resolving these improves the most travellers. Click a row to view that zone on the heatmap.
              </div>
            </div>
          </>
        )}
      </div>
    </div>
  )
}
