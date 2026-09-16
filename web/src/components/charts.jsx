// Dependency-free chart primitives for the Module 7 analytics pages.
// Styled to reuse the existing card/stat CSS variables (see index.css,
// "Analytics UI polish" block) — layout lives in classes, data in props.

const PALETTE = ['#3b82f6', '#8b5cf6', '#f59e0b', '#10b981', '#ef4444', '#06b6d4', '#ec4899']

// Shimmer block shown while analytics rows are still loading. Respects
// prefers-reduced-motion (animation is disabled in CSS).
export function ChartSkeleton({ height = 140 }) {
  return <div className="skeleton" style={{ height }} role="status" aria-label="Loading chart data…" />
}

export function KpiCard({ icon, label, value, sub, tone, loading }) {
  return (
    <div className="stat-card">
      <div className={`stat-icon ${tone || 'primary'}`} aria-hidden="true">
        {icon}
      </div>
      <div>
        <div className="stat-value">
          {loading ? <span className="skeleton skeleton-value" aria-hidden="true" /> : value}
        </div>
        <div className="stat-label">{label}</div>
        {loading
          ? <span className="skeleton skeleton-sub" aria-hidden="true" />
          : sub && <div className="stat-change">{sub}</div>}
      </div>
    </div>
  )
}

// Horizontal bar list: items = [{label, count}]
export function HBars({ items, unit = '', color = 'var(--primary)', showPct = true, total }) {
  const max = Math.max(1, ...items.map((i) => i.count))
  const whole = total != null ? total : items.reduce((s, i) => s + i.count, 0)
  if (!items.length) return <div className="chart-placeholder">No data available for the selected period.</div>
  const ariaLabel = `Bar chart. ${items.map((i) => `${i.label}: ${i.count}${unit}`).join('; ')}.`
  return (
    <div className="hbars" role="img" aria-label={ariaLabel}>
      {items.map((item, idx) => (
        <div key={item.key ?? item.label} className="hbar-row">
          <div className="hbar-head">
            <span>{item.label}</span>
            <span className="hbar-count">
              <strong>{item.count}{unit}</strong>
              {showPct && whole > 0 ? ` • ${Math.round((item.count / whole) * 100)}%` : ''}
            </span>
          </div>
          <div className="hbar-track">
            <div
              className="hbar-fill"
              style={{
                width: `${(item.count / max) * 100}%`,
                background: Array.isArray(color) ? color[idx % color.length] : color
              }}
            />
          </div>
        </div>
      ))}
    </div>
  )
}

// 24-hour vertical bar chart (FR-M7-13 time-of-day trends)
export function HourBars({ counts, color = '#3b82f6', label = 'Reports by hour of day' }) {
  const max = Math.max(1, ...counts)
  const W = 100
  const H = 34
  const bw = W / 24
  return (
    <div>
      <svg viewBox={`0 0 ${W} ${H}`} style={{ width: '100%', height: 'auto' }} preserveAspectRatio="none" role="img" aria-label={label}>
        {counts.map((c, h) => {
          const bh = (c / max) * (H - 4)
          return (
            <rect
              key={h}
              className="hour-bar"
              x={h * bw + 0.4}
              y={H - bh}
              width={bw - 0.8}
              height={bh}
              rx={0.8}
              fill={color}
              opacity={c === 0 ? 0.15 : 0.85}
            >
              <title>{`${String(h).padStart(2, '0')}:00 — ${c}`}</title>
            </rect>
          )
        })}
      </svg>
      <div className="chart-axis-labels">
        {[0, 4, 8, 12, 16, 20, 23].map((h) => (
          <span key={h}>{String(h).padStart(2, '0')}:00</span>
        ))}
      </div>
    </div>
  )
}

