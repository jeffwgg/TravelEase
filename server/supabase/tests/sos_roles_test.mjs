// Isolated PostgreSQL fixture; never connects to a hosted project.
// Uses the same local PGlite installation as sos_history_test.mjs.
import { PGlite } from '../../../.temp/sos-sql-check/node_modules/@electric-sql/pglite/dist/index.js'
import { readFile } from 'node:fs/promises'
import assert from 'node:assert/strict'

const db = new PGlite()
const id = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`
const user = (n) => db.exec(`reset role; set role authenticated; select set_config('request.jwt.claim.sub','${id(n)}',false);`)
const rows = async (sql) => (await db.query(sql)).rows
const update = (n, status, staff) => db.query(`update public.sos_requests set status='${status}'
  ${staff !== undefined ? `, assigned_staff_id=${staff === null ? 'null' : `'${id(staff)}'`}` : ''}
  where id='${id(n)}' returning id`)
const available = async (n) => (await rows(`select status from public.institution_staff where id='${id(n)}'`))[0]?.status
try {
  await db.exec(`
    create role anon; create role authenticated;
    create schema auth;
    create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    grant usage on schema public,auth to authenticated,anon;
    grant execute on function auth.uid() to authenticated,anon;
    create table public.institutions(id uuid primary key, account_user_id uuid, name text);
    create table public.user_profiles(id uuid primary key, full_name text);
    create table public.service_areas(id uuid primary key, institution_id uuid references public.institutions,
      name text, active boolean default true);
    create table public.institution_staff(id uuid primary key, institution_id uuid references public.institutions,
      auth_user_id uuid, name text, contact_number text, active boolean default true,
      role text default 'staff', status text default 'free' check(status in ('free','assigned')));
    create table public.sos_requests(id uuid primary key default gen_random_uuid(), traveller_id uuid references auth.users,
      institution_id uuid references public.institutions, service_area_id uuid references public.service_areas,
      status text default 'sent', latitude double precision, longitude double precision,
      triggered_at timestamptz default now(), acknowledged_at timestamptz, resolved_at timestamptz);
    create table public.traveler_live_locations(session_id uuid primary key, session_type text, latitude float8);
    grant select on public.institutions, public.user_profiles, public.service_areas,
      public.institution_staff, public.traveler_live_locations to authenticated;
    grant update on public.institution_staff to authenticated;
    -- Deliberately broad old policies: restrictive boundaries must still win.
    create policy legacy_read on public.sos_requests for select to authenticated using (true);
    create policy legacy_update on public.sos_requests for update to authenticated using (true) with check (true);
    create policy legacy_delete on public.sos_requests for delete to authenticated using (true);
    create policy legacy_staff on public.institution_staff for all to authenticated using (true) with check (true);
    create policy legacy_locations on public.traveler_live_locations for select to authenticated using (true);
    insert into auth.users select ('00000000-0000-0000-0000-' || lpad(n::text,12,'0'))::uuid from generate_series(1,9) n;
    insert into public.user_profiles values ('${id(1)}','Traveller One'), ('${id(2)}','Traveller Two');
    insert into public.institutions values ('${id(11)}','${id(3)}','Station'), ('${id(12)}','${id(4)}','Airport');
    insert into public.service_areas values ('${id(21)}','${id(11)}','Concourse',true), ('${id(22)}','${id(12)}','Terminal',true);
    insert into public.institution_staff(id,institution_id,auth_user_id,name,active) values
      ('${id(31)}','${id(11)}','${id(5)}','Responder A',true),
      ('${id(32)}','${id(11)}','${id(6)}','Responder B',true),
      ('${id(33)}','${id(12)}','${id(7)}','Other institution',true),
      ('${id(34)}','${id(11)}','${id(8)}','Inactive',false),
      ('${id(35)}','${id(11)}',null,'No login',true);
    insert into public.sos_requests(id,traveller_id,institution_id,service_area_id) values
      ('${id(41)}','${id(1)}','${id(11)}','${id(21)}'),
      ('${id(42)}','${id(2)}','${id(11)}','${id(21)}'),
      ('${id(43)}','${id(2)}','${id(12)}','${id(22)}');
    insert into public.traveler_live_locations values
      ('${id(41)}','sos',1), ('${id(42)}','sos',2), ('${id(43)}','sos',3), ('${id(99)}','assistance',4);
  `)
  for (const name of ['019_traveller_sos_history.sql','020_sos_progress_and_history.sql','021_sos_legacy_transition_compatibility.sql','022_sos_role_permissions_and_availability.sql','022_sos_role_permissions_and_availability.sql']) {
    await db.exec(await readFile(new URL(`../migrations/${name}`, import.meta.url), 'utf8'))
  }
  await user(5)
  assert.equal((await rows('select * from public.sos_requests')).length, 0, 'unassigned staff sees no requests')
  assert.equal((await rows("select * from public.traveler_live_locations where session_type='sos'")).length, 0)
  assert.equal((await rows('select * from public.user_profiles')).length, 0)
  assert.equal((await update(41, 'acknowledged')).rows.length, 0)
  await user(3)
  assert.equal((await rows('select * from public.sos_requests')).length, 2, 'manager sees own institution only')
  assert.equal((await rows("select * from public.traveler_live_locations where session_type='sos'")).length, 2)
  await assert.rejects(update(41, 'assigned', 31), /transition/)
  await update(41, 'acknowledged')
  await update(42, 'acknowledged')
  await assert.rejects(update(41, 'resolved'), /transition/)
  for (const staff of [33,34,35,null]) await assert.rejects(update(41, 'assigned', staff), /active, free staff/)
  // Reservation is transactional, not a second client-side availability write.
  await db.exec('begin')
  await update(41, 'assigned', 31)
  assert.equal(await available(31), 'assigned')
  await db.exec('rollback')
  assert.equal(await available(31), 'free')
  await update(41, 'assigned', 31)
  assert.equal(await available(31), 'assigned')
  await assert.rejects(update(42, 'assigned', 31), /active, free staff/)
  await assert.rejects(update(41, 'en_route'), /Only the assigned staff/)
  await assert.rejects(update(41, 'resolved'), /transition/)
  await assert.rejects(update(41, 'assigned', 32), /assignment can only change/)
  await assert.rejects(db.exec(`update public.institution_staff set status='free' where id='${id(31)}'`), /Resolve the active SOS/)
  await assert.rejects(db.exec(`update public.institution_staff set active=false where id='${id(31)}'`), /Resolve the active SOS/)
  await user(6)
  assert.equal((await rows('select * from public.sos_requests')).length, 0)
  assert.equal((await update(41, 'en_route')).rows.length, 0)
  await user(8)
  assert.equal((await rows('select * from public.sos_requests')).length, 0, 'inactive staff cannot read tasks')
  // Even older column grants cannot bypass immutable ownership/location checks.
  await db.exec('reset role; grant update(latitude, institution_id) on public.sos_requests to authenticated;')
  await user(5)
  assert.deepEqual((await rows('select id from public.sos_requests')).map(r => r.id), [id(41)])
  assert.deepEqual((await rows('select full_name from public.user_profiles')).map(r => r.full_name), ['Traveller One'])
  assert.deepEqual((await rows("select session_id from public.traveler_live_locations where session_type='sos'")).map(r => r.session_id), [id(41)])
  assert.equal((await rows("select * from public.traveler_live_locations where session_type='assistance'")).length, 1, 'other feature policies remain unchanged')
  assert.equal((await update(42, 'assigned', 31)).rows.length, 0, 'staff cannot assign')
  await assert.rejects(db.exec(`update public.sos_requests set latitude=99 where id='${id(41)}'`), /immutable/)
  await assert.rejects(db.exec(`update public.sos_requests set institution_id='${id(12)}' where id='${id(41)}'`), /immutable/)
  await assert.rejects(update(41, 'resolved'), /transition/)
  await assert.rejects(update(41, 'en_route', 32), /assignment can only change/)
  await update(41, 'en_route')
  assert.equal(await available(31), 'assigned')
  await user(3)
  await assert.rejects(update(41, 'resolved'), /Only the assigned staff/)
  await user(4)
  assert.equal((await update(41, 'resolved')).rows.length, 0)
  await user(1)
  assert.equal((await update(41, 'resolved')).rows.length, 0)
  await user(5)
  await update(41, 'resolved')
  assert.equal(await available(31), 'free')
  assert.ok((await rows(`select resolved_at from public.sos_requests where id='${id(41)}'`))[0].resolved_at)
  await assert.rejects(update(41, 'en_route'), /transition/)
  await user(3)
  await update(42, 'assigned', 31)
  assert.equal(await available(31), 'assigned', 'resolved responder can take next task')
  await user(1)
  assert.equal((await rows('select public.get_traveller_sos_history() as h'))[0].h.request.status, 'resolved')
  // Account segregation must reject institution logins even when an old Auth
  // trigger automatically created user_profiles for every account.
  await db.exec(`reset role;
    alter table public.institutions add column active boolean default true;
    alter table public.institution_staff add column email text;
    insert into public.user_profiles values ('${id(3)}','Manager profile'), ('${id(5)}','Staff profile'), ('${id(8)}','Inactive staff profile');`)
  const accounts = await readFile(new URL('../migrations/023_account_access_and_staff_profile.sql', import.meta.url), 'utf8')
  await db.exec(accounts)
  await db.exec(accounts)
  for (const [account, expected] of [[1,true],[3,false],[5,false],[8,false],[9,false]]) {
    await user(account)
    assert.equal((await rows('select public.is_traveller_account() as allowed'))[0].allowed, expected, `traveller access for ${account}`)
  }
  await user(5)
  await db.exec("select public.update_my_staff_name('  Updated Responder  ')")
  assert.equal((await rows(`select name from public.institution_staff where id='${id(31)}'`))[0].name, 'Updated Responder')
  assert.equal(await available(31), 'assigned', 'editing name preserves SOS availability')
  for (const change of ["status='free'", "email='changed@example.test'", "role='manager'", `institution_id='${id(12)}'`, `auth_user_id='${id(6)}'`]) {
    assert.equal((await rows(`update public.institution_staff set ${change} where id='${id(31)}' returning id`)).length, 0, `staff cannot change ${change}`)
  }
  await db.exec('reset role; grant insert, delete on public.institution_staff to authenticated;')
  await user(5)
  assert.equal((await rows(`delete from public.institution_staff where id='${id(32)}' returning id`)).length, 0)
  await assert.rejects(db.exec(`insert into public.institution_staff(id,institution_id,auth_user_id,name) values ('${id(36)}','${id(11)}','${id(5)}','Unauthorized')`), /row-level security/)
  await assert.rejects(db.exec("select public.update_my_staff_name('   ')"), /Name must/)
  await assert.rejects(db.exec("select public.update_my_staff_name(repeat('a',101))"), /Name must/)
  await user(1)
  await assert.rejects(db.exec("select public.update_my_staff_name('Traveller')"), /does not have access/)
  await user(8)
  await assert.rejects(db.exec("select public.update_my_staff_name('Inactive')"), /does not have access/)
  await user(3)
  assert.equal((await rows(`update public.institution_staff set name='Manager edited' where id='${id(32)}' returning id`)).length, 1)
  await user(5)
  await update(42, 'en_route')
  await update(42, 'resolved')
  assert.equal(await available(31), 'free', 'assignment triggers still work through staff write boundary')
  await db.exec('reset role; set role anon;')
  await assert.rejects(db.exec('select public.is_traveller_account()'), /permission denied/)
  await assert.rejects(db.exec("select public.update_my_staff_name('Anonymous')"), /permission denied/)
  await assert.rejects(db.exec('select * from public.sos_requests'), /permission denied/)
  console.log('PASS: SOS roles/lifecycle, scoped details/location, reservations, account segregation, staff profile restrictions and legacy policy boundaries')
} finally {
  await db.close()
}
