# Requirement Changes — Module 7 (Analytics & Reporting) and Module 5 (Assistance)

> Date: 2026-08-29
> Scope: documents the agreed changes to the SRS functional requirements after the
> Module 7 data-feasibility review, and the schema/app changes that implement them.
> Companion schema: `server/supabase/migrations/004_analytics_reporting.sql`
> Companion seed data: `server/supabase/seed/` (mock data for demo/analysis)

## 1. Module 7 — Accessibility Analytics Dashboard and Reporting

### Amended requirements

| FR | Change | Implementation |
|---|---|---|
| FR-M7-04 | **Amended** — the heatmap is a *spatial* heatmap: each venue zone carries layout coordinates on the venue map, and bubble position/size/color reflect barrier density. Zone-level click-through shows categories, exact sample size and time-of-day trend (per UC701). | `venue_zones.map_x` / `map_y` (0–100 %), interactive SVG heatmap on the Accessibility Analytics page |
| FR-M7-08 | **Amended** — "first response time" is measured from request creation to the **first staff action**, stored as `acknowledged_at` (set once, on assignment or first staff chat message). | `assistance_requests.acknowledged_at`; web `assistanceRepository.maybeSetAcknowledgedAt()` |
| FR-M7-11 | **Amended** — report generation covers five report types (accessibility, assistance performance, queue service, communication usage, platform adoption) and saves each export. | `generated_reports` table, Report Generation page |
| FR-M7-12 | **Amended** — export formats are **PDF and CSV** (Excel `.xlsx` option dropped for scope). Anonymization is applied before preview/export: traveller identities are never included — aggregates and request codes only (UC702). | Client-side CSV (Blob download), PDF via `jspdf`/`jspdf-autotable` |
| FR-M7-15 | **Amended** — SLA limits are configurable per institution (with optional per-zone override) instead of being implicit. | `sla_configs` table (default 5 min response / 60 min resolution); SLA Compliance card on the Performance page |

### Confirmed-supported requirements (data already captured, no schema change)

| FR | Note |
|---|---|
| FR-M7-09 / FR-M7-10 | Resolution, unresolved and repeated-request rates and zone comparison computed from `assistance_requests`. Zone satisfaction comparison reads `user_rating`. |
| FR-M7-10 / FR-M7-17 | Satisfaction data is already captured by the mobile app's post-resolution flow (5-star rating + outcome, per FR-M5-16/FR-M5-26 code path): `assistance_requests.user_rating`, `resolution_outcome`, `user_feedback_comment`. Dashboard now visualises it (distribution + monthly trend). |
| FR-M7-14 | Every percentage shown on the dashboard is accompanied by its exact sample size (n). |

### Removed / descoped requirements

| FR | Decision | Reason |
|---|---|---|
| FR-M7-16 (Staff performance metrics) | **REMOVED** | Per project decision — staff-level performance ranking is out of scope. The Performance page's staff leaderboard was replaced by the zone comparison table (FR-M7-10). `assigned_staff_name` remains only as operational data on requests. |
| FR-M7-18 (Announcement send/receive/read analytics) | **DESCOPED to send-count only** | Per project decision — no announcement delivery log will be built. Receive/read counts and read rates are not measurable; only announcement volume and `reach_count` exist. |

### New requirements (cross-module analyses added to Module 7)

| FR | Requirement | Data source | Where |
|---|---|---|---|
| FR-M7-19 | The system shall correlate confirmed accessibility issues with assistance demand per zone and flag "double-jeopardy" hotspots (above-median on both) to prioritise fixes. | `accessibility_issue_reports` + `assistance_requests` joined on `location_zone` | Accessibility page — Hotspot Correlation table |
| FR-M7-20 | The system shall display the distribution of travellers' preferred contact/communication modes across assistance requests. | `assistance_requests.preferred_communication` | Usage Insights (profile preference) + reports |
| FR-M7-21 | The system shall analyse queue service patterns: average and 95th-percentile wait per line, abandonment rate, and arrival peaks by time of day. | `queue_numbers` (`created_at → called_at → completed_at`), `queue_lines` | Usage Insights — Queue Service Analytics |
| FR-M7-22 | The system shall analyse accessible communication usage: session volume trend, traveller input-modality mix (sign/speech/typed/quick phrase) and translation direction ratio (EN→MS vs EN→ZH). | `communication_dialogue_sessions`, `communication_dialogue_messages` | Usage Insights — Accessible Communication Usage |
| FR-M7-23 | The system shall display aggregate platform adoption analytics: total users split traveller/institution, monthly sign-up trend, primary-language mix and communication-preference mix. **Aggregate counts only — no personal data or user lists.** | `get_user_analytics()` SECURITY DEFINER function (RLS on `user_profiles` only allows own-profile reads) | Usage Insights — Platform Users & Adoption |

