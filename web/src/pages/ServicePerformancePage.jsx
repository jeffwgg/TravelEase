import React, { useEffect, useMemo, useState } from 'react'
import { Zap, Clock, Star, ThumbsUp, RefreshCw, ShieldAlert } from 'lucide-react'
import { assistanceRepository } from '../repositories/assistanceRepository'
import { announcementRepository } from '../repositories/announcementRepository'
import { analyticsRepository } from '../repositories/analyticsRepository'
import { useAuth } from '../context/AuthContext'
import { KpiCard, HBars, LineTrend } from '../components/charts'
import {
  PERIODS, periodStart, inPeriod, withDerivedTimes, assistanceKpis,
  zoneStats, ratingDistribution, fmtDuration, pct, ISSUE_TYPE_LABELS, LOW_SAMPLE_MIN
} from '../lib/analytics'

export default function ServicePerformancePage() {
  const { staffContext } = useAuth()
  const [period, setPeriod] = useState('30d')
  const [requests, setRequests] = useState([])
  const [issues, setIssues] = useState([])
  const [zones, setZones] = useState([])
  const [slaConfigs, setSlaConfigs] = useState([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    loadData()
  }, [staffContext?.institution_id])

  async function loadData() {
    setLoading(true)
    const institutionId = staffContext?.institution_id
    const [requestsData, issuesData, zonesData, slaData] = await Promise.all([
      assistanceRepository.getAssistanceRequests(),
      assistanceRepository.getAccessibilityIssueReports(),
      institutionId ? announcementRepository.getZones(institutionId).catch(() => []) : Promise.resolve([]),
      institutionId ? analyticsRepository.getSlaConfigs(institutionId) : Promise.resolve([])
    ])
    setRequests(withDerivedTimes(requestsData || []))
    setIssues(issuesData || [])
    setZones(zonesData || [])
    setSlaConfigs(slaData || [])
    setLoading(false)
  }

  const venueName = staffContext?.institutions?.name
  const start = periodStart(period)
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

  // FR-M7-10: compare service performance across zones.
  const zoneComparison = useMemo(() => {
    const names = [...new Set(periodRequests.map((r) => r.location_zone).filter(Boolean))]
    return names.map((name) => {
      const rows = periodRequests.filter((r) => r.location_zone === name)
      const k = assistanceKpis(rows, {
        response: defaultSla.responseMinutes * 60,
        resolution: defaultSla.resolutionMinutes * 60
      })
      const z = zones.find((zz) => zz.name === name)
      return { name, code: z?.code || name, ...k }
    }).sort((a, b) => b.total - a.total)
  }, [periodRequests, zones, defaultSla])

  return (
    <div>
      <div className="page-header">
        <div>
          <h2>Service Performance Monitoring</h2>
          <div className="header-subtitle">
            Track first response times, resolution speed, SLA compliance and user satisfaction for assistance services.
          </div>
        </div>
        <div style={{ display: 'flex', gap: '8px' }}>
          <select className="input" style={{ width: '160px' }} value={period} onChange={(e) => setPeriod(e.target.value)}>
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
        <div className="stats-grid">
          <KpiCard
            icon={<Zap size={22} />}
            tone="primary"
            label="Avg. First Response Time"
            value={loading ? '…' : fmtDuration(kpis.avgFirstResponseSec)}
            sub={`n = ${kpis.responseSampleCount}`}
          />
          <KpiCard
            icon={<Clock size={22} />}
            tone="accent"
            label="Avg. Resolution Time"
            value={loading ? '…' : fmtDuration(kpis.avgResolutionSec)}
            sub={`n = ${kpis.resolutionSampleCount}`}
          />
          <KpiCard
            icon={<Star size={22} />}
            tone="secondary"
            label="User Satisfaction"
            value={loading ? '…' : kpis.avgRating != null ? `${kpis.avgRating.toFixed(2)} / 5` : '—'}
            sub={`based on ${kpis.ratingCount} ratings`}
          />
          <KpiCard
            icon={<ThumbsUp size={22} />}
            tone="success"
            label="Resolution Rate"
            value={loading ? '…' : `${kpis.resolutionRatePct}%`}
            sub={`unresolved: ${kpis.unresolvedRatePct}% • repeated: ${kpis.repeatedRatePct}% • n = ${kpis.serviceable}`}
          />
        </div>

        <div className="grid-2" style={{ marginBottom: '24px' }}>
          <div className="card">
            <div className="card-header">
              <h3>SLA Compliance</h3>
              <span className="badge secondary">
                Limits: {defaultSla.responseMinutes} min response / {defaultSla.resolutionMinutes} min resolution
              </span>
            </div>
            {loading ? (
              <div className="chart-placeholder">Loading…</div>
            ) : (
              <div style={{ display: 'flex', flexDirection: 'column', gap: '14px' }}>
                <div style={{ display: 'flex', gap: '12px', flexWrap: 'wrap' }}>
                  <div style={{ flex: 1, minWidth: '180px', padding: '14px', border: '1px solid rgba(239,68,68,0.35)', borderRadius: '10px' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '13px', fontWeight: 600 }}>
                      <ShieldAlert size={14} color="#ef4444" /> Response SLA breaches
                    </div>
                    <div style={{ fontSize: '26px', fontWeight: 700, marginTop: '6px' }}>
                      {kpis.respBreaches}
                      <span style={{ fontSize: '14px', fontWeight: 500, color: '#64748b' }}> of {kpis.responseSampleCount}</span>
                    </div>
                    <div style={{ fontSize: '12px', color: '#64748b' }}>
                      {kpis.respBreachPct}% exceeded the {defaultSla.responseMinutes}-minute limit
                    </div>
                  </div>
                  <div style={{ flex: 1, minWidth: '180px', padding: '14px', border: '1px solid rgba(245,158,11,0.35)', borderRadius: '10px' }}>
                    <div style={{ display: 'flex', alignItems: 'center', gap: '6px', fontSize: '13px', fontWeight: 600 }}>
                      <ShieldAlert size={14} color="#f59e0b" /> Resolution SLA breaches
                    </div>
                    <div style={{ fontSize: '26px', fontWeight: 700, marginTop: '6px' }}>
                      {kpis.resolBreaches}
                      <span style={{ fontSize: '14px', fontWeight: 500, color: '#64748b' }}> of {kpis.resolutionSampleCount}</span>
                    </div>
                    <div style={{ fontSize: '12px', color: '#64748b' }}>
                      {kpis.resolBreachPct}% exceeded the {defaultSla.resolutionMinutes}-minute limit
                    </div>
                  </div>
                </div>
                <div style={{ fontSize: '12px', color: '#64748b' }}>
                  FR-M7-15: total assistance requests exceeding the institution's predefined response or resolution limits.
                </div>
              </div>
            )}
          </div>

          <div className="card">
            <div className="card-header">
              <h3>Satisfaction Rating Distribution</h3>
              <span className="badge secondary">n = {kpis.ratingCount}</span>
            </div>
            {loading
              ? <div className="chart-placeholder">Loading…</div>
              : <HBars items={ratingDist} total={kpis.ratingCount} color="var(--secondary-dark, #8b5cf6)" showPct={kpis.ratingCount >= LOW_SAMPLE_MIN} />}
          </div>
        </div>

        <div className="grid-2" style={{ marginBottom: '24px' }}>
          <div className="card">
            <div className="card-header">
              <h3>Satisfaction Trend (FR-M7-17)</h3>
            </div>
            {loading || satisfactionTrend.length < 2
              ? <div className="chart-placeholder">Not enough rated months to draw a trend yet.</div>
              : <LineTrend points={satisfactionTrend} color="#8b5cf6" suffix=" stars" />}
          </div>

          <div className="card">
            <div className="card-header">
              <h3>Unresolved & Repeated Requests</h3>
            </div>
            {loading ? (
              <div className="chart-placeholder">Loading…</div>
            ) : (
              <div style={{ display: 'flex', flexDirection: 'column', gap: '10px', fontSize: '14px' }}>
                <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                  <span>Unresolved (pending + in progress)</span>
                  <strong>{kpis.unresolvedCount} ({kpis.unresolvedRatePct}%)</strong>
                </div>
                <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                  <span>Cancelled by traveller</span>
                  <strong>{kpis.cancelled}</strong>
                </div>
                <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                  <span>Repeated requests (same traveller, &gt;1 in period)</span>
                  <strong>{kpis.repeatedRatePct}%</strong>
                </div>
                <div style={{ fontSize: '12px', color: '#64748b', marginTop: '6px' }}>
                  FR-M7-09: resolution, unresolved and repeated request rates for assistance services.
                </div>
              </div>
            )}
          </div>
        </div>

        <div className="card">
          <div className="card-header">
            <h3>Zone Performance Comparison (FR-M7-10)</h3>
            <span className="badge muted">{venueName || 'All Venues'}</span>
          </div>
          <table className="data-table">
            <thead>
              <tr>
                <th>Zone</th>
                <th>Requests</th>
                <th>Avg. First Response</th>
                <th>Avg. Resolution</th>
                <th>Avg. Rating</th>
                <th>Ratings (n)</th>
              </tr>
            </thead>
            <tbody>
              {loading ? (
                <tr><td colSpan="6" style={{ textAlign: 'center', padding: '32px' }}>Loading…</td></tr>
              ) : zoneComparison.length === 0 ? (
                <tr><td colSpan="6" style={{ textAlign: 'center', padding: '32px' }}>No data available for the selected period.</td></tr>
              ) : (
                zoneComparison.map((z) => (
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
      </div>
    </div>
  )
}
