// Pill-style tab row used by the analytics pages. `actions` renders on the
// right side (typically the per-tab export buttons).
export default function Tabs({ tabs, active, onChange, actions }) {
  return (
    <div className="tab-row">
      <div className="tab-list" role="tablist">
        {tabs.map((t) => (
          <button
            key={t.key}
            role="tab"
            aria-selected={active === t.key}
            className={`tab-btn ${active === t.key ? 'active' : ''}`}
            onClick={() => onChange(t.key)}
          >
            {t.icon}
            {t.label}
          </button>
        ))}
      </div>
      {actions && <div className="tab-actions">{actions}</div>}
    </div>
  )
}