// Simple SVG area/line trend: points = [{key, count}]
export function LineTrend({ points, color = '#3b82f6', height = 120, suffix = '' }) {
  if (!points.length) return <div className="chart-placeholder">No data available.</div>
  const W = 100
  const H = 40
  const max = Math.max(1, ...points.map((p) => p.count))
  const step = points.length > 1 ? W / (points.length - 1) : W
  const coords = points.map((p, i) => [i * step, H - 4 - (p.count / max) * (H - 8)])
  const line = coords.map(([x, y]) => `${x.toFixed(2)},${y.toFixed(2)}`).join(' ')
  const area = `0,${H} ${line} ${W},${H}`
  const peak = points.reduce((a, b) => (b.count > a.count ? b : a), points[0])
  return (
    <div>
      <div className="trend-headline">
        Peak: <strong>{peak.key}</strong> — {peak.count}{suffix}
      </div>
      <svg viewBox={`0 0 ${W} ${H}`} style={{ width: '100%', height }} preserveAspectRatio="none" role="img" aria-label={`Trend line, peak ${peak.count}${suffix} on ${peak.key}`}>
        <polygon points={area} fill={color} opacity="0.12" />
        <polyline points={line} fill="none" stroke={color} strokeWidth="0.8" strokeLinejoin="round" />
        {coords.map(([x, y], i) => (
          <circle key={i} cx={x} cy={y} r="0.9" fill={color}>
            <title>{`${points[i].key}: ${points[i].count}${suffix}`}</title>
          </circle>
        ))}
      </svg>
      <div className="chart-axis-labels">
        <span>{points[0]?.key}</span>
        <span>{points[Math.floor(points.length / 2)]?.key}</span>
        <span>{points[points.length - 1]?.key}</span>
      </div>
    </div>
  )
}

// Donut: items = [{label, count}]
export function Donut({ items, size = 150, thickness = 16 }) {
  const total = items.reduce((s, i) => s + i.count, 0)
  if (!total) return <div className="chart-placeholder">No data available for the selected period.</div>
  const r = (size - thickness) / 2
  const c = 2 * Math.PI * r
  let offset = 0
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: '18px', flexWrap: 'wrap' }}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} role="img" aria-label={`Donut chart. ${items.map((i) => `${i.label}: ${i.count}`).join('; ')}.`}>
        <g transform={`rotate(-90 ${size / 2} ${size / 2})`}>
          {items.map((item, idx) => {
            const frac = item.count / total
            const dash = frac * c
            const el = (
              <circle
                key={item.key ?? item.label}
                cx={size / 2}
                cy={size / 2}
                r={r}
                fill="none"
                stroke={PALETTE[idx % PALETTE.length]}
                strokeWidth={thickness}
                strokeDasharray={`${dash} ${c - dash}`}
                strokeDashoffset={-offset}
              >
                <title>{`${item.label}: ${item.count} (${Math.round(frac * 100)}%)`}</title>
              </circle>
            )
            offset += dash
            return el
          })}
        </g>
        <text x="50%" y="50%" textAnchor="middle" dy="0.35em" fontSize="20" fontWeight="700" fill="currentColor">
          {total}
        </text>
      </svg>
      <div className="donut-legend">
        {items.map((item, idx) => (
          <div key={item.label} className="donut-legend-row">
            <span className="legend-swatch" style={{ background: PALETTE[idx % PALETTE.length] }} />
            <span>{item.label}</span>
            <span className="donut-legend-count">{item.count} • {Math.round((item.count / total) * 100)}%</span>
          </div>
        ))}
      </div>
    </div>
  )
}

