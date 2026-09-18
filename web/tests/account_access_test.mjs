import assert from 'node:assert/strict'
import { validatePortalContext, validateNewPassword, portalAccessMessage } from '../src/lib/accountAccess.js'

const institution = { id: 'institution', account_user_id: 'manager', active: true, verification_status: 'email_verified' }
const manager = { role: 'manager', institutions: institution }
const staff = { role: 'staff', institutions: institution, staff: { auth_user_id: 'staff', institution_id: 'institution', role: 'staff', active: true } }
assert.equal(validatePortalContext(manager, 'manager'), manager)
assert.equal(validatePortalContext(staff, 'staff'), staff)
for (const [context, user] of [[null,'traveller'],[manager,'traveller'],[staff,'traveller'],[staff,'other-staff'],[{ ...staff, staff: { ...staff.staff, institution_id: 'other' } },'staff']]) {
  assert.throws(() => validatePortalContext(context, user), error => error.message === portalAccessMessage)
}
assert.throws(() => validatePortalContext({ ...staff, staff: { ...staff.staff, active: false } }, 'staff'), /not active/)
assert.throws(() => validatePortalContext({ ...manager, institutions: { ...institution, active: false } }, 'manager'), /not active/)
assert.throws(() => validatePortalContext({ ...manager, institutions: { ...institution, verification_status: 'pending' } }, 'manager'), /Verify/)
assert.equal(validateNewPassword('NewPassword123', 'NewPassword123'), '')
assert.match(validateNewPassword('NewPassword123', 'Different123'), /do not match/)
assert.match(validateNewPassword('weak', 'weak'), /at least 8/)
assert.match(validateNewPassword('weakpassword', 'weakpassword'), /uppercase/)
console.log('PASS: Linked manager/staff identity, traveller rejection, active/verified accounts, password validation')
