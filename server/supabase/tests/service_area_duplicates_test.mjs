import { PGlite } from '../../../.temp/sos-sql-check/node_modules/@electric-sql/pglite/dist/index.js'
import { readFile } from 'node:fs/promises'
import assert from 'node:assert/strict'

const db = new PGlite()
try {
  await db.exec(`create table service_areas (
    id serial primary key, institution_id text not null, name text not null,
    latitude double precision not null, longitude double precision not null,
    radius_m integer not null, active boolean default true
  )`)
  const migration = await readFile(new URL('../migrations/025_unique_service_areas.sql', import.meta.url), 'utf8')
  await db.exec(migration)
  await db.exec(migration)
  const insert = (institution, name, lat = 3.14, lon = 101.69, radius = 500) => db.query(
    'insert into service_areas (institution_id,name,latitude,longitude,radius_m) values ($1,$2,$3,$4,$5)',
    [institution, name, lat, lon, radius],
  )
  await insert('one', 'Main Terminal')
  await assert.rejects(insert('one', '  MAIN   Terminal  ', 4, 102), { code: '23505' })
  await assert.rejects(insert('one', 'Another name'), { code: '23505' })
  await assert.rejects(insert('one', 'Tiny coordinate difference', 3.14000001), { code: '23505' })
  await db.exec('update service_areas set active = false where id = 1')
  await assert.rejects(insert('one', 'Main Terminal'), { code: '23505' })
  await insert('two', 'Main Terminal')
  await insert('one', 'Other Terminal', 4, 102)
  await assert.rejects(db.exec("update service_areas set name='main terminal' where name='Other Terminal'"), { code: '23505' })
  await db.exec('update service_areas set active = true where id = 1')
  assert.equal((await db.query('select count(*)::int as count from service_areas')).rows[0].count, 3)
  console.log('PASS: Duplicate names/coverage, rounded coordinates, inactive areas, edits, institution isolation and migration reapplication')
} finally {
  await db.close()
}
