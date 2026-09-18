# Staff workspace and account access

## Deployment

Apply `server/supabase/migrations/023_account_access_and_staff_profile.sql` after
022 before releasing the updated mobile app and portal. This migration has been
tested locally, but has not been applied to hosted Supabase in this session.

No new tables or authentication providers are introduced. The mobile app calls
`is_traveller_account()` after password login, during session restoration/auth
events, and before password changes. The helper requires a `user_profiles` row
and rejects any account linked to `institutions.account_user_id` or
`institution_staff.auth_user_id`, including inactive institution accounts. It
does not trust editable user metadata. Historical automatic traveller profiles
on institution accounts do not grant mobile access. Missing/failed validation
leaves the mobile protected routes inaccessible.

The web provider validates the manager/staff relationship before exposing a
session to protected routes, including restored sessions and auth callbacks.
Active institution/staff and manager email verification checks remain in place.
Wrong-account sessions are signed out locally and the requested access message
is displayed. Supabase Auth still handles credentials, recovery, and password
updates; this is application access validation, not a second login system.

## Staff workspace

- Dashboard: original assistance dashboard layout retained. Its existing totals,
  progress, categories and recent assignments include both assistance and SOS
  tasks assigned to the current staff member.
- SOS / Emergency: the new staff overview lives here, showing availability,
  active-task links and five most recent SOS completions ordered by resolution time.
- Emergency page: compact cards, readable status chips, small progress markers,
  collapsible responder selection, and task links that focus the requested card.
- Profile: own name editor, read-only email, institution, role and availability,
  plus confirmed password changes through Supabase Auth. Password changes sign
  out the local session so the user signs in again.
- Name updates use `update_my_staff_name(p_name)` with no caller-supplied identity.
  The server validates the authenticated active staff member and updates only
  their name. Restrictive policies block direct staff inserts, updates and deletes
  even if older permissive policies allowed them. Manager management and SOS
  assignment triggers retain their existing behavior.

Dashboard/profile data refresh every ten seconds and on assigned-SOS events.
There is no second assignment workflow; migration 022 remains authoritative for
availability and the Manager/Staff transition permissions.

## Verification

```text
node server/supabase/tests/sos_roles_test.mjs
node server/supabase/tests/sos_history_test.mjs
node web/tests/account_access_test.mjs
node web/tests/sos_roles_test.mjs
cd web
npm run build
npm run lint
cd ../mobile
flutter test --no-pub test/auth_account_access_test.dart
```

SQL tests use the local PGlite installation described in `sos_history_test.mjs`.
They include account segregation with duplicate historical profiles, self-service
field restrictions, and SOS lifecycle checks after the new policies. Web tests
cover account validation, password confirmation, role actions, dashboard states,
staff filtering and task links. Mobile tests exercise the real auth repository
against mocked HTTP responses for accepted, rejected and failed access checks.

No connected browser was available for visual verification in this session.
