-- One event per active SOS, including events with no location/institution.
-- Contact status records the existing send-sos-contact function's outcome;
-- it is not a delivery/read receipt. Existing institution requests stay intact.
begin;

create table public.traveller_sos_events (
  id uuid primary key default gen_random_uuid(),
  traveller_id uuid not null references auth.users(id) on delete cascade,
  triggered_at timestamptz not null default now(),
  ended_at timestamptz,
  status text not null default 'active' check (status in ('active', 'ended', 'unknown')),
  latitude double precision,
  longitude double precision,
  sos_request_id uuid references public.sos_requests(id) on delete set null,
  institution_name text,
  service_area_name text,
  institution_status text not null default 'pending',
  contact_name text,
  contact_status text not null default 'pending',
  contact_attempted_at timestamptz,
  institution_attempted_at timestamptz,
  unique (traveller_id, triggered_at)
);
create index traveller_sos_events_owner_time
  on public.traveller_sos_events (traveller_id, triggered_at desc);
alter table public.traveller_sos_events enable row level security;
revoke all on public.traveller_sos_events from anon;
grant select, insert, update on public.traveller_sos_events to authenticated;
create policy "Traveller reads own SOS history" on public.traveller_sos_events
  for select to authenticated using ((select auth.uid()) = traveller_id);
create policy "Traveller creates own SOS history" on public.traveller_sos_events
  for insert to authenticated with check (
    (select auth.uid()) = traveller_id and
    (sos_request_id is null or exists (
      select 1 from public.sos_requests r
      where r.id = sos_request_id and r.traveller_id = (select auth.uid())
    ))
  );
create policy "Traveller updates own SOS history" on public.traveller_sos_events
  for update to authenticated using ((select auth.uid()) = traveller_id)
  with check (
    (select auth.uid()) = traveller_id and
    (sos_request_id is null or exists (
      select 1 from public.sos_requests r
      where r.id = sos_request_id and r.traveller_id = (select auth.uid())
    ))
  );

-- Preserve existing institution-side policies; add traveller read access only.
alter table public.sos_requests enable row level security;
create policy "Traveller reads own institution SOS requests" on public.sos_requests
  for select to authenticated using ((select auth.uid()) = traveller_id);

-- Do not copy existing requests into this metadata table. Migration 020 reads
-- existing requests directly, including requests without an event row.

commit;
