import { PGlite } from '../../../.temp/sos-sql-check/node_modules/@electric-sql/pglite/dist/index.js'
import { readFile } from 'node:fs/promises'
import assert from 'node:assert/strict'

const db = new PGlite()
const id = n => `00000000-0000-0000-0000-${String(n).padStart(12, '0')}`
try {
  // Intentionally omit all 022 helper functions to reproduce the reported error.
  await db.exec(`create role anon; create role authenticated; create schema auth;
    create function auth.uid() returns uuid language sql stable as
      $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
    grant usage on schema public,auth to authenticated,anon;
    create table public.user_profiles(id uuid primary key, full_name text);
    create table public.institutions(id uuid primary key, account_user_id uuid);
    create table public.institution_staff(id uuid primary key, institution_id uuid, auth_user_id uuid, active boolean, role text);
    create table public.sos_requests(id uuid primary key, traveller_id uuid, institution_id uuid, assigned_staff_id uuid, status text);
    alter table public.user_profiles enable row level security;
    grant select on public.user_profiles to authenticated;
    insert into public.user_profiles values ('${id(1)}','  Actual Traveller Name  ');
    insert into public.institutions values ('${id(10)}','${id(2)}'),('${id(20)}','${id(3)}');
    insert into public.institution_staff values
      ('${id(30)}','${id(10)}','${id(4)}',true,'staff'),
      ('${id(31)}','${id(10)}','${id(5)}',true,'staff');
    insert into public.sos_requests values
      ('${id(40)}','${id(1)}','${id(10)}','${id(30)}','resolved'),
      ('${id(41)}','${id(1)}','${id(20)}',null,'sent');`)
  const migration = await readFile(new URL('../migrations/024_sos_traveller_names.sql', import.meta.url), 'utf8')
  await db.exec(migration)
  await db.exec(migration)
  const readNames = async user => {
    await db.exec(`reset role; set role authenticated; select set_config('request.jwt.claim.sub','${id(user)}',false);`)
    return (await db.query(`select * from public.get_sos_traveller_names(array['${id(40)}','${id(41)}']::uuid[])`)).rows
  }
  for (const user of [2,4]) assert.deepEqual(await readNames(user), [{request_id:id(40), full_name:'Actual Traveller Name'}])
  assert.equal((await db.query('select * from public.user_profiles')).rows.length, 0, 'name lookup works without broad profile access')
  assert.deepEqual(await readNames(5), [], 'unassigned staff cannot retrieve the name')
  assert.deepEqual(await readNames(1), [], 'traveller cannot use institution name lookup')
  assert.deepEqual(await readNames(3), [{request_id:id(41), full_name:'Actual Traveller Name'}])
  await db.exec(`reset role; update public.institution_staff set active=false where id='${id(30)}';`)
  assert.deepEqual(await readNames(4), [], 'inactive staff cannot retrieve names')
  await db.exec('reset role; set role anon;')
  await assert.rejects(db.query('select * from public.get_sos_traveller_names(array[]::uuid[])'), /permission denied/)
  console.log('PASS: 024 without helper functions, completed traveller names, manager/staff scope, inactive and anonymous rejection')
} finally { await db.close() }
