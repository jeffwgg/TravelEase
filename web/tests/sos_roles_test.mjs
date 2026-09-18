import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { fileURLToPath } from 'node:url'
import { createElement } from 'react'
import { renderToStaticMarkup } from 'react-dom/server'
import { createServer } from 'vite'
import { MemoryRouter } from 'react-router-dom'

const server = await createServer({ root: fileURLToPath(new URL('..', import.meta.url)), server: { middlewareMode: true } })
try {
  const { default: Card } = await server.ssrLoadModule('/src/components/SosRequestCard.jsx')
  const stages = ['sent', 'acknowledged', 'assigned', 'en_route', 'resolved']
  const labels = ['Acknowledge', 'Confirm assignment', 'Mark On The Way', 'Mark Resolved']
  for (const role of ['manager', 'staff']) {
    for (const status of stages) {
      const html = renderToStaticMarkup(createElement(Card, {
        request: { id: 'sos', status, latitude: 3.1, longitude: 101.6, triggered_at: '2026-09-17T10:00:00Z', traveller: { full_name: 'Traveller Example' } },
        isManager: role === 'manager', canRespond: role === 'staff',
      }))
      const buttons = [...html.matchAll(/<button\b[^>]*>([\s\S]*?)<\/button>/g)].map(match => match[1].replace(/<[^>]*>/g, ''))
      const expected = role === 'manager'
        ? ({ sent: 'Acknowledge', acknowledged: 'Confirm assignment' })[status]
        : ({ assigned: 'Mark On The Way', en_route: 'Mark Resolved' })[status]
      assert.deepEqual(buttons.filter(label => labels.includes(label)), expected ? [expected] : [], `${role}/${status} action matrix`)
      assert.ok(html.includes('Traveller Example'))
      assert.ok(html.includes('3.100000'))
      assert.ok(buttons.some(label => /Tracking Map|View Location/.test(label)))
      assert.equal(html.includes('aria-label="Assign a responder"'), role === 'manager' && status === 'acknowledged')
    }
  }
  console.log('PASS: Manager/Staff action matrix for all five states, traveller details and location controls')
  const { default: Overview } = await server.ssrLoadModule('/src/components/StaffSosOverview.jsx')
  const renderOverview = tasks => renderToStaticMarkup(createElement(MemoryRouter, null, createElement(Overview, {
    tasks, staff: { name: 'Responder', active: true, status: tasks.some(task => task.status !== 'resolved') ? 'assigned' : 'free' },
  })))
  assert.match(renderOverview([]), /No active emergency task/)
  assert.match(renderOverview([]), />Free</)
  const task = { id: 'my-task', status: 'assigned', traveller: { full_name: 'My traveller' }, service_area: { name: 'Concourse' }, triggered_at: '2026-09-18T10:00:00Z' }
  const activeHtml = renderOverview([task])
  assert.match(activeHtml, /href="\/sos\?task=my-task"/)
  assert.match(activeHtml, /Open task/)
  assert.match(activeHtml, /Assigned \/ Busy/)
  assert.match(renderOverview([{ ...task, status: 'en_route' }]), /On The Way/)
  const completedHtml = renderOverview([{ ...task, status: 'resolved', resolved_at: '2026-09-18T11:00:00Z' }])
  assert.match(completedHtml, /Recent completed tasks/)
  assert.match(completedHtml, /My traveller/)
  assert.doesNotMatch(completedHtml, /Open task/)
  console.log('PASS: Staff dashboard active/empty/completed states, availability and task links')
} finally {
  await server.close()
}

// Execute the real repository against a recording client without network calls.
const source = await readFile(new URL('../src/repositories/sosRequestRepository.js', import.meta.url), 'utf8')
const calls = []
const query = new Proxy({}, { get: (_target, key) => key === 'then'
  ? (resolve) => resolve({ data: [], error: null })
  : (...args) => { calls.push([key, ...args]); return query } })
globalThis.__sosTestClient = { from: (...args) => { calls.push(['from', ...args]); return query } }
try {
  const moduleSource = source.replace("import { supabase } from '../lib/supabase'", 'const supabase = globalThis.__sosTestClient')
  const { sosRequestRepository: repo, availableSosStaff } = await import(`data:text/javascript;base64,${Buffer.from(moduleSource).toString('base64')}`)
  const staff = { id: 'free', institution_id: 'institution', role: 'staff', active: true, status: 'free', auth_user_id: 'account' }
  assert.deepEqual(availableSosStaff([
    staff, { ...staff, id: 'busy', status: 'assigned' }, { ...staff, id: 'inactive', active: false },
    { ...staff, id: 'foreign', institution_id: 'other' }, { ...staff, id: 'unlinked', auth_user_id: null },
    { ...staff, id: 'manager', role: 'manager' }, { ...staff, id: 'occupied' },
  ], [{ assigned_staff_id: 'occupied', status: 'en_route' }], 'institution').map(member => member.id), ['free'])
  await repo.listForInstitution('institution', 'staff-account-row')
  assert.ok(calls.some(([method, column, value]) => method === 'eq' && column === 'institution_id' && value === 'institution'))
  assert.ok(calls.some(([method, column, value]) => method === 'eq' && column === 'assigned_staff_id' && value === 'staff-account-row'))
  for (const current of ['sent', 'acknowledged', 'assigned', 'resolved']) {
    await assert.rejects(repo.updateStatus('institution', 'request', current, 'resolved'), /Invalid SOS workflow/)
  }
  calls.length = 0
  await repo.updateStatus('institution', 'request', 'assigned', 'en_route')
  assert.ok(calls.some(([method, column, value]) => method === 'eq' && column === 'status' && value === 'assigned'), 'updates guard against stale request status')
  console.log('PASS: Staff query scope, no lifecycle shortcuts, optimistic status guard')
} finally {
  delete globalThis.__sosTestClient
}
