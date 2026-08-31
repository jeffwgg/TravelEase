-- ============================================================================
-- TravelEase: Migration 008
-- Institution accounts may update their venue location columns
-- Fixes "permission denied for table institutions" from the temporary
-- location test section on the web Announcement page: the authenticated role
-- had no UPDATE privilege on public.institutions. The grant is column-scoped
-- to exactly the location fields, and migration 007's policy still restricts
-- updates to the institution's own active row. Run in the Supabase SQL editor
-- together with migration 007.
-- ============================================================================

GRANT UPDATE (latitude, longitude, location_match_radius_m)
    ON public.institutions TO authenticated;
