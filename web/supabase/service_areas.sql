-- Institution-owned geographic service coverage. This does not alter venue_zones.
create extension if not exists pgcrypto;

create table if not exists public.service_areas (
  id uuid primary key default gen_random_uuid(),
  institution_id uuid not null references public.institutions(id) on delete cascade,
  name text not null,
  address text,
  latitude double precision not null,
  longitude double precision not null,
  radius_m integer not null,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint service_areas_name_check check (char_length(btrim(name)) between 2 and 120),
  constraint service_areas_address_check check (address is null or char_length(address) <= 500),
  constraint service_areas_latitude_check check (latitude between -90 and 90),
  constraint service_areas_longitude_check check (longitude between -180 and 180),
  constraint service_areas_radius_check check (radius_m between 1 and 50000)
);

create index if not exists service_areas_institution_id_idx on public.service_areas(institution_id);
create index if not exists service_areas_active_idx on public.service_areas(active) where active = true;

create or replace function public.set_service_areas_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin new.updated_at = now(); return new; end;
$$;
drop trigger if exists set_service_areas_updated_at_trigger on public.service_areas;
create trigger set_service_areas_updated_at_trigger before update on public.service_areas
for each row execute function public.set_service_areas_updated_at();

alter table public.service_areas enable row level security;

drop policy if exists "Institution users can view own service areas" on public.service_areas;
create policy "Institution users can view own service areas" on public.service_areas
for select to authenticated using (exists (
  select 1 from public.institutions i
  where i.id = service_areas.institution_id and i.account_user_id = (select auth.uid())
));

drop policy if exists "Institution users can create own service areas" on public.service_areas;
create policy "Institution users can create own service areas" on public.service_areas
for insert to authenticated with check (exists (
  select 1 from public.institutions i
  where i.id = service_areas.institution_id and i.account_user_id = (select auth.uid())
));

drop policy if exists "Institution users can update own service areas" on public.service_areas;
create policy "Institution users can update own service areas" on public.service_areas
for update to authenticated using (exists (
  select 1 from public.institutions i
  where i.id = service_areas.institution_id and i.account_user_id = (select auth.uid())
)) with check (exists (
  select 1 from public.institutions i
  where i.id = service_areas.institution_id and i.account_user_id = (select auth.uid())
));

drop policy if exists "Institution users can delete own service areas" on public.service_areas;
create policy "Institution users can delete own service areas" on public.service_areas
for delete to authenticated using (exists (
  select 1 from public.institutions i
  where i.id = service_areas.institution_id and i.account_user_id = (select auth.uid())
));

revoke all on public.service_areas from anon;
grant select, insert, update, delete on public.service_areas to authenticated;