### Data-integrity rules applied to all Module 7 analytics

- **FR-M7-07 separation**: dashboards count *confirmed* issue reports and *consented* assistance requests only (`analytics_consent = true`; UC504 A2 declined-consent rows are excluded from institution analytics).
- **FR-M7-06 low-sample protection**: when a sample size is below 5 (`LOW_SAMPLE_MIN` in `web/src/lib/analytics.js`), percentages are hidden and a warning is displayed instead.
- **FR-M7-14 transparency**: exact n is displayed next to every percentage.

## 2. Module 5 — Institutional Assistance Request and Response

| Change | Detail | Status |
|---|---|---|
| Traveller identity from authenticated user | Requested change (replace hardcoded `'Jeff Wong'` in `assistance_request_viewmodel.dart`, `assistance_repository.dart` chat sender, and `accessibility_issue_reports` insert) **requires working mobile authentication.** Review found mobile sign-in is currently a mock UI (`authentication_view.dart` navigates to `/home` without calling Supabase auth). | **DEFERRED** — agreed to implement mobile auth later. The database is already ready: `assistance_requests.user_id`, `accessibility_issue_reports.user_id` and the `user_profiles` table exist. When auth lands, wire `supabase.auth.currentUser.id` + `user_profiles.full_name` into the three call sites and delete the hardcoded strings. |
| Post-resolution satisfaction rating | The mobile app already collects outcome + 5-star rating + comment after resolution (`submitResolutionFeedback` → `resolution_outcome`, `user_rating`, `user_feedback_comment`), satisfying the data capture needed by FR-M7-10/17. | Already implemented (no change) |
| First-response timestamp | No traveller-side change; `acknowledged_at` is stamped by the staff dashboard on assignment or first staff chat reply. | Implemented (Module 7 dependency) |

## 3. Known gaps / future work

- **Module 6 (SOS)**: no SOS request table exists in the database yet (only `emergency_contacts`), so no SOS analytics are possible. Future work once the SOS backend is built.
- **Sign-dictionary search analytics**: `dictionary_search_history` exists in the migration file but not in the live database, and the app never records searches. Zero-result-search analysis requires new capture (not in scope).
- **Traveller-to-institution link**: travellers are platform-wide (no `institution_id` on `user_profiles`), so user analytics are system-wide; per-institution breakdown exists only for staff counts.
- **Mobile Gradle/AGP/Kotlin warnings**: Flutter will soon require Gradle ≥ 9.1.0, AGP ≥ 9.0.1, Kotlin ≥ 2.3.20. Not urgent; upgrade before the next Flutter upgrade.

## 4. Files changed

| Area | Files |
|---|---|
| Database | `server/supabase/migrations/004_analytics_reporting.sql`; seed scripts `server/supabase/seed/01…05.sql` + `README.md` |
| Web – data | `src/lib/analytics.js` (new), `src/repositories/analyticsRepository.js` (new), `src/repositories/assistanceRepository.js` (acknowledged_at), `src/repositories/announcementRepository.js` (zone coords) |
| Web – UI | `src/components/charts.jsx` (new), `src/components/Tabs.jsx` (new), `src/lib/exporter.js` (new — shared CSV/PDF export used by every analytics tab and the Reports page), `src/pages/AnalyticsPage.jsx`, `src/pages/ServicePerformancePage.jsx`, `src/pages/UsageInsightsPage.jsx` (new), `src/pages/ReportGenerationPage.jsx`, `src/pages/StaffChatPage.jsx` (staff name fix), `src/App.jsx` (route + sidebar), `src/index.css` (spinner + tab styles) |
| Dependency | `jspdf`, `jspdf-autotable` (PDF export; loaded via dynamic import) |
| Mobile | none (by decision) |
