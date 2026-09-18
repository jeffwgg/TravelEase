-- Apply after 022. Authorization uses linked rows, never editable Auth metadata.
begin;

create or replace function public.is_traveller_account()
returns boolean language sql stable security definer set search_path = '' as $$
  select auth.uid() is not null
    and exists (select 1 from public.user_profiles p where p.id = auth.uid())
    and not exists (select 1 from public.institutions i where i.account_user_id = auth.uid())
    and not exists (select 1 from public.institution_staff s where s.auth_user_id = auth.uid());
$$;
revoke all on function public.is_traveller_account() from public, anon;
grant execute on function public.is_traveller_account() to authenticated;

-- Staff cannot change account identity, email, role or availability through
-- direct REST writes, even if an older permissive policy allowed self-updates.
drop policy if exists staff_manager_update_boundary on public.institution_staff;
create policy staff_manager_update_boundary on public.institution_staff
  as restrictive for update to authenticated
  using (public.can_manage_sos_institution(institution_id))
  with check (public.can_manage_sos_institution(institution_id));
drop policy if exists staff_manager_insert_boundary on public.institution_staff;
create policy staff_manager_insert_boundary on public.institution_staff
  as restrictive for insert to authenticated
  with check (public.can_manage_sos_institution(institution_id));
drop policy if exists staff_manager_delete_boundary on public.institution_staff;
create policy staff_manager_delete_boundary on public.institution_staff
  as restrictive for delete to authenticated
  using (public.can_manage_sos_institution(institution_id));

-- Narrow self-service entry point. No caller-provided user/staff/institution ID.
create or replace function public.update_my_staff_name(p_name text)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if p_name is null or char_length(btrim(p_name)) not between 1 and 100 then
    raise exception 'Name must be between 1 and 100 characters';
  end if;
  update public.institution_staff s set name = btrim(p_name)
    where s.auth_user_id = auth.uid() and s.role = 'staff' and s.active
      and exists (select 1 from public.institutions i where i.id = s.institution_id and i.active);
  if not found then raise exception 'This account does not have access to the institution portal.'; end if;
end;
$$;
revoke all on function public.update_my_staff_name(text) from public, anon;
grant execute on function public.update_my_staff_name(text) to authenticated;

notify pgrst, 'reload schema';
commit;
