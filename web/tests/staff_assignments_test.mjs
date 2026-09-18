import assert from 'node:assert/strict'
import { mergeStaffAssignments } from '../src/lib/staffAssignments.js'

const assistance = [
  { id: 'a', assigned_staff_id: 'me', status: 'in_progress', request_category: 'communication', traveler_name: 'Assistance traveller' },
  { id: 'other', assigned_staff_id: 'someone-else', status: 'pending' },
]
const sos = [
  { id: 's', assigned_staff_id: 'me', status: 'assigned', traveller: { full_name: 'SOS traveller' }, service_area: { name: 'Gate A' }, triggered_at: '2026-09-18T10:00:00Z' },
  { id: 'done', assigned_staff_id: 'me', status: 'resolved' },
  { id: 'private', assigned_staff_id: 'someone-else', status: 'en_route' },
]
const combined = mergeStaffAssignments(assistance, sos, 'me')
assert.equal(combined.length, 3)
assert.equal(combined[0].request_category, 'communication')
assert.equal(combined[0].destination, '/requests')
assert.equal(combined[1].request_category, 'emergency')
assert.equal(combined[1].traveler_name, 'SOS traveller')
assert.equal(combined[1].location_zone, 'Gate A')
assert.equal(combined[1].created_at, sos[0].triggered_at)
assert.equal(combined[1].destination, '/sos?task=s')
assert.equal(combined[1].urgency, 'urgent')
assert.equal(combined[2].urgency, 'normal')
assert.deepEqual(mergeStaffAssignments(assistance, sos, null), [])
assert.equal(assistance[0].request_type, undefined, 'source rows remain unchanged')
console.log('PASS: Combined assistance/SOS dashboard data, staff scope, task destinations and resolved priority')
