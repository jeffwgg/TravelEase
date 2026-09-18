# Institution SOS permissions and assignment

The lifecycle is strictly `sent -> acknowledged -> assigned -> en_route -> resolved`.

| Status | Manager | Assigned staff |
| --- | --- | --- |
| sent | Acknowledge | Not visible |
| acknowledged | Assign Staff | Not visible |
| assigned | Monitor | Mark On The Way |
| en_route | Monitor | Mark Resolved |
| resolved | View history | View own completed task |

Managers see all requests in their institution. Staff queries and realtime subscriptions
filter by their own `institution_staff.id`, and RLS enforces that assignment independently
of the browser. Both roles can view traveller details and location for permitted requests.
Travellers retain access to their own SOS history.

Only active staff accounts in the same institution whose existing `status` is `free`
can be assigned. The existing SOS validator atomically updates staff to `assigned`;
a conditional row update and unique index prevent competing SOS requests from reserving
the same responder. Resolution frees the responder in the same transaction. Staff
management cannot mark an occupied responder free, deactivate them, unlink their login,
or delete them during a task. No new tables or parallel assignment API are introduced.

## Database deployment

Apply `server/supabase/migrations/022_sos_role_permissions_and_availability.sql` after
migrations 019, 020 and 021, before releasing the web changes. It replaces the existing
`validate_sos_progress` function and tightens RLS, including SOS live-location reads.
Migration 021 remains necessary for the legacy three-state validator, whose original
migrations are absent from this checkout. Unknown deployed triggers still need review.

Migration 022 reuses `institution_staff.role`, `auth_user_id`, `active`, and `status`
(`free` / `assigned`). Accounts without a linked login cannot be assigned. Existing active
SOS assignments are marked occupied. If records assign multiple ongoing SOS requests to
one responder, the unique index stops the migration transaction: reconcile those records
before retrying. The migration does not silently reassign or resolve emergencies.

Validated locally; not applied to hosted Supabase in this session.

## Local verification

From the repository root:

```text
node server/supabase/tests/sos_roles_test.mjs
node server/supabase/tests/sos_history_test.mjs
node web/tests/sos_roles_test.mjs
```

SQL tests use the local PGlite installation documented in `sos_history_test.mjs`.
They test real RLS/trigger execution, including broad legacy policies, role restrictions,
invalid transitions, busy staff rejection, transaction rollback, freeing/reusing staff,
and scoped profile/location reads. Web tests render both roles in all five states and
check repository filters, staff eligibility, and stale-status protection. Tests do not
simulate separate concurrent PostgreSQL connections or a deployed Supabase session.