// FR-M7-04 spatial heatmap: bubbles positioned by each service area's
// lat/lng (normalised onto the canvas), sized/colored by issue count.
export function ServiceAreaHeatmap({ areas, selected, onSelect }) {
  const mapped = areas.filter((a) => a.latitude != null && a.longitude != null)
  if (!mapped.length) {
    return <div className="chart-placeholder">No active service areas with coordinates yet. Add them under Profile → Service Areas to enable the geographic heatmap.</div>
  }
  const max = Math.max(1, mapped.reduce((m, a) => Math.max(m, a.issueCount), 0))
  const W = 100
  const H = 60
  const PAD = 10
  // Project lat/lng into the viewBox; single point (or identical coords)
  // centres all bubbles.
  const lats = mapped.map((a) => a.latitude)
  const lngs = mapped.map((a) => a.longitude)
  const minLat = Math.min(...lats); const maxLat = Math.max(...lats)
  const minLng = Math.min(...lngs); const maxLng = Math.max(...lngs)
  const spanLat = maxLat - minLat
  const spanLng = maxLng - minLng
  const project = (a) => ({
    x: spanLng > 0 ? PAD + ((a.longitude - minLng) / spanLng) * (W - 2 * PAD) : W / 2,
    // higher latitude = higher on screen
    y: spanLat > 0 ? H - PAD - ((a.latitude - minLat) / spanLat) * (H - 2 * PAD) : H / 2,
  })
  const intensity = (c) => c / max
  const bubbleColor = (t) => (t > 0.66 ? '#ef4444' : t > 0.33 ? '#f59e0b' : '#10b981')
  const select = (a) => onSelect && onSelect(a)
  return (
    <div>
      <svg viewBox={`0 0 ${W} ${H}`} className="heatmap-svg" role="group" aria-label="Service area barrier heatmap. Select an area for its breakdown.">
        {/* geography grid */}
        {Array.from({ length: 9 }, (_, i) => (
          <line key={`v${i}`} x1={(i + 1) * 10} y1="0" x2={(i + 1) * 10} y2={H} stroke="rgba(148,163,184,0.12)" strokeWidth="0.25" />
        ))}
        {Array.from({ length: 5 }, (_, i) => (
          <line key={`h${i}`} x1="0" y1={(i + 1) * 10} x2={W} y2={(i + 1) * 10} stroke="rgba(148,163,184,0.12)" strokeWidth="0.25" />
        ))}
        <text x="2.5" y="5" fontSize="2.6" fill="rgba(148,163,184,0.7)">Service Areas — Barrier Density</text>
        {mapped.map((a) => {
          const { x, y } = project(a)
          const t = intensity(a.issueCount)
          const radius = 4 + 6 * Math.sqrt(t)
          const isSel = selected && selected.id === a.id
          return (
            <g
              key={a.id}
              className="heat-zone"
              role="button"
              tabIndex={0}
              aria-label={`${a.name}: ${a.issueCount} barriers, ${a.requestCount} assistance requests`}
              aria-pressed={Boolean(isSel)}
              onClick={() => select(a)}
              onKeyDown={(e) => {
                if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); select(a) }
              }}
            >
              <circle
                cx={x}
                cy={y}
                r={radius}
                fill={bubbleColor(t)}
                fillOpacity={isSel ? 0.85 : 0.55}
                stroke={isSel ? '#ffffff' : 'transparent'}
                strokeWidth="0.8"
              >
                <title>{`${a.name}${a.radiusM ? ` (r = ${a.radiusM} m)` : ''} — ${a.issueCount} barriers, ${a.requestCount} assistance requests`}</title>
              </circle>
              <text x={x} y={y + radius + 2.8} fontSize="2.4" textAnchor="middle" fill={isSel ? '#fff' : 'rgba(226,232,240,0.85)'}>
                {a.name}
              </text>
            </g>
          )
        })}
      </svg>
      <div className="heatmap-legend">
        <span className="legend-item"><span className="legend-dot" style={{ background: '#10b981' }} /> Low</span>
        <span className="legend-item"><span className="legend-dot" style={{ background: '#f59e0b' }} /> Medium</span>
        <span className="legend-item"><span className="legend-dot" style={{ background: '#ef4444' }} /> High density</span>
        <span className="heatmap-hint">Click an area for its breakdown</span>
      </div>
    </div>
  )
}
