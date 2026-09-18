// Isolated PostgreSQL regression checks, never connects to a hosted project.
// From repo root:
// npm install --prefix .temp/sos-sql-check --no-save --package-lock=false @electric-sql/pglite
// node server/supabase/tests/sos_history_test.mjs
import { PGlite } from '../../../.temp/sos-sql-check/node_modules/@electric-sql/pglite/dist/index.js'
import { readFile } from 'node:fs/promises'
import assert from 'node:assert/strict'

const db = new PGlite()
const id = (n) => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`
async function asUser(n) {
  await db.exec(`reset role; set role authenticated; select set_config('request.jwt.claim.sub', '${id(n)}', false);`)
}
async function history() {
  return (await db.query('select public.get_traveller_sos_history() as entry')).rows.map((row) => row.entry)
}
try {
  // Only the pre-existing schema contract used by these migrations is modeled.
  // This does not substitute for checking the deployed schema/legacy triggers.
  await db.exec(`
    create role anon;
    create role authenticated;
    create schema auth;
    create table auth.users(id uuid primary key);
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
    grant usage on schema public, auth to authenticated, anon;
    grant execute on function auth.uid() to authenticated, anon;
    create table public.institutions(id uuid primary key, account_user_id uuid, name text);
    create table public.service_areas(id uuid primary key, institution_id uuid references public.institutions,
      name text, active boolean default true);
    create table public.institution_staff(id uuid primary key, institution_id uuid references public.institutions,
      auth_user_id uuid, name text, contact_number text, active boolean default true);
    create table public.sos_requests(id uuid primary key default gen_random_uuid(), traveller_id uuid references auth.users,
      institution_id uuid references public.institutions, service_area_id uuid references public.service_areas,
      status text default 'sent' check(status in ('sent','acknowledged','resolved')),
      latitude double precision, longitude double precision, triggered_at timestamptz default now(),
      acknowledged_at timestamptz, resolved_at timestamptz);
    alter table public.institutions enable row level security;
    grant select on public.institutions, public.institution_staff to authenticated;
    -- Deliberately permissive legacy policies to exercise restrictive boundaries.
    create policy legacy_sos_read on public.sos_requests for select to authenticated using (true);
    create policy legacy_staff_read on public.institution_staff for select to authenticated using (true);
    insert into auth.users values ('${id(1)}'), ('${id(2)}'), ('${id(3)}'), ('${id(4)}'), ('${id(5)}');
    insert into public.institutions values ('${id(11)}','${id(3)}','Station'), ('${id(12)}','${id(4)}','Airport');
    insert into public.service_areas values ('${id(21)}','${id(11)}','Concourse',true), ('${id(22)}','${id(12)}','Terminal',true);
    insert into public.institution_staff values ('${id(31)}','${id(11)}','${id(5)}','Responder','123',true),
      ('${id(32)}','${id(12)}',null,'Other responder','456',true);
    insert into public.sos_requests(id,traveller_id,institution_id,service_area_id,triggered_at)
      values ('${id(41)}','${id(1)}','${id(11)}','${id(21)}','2026-09-16T10:00:00Z'),
      ('${id(42)}','${id(2)}','${id(12)}','${id(22)}','2026-09-16T11:00:00Z');
  `)
  for (const file of ['019_traveller_sos_history.sql', '020_sos_progress_and_history.sql']) {
    await db.exec(await readFile(new URL(`../migrations/${file}`, import.meta.url), 'utf8'))
  }
  // 020 can be reapplied without duplicating data or policies.
  await db.exec(await readFile(new URL('../migrations/020_sos_progress_and_history.sql', import.meta.url), 'utf8'))
  // Reproduce the legacy trigger left in place by 020, then extend it in 021.
  await db.exec(`create function public.legacy_sos_validator() returns trigger language plpgsql as $$
    begin
      if new.status is distinct from old.status and not (
        (old.status = 'sent' and new.status = 'acknowledged') or
        (old.status = 'acknowledged' and new.status = 'resolved')
      ) then raise exception 'Invalid SOS status transition from % to %', old.status, new.status;
      end if;
      return new;
    end $$;
    create trigger legacy_sos_validator before update on public.sos_requests
    for each row execute function public.legacy_sos_validator();`)
  const compatibility = await readFile(new URL('../migrations/021_sos_legacy_transition_compatibility.sql', import.meta.url), 'utf8')
  await db.exec(compatibility)
  await db.exec(compatibility)
  assert.equal((await db.query('select count(*)::int as n from public.traveller_sos_events')).rows[0].n, 0)
  await asUser(1)
  let rows = await history()
  assert.equal(rows.length, 1)
  assert.equal(rows[0].id, id(41))
  assert.equal(rows[0].institution_name, 'Station')
  assert.equal(rows[0].service_area_name, 'Concourse')
  assert.equal((await db.query('select * from public.institution_staff')).rows.length, 0)
  assert.equal((await db.query('select * from public.sos_requests')).rows.length, 1)
  assert.equal((await db.query("update public.sos_requests set status='resolved' returning id")).rows.length, 0)
  await assert.rejects(db.exec(`insert into public.traveller_sos_events(traveller_id,sos_request_id)
    values ('${id(1)}','${id(42)}')`), /row-level security/)
  await assert.rejects(db.exec(`insert into public.sos_requests(traveller_id,institution_id,service_area_id)
    values ('${id(2)}','${id(11)}','${id(21)}')`), /row-level security/)
  await assert.rejects(db.exec(`insert into public.sos_requests(traveller_id,institution_id,service_area_id)
    values ('${id(1)}','${id(11)}','${id(22)}')`), /service area/)
  await db.exec(`insert into public.traveller_sos_events(traveller_id,triggered_at,contact_name,contact_status,contact_attempted_at)
    values ('${id(1)}','2026-09-16T10:00:00Z','Family','notified','2026-09-16T10:00:01Z'),
    ('${id(1)}','2026-09-17T10:00:00Z','Friend','failed','2026-09-17T10:00:01Z')`)
  rows = await history()
  assert.equal(rows.length, 2, 'unlinked matching metadata must not duplicate a request')
  assert.equal(rows[0].contact_name, 'Friend', 'newest first')
  assert.equal(rows[1].contact_name, 'Family')
  assert.equal(rows[1].request.status, 'sent')
  await asUser(3)
  assert.equal((await history()).length, 0, 'institution login cannot read traveller RPC data')
  await assert.rejects(db.exec(`update public.sos_requests set status='en_route' where id='${id(41)}'`), /transition/)
  await db.exec(`update public.sos_requests set status='acknowledged' where id='${id(41)}'`)
  await assert.rejects(db.exec(`update public.sos_requests set status='assigned', assigned_staff_id='${id(32)}'
    where id='${id(41)}'`), /active in the SOS institution/)
  await db.exec(`update public.sos_requests set status='assigned', assigned_staff_id='${id(31)}' where id='${id(41)}'`)
  await asUser(1)
  rows = await history()
  assert.equal(rows[1].request.staff_name, 'Responder')
  assert.equal(rows[1].request.staff_contact, '123')
  await db.exec(`update public.traveller_sos_events set status='ended', ended_at=now()`)
  assert.equal((await history())[1].request.status, 'assigned')
  await asUser(5)
  await db.exec(`update public.sos_requests set status='en_route' where id='${id(41)}'`)
  await asUser(4)
  assert.equal((await db.query(`update public.sos_requests set status='resolved' where id='${id(41)}' returning id`)).rows.length, 0)
  await asUser(3)
  await db.exec(`update public.sos_requests set status='resolved' where id='${id(41)}'`)
  await assert.rejects(db.exec(`update public.sos_requests set status='sent' where id='${id(41)}'`), /transition/)
  await asUser(1)
  rows = await history()
  assert.equal(rows[1].request.status, 'resolved')
  assert.ok(rows[1].request.resolved_at)
  assert.equal(rows[1].request.staff_contact, null, 'contact is only shared during assistance')
  await db.exec('reset role; set role anon;')
  await assert.rejects(history(), /permission denied/)
  console.log('PASS: migrations, no backfill/duplicates, ownership/RLS, safe joins, assignment, lifecycle and notification metadata')
} finally {
  await db.close()
}
