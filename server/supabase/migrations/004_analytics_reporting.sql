-- 004: Module 7 — Accessibility Analytics Dashboard and Reporting schema additions
--
-- FR-M7-04  : spatial heatmap  -> venue_zones.map_x / map_y (position on venue layout, 0-100)
-- FR-M7-08  : avg first response time -> assistance_requests.acknowledged_at
--              (set by the web dashboard on the first staff action: assignment or first staff chat message)
-- FR-M7-11/12: generated report records -> generated_reports
-- FR-M7-15  : response / resolution SLA limits per institution/zone -> sla_configs
-- FR-M7-10/17: satisfaction analytics read existing assistance_requests.user_rating (no schema change)

-- ---------------------------------------------------------------------------
-- 1. Venue zone layout coordinates (percentages of the venue map, 0-100)
-- ---------------------------------------------------------------------------
ALTER TABLE public.venue_zones
  ADD COLUMN IF NOT EXISTS map_x numeric(5, 2),
  ADD COLUMN IF NOT EXISTS map_y numeric(5, 2);

-- ---------------------------------------------------------------------------
-- 2. First staff response timestamp
-- ---------------------------------------------------------------------------
ALTER TABLE public.assistance_requests
  ADD COLUMN IF NOT EXISTS acknowledged_at timestamptz;

-- ---------------------------------------------------------------------------
-- 3. SLA configuration (FR-M7-15)
--    zone_id NULL = institution-wide default; a zone row overrides the default.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.sla_configs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id uuid NOT NULL REFERENCES public.institutions (id) ON DELETE CASCADE,
  zone_id uuid REFERENCES public.venue_zones (id) ON DELETE CASCADE,
  response_limit_minutes integer NOT NULL DEFAULT 5 CHECK (response_limit_minutes > 0),
  resolution_limit_minutes integer NOT NULL DEFAULT 60 CHECK (resolution_limit_minutes > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

-- zone_id is nullable, so a plain UNIQUE(institution_id, zone_id) would not
-- dedupe NULL rows; coalesce into a sentinel for the uniqueness check.
CREATE UNIQUE INDEX IF NOT EXISTS sla_configs_institution_zone_key
  ON public.sla_configs (
    institution_id,
    COALESCE(zone_id, '00000000-0000-0000-0000-000000000000'::uuid)
  );

-- ---------------------------------------------------------------------------
-- 4. Generated reports (FR-M7-11 / FR-M7-12)
--    data_snapshot stores the aggregated report payload so history rows can be
--    re-downloaded without recomputing. traveler identities are never stored
--    here (anonymization per UC702).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.generated_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  institution_id uuid NOT NULL REFERENCES public.institutions (id) ON DELETE CASCADE,
  report_title text NOT NULL,
  report_type text NOT NULL CHECK (report_type IN (
    'accessibility', 'assistance_performance', 'queue_service', 'communication_usage', 'users'
  )),
  date_from date NOT NULL,
  date_to date NOT NULL,
  zone_filter text NOT NULL DEFAULT 'all',
  format text NOT NULL CHECK (format IN ('pdf', 'csv')),
  data_snapshot jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by uuid REFERENCES auth.users (id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 5. RLS — mirror the institution-account pattern used by announcements /
--    queue_lines (is_institution_account checks the signed-in account owns
--    the institution). These tables are dashboard-only (web, authenticated).
-- ---------------------------------------------------------------------------
ALTER TABLE public.sla_configs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.generated_reports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Institution accounts manage sla_configs" ON public.sla_configs;
CREATE POLICY "Institution accounts manage sla_configs"
  ON public.sla_configs
  FOR ALL
  TO authenticated
  USING (is_institution_account(institution_id))
  WITH CHECK (is_institution_account(institution_id));

DROP POLICY IF EXISTS "Institution accounts manage generated_reports" ON public.generated_reports;
CREATE POLICY "Institution accounts manage generated_reports"
  ON public.generated_reports
  FOR ALL
  TO authenticated
  USING (is_institution_account(institution_id))
  WITH CHECK (is_institution_account(institution_id));

-- ---------------------------------------------------------------------------
-- 6. Aggregate-only user analytics (FR-M7-23)
--    user_profiles RLS only allows reading one's own profile, so the dashboard
--    cannot aggregate rows client-side. This function exposes COUNTS ONLY
--    (no personal data) to signed-in institution accounts.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_user_analytics()
RETURNS TABLE (
  total_users bigint,
  travellers bigint,
  institution_users bigint,
  signups jsonb,
  language_mix jsonb,
  comm_pref_mix jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO public
AS $$
  SELECT
    count(*),
    count(*) FILTER (WHERE user_type = 'traveller'),
    count(*) FILTER (WHERE user_type = 'institution'),
    COALESCE((
      SELECT jsonb_agg(jsonb_build_object('month', m, 'count', c) ORDER BY m)
      FROM (SELECT to_char(date_trunc('month', created_at), 'YYYY-MM') AS m, count(*) AS c
            FROM public.user_profiles GROUP BY 1) s
    ), '[]'::jsonb),
    COALESCE((
      SELECT jsonb_agg(jsonb_build_object('key', k, 'count', c) ORDER BY c DESC)
      FROM (SELECT COALESCE(primary_language, 'unknown') AS k, count(*) AS c
            FROM public.user_profiles GROUP BY 1) s
    ), '[]'::jsonb),
    COALESCE((
      SELECT jsonb_agg(jsonb_build_object('key', k, 'count', c) ORDER BY c DESC)
      FROM (SELECT COALESCE(preferred_communication, 'unspecified') AS k, count(*) AS c
            FROM public.user_profiles GROUP BY 1) s
    ), '[]'::jsonb)
  FROM public.user_profiles;
$$;

REVOKE EXECUTE ON FUNCTION public.get_user_analytics() FROM anon, public;
GRANT EXECUTE ON FUNCTION public.get_user_analytics() TO authenticated;
