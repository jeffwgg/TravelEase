import { PGlite } from '../../../.temp/sos-sql-check/node_modules/@electric-sql/pglite/dist/index.js'
import { readFile } from 'node:fs/promises'
import assert from 'node:assert/strict'

const db = new PGlite()
try {
  await db.exec(`
    create role anon; create role authenticated;
    create table institution_staff (id int primary key, institution_id int, status text);
    create table sos_requests (id int primary key, institution_id int, assigned_staff_id int, status text);
    insert into institution_staff values (1, 10, 'free'), (2, 10, 'free'), (3, 20, 'free');
    insert into sos_requests values (1, 10, 1, 'assigned');
  `)
  const sql = await readFile(new URL('../migrations/026_sync_sos_staff_availability.sql', import.meta.url), 'utf8')
  await db.exec(sql)
  await db.exec(sql)
  const status = async id => (await db.query('select status from institution_staff where id=$1', [id])).rows[0].status
  assert.equal(await status(1), 'assigned', 'repairs existing stale availability')
  await db.exec("update sos_requests set status='en_route' where id=1")
  assert.equal(await status(1), 'assigned')
  await db.exec("update sos_requests set status='resolved' where id=1")
  assert.equal(await status(1), 'free')
  await db.exec("insert into sos_requests values (2, 10, null, 'acknowledged')")
  await db.exec("update sos_requests set assigned_staff_id=2, status='assigned' where id=2")
  assert.equal(await status(2), 'assigned')
  await db.exec("insert into sos_requests values (3, 10, 2, 'en_route')")
  await db.exec("update sos_requests set status='resolved' where id=2")
  assert.equal(await status(2), 'assigned', 'legacy extra active task prevents early release')
  await db.exec("update sos_requests set status='resolved' where id=3")
  assert.equal(await status(2), 'free')
  assert.equal(await status(3), 'free', 'other institution unchanged')
  console.log('PASS: Availability backfill, assignment, en route, resolution, remaining tasks and migration reapplication')
} finally { await db.close() }
