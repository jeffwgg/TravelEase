-- ============================================================================
-- TravelEase: Migration 009
-- Queue line prefixes are unique per institution
-- Staff must not create two queue lines with the same prefix, otherwise
-- queue numbers (prefix-number) become ambiguous between lines. The web
-- console and the create-queue-line edge function also validate this; the
-- constraint is the final guard. Run in the Supabase SQL editor.
-- NOTE: fails if existing rows already share a prefix within one
-- institution. Live data was verified duplicate-free before writing this.
-- ============================================================================

ALTER TABLE public.queue_lines
    ADD CONSTRAINT queue_lines_institution_id_prefix_key
    UNIQUE (institution_id, prefix);
