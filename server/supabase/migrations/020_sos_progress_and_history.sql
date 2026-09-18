-- Extends existing SOS records; no new tables and no request backfill.
-- Apply after 019. Requires existing institution_staff(auth_user_id, active,
-- institution_id, name, contact_number), institutions(account_user_id), and the
-- existing SOS status/timestamp columns used by the institution web app.
begin;

alter table public.sos_requests
  add column if not exists assigned_staff_id uuid;
do $$
begin
  if not exists (select 1 from pg_constraint
    where conrelid = 'public.sos_requests'::regclass and contype = 'f'
      and confrelid = 'public.institution_staff'::regclass
      and conkey = array[(select attnum from pg_attribute
        where attrelid = 'public.sos_requests'::regclass and attname = 'assigned_staff_id')]
  ) then
    alter table public.sos_requests add constraint sos_requests_assigned_staff_id_fkey
      foreign key (assigned_staff_id) references public.institution_staff(id) on delete set null;
  end if;
end $$;
create index if not exists sos_requests_traveller_time_idx
  on public.sos_requests(traveller_id, triggered_at desc);
create index if not exists sos_requests_assigned_staff_idx
  on public.sos_requests(assigned_staff_id);

-- Replace only a single-column status CHECK, preserving unrelated constraints.
do $$
declare c record;
begin
  for c in select conname from pg_constraint
    where conrelid = 'public.sos_requests'::regclass and contype = 'c'
      and conkey = array[(select attnum from pg_attribute
        where attrelid = 'public.sos_requests'::regclass and attname = 'status')]
  loop
    execute format('alter table public.sos_requests drop constraint %I', c.conname);
  end loop;
end $$;
alter table public.sos_requests add constraint sos_requests_status_check
  check (status in ('sent', 'acknowledged', 'assigned', 'en_route', 'resolved'));

