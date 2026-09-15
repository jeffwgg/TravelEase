-- Queue notifications are audit events, not queue-number status updates.
-- Keep writes behind security-definer RPCs because queue_events is not
-- writable by browser clients under its row-level-security policy.

do $$
declare constraint_name text;
begin
  for constraint_name in
    select con.conname
    from pg_constraint con
    where con.conrelid = 'public.queue_lines'::regclass
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%status%'
  loop
    execute format('alter table public.queue_lines drop constraint %I', constraint_name);
  end loop;
end;
$$;

alter table public.queue_lines
  add constraint queue_lines_status_check
  check (status in ('active', 'closed', 'reset'));

create or replace function public.queue_staff_can_manage(p_institution_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.institutions institution
    where institution.id = p_institution_id
      and institution.account_user_id = (select auth.uid())
  ) or p_institution_id = public.current_staff_institution_id();
$$;

revoke all on function public.queue_staff_can_manage(uuid) from public;

create or replace function public.queue_log_event(
  p_queue_line_id uuid,
  p_number text,
  p_event_type text,
  p_details jsonb default '{}'::jsonb
)
returns public.queue_events
language plpgsql
security definer
set search_path = public
as $$
declare
  v_line public.queue_lines%rowtype;
  v_event public.queue_events%rowtype;
begin
  select * into v_line from public.queue_lines where id = p_queue_line_id;
  if not found or not public.queue_staff_can_manage(v_line.institution_id) then
    raise exception 'You do not have permission to update this queue line.';
  end if;

  insert into public.queue_events (
    institution_id, queue_line_id, event_type, event_number, created_by, details
  ) values (
    v_line.institution_id, v_line.id, p_event_type, trim(p_number), auth.uid(),
    coalesce(p_details, '{}'::jsonb)
  ) returning * into v_event;
  return v_event;
end;
$$;

-- PostgreSQL cannot change a function return type through CREATE OR REPLACE.
-- The previous implementation returned a different type and also changed the
-- queue status, so replace that exact signature before defining the new,
-- status-neutral event function.
drop function if exists public.queue_notify_number(uuid, text);

create function public.queue_notify_number(
  p_queue_line_id uuid,
  p_number text
)
returns public.queue_events
language plpgsql
security definer
set search_path = public
as $$
declare
  v_line public.queue_lines%rowtype;
  v_number public.queue_numbers%rowtype;
  v_event public.queue_events%rowtype;
begin
  select * into v_line from public.queue_lines where id = p_queue_line_id;
  if not found or not public.queue_staff_can_manage(v_line.institution_id) then
    raise exception 'You do not have permission to notify this queue number.';
  end if;
  if v_line.status in ('closed', 'reset') then
    raise exception 'This queue line is not active for notifications.';
  end if;

  select * into v_number
  from public.queue_numbers
  where queue_line_id = v_line.id
    and upper(regexp_replace(number, '[[:space:]-]', '', 'g')) =
        upper(regexp_replace(trim(p_number), '[[:space:]-]', '', 'g'))
  limit 1;
  if not found then
    raise exception 'Queue number % was not found in this queue line.', trim(p_number);
  end if;
  if v_number.status in ('completed', 'cancelled') then
    raise exception 'Queue number % is already % and cannot be notified.', v_number.number, v_number.status;
  end if;

  insert into public.queue_events (
    institution_id, queue_line_id, queue_number_id, event_type, event_number,
    created_by, details
  ) values (
    v_line.institution_id, v_line.id, v_number.id, 'notified', v_number.number,
    auth.uid(), '{"source":"staff_console","kind":"call_again"}'::jsonb
  ) returning * into v_event;
  return v_event;
end;
$$;

revoke all on function public.queue_log_event(uuid, text, text, jsonb) from public;
revoke all on function public.queue_notify_number(uuid, text) from public;
grant execute on function public.queue_log_event(uuid, text, text, jsonb) to authenticated;
grant execute on function public.queue_notify_number(uuid, text) to authenticated;
