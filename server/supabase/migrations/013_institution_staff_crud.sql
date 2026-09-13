-- Staff CRUD: extend the existing institution_staff table in place.
-- Existing semantic columns are retained:
--   name = full name, contact_number = phone, status = availability.

alter table public.institution_staff
  add column if not exists auth_user_id uuid references auth.users(id) on delete cascade,
  add column if not exists email text,
  add column if not exists contact_number text,
  add column if not exists active boolean not null default true,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

-- Bring legacy seed values into the new two-state availability vocabulary.
update public.institution_staff
set status = case
  when lower(coalesce(status, '')) in ('available', 'free') then 'free'
  else 'assigned'
end;

alter table public.institution_staff alter column status set default 'free';
alter table public.institution_staff alter column status set not null;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'institution_staff_availability_check'
      and conrelid = 'public.institution_staff'::regclass
  ) then
    alter table public.institution_staff
      add constraint institution_staff_availability_check
      check (status in ('free', 'assigned'));
  end if;
end;
$$;

create unique index if not exists institution_staff_auth_user_id_uidx
  on public.institution_staff(auth_user_id) where auth_user_id is not null;
create unique index if not exists institution_staff_institution_email_uidx
  on public.institution_staff(institution_id, lower(email)) where email is not null;
create index if not exists institution_staff_institution_id_idx
  on public.institution_staff(institution_id);

create or replace function public.set_institution_staff_updated_at()
returns trigger language plpgsql set search_path = public as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_institution_staff_updated_at_trigger on public.institution_staff;
create trigger set_institution_staff_updated_at_trigger
before update on public.institution_staff
for each row execute function public.set_institution_staff_updated_at();

alter table public.institution_staff enable row level security;

-- Replace table policies so an old broad policy cannot expose another institution.
do $$
declare existing_policy record;
begin
  for existing_policy in
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'institution_staff'
  loop
    execute format('drop policy if exists %I on public.institution_staff', existing_policy.policyname);
  end loop;
end;
$$;

create policy "Institution managers can view own staff"
on public.institution_staff for select to authenticated
using (exists (
  select 1 from public.institutions institution
  where institution.id = institution_staff.institution_id
    and institution.account_user_id = (select auth.uid())
));

-- Supports a later staff portal without granting access to colleagues.
create policy "Staff can view own profile"
on public.institution_staff for select to authenticated
using (auth_user_id = (select auth.uid()));

revoke all on public.institution_staff from anon;
revoke insert, update, delete on public.institution_staff from authenticated;
grant select on public.institution_staff to authenticated;

