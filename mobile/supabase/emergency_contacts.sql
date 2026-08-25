-- Run this script in the Supabase SQL editor before using Emergency Contacts.
create extension if not exists pgcrypto;

create table if not exists public.emergency_contacts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(trim(name)) between 1 and 100),
  relationship text not null check (char_length(trim(relationship)) between 1 and 100),
  phone_number text not null check (char_length(trim(phone_number)) between 1 and 30),
  is_primary boolean not null default false,
  is_verified boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Supports databases created with an earlier version of this script.
alter table public.emergency_contacts
  add column if not exists is_verified boolean not null default false;

-- Existing contacts predate verification, so they must not remain Primary.
update public.emergency_contacts
set is_primary = false, updated_at = now()
where is_primary = true and is_verified = false;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'emergency_contacts_primary_requires_verification'
      and conrelid = 'public.emergency_contacts'::regclass
  ) then
    alter table public.emergency_contacts
      add constraint emergency_contacts_primary_requires_verification
      check (is_primary = false or is_verified = true);
  end if;
end
$$;

create index if not exists emergency_contacts_user_id_idx
  on public.emergency_contacts(user_id);

create unique index if not exists emergency_contacts_one_primary_per_user_idx
  on public.emergency_contacts(user_id)
  where is_primary;

alter table public.emergency_contacts enable row level security;

create or replace function public.set_primary_emergency_contact(contact_id uuid)
returns void
language plpgsql
security invoker
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.emergency_contacts
    where id = contact_id and user_id = (select auth.uid())
  ) then
    raise exception 'Emergency contact not found';
  end if;

  if not exists (
    select 1 from public.emergency_contacts
    where id = contact_id
      and user_id = (select auth.uid())
      and is_verified = true
  ) then
    raise exception 'Only verified emergency contacts can be primary';
  end if;

  update public.emergency_contacts
  set is_primary = false, updated_at = now()
  where user_id = (select auth.uid()) and is_primary;

  update public.emergency_contacts
  set is_primary = true, updated_at = now()
  where id = contact_id and user_id = (select auth.uid());
end;
$$;

revoke all on function public.set_primary_emergency_contact(uuid) from public;
grant execute on function public.set_primary_emergency_contact(uuid) to authenticated;

drop policy if exists "Users can view their emergency contacts" on public.emergency_contacts;
create policy "Users can view their emergency contacts"
  on public.emergency_contacts for select
  to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "Users can add their emergency contacts" on public.emergency_contacts;
create policy "Users can add their emergency contacts"
  on public.emergency_contacts for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can update their emergency contacts" on public.emergency_contacts;
create policy "Users can update their emergency contacts"
  on public.emergency_contacts for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists "Users can delete their emergency contacts" on public.emergency_contacts;
create policy "Users can delete their emergency contacts"
  on public.emergency_contacts for delete
  to authenticated
  using ((select auth.uid()) = user_id);
