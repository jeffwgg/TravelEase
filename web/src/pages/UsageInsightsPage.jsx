import React, { useEffect, useMemo, useState } from 'react'
import { Users, ListOrdered, MessageSquareText, RefreshCw, Hourglass, UserX, Download, FileDown } from 'lucide-react'
import { analyticsRepository } from '../repositories/analyticsRepository'
import { assistanceRepository } from '../repositories/assistanceRepository'
import { useAuth } from '../context/AuthContext'
import Tabs from '../components/Tabs'
import { KpiCard, HBars, HourBars, LineTrend } from '../components/charts'
import { downloadCsv, downloadPdf } from '../lib/exporter'
import {
  PERIODS, periodStart, inPeriod, queueStats, communicationStats,
  fmtDuration, LOW_SAMPLE_MIN
} from '../lib/analytics'

const TABS = [
  { key: 'users', label: 'Users & Adoption' },
  { key: 'queue', label: 'Queue Analytics' },
  { key: 'communication', label: 'Communication Usage' }
]

export default function UsageInsightsPage() {
  const { staffContext } = useAuth()
  const [period, setPeriod] = useState('90d')
  const [tab, setTab] = useState('users')
  const [loading, setLoading] = useState(true)
  const [queueLines, setQueueLines] = useState([])
  const [queueNumbers, setQueueNumbers] = useState([])
  const [sessions, setSessions] = useState([])
  const [messages, setMessages] = useState([])
  const [userAnalytics, setUserAnalytics] = useState(null)
  const [staffCount, setStaffCount] = useState(0)

  useEffect(() => {
    loadData()
  }, [staffContext?.institution_id])

  async function loadData() {
    setLoading(true)
    const institutionId = staffContext?.institution_id
    const [lines, numbers, sess, msgs, users, staff] = await Promise.all([
      analyticsRepository.getQueueLines(),
      analyticsRepository.getQueueNumbers(),
      analyticsRepository.getDialogueSessions(),
      analyticsRepository.getDialogueMessages(),
      analyticsRepository.getUserAnalytics(),
      assistanceRepository.getInstitutionStaff()
    ])
    setQueueLines(lines)
    setQueueNumbers(numbers)
    setSessions(sess)
    setMessages(msgs)
    setUserAnalytics(users)
    setStaffCount(staff.length)
    setLoading(false)
  }

  const start = periodStart(period)
  const periodQueue = useMemo(() => queueNumbers.filter((n) => inPeriod(n, 'created_at', start)), [queueNumbers, start])
  const periodSessions = useMemo(() => sessions.filter((s) => inPeriod(s, 'created_at', start)), [sessions, start])
  const periodSessionIds = useMemo(() => new Set(periodSessions.map((s) => s.id)), [periodSessions])
  const periodMessages = useMemo(() => messages.filter((m) => periodSessionIds.has(m.session_id)), [messages, periodSessionIds])

  const queue = useMemo(() => queueStats(queueLines, periodQueue), [queueLines, periodQueue])
  const comm = useMemo(() => communicationStats(periodSessions, periodMessages), [periodSessions, periodMessages])

  const signups = useMemo(
    () => (userAnalytics?.signups || []).map((s) => ({ key: s.month, count: Number(s.count) })).sort((a, b) => a.key.localeCompare(b.key)),
    [userAnalytics]
  )

  const periodLabel = PERIODS.find((p) => p.key === period)?.label
  const venueLabel = staffContext?.institutions?.name || 'All Venues'

  // ------------------------------------------------- per-tab export builders
  function exportCurrentTab(format) {
    const base = {
      title: 'Usage Insights Export',
      metaLines: [
        ['Venue', venueLabel],
        ['Period', tab === 'users' ? 'All time (adoption history)' : periodLabel],
        ['Generated', new Date().toISOString()],
        ['Note', 'Aggregate counts only — no personal data.']
      ]
    }
    let spec
    if (tab === 'users') {
      spec = {
        ...base,
        title: 'Platform Users & Adoption Export',
        kpis: [
          { label: 'Total registered users', value: userAnalytics?.total_users ?? '—' },
          { label: 'Staff at this institution', value: staffCount }
        ],
        tables: [
          { title: 'Monthly sign-ups', headers: ['Month', 'Users'], rows: signups.map((s) => [s.key, s.count]) }
        ]
      }
    } else if (tab === 'queue') {
      spec = {
        ...base,
        title: 'Queue Service Analytics Export',
        kpis: [
          { label: 'Queue numbers issued', value: queue.total },
          { label: 'Completed', value: queue.total - queue.cancelled },
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
    const filename = `travelease_usage_${tab}_${tab === 'users' ? 'all' : period}_${new Date().toISOString().slice(0, 10)}`
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
          <h2>Usage Insights</h2>
          <div className="header-subtitle">
            Cross-module analytics: platform adoption (Module 1), queue service patterns (Module 2) and accessible
            communication usage (Module 3) feeding the Module 7 dashboard.
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
        <Tabs tabs={TABS} active={tab} onChange={setTab} actions={tabActions} />

        {tab === 'users' && (
          <div className="card">
            <div className="card-header">
              <h3 style={{ display: 'flex', alignItems: 'center', gap: '8px' }}><Users size={18} /> Platform Users & Adoption</h3>
              <span className="badge muted">aggregate counts only — no personal data</span>
            </div>
            <div className="stats-grid" style={{ margin: '16px 0 20px' }}>
              <KpiCard
                icon={<Users size={22} />}
                tone="primary"
                label="Total Registered Users"
                value={loading || !userAnalytics ? '…' : userAnalytics.total_users}
                sub="traveller + institution accounts"
              />
              <KpiCard
                icon={<Users size={22} />}
                tone="secondary"
                label="Staff at This Institution"
                value={loading ? '…' : staffCount}
                sub={venueLabel}
              />
            </div>
            <div>
              <div style={{ fontSize: '13px', fontWeight: 600, marginBottom: '8px' }}>New sign-ups per month</div>
              {loading ? <div className="chart-placeholder">Loading…</div> : <LineTrend points={signups} />}
            </div>
          </div>
        )}

        {tab === 'queue' && (
          <div className="card">
            <div className="card-header">
              <h3 style={{ display: 'flex', alignItems: 'center', gap: '8px' }}><ListOrdered size={18} /> Queue Service Analytics</h3>
              <span className="badge muted">{venueLabel}</span>
            </div>
            <div className="stats-grid" style={{ margin: '16px 0 20px' }}>
              <KpiCard
                icon={<ListOrdered size={22} />}
                tone="primary"
                label="Queue Numbers Issued"
                value={loading ? '…' : queue.total}
                sub={`${queue.total - queue.cancelled} completed • n = ${queue.total}`}
              />
              <KpiCard
                icon={<Hourglass size={22} />}
                tone="accent"
                label="Median Wait Before Call"
                value={loading ? '…' : fmtDuration(queue.medianWaitSec)}
                sub="issued → called"
              />
              <KpiCard
                icon={<UserX size={22} />}
                tone="secondary"
                label="Abandonment Rate"
                value={loading ? '…' : `${queue.abandonmentPct}%`}
                sub={`${queue.cancelled} cancelled without service`}
              />
            </div>
            <div className="grid-2">
              <div>
                <div style={{ fontSize: '13px', fontWeight: 600, marginBottom: '8px' }}>Queue arrivals by time of day</div>
                {loading ? <div className="chart-placeholder">Loading…</div> : <HourBars counts={queue.hourly} color="#8b5cf6" />}
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
                    <tr><td colSpan="5" style={{ textAlign: 'center', padding: '24px' }}>Loading…</td></tr>
                  ) : queue.perLine.length === 0 ? (
                    <tr><td colSpan="5" style={{ textAlign: 'center', padding: '24px' }}>No data available for the selected period.</td></tr>
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

        {tab === 'communication' && (
          <div className="card">
            <div className="card-header">
              <h3 style={{ display: 'flex', alignItems: 'center', gap: '8px' }}><MessageSquareText size={18} /> Accessible Communication Usage</h3>
              <span className="badge muted">Module 3 two-way dialogue</span>
            </div>
            <div className="stats-grid" style={{ margin: '16px 0 20px' }}>
              <KpiCard
                icon={<MessageSquareText size={22} />}
                tone="primary"
                label="Dialogue Sessions"
                value={loading ? '…' : comm.total}
                sub={`n = ${comm.total}`}
              />
              <KpiCard
                icon={<Hourglass size={22} />}
                tone="accent"
                label="Avg. Session Duration"
                value={loading ? '…' : fmtDuration(comm.avgDurationSec)}
                sub={`${comm.completed} completed`}
              />
            </div>
            <div className="grid-2" style={{ marginBottom: '20px' }}>
              <div>
                <div style={{ fontSize: '13px', fontWeight: 600, marginBottom: '8px' }}>Traveller input modality mix</div>
                {loading
                  ? <div className="chart-placeholder">Loading…</div>
                  : <HBars items={comm.modalityMix} showPct={comm.modalityMix.reduce((s, i) => s + i.count, 0) >= LOW_SAMPLE_MIN} />}
              </div>
              <div>
                <div style={{ fontSize: '13px', fontWeight: 600, marginBottom: '8px' }}>Translation direction (EN → ?)</div>
                {loading
                  ? <div className="chart-placeholder">Loading…</div>
                  : <HBars items={comm.targetMix} total={comm.total} color="#10b981" />}
              </div>
            </div>
            <div>
              <div style={{ fontSize: '13px', fontWeight: 600, marginBottom: '8px' }}>Sessions per month</div>
              {loading ? <div className="chart-placeholder">Loading…</div> : <LineTrend points={comm.monthly} color="#10b981" />}
            </div>
          </div>
        )}
      </div>
    </div>
  )
}
