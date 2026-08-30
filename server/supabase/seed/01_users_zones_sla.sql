-- ============================================================================
-- 01_users_zones_sla.sql — demo accounts, staff, zones + layout, SLA config
-- Idempotent: re-running removes the previous seed run first.
-- Requires: migration 004_analytics_reporting.sql (map_x/map_y columns, sla_configs)
-- ============================================================================

select setseed(0.42);

-- ---------------------------------------------------------------------------
-- 1. Demo auth accounts (80, signup volume rising over ~6 months)
-- ---------------------------------------------------------------------------
delete from public.user_profiles
where id in (select id from auth.users where email like '%@seed.travelease.dev');
delete from auth.identities
where user_id in (select id from auth.users where email like '%@seed.travelease.dev');
delete from auth.users where email like '%@seed.travelease.dev';

with gen as (
  select g,
         gen_random_uuid() as uid,
         (now() - make_interval(days => 1 + floor(random() * 179)::int))
           - make_interval(secs => floor(random() * 86400)::int) as created_at
  from generate_series(0, 159) g
  -- acceptance probability rises over time -> adoption growth curve
  where random() < (0.25 + 0.75 * (g::numeric / 159))
),
ins as (
  insert into auth.users
    (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
     raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
  select '00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated',
         'seed.user' || lpad(g::text, 3, '0') || '@seed.travelease.dev',
         extensions.crypt('SeedDemo!2026', extensions.gen_salt('bf')),
         created_at,
         '{"provider":"email","providers":["email"]}'::jsonb,
         '{"seed": true}'::jsonb,
         created_at, created_at
  from gen
  on conflict (id) do nothing
  returning id, email, created_at
)
insert into auth.identities (provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
select id::text, id,
       jsonb_build_object('sub', id::text, 'email', email, 'email_verified', true),
       'email', created_at, created_at, created_at
from ins
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- 2. Profiles for the demo accounts
--    NOTE: inserting into auth.users fires the travelease_handle_new_user
--    trigger, which creates a bare user_profiles row first. So we UPDATE the
--    trigger-created rows and INSERT only any that are still missing.
--    (user_type / *_language / preferred_communication were dropped from the
--    table on 2026-08-30 — profiles carry full_name, nationality, avatar_url,
--    profile_completed only.)
-- ---------------------------------------------------------------------------
with seed_users as (
  select id, created_at, row_number() over (order by created_at) - 1 as g
  from auth.users where email like '%@seed.travelease.dev'
),
vals as (
  select u.id, u.created_at,
         (array['Aisyah Rahman','Wei Jie Tan','Arjun Patel','Daniel Wong','Farah Zainal',
                'Hui Ling Chan','Kavitha Raman','Liam Carter','Mei Ling Ong','Nabil Haikal',
                'Olivia Reyes','Rajesh Kumar','Sofia Marinescu','Tunku Aiman','Xin Yi Lim',
                'Yusof Ismail','Chen Wei Goh','Emily Drake','Hakim Sulaiman','Grace Lau'])[1 + (u.g % 20)] as fname,
         (array['Malaysian','Singaporean','Indonesian','Chinese','Indian','Australian','British','Thai'])[1 + (u.g % 8)] as nat
  from seed_users u
)
update public.user_profiles p set
  full_name = v.fname,
  nationality = v.nat,
  profile_completed = true,
  created_at = v.created_at,
  updated_at = v.created_at
from vals v
where p.id = v.id
  and (p.nationality is distinct from v.nat
       or p.created_at is distinct from v.created_at);

insert into public.user_profiles
  (id, full_name, nationality, profile_completed, created_at, updated_at)
select v.id, v.fname, v.nat, true, v.created_at, v.created_at
from vals v
where not exists (select 1 from public.user_profiles p where p.id = v.id);


-- ---------------------------------------------------------------------------
-- 3. Extra institution staff (only added when missing)
-- ---------------------------------------------------------------------------
insert into public.institution_staff (institution_id, name, role, department, status)
select i.id, v.name, v.role, v.dept, 'available'
from public.institutions i,
     (values
        ('Farid Azlan',   'Customer Service Officer', 'Terminal 1 - Counter 8'),
        ('Chong Mei Kuan','Accessibility Liaison',    'Terminal 1 - Info Desk A'),
        ('Harith Danial', 'Queue Marshal',            'Terminal 1 - Check-in Row'),
        ('Aina Sofea',    'Passenger Support',        'Terminal 1 - Baggage Claim')
     ) as v(name, role, dept)
where i.name like 'Kuala Lumpur%'
  and not exists (select 1 from public.institution_staff s where s.name = v.name);

-- ---------------------------------------------------------------------------
-- 4. Venue zones: extra zones + layout coordinates for the spatial heatmap.
--    map_x / map_y are percentages (0-100) of the venue layout.
--    The pseudo-zone 'All Zones' (code ALL) intentionally has no coordinates.
-- ---------------------------------------------------------------------------
insert into public.venue_zones (institution_id, name, code, zone_type, map_x, map_y)
select i.id, v.name, v.code, v.zone_type, v.x, v.y
from public.institutions i,
     (values
        ('Check-in Counters 1-16',  'CHECKIN',     'checkin',   55, 12),
        ('Immigration & Security',  'IMMIGRATION', 'security',  42, 40),
        ('Boarding Lounge C1 - C8', 'GATE-C',      'gate',      78, 35)
     ) as v(name, code, zone_type, x, y)
where i.name like 'Kuala Lumpur%'
  and not exists (
    select 1 from public.venue_zones z
    where z.code = v.code and z.institution_id = i.id
  );

update public.venue_zones z
set map_x = v.x, map_y = v.y
from (values
        ('GATE-A', 18, 25),
        ('GATE-B', 18, 68),
        ('BAGGAGE', 72, 78)
     ) as v(code, x, y)
where z.code = v.code;

-- ---------------------------------------------------------------------------
-- 5. SLA configuration (FR-M7-15): institution default + one zone override
-- ---------------------------------------------------------------------------
delete from public.sla_configs
where institution_id in (select id from public.institutions where name like 'Kuala Lumpur%');

insert into public.sla_configs (institution_id, response_limit_minutes, resolution_limit_minutes)
select id, 5, 60
from public.institutions
where name like 'Kuala Lumpur%';

insert into public.sla_configs (institution_id, zone_id, response_limit_minutes, resolution_limit_minutes)
select i.id, z.id, 8, 90
from public.institutions i
join public.venue_zones z on z.institution_id = i.id and z.code = 'BAGGAGE'
where i.name like 'Kuala Lumpur%';
