-- Apply after 023. Return only the name needed for an authorized SOS task,
-- even when older profile RLS hides the embedded user_profiles join.
begin;
create or replace function public.get_sos_traveller_names(p_request_ids uuid[])
returns table(request_id uuid, full_name text)
language sql stable security definer set search_path = '' as $$
  select r.id, nullif(btrim(p.full_name), '')
  from public.sos_requests r
  left join public.user_profiles p on p.id = r.traveller_id
  where r.id = any(p_request_ids)
    and auth.uid() is not null
    and (
      exists (select 1 from public.institutions i
        where i.id = r.institution_id and i.account_user_id = auth.uid())
      or exists (select 1 from public.institution_staff s
        where s.id = r.assigned_staff_id and s.institution_id = r.institution_id
          and s.auth_user_id = auth.uid() and s.active and s.role = 'staff')
    );
$$;
revoke all on function public.get_sos_traveller_names(uuid[]) from public, anon;
grant execute on function public.get_sos_traveller_names(uuid[]) to authenticated;
notify pgrst, 'reload schema';
commit;
