import React, { useEffect, useMemo, useState } from 'react'
import { FileText, Download, RefreshCw, Loader2 } from 'lucide-react'
import { assistanceRepository } from '../repositories/assistanceRepository'
import { serviceAreaRepository } from '../repositories/serviceAreaRepository'
import { analyticsRepository } from '../repositories/analyticsRepository'
import { useAuth } from '../context/AuthContext'
import { HBars, LineTrend, HourBars } from '../components/charts'
import { downloadCsv, downloadPdf } from '../lib/exporter'
import {
  withDerivedTimes, assistanceKpis, countBy, toList, hourlyTrend,
  serviceAreaStats, assignServiceArea, UNMAPPED_ID,
  queueStats, communicationStats, ratingDistribution,
  fmtDuration, pct, ISSUE_TYPE_LABELS, LOW_SAMPLE_MIN
} from '../lib/analytics'

const REPORT_TYPES = [
  { key: 'accessibility', title: 'Accessibility Barrier & Heatmap Summary', desc: 'Confirmed barriers by service area, category and time of day.' },
  { key: 'assistance_performance', title: 'Assistance Service Performance', desc: 'Response/resolution KPIs, SLA breaches and satisfaction.' },
  { key: 'queue_service', title: 'Queue Service Summary', desc: 'Wait times, abandonment and throughput per queue line.' },
  { key: 'communication_usage', title: 'Accessible Communication Usage', desc: 'Dialogue session volume, modality and language mix.' },
  { key: 'users', title: 'Platform Adoption & User Mix', desc: 'Aggregate user counts, sign-up trend and preference mix.' }
]

const today = () => new Date().toISOString().slice(0, 10)
const daysAgo = (n) => new Date(Date.now() - n * 86400000).toISOString().slice(0, 10)

