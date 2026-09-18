-- Apply after 021. Reuse sos_requests.assigned_staff_id and staff.status.
-- Existing conflicting assignments fail the unique index rather than silently
-- reassigning emergencies. Resolve those records before retrying this migration.
begin;

create or replace function public.can_manage_sos_institution(p_institution_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.institutions i
    where i.id = p_institution_id and i.account_user_id = auth.uid());
$$;

create or replace function public.is_assigned_sos_staff(p_institution_id uuid, p_staff_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.institution_staff s
    where s.id = p_staff_id and s.institution_id = p_institution_id
      and s.auth_user_id = auth.uid() and s.active and s.role = 'staff');
$$;
revoke all on function public.is_assigned_sos_staff(uuid, uuid) from public, anon;
grant execute on function public.is_assigned_sos_staff(uuid, uuid) to authenticated;

drop policy if exists sos_history_read_boundary on public.sos_requests;
create policy sos_history_read_boundary on public.sos_requests
  as restrictive for select to authenticated using (
    traveller_id = (select auth.uid())
    or public.can_manage_sos_institution(institution_id)
    or public.is_assigned_sos_staff(institution_id, assigned_staff_id));
drop policy if exists sos_history_read on public.sos_requests;
create policy sos_history_read on public.sos_requests for select to authenticated using (
    traveller_id = (select auth.uid())
    or public.can_manage_sos_institution(institution_id)
    or public.is_assigned_sos_staff(institution_id, assigned_staff_id));
drop policy if exists sos_progress_update_boundary on public.sos_requests;
create policy sos_progress_update_boundary on public.sos_requests
  as restrictive for update to authenticated
  using (public.can_manage_sos_institution(institution_id)
    or public.is_assigned_sos_staff(institution_id, assigned_staff_id))
  with check (public.can_manage_sos_institution(institution_id)
    or public.is_assigned_sos_staff(institution_id, assigned_staff_id));
drop policy if exists sos_progress_update on public.sos_requests;
create policy sos_progress_update on public.sos_requests for update to authenticated
  using (public.can_manage_sos_institution(institution_id)
    or public.is_assigned_sos_staff(institution_id, assigned_staff_id))
  with check (public.can_manage_sos_institution(institution_id)
    or public.is_assigned_sos_staff(institution_id, assigned_staff_id));
-- Prevent legacy DELETE policies from becoming an alternative to resolution.
drop policy if exists sos_no_client_delete on public.sos_requests;
create policy sos_no_client_delete on public.sos_requests
  as restrictive for delete to authenticated using (false);
revoke update, delete on public.sos_requests from authenticated;
grant update(status, assigned_staff_id) on public.sos_requests to authenticated;

-- The manager sees the directory; a responder can join their own work contact.
drop policy if exists sos_staff_directory on public.institution_staff;
create policy sos_staff_directory on public.institution_staff for select to authenticated
  using (auth_user_id = (select auth.uid()) or public.can_manage_sos_institution(institution_id));

create unique index if not exists sos_one_active_task_per_staff_idx
  on public.sos_requests(assigned_staff_id)
  where assigned_staff_id is not null and status in ('assigned', 'en_route');
update public.institution_staff s set status = 'assigned'
  where s.status is distinct from 'assigned' and exists (
    select 1 from public.sos_requests r where r.assigned_staff_id = s.id
      and r.status in ('assigned', 'en_route'));