-- Central membership check avoids recursive staff/institution RLS joins.
create or replace function public.can_manage_sos_institution(p_institution_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null and (
    exists (select 1 from public.institutions i
      where i.id = p_institution_id and i.account_user_id = auth.uid())
    or exists (select 1 from public.institution_staff s
      where s.institution_id = p_institution_id
        and s.auth_user_id = auth.uid() and s.active = true)
  );
$$;
revoke all on function public.can_manage_sos_institution(uuid) from public, anon;
grant execute on function public.can_manage_sos_institution(uuid) to authenticated;

alter table public.sos_requests enable row level security;
-- Restrictive policies bound any older permissive policies as well.
drop policy if exists sos_history_read_boundary on public.sos_requests;
create policy sos_history_read_boundary on public.sos_requests
  as restrictive for select to authenticated
  using (traveller_id = (select auth.uid())
    or public.can_manage_sos_institution(institution_id));
drop policy if exists sos_history_read on public.sos_requests;
create policy sos_history_read on public.sos_requests for select to authenticated
  using (traveller_id = (select auth.uid())
    or public.can_manage_sos_institution(institution_id));
drop policy if exists sos_progress_update_boundary on public.sos_requests;
create policy sos_progress_update_boundary on public.sos_requests
  as restrictive for update to authenticated
  using (public.can_manage_sos_institution(institution_id))
  with check (public.can_manage_sos_institution(institution_id));
drop policy if exists sos_progress_update on public.sos_requests;
create policy sos_progress_update on public.sos_requests for update to authenticated
  using (public.can_manage_sos_institution(institution_id))
  with check (public.can_manage_sos_institution(institution_id));
drop policy if exists sos_owner_insert_boundary on public.sos_requests;
create policy sos_owner_insert_boundary on public.sos_requests
  as restrictive for insert to authenticated
  with check (traveller_id = (select auth.uid()) and status = 'sent'
    and assigned_staff_id is null);
drop policy if exists sos_owner_insert on public.sos_requests;
create policy sos_owner_insert on public.sos_requests for insert to authenticated
  with check (traveller_id = (select auth.uid()) and status = 'sent'
    and assigned_staff_id is null);
revoke all on public.sos_requests from anon;
grant select, insert on public.sos_requests to authenticated;
grant update(status, assigned_staff_id) on public.sos_requests to authenticated;

-- Validate all writers, including direct REST updates, not just the web UI.
create or replace function public.validate_sos_progress()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'UPDATE' then
    if new.traveller_id is distinct from old.traveller_id
      or new.institution_id is distinct from old.institution_id
      or new.service_area_id is distinct from old.service_area_id
      or new.triggered_at is distinct from old.triggered_at then
      raise exception 'SOS ownership, service area and trigger time are immutable';
    end if;
    if new.status is distinct from old.status and not (
      (old.status = 'sent' and new.status = 'acknowledged') or
      (old.status = 'acknowledged' and new.status in ('assigned', 'resolved')) or
      (old.status = 'assigned' and new.status in ('en_route', 'resolved')) or
      (old.status = 'en_route' and new.status = 'resolved')
    ) then
      raise exception 'Invalid SOS transition: % -> %', old.status, new.status;
    end if;
    if new.assigned_staff_id is distinct from old.assigned_staff_id
      and new.assigned_staff_id is not null
      and new.status not in ('assigned', 'en_route') then
      raise exception 'Staff can only be assigned to an ongoing acknowledged SOS';
    end if;
  end if;
  if tg_op = 'INSERT' and not exists (
    select 1 from public.service_areas a where a.id = new.service_area_id
      and a.institution_id = new.institution_id and a.active = true
  ) then raise exception 'SOS service area does not belong to the institution'; end if;
  if new.assigned_staff_id is not null and (
    tg_op = 'INSERT' or new.assigned_staff_id is distinct from old.assigned_staff_id
  ) and not exists (
    select 1 from public.institution_staff s where s.id = new.assigned_staff_id
      and s.institution_id = new.institution_id and s.active = true
  ) then raise exception 'Assigned staff must be active in the SOS institution'; end if;
  -- Allow a historical assignee to be deleted (FK SET NULL); require an assignee
  -- when entering the assigned/on-the-way stages.
  if new.status in ('assigned', 'en_route') and new.assigned_staff_id is null
    and (tg_op = 'INSERT' or new.status is distinct from old.status) then
    raise exception 'Assign a staff member before advancing the SOS';
  end if;
  if tg_op = 'UPDATE' then
    new.acknowledged_at := old.acknowledged_at;
    new.resolved_at := old.resolved_at;
    if old.status = 'sent' and new.status = 'acknowledged' then
      new.acknowledged_at := coalesce(old.acknowledged_at, now());
    end if;
    if old.status <> 'resolved' and new.status = 'resolved' then
      new.resolved_at := now();
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.validate_sos_progress() from public, anon, authenticated;
drop trigger if exists validate_sos_progress on public.sos_requests;
create trigger validate_sos_progress before insert or update on public.sos_requests
  for each row execute function public.validate_sos_progress();

-- Staff directory access remains institution-scoped. Travellers get only the
-- assigned name/work contact via the owner-checked history function below.
alter table public.institution_staff enable row level security;
drop policy if exists sos_staff_directory_boundary on public.institution_staff;
create policy sos_staff_directory_boundary on public.institution_staff
  as restrictive for select to authenticated
  using (auth_user_id = (select auth.uid())
    or public.can_manage_sos_institution(institution_id));
drop policy if exists sos_staff_directory on public.institution_staff;
create policy sos_staff_directory on public.institution_staff for select to authenticated
  using (public.can_manage_sos_institution(institution_id));

-- Matching needs active service areas, but not private institution profiles.
alter table public.service_areas enable row level security;
drop policy if exists sos_active_service_areas on public.service_areas;
create policy sos_active_service_areas on public.service_areas for select to authenticated
  using (active = true);
grant select on public.service_areas to authenticated;

-- This projection bypasses joins blocked by institution/staff RLS without
-- granting travellers SELECT on private institution or staff directory rows.
-- Both sides are explicitly owner-filtered; there is no caller-supplied owner.
create or replace function public.get_traveller_sos_history()
returns setof jsonb language sql stable security definer set search_path = '' as $$
  with owned_requests as (
    select r.*, i.name as institution_name, a.name as service_area_name,
      s.name as staff_name,
      case when r.status <> 'resolved' and s.active then s.contact_number end as staff_contact
    from public.sos_requests r
    left join public.institutions i on i.id = r.institution_id
    left join public.service_areas a on a.id = r.service_area_id
      and a.institution_id = r.institution_id
    left join public.institution_staff s on s.id = r.assigned_staff_id
      and s.institution_id = r.institution_id
    where r.traveller_id = auth.uid()
  ), owned_events as (
    select e.* from public.traveller_sos_events e where e.traveller_id = auth.uid()
  ), history as (
    select jsonb_build_object(
      'id', coalesce(r.id, e.id),
      'triggered_at', coalesce(r.triggered_at, e.triggered_at),
      'ended_at', e.ended_at, 'status', coalesce(e.status, 'unknown'),
      'latitude', coalesce(r.latitude, e.latitude),
      'longitude', coalesce(r.longitude, e.longitude),
      'institution_name', coalesce(r.institution_name, e.institution_name),
      'service_area_name', coalesce(r.service_area_name, e.service_area_name),
      'institution_status', case when r.id is not null then 'requestSent' else e.institution_status end,
      'institution_attempted_at', coalesce(r.triggered_at, e.institution_attempted_at),
      'contact_name', e.contact_name, 'contact_status', coalesce(e.contact_status, 'notRecorded'),
      'contact_attempted_at', e.contact_attempted_at,
      'request', case when r.id is null then null else jsonb_build_object(
        'id', r.id, 'status', r.status, 'acknowledged_at', r.acknowledged_at,
        'resolved_at', r.resolved_at, 'staff_name', r.staff_name, 'staff_contact', r.staff_contact
      ) end
    ) as entry, coalesce(r.triggered_at, e.triggered_at) as event_time
    from owned_requests r
    -- At most one metadata event per request. Prefer actual contact metadata
    -- over any legacy backfilled snapshot. A timestamp match covers a failed
    -- client-side link write after successful institution request creation.
    left join lateral (
      select e.* from owned_events e where e.sos_request_id = r.id
        or (e.sos_request_id is null and e.triggered_at = r.triggered_at)
      order by e.contact_attempted_at desc nulls last, e.id limit 1
    ) e on true
    union all
    select jsonb_build_object(
      'id', e.id, 'triggered_at', e.triggered_at, 'ended_at', e.ended_at,
      'status', e.status, 'latitude', e.latitude, 'longitude', e.longitude,
      'institution_name', e.institution_name, 'service_area_name', e.service_area_name,
      'institution_status', e.institution_status, 'institution_attempted_at', e.institution_attempted_at,
      'contact_name', e.contact_name, 'contact_status', e.contact_status,
      'contact_attempted_at', e.contact_attempted_at, 'request', null
    ), e.triggered_at from owned_events e
    where not exists (select 1 from owned_requests r where r.id = e.sos_request_id
      or (e.sos_request_id is null and r.triggered_at = e.triggered_at))
  ) select entry from history order by event_time desc, entry->>'id';
$$;
revoke all on function public.get_traveller_sos_history() from public, anon;
grant execute on function public.get_traveller_sos_history() to authenticated;

notify pgrst, 'reload schema';
commit;
