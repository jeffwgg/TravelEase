-- 005: persist analytics consent for accessibility issue reports (FR-M5-27 / FR-M7-07)
--
-- The traveller-facing consent checkbox was mandatory in the UI but never
-- persisted. This adds the same opt-in column that assistance_requests
-- already has, so institution dashboards can respect consent on both data
-- types. Existing app-created rows keep the strict default (false = excluded
-- from institution analytics until resubmitted with consent).

ALTER TABLE public.accessibility_issue_reports
  ADD COLUMN IF NOT EXISTS analytics_consent boolean NOT NULL DEFAULT false;