-- Replace the existing validator, keeping a single assignment entry point.
create or replace function public.validate_sos_progress()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    if new.status <> 'sent' or new.assigned_staff_id is not null then
      raise exception 'New SOS requests must start at sent without an assignee';
    end if;
    if not exists (select 1 from public.service_areas a
      where a.id = new.service_area_id and a.institution_id = new.institution_id and a.active) then
      raise exception 'SOS service area does not belong to the institution';
    end if;
    new.acknowledged_at := null;
    new.resolved_at := null;
    return new;
  end if;

  if (to_jsonb(new) - array['status','assigned_staff_id','acknowledged_at','resolved_at','updated_at'])
    is distinct from (to_jsonb(old) - array['status','assigned_staff_id','acknowledged_at','resolved_at','updated_at']) then
    raise exception 'SOS details are immutable';
  end if;
  new.acknowledged_at := old.acknowledged_at;
  new.resolved_at := old.resolved_at;
  -- Keep ON DELETE SET NULL working for a historical responder only.
  if pg_trigger_depth() > 1 and old.status = 'resolved' and new.status = 'resolved'
    and new.assigned_staff_id is null then return new; end if;

  if new.status is not distinct from old.status then
    if new.assigned_staff_id is distinct from old.assigned_staff_id then
      raise exception 'Staff assignment can only change from acknowledged to assigned';
    end if;
    return new;
  end if;
  if not ((old.status = 'sent' and new.status = 'acknowledged')
    or (old.status = 'acknowledged' and new.status = 'assigned')
    or (old.status = 'assigned' and new.status = 'en_route')
    or (old.status = 'en_route' and new.status = 'resolved')) then
    raise exception 'Invalid SOS transition: % -> %', old.status, new.status;
  end if;

  if new.status in ('acknowledged', 'assigned') then
    if not public.can_manage_sos_institution(old.institution_id) then
      raise exception 'Only the institution manager can acknowledge or assign SOS requests';
    end if;
  else
    -- A manager account never performs responder actions, even if linked as staff.
    if public.can_manage_sos_institution(old.institution_id)
      or not public.is_assigned_sos_staff(old.institution_id, old.assigned_staff_id) then
      raise exception 'Only the assigned staff account can mark On The Way or Resolved';
    end if;
  end if;

  if new.status = 'assigned' then
    -- Conditional UPDATE locks the staff row. Concurrent assignments serialize
    -- here and recheck status after the first transaction commits.
    update public.institution_staff s set status = 'assigned'
      where s.id = new.assigned_staff_id and s.institution_id = old.institution_id
        and s.active and s.role = 'staff' and s.auth_user_id is not null and s.status = 'free'
        and not exists (select 1 from public.sos_requests r
          where r.assigned_staff_id = s.id and r.status in ('assigned', 'en_route'));
    if not found then
      raise exception 'Choose an active, free staff account in the SOS institution; this responder may already be busy';
    end if;
  elsif new.assigned_staff_id is distinct from old.assigned_staff_id then
    raise exception 'Staff assignment can only change from acknowledged to assigned';
  end if;
  if new.status = 'acknowledged' then new.acknowledged_at := now(); end if;
  if new.status = 'resolved' then new.resolved_at := now(); end if;
  return new;
end;
$$;

-- Availability is released after the row is resolved, in the same transaction.
create or replace function public.release_resolved_sos_staff()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status = 'en_route' and new.status = 'resolved' then
    update public.institution_staff set status = 'free'
      where id = new.assigned_staff_id and institution_id = new.institution_id;
  end if;
  return new;
end;
$$;
revoke all on function public.release_resolved_sos_staff() from public, anon, authenticated;
drop trigger if exists release_resolved_sos_staff on public.sos_requests;
create trigger release_resolved_sos_staff after update on public.sos_requests
  for each row execute function public.release_resolved_sos_staff();

-- Staff management (including service-role writes) cannot reset an occupied
-- responder to free or remove the login needed to complete the emergency.
create or replace function public.protect_active_sos_staff()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if exists (select 1 from public.sos_requests r
    where r.assigned_staff_id = old.id and r.status in ('assigned', 'en_route')) then
    if tg_op = 'DELETE' then raise exception 'Resolve the active SOS before deleting this staff account'; end if;
    if new.status is distinct from 'assigned' or new.active is distinct from true
      or new.auth_user_id is distinct from old.auth_user_id
      or new.institution_id is distinct from old.institution_id
      or new.role is distinct from old.role then
      raise exception 'Resolve the active SOS before changing this staff account or availability';
    end if;
  end if;
  if tg_op = 'DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function public.protect_active_sos_staff() from public, anon, authenticated;
drop trigger if exists protect_active_sos_staff on public.institution_staff;
create trigger protect_active_sos_staff before update or delete on public.institution_staff
  for each row execute function public.protect_active_sos_staff();

-- Join the traveller details only for requests the caller can already read.
-- Other feature-specific profile policies remain intact.
alter table public.user_profiles enable row level security;
drop policy if exists sos_participant_profile_read on public.user_profiles;
create policy sos_participant_profile_read on public.user_profiles for select to authenticated
  using (exists (select 1 from public.sos_requests r
    where r.traveller_id = user_profiles.id
      and (public.can_manage_sos_institution(r.institution_id)
        or public.is_assigned_sos_staff(r.institution_id, r.assigned_staff_id))));

-- Some installations have not enabled live tracking yet. When present, bound
-- any legacy institution-wide live-location policy for SOS sessions.
do $$
begin
  if to_regclass('public.traveler_live_locations') is not null then
    alter table public.traveler_live_locations enable row level security;
    drop policy if exists sos_location_read_boundary on public.traveler_live_locations;
    create policy sos_location_read_boundary on public.traveler_live_locations
      as restrictive for select to authenticated using (
        session_type is distinct from 'sos' or exists (
          select 1 from public.sos_requests r where r.id = session_id));
    drop policy if exists sos_location_read on public.traveler_live_locations;
    create policy sos_location_read on public.traveler_live_locations
      for select to authenticated using (session_type = 'sos' and exists (
        select 1 from public.sos_requests r where r.id = session_id));
  end if;
end $$;

notify pgrst, 'reload schema';
commit;
