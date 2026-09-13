-- Resolve staff ownership without creating circular RLS evaluation between
-- institutions and institution_staff.
create or replace function public.current_staff_institution_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select staff.institution_id
  from public.institution_staff staff
  where staff.auth_user_id = (select auth.uid())
    and staff.role = 'staff'
    and staff.active = true
  limit 1;
$$;

revoke all on function public.current_staff_institution_id() from public;
grant execute on function public.current_staff_institution_id() to authenticated;

-- Permit an active staff account to restore only its linked institution context.
drop policy if exists "Staff can view linked institution" on public.institutions;
create policy "Staff can view linked institution"
on public.institutions for select to authenticated
using (id = (select public.current_staff_institution_id()));
