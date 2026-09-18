# SOS and emergency communication history

The mobile profile's SOS History and Communication History use the existing SOS
repository and history ViewModel. Saved translation conversations remain a separate
feature and are now labelled **Saved conversations**.

## Sources and persistence

- `sos_requests` is authoritative for institution requests and current progress.
  Ending mobile alerts does not resolve an institution request.
- The existing draft `019_traveller_sos_history.sql` stores activation/contact
  notification metadata in `traveller_sos_events`, including contact-only SOS
  activations with no location or matching institution. Its request-copy backfill
  has been removed. Existing backfilled rows, if already deployed, still work.
- `020_sos_progress_and_history.sql` adds only `sos_requests.assigned_staff_id`,
  referencing `institution_staff`. No new staff/communication/history table is
  added by 020, and no requests are copied.
- `get_traveller_sos_history()` merges the authenticated user's request rows with
  optional event metadata. It includes old requests with no event, and matches
  unlinked events by the same traveller and exact trigger timestamp. A request
  appears once even when its metadata link write failed.
- Communication History contains attempted emergency contact notifications and
  institution SOS notifications, sorted by timestamp. It never queries dialogue,
  translation or saved-conversation tables. Historical contact sends that were
  never recorded cannot be reconstructed. Contact success means the existing
  Edge Function returned success; it is not a delivery/read receipt.
- History creation retries use the existing `(traveller_id, triggered_at)` unique
  key. Queued metadata outcomes are flushed after emergency actions complete.
  Network/database failures do not prevent emergency actions; persistence remains
  best effort if connectivity fails or the process is killed. No new notification
  sender or duplicate institution-notification table is introduced.

## Progress and access

The web SOS page uses the strict lifecycle `sent -> acknowledged -> assigned -> en_route -> resolved`. Managers acknowledge and assign active, free staff from their institution, then monitor. Only the assigned staff account marks On The Way and Resolved. Migration 022 reserves the existing staff availability field atomically and releases it on resolution. Updates compare the existing request status to reject stale actions; no early resolution is allowed.

Mobile list/detail reads current request progress, institution, area, coordinates,
and assigned staff. The detail refreshes on entry, manually, and every 15 seconds
while the history route remains mounted. Staff contact is shown only while the
request is unresolved and the staff member is active. The UI marks the current
stage without claiming all earlier stages occurred.

The history RPC is a narrowly scoped `SECURITY DEFINER` projection with an empty
search path and explicit `auth.uid()` filters on both underlying sources. It
exposes only the assigned staff name/work contact, never staff emails/auth IDs or
private institution profiles. Restrictive RLS boundaries also limit direct SOS
reads/updates and staff directory reads despite older permissive policies. Other
travellers cannot read a request; institution managers can access their institution's requests, and active staff can access only requests assigned to their own account. Active service areas remain readable for matching.

## Deployment and verification

1. If `traveller_sos_events` does not exist, apply migration 019 once. If 019 is
   already deployed, keep those rows and proceed directly to 020.
2. Review/apply 020 to the existing project before releasing the mobile/web
   changes. It expects the existing fields referenced by the current repositories.
3. Check deployed `sos_requests` triggers, especially any legacy function that
   only permits sent/acknowledged/resolved. Those original migrations (011/012)
   and `send-sos-contact` source are absent from this checkout. 020 preserves
   existing triggers rather than guessing which production function to remove.
   The live schema was not accessible in this session and the migration was not
   applied to hosted Supabase.
4. Verify with two traveller accounts and an institution account: each traveller
   sees only their own records; assignment/progress updates reach mobile after
   refresh; a contact-only activation appears in both applicable histories;
   ending local alerts leaves ongoing institution assistance intact.

Useful read-only deployment inspection:

```sql
select column_name, data_type, udt_name
from information_schema.columns
where table_schema = 'public' and table_name = 'sos_requests';
select pg_get_triggerdef(oid), pg_get_functiondef(tgfoid)
from pg_trigger
where tgrelid = 'public.sos_requests'::regclass and not tgisinternal;
select tablename, policyname, permissive, roles, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('sos_requests', 'traveller_sos_events', 'institution_staff', 'service_areas');
```

Automated checks:

- SOS model/ViewModel/widget/lifecycle regression tests, including sign-out,
  notification ordering, current progress, and persistence completion.
- Isolated PostgreSQL tests in `server/supabase/tests/sos_history_test.mjs` cover
  both migrations, reapplying 020, zero backfill, old requests, unlinked metadata,
  restrictive RLS against permissive legacy policies, safe joins, same-institution
  assignment, transitions, and contact privacy. They use a fixture of the schema
  visible in the code, not a copy of the hosted database.
- `flutter analyze --no-pub`: zero errors/new diagnostics; 31 existing findings
  remain elsewhere (3 warnings, 28 informational lints).
- Web production build and targeted lint pass. Build retains its existing bundle
  size warning.
