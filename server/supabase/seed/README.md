# TravelEase Mock Data Seed Scripts

Synthetic demo data for the Module 7 (Accessibility Analytics Dashboard and Reporting)
analytics, so charts and reports have realistic results to display. The data models
realistic patterns (morning/evening peaks, zone hotspots, rating skews, SLA breaches)
in the style of public service-request datasets such as NYC 311.

**All rows are tagged with a marker (`SEED-` code prefix / `@seed.travelease.dev` email /
`{"seeded": true}` event detail), so every script is idempotent — running it again
removes the previous run and re-seeds. Real user data is never deleted.**

## Run order (run each file against the Supabase SQL editor / MCP `execute_sql`)

| Order | File | What it seeds |
|---|---|---|
| 1 | `01_users_zones_sla.sql` | ~80 demo auth users + `user_profiles`, 4 extra `institution_staff`, 3 extra `venue_zones` + layout coordinates for all zones, default + per-zone `sla_configs` |
| 2 | `02_assistance.sql` | ~520 `assistance_requests` (+ chat messages) and ~210 `accessibility_issue_reports` over ~180 days |
| 3 | `03_queue.sql` | ~400 historical `queue_numbers` + matching `queue_events` across all queue lines |
| 4 | `04_communication.sql` | ~160 `communication_dialogue_sessions` + ~1,200 `communication_dialogue_messages` |
| 5 | `05_metrics.sql` | Regenerates the `analytics_daily_metrics` rollup from all request/issue rows |

`05_metrics.sql` **replaces** all rows in `analytics_daily_metrics` (it is a derived
cache, safe to rebuild).

## Markers used for idempotent cleanup

| Table | Seed marker |
|---|---|
| `auth.users`, `auth.identities`, `user_profiles` | email ends `@seed.travelease.dev` |
| `assistance_requests` / `accessibility_issue_reports` | `request_code` / `report_code` starts `SEED-` |
| `queue_numbers` / `queue_events` | event `details -> 'seeded' = true` |
| `communication_dialogue_sessions` | `session_code` starts `SEED-` |
| `institution_staff`, `venue_zones`, `sla_configs` | inserted only when the name/code does not already exist |

## Notes

- Demo accounts share the password `SeedDemo!2026` (bcrypt-hashed). They are for
  analytics volume only — do not use them as real logins.
- `assistance_requests.acknowledged_at`, `response_time_seconds` and
  `resolution_time_seconds` are populated so FR-M7-08 / FR-M7-15 first-response and
  SLA analytics work; ~10% of requests deliberately breach the SLA limits.
- Timestamps are generated so that Malaysia-time (UTC+8) hour-of-day charts show
  realistic morning (7–11am) and evening (5–9pm) peaks.
- `analytics_consent` is true for ~90% of seeded requests; institution-facing
  dashboards only count consented rows (FR-M7-07 / UC504 A2).
- Requires migration `004_analytics_reporting.sql` to be applied first
  (`map_x`/`map_y`, `acknowledged_at`, `sla_configs`, `generated_reports`).
