-- Institution staff may optionally set an end time for a broadcast. Clients
-- exclude rows once this time has passed while preserving the row for the
-- institution's announcement history.
alter table public.announcements
  add column if not exists expires_at timestamptz;

create index if not exists announcements_active_expiry_idx
  on public.announcements (institution_id, expires_at)
  where status = 'active';