export default function ReportGenerationPage() {
  const { staffContext } = useAuth()
  const [data, setData] = useState(null)
  const [areas, setAreas] = useState([])
  const [slaConfigs, setSlaConfigs] = useState([])
  const [history, setHistory] = useState([])
  const [reportType, setReportType] = useState('accessibility')
  const [dateFrom, setDateFrom] = useState(daysAgo(30))
  const [dateTo, setDateTo] = useState(today())
  const [areaFilter, setAreaFilter] = useState('all')
  const [format, setFormat] = useState('pdf')
  const [preview, setPreview] = useState(null)
  const [working, setWorking] = useState(false)

  useEffect(() => {
    loadAll()
  }, [staffContext?.institution_id])

  async function loadAll() {
    setWorking(true)
    const institutionId = staffContext?.institution_id
    const [requests, issues, lines, numbers, sess, msgs, users, slaData, areasData, historyData] = await Promise.all([
      assistanceRepository.getAssistanceRequests(),
      assistanceRepository.getAccessibilityIssueReports(),
      analyticsRepository.getQueueLines(),
      analyticsRepository.getQueueNumbers(),
      analyticsRepository.getDialogueSessions(),
      analyticsRepository.getDialogueMessages(),
      analyticsRepository.getUserAnalytics(),
      institutionId ? analyticsRepository.getSlaConfigs(institutionId) : Promise.resolve([]),
      staffContext ? serviceAreaRepository.list(staffContext).catch(() => []) : Promise.resolve([]),
      institutionId ? assistanceRepository.getGeneratedReports() : Promise.resolve([])
    ])
    setData({
      requests: withDerivedTimes(requests || []),
      issues: issues || [],
      queueLines: lines,
      queueNumbers: numbers,
      sessions: sess,
      messages: msgs,
      users
    })
    setSlaConfigs(slaData || [])
    setAreas((areasData || []).filter((a) => a.active))
    setHistory(historyData || [])
    setWorking(false)
  }

  const sla = useMemo(() => {
    const row = slaConfigs.find((s) => s.zone_id == null)
    return { response: (row?.response_limit_minutes ?? 5) * 60, resolution: (row?.resolution_limit_minutes ?? 60) * 60 }
  }, [slaConfigs])

  // --------------------------------------------------------------- snapshot
  function buildSnapshot() {
    if (!data) return null
    const from = new Date(`${dateFrom}T00:00:00`)
    const to = new Date(`${dateTo}T23:59:59`)
    const venueName = staffContext?.institutions?.name
    const inRange = (row, field = 'created_at') => {
      const t = new Date(row[field])
      return t >= from && t <= to
    }

    let requests = data.requests.filter(
      (r) => inRange(r) && (!venueName || r.venue_name === venueName) && r.analytics_consent !== false
    )
    let issues = data.issues.filter(
      (i) => inRange(i) && (!venueName || i.venue_name === venueName) && i.analytics_consent !== false
    )
    if (areaFilter !== 'all') {
      const match = (row) => {
        const area = assignServiceArea(areas, row)
        return areaFilter === UNMAPPED_ID ? !area : area?.id === areaFilter
      }
      requests = requests.filter(match)
      issues = issues.filter(match)
    }
    const numbers = data.queueNumbers.filter((n) => inRange(n))
    const sessions = data.sessions.filter((s) => inRange(s))
    const sessionIds = new Set(sessions.map((s) => s.id))
    const messages = data.messages.filter((m) => sessionIds.has(m.session_id))

    const meta = {
      reportType,
      title: REPORT_TYPES.find((t) => t.key === reportType)?.title,
      from: dateFrom,
      to: dateTo,
      area: areaFilter === 'all'
        ? 'All Service Areas'
        : areaFilter === UNMAPPED_ID
          ? 'Unmapped'
          : areas.find((a) => a.id === areaFilter)?.name,
      venue: venueName || 'All Venues',
      generatedAt: new Date().toISOString(),
      // UC702: reports contain no traveller identities — aggregates + codes only.
      anonymized: true
    }

    if (reportType === 'accessibility') {
      const areaList = serviceAreaStats(areas, issues, requests)
      return {
        meta,
        kpis: [
          { label: 'Confirmed barriers', value: issues.length },
          { label: 'Assistance requests', value: requests.length },
          { label: 'Resolved barriers', value: `${issues.filter((i) => i.status === 'resolved').length} (${pct(issues.filter((i) => i.status === 'resolved').length, issues.length)}%)` },
          { label: 'Busiest hour', value: `${String(hourlyTrend(issues).indexOf(Math.max(...hourlyTrend(issues))))}:00` }
        ],
        categoryMix: toList(countBy(issues, (i) => i.issue_type), (k) => ISSUE_TYPE_LABELS[k] || k),
        areas: areaList.map((a) => ({
          area: a.name, barriers: a.issueCount, requests: a.requestCount,
          topCategory: a.categories[0]?.label || '—'
        })),
        hours: hourlyTrend(issues)
      }
    }

    if (reportType === 'assistance_performance') {
      const k = assistanceKpis(requests, sla)
      return {
        meta,
        kpis: [
          { label: 'Requests', value: k.total },
          { label: 'Avg first response', value: fmtDuration(k.avgFirstResponseSec) },
          { label: 'Avg resolution', value: fmtDuration(k.avgResolutionSec) },
          { label: 'Resolution rate', value: `${k.resolutionRatePct}%` },
          { label: 'Unresolved rate', value: `${k.unresolvedRatePct}%` },
          { label: 'Repeated request rate', value: `${k.repeatedRatePct}%` },
          { label: 'Response SLA breaches', value: `${k.respBreaches} (${k.respBreachPct}%)` },
          { label: 'Resolution SLA breaches', value: `${k.resolBreaches} (${k.resolBreachPct}%)` },
          { label: 'Avg satisfaction', value: k.avgRating != null ? `${k.avgRating.toFixed(2)} / 5 (n=${k.ratingCount})` : '—' }
        ],
        ratingMix: ratingDistribution(requests),
        monthly: monthlyRows(requests)
      }
    }

    if (reportType === 'queue_service') {
      const q = queueStats(data.queueLines, numbers)
      return {
        meta,
        kpis: [
          { label: 'Numbers issued', value: q.total },
          { label: 'Completed', value: q.total - q.cancelled },
          { label: 'Median wait before call', value: fmtDuration(q.medianWaitSec) },
          { label: 'Abandonment rate', value: `${q.abandonmentPct}%` }
        ],
        lines: q.perLine.map((l) => ({
          line: l.name, issued: l.total, completed: l.completed,
          medianWait: fmtDuration(l.medianWaitSec), p95Wait: fmtDuration(l.p95WaitSec),
          abandoned: `${l.cancelled} (${l.abandonmentPct}%)`
        })),
        hours: q.hourly
      }
    }

    if (reportType === 'communication_usage') {
      const c = communicationStats(sessions, messages)
      return {
        meta,
        kpis: [
          { label: 'Dialogue sessions', value: c.total },
          { label: 'Avg session duration', value: fmtDuration(c.avgDurationSec) },
          { label: 'Top modality', value: c.modalityMix[0]?.label || '—' },
          { label: 'Top target language', value: c.targetMix[0]?.label || '—' }
        ],
        modalityMix: c.modalityMix,
        targetMix: c.targetMix,
        monthly: c.monthly
      }
    }

    // users
    const u = data.users || {}
    return {
      meta,
      kpis: [
        { label: 'Total users', value: u.total_users ?? '—' },
        { label: 'New sign-ups (period)', value: (u.signups || []).reduce((s2, x) => s2 + Number(x.count), 0) }
      ],
      monthly: (u.signups || []).map((x) => ({ key: x.month, count: Number(x.count) })).sort((a, b) => a.key.localeCompare(b.key))
    }
  }

  function monthlyRows(requests) {
    const buckets = new Map()
    for (const r of requests) {
      const d = new Date(r.created_at)
      const k = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`
      const cur = buckets.get(k) || { total: 0, resolved: 0, rated: 0, ratingSum: 0 }
      cur.total += 1
      if (r.status === 'resolved' || r.status === 'closed') cur.resolved += 1
      if (r.user_rating != null) {
        cur.rated += 1
        cur.ratingSum += Number(r.user_rating)
      }
      buckets.set(k, cur)
    }
    return [...buckets.entries()].sort((a, b) => a[0].localeCompare(b[0])).map(([month, v]) => ({
      month,
      requests: v.total,
      resolved: v.resolved,
      resolutionRate: pct(v.resolved, v.total),
      avgRating: v.rated ? Math.round((v.ratingSum / v.rated) * 100) / 100 : '—'
    }))
  }

  // --------------------------------------------------------------- generate
  function handleGenerate(e) {
    e.preventDefault()
    const snapshot = buildSnapshot()
    if (!snapshot) return
    setPreview(snapshot)
  }

  // ------------------------------------------------- export (shared exporter)
  function specFromSnapshot(snapshot) {
    return {
      title: snapshot.meta.title,
      metaLines: [
        ['Venue', snapshot.meta.venue],
        ['Service area', snapshot.meta.area ?? snapshot.meta.zone],
        ['Period', `${snapshot.meta.from} to ${snapshot.meta.to}`],
        ['Generated', snapshot.meta.generatedAt],
        ['Anonymized', 'true — no traveller identities included']
      ],
      kpis: snapshot.kpis,
      tables: tablesFromSnapshot(snapshot)
    }
  }

  function exportFilename(snapshot, ext) {
    return `${snapshot.meta.reportType}_${snapshot.meta.from}_${snapshot.meta.to}.${ext}`
  }

  function tablesFromSnapshot(snapshot) {
    const tables = []
    if (snapshot.categoryMix) tables.push({ title: 'Barrier category distribution', headers: ['Category', 'Count'], rows: snapshot.categoryMix.map((c) => [c.label, c.count]) })
    if (snapshot.areas) tables.push({ title: 'Service area breakdown', headers: ['Service area', 'Barriers', 'Requests', 'Top category'], rows: snapshot.areas.map((a) => [a.area, a.barriers, a.requests, a.topCategory]) })
    // Older saved snapshots used the venue-zone model; keep them exportable.
    else if (snapshot.zones) tables.push({ title: 'Zone breakdown', headers: ['Zone', 'Barriers', 'Requests', 'Top category'], rows: snapshot.zones.map((z) => [z.zone, z.barriers, z.requests, z.topCategory]) })
    if (snapshot.lines) tables.push({ title: 'Queue line performance', headers: ['Line', 'Issued', 'Completed', 'Median wait', 'P95 wait', 'Abandoned'], rows: snapshot.lines.map((l) => [l.line, l.issued, l.completed, l.medianWait, l.p95Wait, l.abandoned]) })
    if (snapshot.modalityMix) tables.push({ title: 'Input modality mix', headers: ['Modality', 'Count'], rows: snapshot.modalityMix.map((c) => [c.label, c.count]) })
    if (snapshot.targetMix) tables.push({ title: 'Translation direction', headers: ['Target language', 'Sessions'], rows: snapshot.targetMix.map((c) => [c.label, c.count]) })
    if (snapshot.ratingMix) tables.push({ title: 'Satisfaction distribution', headers: ['Rating', 'Count'], rows: snapshot.ratingMix.map((c) => [c.label, c.count]) })
    if (snapshot.monthly) tables.push({ title: 'Monthly trend', headers: Object.keys(snapshot.monthly[0] || { key: 1 }), rows: snapshot.monthly.map((m) => Object.values(m)) })
    return tables
  }

  async function persistReport(snapshot, chosenFormat) {
    if (!staffContext?.institution_id) return
    try {
      await analyticsRepository.saveGeneratedReport({
        institution_id: staffContext.institution_id,
        report_title: `${snapshot.meta.title} (${snapshot.meta.from} → ${snapshot.meta.to})`,
        report_type: snapshot.meta.reportType,
        date_from: snapshot.meta.from,
        date_to: snapshot.meta.to,
        zone_filter: snapshot.meta.area ?? snapshot.meta.zone,
        format: chosenFormat,
        data_snapshot: snapshot
      })
      const refreshed = await assistanceRepository.getGeneratedReports()
      setHistory(refreshed || [])
    } catch (err) {
      console.error('Failed to save report record:', err)
    }
  }

  async function handleExportCsv(snapshot = preview) {
    if (!snapshot) return
    setWorking(true)
    downloadCsv(exportFilename(snapshot, 'csv'), specFromSnapshot(snapshot))
    await persistReport(snapshot, 'csv')
    setWorking(false)
  }

  async function handleExportPdf(snapshot = preview) {
    if (!snapshot) return
    setWorking(true)
    try {
      await downloadPdf(exportFilename(snapshot, 'pdf'), specFromSnapshot(snapshot))
      await persistReport(snapshot, 'pdf')
    } catch (err) {
      console.error('PDF export failed:', err)
      alert('PDF export failed. See console for details.')
    }
    setWorking(false)
  }

  async function handleHistoryDownload(row) {
    const snapshot = row.data_snapshot
    if (!snapshot?.meta) return
    if (row.format === 'pdf') {
      await handleExportPdf(snapshot)
    } else {
      await handleExportCsv(snapshot)
    }
  }

  const selectedType = REPORT_TYPES.find((t) => t.key === reportType)

  return (
    <div>
      <div className="page-header">
        <div>
          <h2>Report Generation</h2>
          <div className="header-subtitle">
            Compile analytics into an anonymized, exportable report for management.
          </div>
        </div>
        <button className="btn btn-outline" onClick={loadAll}>
          <RefreshCw size={16} /> Reload Data
        </button>
      </div>

      <div className="page-body">
        <div className="grid-2 section-gap">
          <div className="card">
            <div className="card-header">
              <h3>Generate Custom Report</h3>
            </div>
            <form onSubmit={handleGenerate}>
              <div className="form-group">
                <label>Report Type</label>
                <select className="input" value={reportType} onChange={(e) => setReportType(e.target.value)}>
                  {REPORT_TYPES.map((t) => (
                    <option key={t.key} value={t.key}>{t.title}</option>
                  ))}
                </select>
                {selectedType && <span className="field-help">{selectedType.desc}</span>}
              </div>

              <div style={{ display: 'flex', gap: '16px' }} className="form-group">
                <div style={{ flex: 1 }}>
                  <label>Start Date</label>
                  <input type="date" className="input" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} />
                </div>
                <div style={{ flex: 1 }}>
                  <label>End Date</label>
                  <input type="date" className="input" value={dateTo} onChange={(e) => setDateTo(e.target.value)} />
                </div>
              </div>

              <div className="form-group">
                <label>Target Service Area</label>
                <select className="input" value={areaFilter} onChange={(e) => setAreaFilter(e.target.value)}>
                  <option value="all">All Service Areas (Entire Venue)</option>
                  {areas.map((a) => (
                    <option key={a.id} value={a.id}>{a.name}</option>
                  ))}
                  <option value={UNMAPPED_ID}>Unmapped (no usable location)</option>
                </select>
              </div>

              <div className="form-group">
                <label>Export Format</label>
                <div style={{ display: 'flex', gap: '16px', marginTop: '8px' }}>
                  <label style={{ fontSize: '14px', display: 'flex', alignItems: 'center', gap: '6px' }}>
                    <input type="radio" name="format" checked={format === 'pdf'} onChange={() => setFormat('pdf')} /> PDF Document
                  </label>
                  <label style={{ fontSize: '14px', display: 'flex', alignItems: 'center', gap: '6px' }}>
                    <input type="radio" name="format" checked={format === 'csv'} onChange={() => setFormat('csv')} /> CSV Data Sheet
                  </label>
                </div>
              </div>

              <button className="btn btn-primary" type="submit" disabled={working} style={{ width: '100%', justifyContent: 'center', marginTop: '16px' }}>
                <FileText size={16} /> {working ? <Loader2 size={16} className="spin" /> : null} Generate Report Preview
              </button>
            </form>

            {preview && (
              <div className="button-row" style={{ marginTop: '12px' }}>
                <button className="btn btn-primary" onClick={() => handleExportPdf()} disabled={working}>
                  <Download size={16} /> Export PDF
                </button>
                <button className="btn btn-outline" onClick={() => handleExportCsv()} disabled={working}>
                  <Download size={16} /> Export CSV
                </button>
              </div>
            )}
          </div>

          <div className="card">
            <div className="card-header">
              <h3>Recently Generated Reports</h3>
              <span className="badge muted">{history.length} saved</span>
            </div>
            <table className="data-table">
              <thead>
                <tr>
                  <th>Report Title</th>
                  <th>Date Range</th>
                  <th>Format</th>
                  <th>Action</th>
                </tr>
              </thead>
              <tbody>
                {history.length === 0 ? (
                  <tr>
                    <td colSpan={4} className="table-message">
                      No reports generated yet. Generate a preview, then export it to save it here.
                    </td>
                  </tr>
                ) : (
                  history.map((row) => (
                    <tr key={row.id}>
                      <td><strong>{row.report_title}</strong></td>
                      <td>{row.date_from} → {row.date_to}</td>
                      <td>
                        <span className={`badge ${row.format === 'pdf' ? 'primary' : 'success'}`}>
                          {String(row.format).toUpperCase()}
                        </span>
                      </td>
                      <td>
                        <button className="btn btn-outline btn-sm" onClick={() => handleHistoryDownload(row)}>Download</button>
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>
        </div>

        {/* ------------------------------------------------------- preview */}
        {preview && (
          <div className="card">
            <div className="card-header">
              <h3>Report Preview — {preview.meta.title}</h3>
              <span className="badge secondary">{preview.meta.from} → {preview.meta.to} • {preview.meta.area}</span>
            </div>
            <div style={{ padding: '16px' }}>
              <div className="mini-kpi-grid">
                {preview.kpis.map((k) => (
                  <div key={k.label} className="mini-kpi">
                    <div className="mini-kpi-value">{k.value}</div>
                    <div className="mini-kpi-label">{k.label}</div>
                  </div>
                ))}
              </div>

              {preview.areas && (
                <>
                  <Chart title="Service area breakdown">
                    <table className="data-table">
                      <thead><tr><th>Service Area</th><th>Barriers</th><th>Requests</th><th>Top category</th></tr></thead>
                      <tbody>
                        {preview.areas.map((a) => (
                          <tr key={a.area}><td>{a.area}</td><td>{a.barriers}</td><td>{a.requests}</td><td>{a.topCategory}</td></tr>
                        ))}
                      </tbody>
                    </table>
                  </Chart>
                  <Chart title="Barrier reports by time of day">
                    <HourBars counts={preview.hours} />
                  </Chart>
                </>
              )}

              {preview.categoryMix && (
                <Chart title="Barrier category distribution">
                  <HBars items={preview.categoryMix} showPct={preview.categoryMix.reduce((s, i) => s + i.count, 0) >= LOW_SAMPLE_MIN} />
                </Chart>
              )}

              {preview.ratingMix && (
                <Chart title="Satisfaction rating distribution">
                  <HBars items={preview.ratingMix} color="#8b5cf6" />
                </Chart>
              )}

              {preview.modalityMix && (
                <Chart title="Traveller input modality mix">
                  <HBars items={preview.modalityMix} color="#06b6d4" />
                </Chart>
              )}
              {preview.targetMix && (
                <Chart title="Translation direction (EN → ?)">
                  <HBars items={preview.targetMix} total={preview.targetMix.reduce((s, i) => s + i.count, 0)} color="#10b981" />
                </Chart>
              )}
              {preview.lines && (
                <Chart title="Queue line performance">
                  <table className="data-table">
                    <thead><tr><th>Line</th><th>Issued</th><th>Completed</th><th>Median wait</th><th>P95 wait</th><th>Abandoned</th></tr></thead>
                    <tbody>
                      {preview.lines.map((l) => (
                        <tr key={l.line}><td>{l.line}</td><td>{l.issued}</td><td>{l.completed}</td><td>{l.medianWait}</td><td>{l.p95Wait}</td><td>{l.abandoned}</td></tr>
                      ))}
                    </tbody>
                  </table>
                </Chart>
              )}

              {preview.monthly && (
                <Chart title="Monthly trend">
                  <LineTrend points={preview.monthly} height={110} />
                  <table className="data-table" style={{ marginTop: '10px' }}>
                    <thead><tr>{Object.keys(preview.monthly[0] || {}).map((k) => <th key={k}>{k}</th>)}</tr></thead>
                    <tbody>
                      {preview.monthly.map((m, i) => (
                        <tr key={i}>{Object.values(m).map((v, j) => <td key={j}>{String(v)}</td>)}</tr>
                      ))}
                    </tbody>
                  </table>
                </Chart>
              )}

              <div style={{ marginTop: '16px', fontSize: '12px', color: '#64748b' }}>
                Anonymization: this report contains aggregates and codes only — no traveller names or contact details
                are included. Export saves a copy under "Recently Generated Reports" for re-download.
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}

function Chart({ title, children }) {
  return (
    <div style={{ marginBottom: '20px' }}>
      <div style={{ fontSize: '13px', fontWeight: 600, marginBottom: '8px' }}>{title}</div>
      {children}
    </div>
  )
}
