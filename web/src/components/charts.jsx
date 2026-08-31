// Dependency-free chart primitives for the Module 7 analytics pages.
// Styled to reuse the existing card/stat CSS variables.

const PALETTE = ['#3b82f6', '#8b5cf6', '#f59e0b', '#10b981', '#ef4444', '#06b6d4', '#ec4899']

export function KpiCard({ icon, color = 'var(--primary)', label, value, sub, tone }) {
  return (
    <div className="stat-card">
      <div className={`stat-icon ${tone || 'primary'}`} style={{ color }}>
        {icon}
      </div>
      <div>
        <div className="stat-value">{value}</div>
        <div className="stat-label">{label}</div>
        {sub && <div className="stat-change">{sub}</div>}
      </div>
    </div>
  )
}

// Horizontal bar list: items = [{label, count}]
export function HBars({ items, unit = '', color = 'var(--primary)', showPct = true, total }) {
  const max = Math.max(1, ...items.map((i) => i.count))
  const whole = total != null ? total : items.reduce((s, i) => s + i.count, 0)
  if (!items.length) return <div className="chart-placeholder">No data available for the selected period.</div>
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: '10px' }}>
      {items.map((item, idx) => (
        <div key={item.key ?? item.label}>
          <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '13px', marginBottom: '4px' }}>
            <span>{item.label}</span>
            <span style={{ color: 'var(--text-muted, #64748b)' }}>
              <strong style={{ color: 'var(--text, inherit)' }}>{item.count}{unit}</strong>
              {showPct && whole > 0 ? ` • ${Math.round((item.count / whole) * 100)}%` : ''}
            </span>
          </div>
          <div style={{ height: '8px', background: 'rgba(100,116,139,0.15)', borderRadius: '4px', overflow: 'hidden' }}>
            <div style={{
              width: `${(item.count / max) * 100}%`,
              height: '100%',
              borderRadius: '4px',
              background: Array.isArray(color) ? color[idx % color.length] : color
            }} />
          </div>
        </div>
      ))}
    </div>
  )
}

// 24-hour vertical bar chart (FR-M7-13 time-of-day trends)
export function HourBars({ counts, color = '#3b82f6' }) {
  const max = Math.max(1, ...counts)
  const W = 100
  const H = 34
  const bw = W / 24
  return (
    <div>
      <svg viewBox={`0 0 ${W} ${H}`} style={{ width: '100%', height: 'auto' }} preserveAspectRatio="none">
        {counts.map((c, h) => {
          const bh = (c / max) * (H - 4)
          return (
            <rect
              key={h}
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
      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '10px', color: '#94a3b8', marginTop: '4px' }}>
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
  return (
    <div>
      <svg viewBox={`0 0 ${W} ${H}`} style={{ width: '100%', height }} preserveAspectRatio="none">
        <polygon points={area} fill={color} opacity="0.12" />
        <polyline points={line} fill="none" stroke={color} strokeWidth="0.8" strokeLinejoin="round" />
        {coords.map(([x, y], i) => (
          <circle key={i} cx={x} cy={y} r="0.9" fill={color}>
            <title>{`${points[i].key}: ${points[i].count}${suffix}`}</title>
          </circle>
        ))}
      </svg>
      <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: '10px', color: '#94a3b8', marginTop: '4px' }}>
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
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`}>
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
      <div style={{ display: 'flex', flexDirection: 'column', gap: '6px', fontSize: '13px' }}>
        {items.map((item, idx) => (
          <div key={item.label} style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
            <span style={{ width: '10px', height: '10px', borderRadius: '3px', background: PALETTE[idx % PALETTE.length] }} />
            <span>{item.label}</span>
            <span style={{ color: '#64748b' }}>{item.count} • {Math.round((item.count / total) * 100)}%</span>
          </div>
        ))}
      </div>
    </div>
  )
}

// FR-M7-04 spatial heatmap: bubbles positioned by venue_zones.map_x/map_y
// (percent coordinates on the venue layout), sized/colored by issue count.
export function ZoneHeatmap({ zones, selected, onSelect }) {
  if (!zones.length) {
    return <div className="chart-placeholder">No zones have layout coordinates yet. Set map_x / map_y on venue zones to enable the spatial heatmap.</div>
  }
  const max = Math.max(1, ...zones.map((z) => z.issueCount))
  const W = 100
  const H = 60
  const intensity = (c) => c / max
  const bubbleColor = (t) => (t > 0.66 ? '#ef4444' : t > 0.33 ? '#f59e0b' : '#10b981')
  return (
    <div>
      <svg viewBox={`0 0 ${W} ${H}`} style={{ width: '100%', height: 'auto', background: '#1e293b', borderRadius: '10px' }}>
        {/* floorplan grid */}
        {Array.from({ length: 9 }, (_, i) => (
          <line key={`v${i}`} x1={(i + 1) * 10} y1="0" x2={(i + 1) * 10} y2={H} stroke="rgba(148,163,184,0.12)" strokeWidth="0.25" />
        ))}
        {Array.from({ length: 5 }, (_, i) => (
          <line key={`h${i}`} x1="0" y1={(i + 1) * 10} x2={W} y2={(i + 1) * 10} stroke="rgba(148,163,184,0.12)" strokeWidth="0.25" />
        ))}
        <text x="2.5" y="5" fontSize="2.6" fill="rgba(148,163,184,0.7)">Facility Layout — Barrier Density</text>
        {zones.map((z) => {
          const t = intensity(z.issueCount)
          const radius = 4 + 6 * Math.sqrt(t)
          const isSel = selected && selected.id === z.id
          return (
            <g key={z.id} onClick={() => onSelect && onSelect(z)} style={{ cursor: 'pointer' }}>
              <circle
                cx={z.x}
                cy={z.y}
                r={radius}
                fill={bubbleColor(t)}
                fillOpacity={isSel ? 0.85 : 0.55}
                stroke={isSel ? '#ffffff' : 'transparent'}
                strokeWidth="0.8"
              >
                <title>{`${z.name} — ${z.issueCount} barriers, ${z.requestCount} assistance requests`}</title>
              </circle>
              <text x={z.x} y={z.y + radius + 2.8} fontSize="2.4" textAnchor="middle" fill={isSel ? '#fff' : 'rgba(226,232,240,0.85)'}>
                {z.code}
              </text>
            </g>
          )
        })}
      </svg>
      <div style={{ display: 'flex', gap: '16px', fontSize: '12px', color: '#64748b', marginTop: '8px', alignItems: 'center' }}>
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: '5px' }}>
          <span style={{ width: '10px', height: '10px', borderRadius: '50%', background: '#10b981' }} /> Low
        </span>
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: '5px' }}>
          <span style={{ width: '10px', height: '10px', borderRadius: '50%', background: '#f59e0b' }} /> Medium
        </span>
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: '5px' }}>
          <span style={{ width: '10px', height: '10px', borderRadius: '50%', background: '#ef4444' }} /> High density
        </span>
        <span style={{ marginLeft: 'auto' }}>Click a zone for its breakdown</span>
      </div>
    </div>
  )
}
