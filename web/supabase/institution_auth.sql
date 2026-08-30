-- Run in Supabase Dashboard > SQL Editor before deploying register-institution.
-- This migration repairs an existing institutions table as well as creating it.
create extension if not exists pgcrypto;

create table if not exists public.institutions (
  id uuid primary key default gen_random_uuid(),
  account_user_id uuid not null unique references auth.users(id) on delete cascade,
  name text not null,
  branch text,
  active boolean not null default true,
  institution_type text not null,
  official_contact text not null,
  service_address text not null,
  registration_document_path text,
  verification_status text not null default 'email_pending',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.institutions
  add column if not exists account_user_id uuid,
  add column if not exists name text,
  add column if not exists branch text,
  add column if not exists active boolean,
  add column if not exists institution_type text,
  add column if not exists official_contact text,
  add column if not exists service_address text,
  add column if not exists registration_document_path text,
  add column if not exists verification_status text,
  add column if not exists created_at timestamptz,
  add column if not exists updated_at timestamptz;

-- Safe backfills for columns added to legacy institution rows.
update public.institutions
set
  active = coalesce(active, true),
  institution_type = coalesce(institution_type, 'other'),
  official_contact = coalesce(official_contact, 'Not provided'),
  service_address = coalesce(service_address, branch, 'Not provided'),
  verification_status = coalesce(verification_status, 'email_pending'),
  created_at = coalesce(created_at, now()),
  updated_at = coalesce(updated_at, created_at, now());

-- account_user_id and name cannot be safely invented. Stop with a clear error
-- if legacy rows must be repaired manually before constraints are installed.
do $$
begin
  if exists (
    select 1 from public.institutions
    where account_user_id is null or name is null or btrim(name) = ''
  ) then
    raise exception
      'Repair institutions rows with null account_user_id or name before continuing.';
  end if;

  if exists (
    select 1
    from public.institutions i
    left join auth.users u on u.id = i.account_user_id
    where u.id is null
  ) then
    raise exception
      'Repair institutions.account_user_id values that do not reference auth.users.id.';
  end if;
end
$$;

alter table public.institutions
  alter column id set default gen_random_uuid(),
  alter column account_user_id set not null,
  alter column name set not null,
  alter column active set default true,
  alter column active set not null,
  alter column institution_type set not null,
  alter column official_contact set not null,
  alter column service_address set not null,
  alter column verification_status set default 'email_pending',
  alter column verification_status set not null,
  alter column created_at set default now(),
  alter column created_at set not null,
  alter column updated_at set default now(),
  alter column updated_at set not null;

create unique index if not exists institutions_account_user_id_key
  on public.institutions(account_user_id);

do $$
begin
  if not exists (
    select 1
    from pg_constraint c
    join pg_class t on t.oid = c.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'public'
      and t.relname = 'institutions'
      and c.contype = 'f'
      and pg_get_constraintdef(c.oid) like
        'FOREIGN KEY (account_user_id) REFERENCES auth.users(id)%'
  ) then
    alter table public.institutions
      add constraint institutions_account_user_id_fkey
      foreign key (account_user_id)
      references auth.users(id)
      on delete cascade;
  end if;
end
$$;

alter table public.institutions
  drop constraint if exists institutions_institution_type_check,
  add constraint institutions_institution_type_check check (
    institution_type in (
      'airport_transport',
      'hotel_hospitality',
      'tourist_attraction',
      'healthcare',
      'government',
      'other'
    )
  ),
  drop constraint if exists institutions_verification_status_check,
  add constraint institutions_verification_status_check check (
    verification_status in ('email_pending', 'email_verified', 'rejected')
  );

create or replace function public.set_institutions_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_institutions_updated_at_trigger
  on public.institutions;
create trigger set_institutions_updated_at_trigger
before update on public.institutions
for each row execute function public.set_institutions_updated_at();

-- Keep verification_status aligned with Supabase Auth email confirmation.
update public.institutions i
set verification_status = 'email_verified'
from auth.users u
where u.id = i.account_user_id
  and u.email_confirmed_at is not null
  and i.verification_status = 'email_pending';

create or replace function public.sync_institution_email_verification()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if new.email_confirmed_at is not null
     and old.email_confirmed_at is null then
    update public.institutions
    set verification_status = 'email_verified'
    where account_user_id = new.id;
  end if;
  return new;
end;
$$;

drop trigger if exists sync_institution_email_verification_trigger
  on auth.users;
create trigger sync_institution_email_verification_trigger
after update of email_confirmed_at on auth.users
for each row execute function public.sync_institution_email_verification();

alter table public.institutions enable row level security;

drop policy if exists "Institution users can view own profile"
  on public.institutions;
create policy "Institution users can view own profile"
  on public.institutions for select to authenticated
  using (account_user_id = (select auth.uid()));

-- Institution creation is intentionally omitted from client RLS policies.
-- register-institution performs the insert with the service-role client.
drop policy if exists "Institution users can update own profile"
  on public.institutions;
create policy "Institution users can update own profile"
  on public.institutions for update to authenticated
  using (account_user_id = (select auth.uid()))
  with check (account_user_id = (select auth.uid()));

-- RLS limits rows, while column grants prevent institution users from changing
-- ownership, activation, verification, or the stored document reference.
revoke insert, delete on public.institutions from anon, authenticated;
revoke update on public.institutions from authenticated;
grant select on public.institutions to authenticated;
grant update (
  name,
  branch,
  institution_type,
  official_contact,
  service_address
) on public.institutions to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'institution-registration-documents',
  'institution-registration-documents',
  false,
  10485760,
  array['application/pdf', 'image/jpeg', 'image/png']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Upload/delete during registration and rollback use the Edge Function's
-- service role. Institution users can read only their own private document.
drop policy if exists "Institution users can view own registration document"
  on storage.objects;
create policy "Institution users can view own registration document"
  on storage.objects for select to authenticated
  using (
    bucket_id = 'institution-registration-documents'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- Institution registration never inserts into user_profiles. Add a defensive
-- trigger only when that traveller table exists.
create or replace function public.prevent_institution_traveller_profile()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  if exists (
    select 1 from public.institutions
    where account_user_id = new.id
  ) or exists (
    select 1 from auth.users
    where id = new.id
      and raw_user_meta_data ->> 'account_type' = 'institution'
  ) then
    raise exception 'Institution accounts cannot create traveller profiles';
  end if;
  return new;
end;
$$;

do $$
begin
  if to_regclass('public.user_profiles') is not null then
    drop trigger if exists prevent_institution_traveller_profile_trigger
      on public.user_profiles;
    create trigger prevent_institution_traveller_profile_trigger
    before insert or update on public.user_profiles
    for each row execute function public.prevent_institution_traveller_profile();
  end if;
end
$$;
