# Traveller mobile update

The existing View → ViewModel → Repository → Supabase and ViewModel → Service boundaries are retained. No package, service or repository was added. Existing SOS matching and contact notification delivery are reused.

## Files changed

Paths below are relative to `mobile/` unless stated otherwise.

| Area | Files |
| --- | --- |
| Registration and email-only auth | `lib/core/traveller_name.dart` (new), `lib/viewmodels/auth_viewmodel.dart`, `lib/views/auth/authentication_view.dart` |
| Profile-backed greeting and profile-edit refresh | `lib/models/repositories/profile_repository.dart`, `lib/viewmodels/profile_viewmodel.dart`, `lib/views/location/venue_identification_view.dart` |
| Remove remaining sample caller name | `lib/services/webrtc_service.dart` |
| SOS alert lifecycle | `lib/core/hardware_services.dart`, `lib/services/flash_alert_service.dart`, `lib/services/accessibility_alert_service.dart`, `lib/viewmodels/sos_viewmodel.dart`, `lib/views/emergency/sos_active_view.dart`, `lib/views/emergency/sos_countdown_view.dart` |
| History data | `lib/models/repositories/sos_repository.dart`, `lib/models/entities/sos_history_entry.dart` (new), `lib/viewmodels/sos_history_viewmodel.dart` (new) |
| History pages and navigation | `lib/views/emergency/sos_history_view.dart` (new; contains both pages), `lib/core/router.dart`, `lib/views/profile/profile_management_view.dart` |
| Tests | `test/traveller_name_test.dart`, `test/profile_greeting_test.dart`, `test/sos_history_test.dart`, `test/sos_lifecycle_test.dart`, `test/sos_flash_test.dart` (all new) |
| Database | `server/supabase/migrations/019_traveller_sos_history.sql` (new, relative to repository root) |

Earlier SDK setup changes in `mobile/README.md`, `.fvmrc` and local VS Code settings are separate from this update.

## Database deployment and history sources

Apply migration `019_traveller_sos_history.sql` to the existing Supabase project before using the history pages. It has been added locally, not applied to the hosted database. It expects the existing `sos_requests`, `institutions` and `service_areas` tables used by the current app.

The migration adds one table, `traveller_sos_events`, with owner-only SELECT/INSERT/UPDATE policies, and traveller read access to their own existing institution SOS requests. The repository also filters queries by the authenticated traveller ID. History state is cleared on sign-out, including pending responses.

The follow-up migration 020 reads existing institution SOS requests directly instead of backfilling copies. It joins current institution/service-area names and staff/progress data through an owner-scoped history function. Older contact notifications cannot be reconstructed from the checked-in code and are not fabricated. See [SOS history and progress](sos-history-progress.md) for deployment instructions and the updated data/access model.

Future events are recorded when SOS activates, even with no location or matched institution. Communication History derives contact notification entries from the existing `send-sos-contact` result, and institution entries from the existing service-area matching/request-creation result. Current institution request status is read from `sos_requests`; recipient names are retained as event snapshots. Contact success means the function confirmed the notification, not that the recipient read it. Only attempted communications appear. Dates are displayed in local time, newest first.

History writes run independently of emergency actions. A database/network failure can prevent history persistence but cannot block alerts, location retrieval, contact notification or institution matching. No production SOS or contact message was sent during testing.

## Device lifecycle

`SosViewModel.activateSos` is idempotent and starts existing device services independently of location and network work. The countdown does not start device alerts. The active screen blocks accidental back navigation.

`HardwareServices` owns one dedicated looping audio player using `ReleaseMode.loop` and its existing generated WAV helper. `FlashAlertService` owns a steady torch session and serializes start/stop against notification flashes. A process-local ownership marker also suppresses background-isolate notification flashes during SOS. Existing vibration preference checks and waveform remain in `AccessibilityAlertService`.

End SOS, screen disposal and sign-out all stop the alerts. Queued cleanup disables the torch, releases its ownership marker, stops/disposes the player and cancels vibration. Late location results do not initiate new emergency operations after the lifecycle has ended. Hardware failures are handled independently of emergency requests.

Physical flashlight/audio behavior still needs a controlled phone check; automated tests mock device methods and emergency delivery.

## Verification

- Flutter 3.47.1 / Dart 3.13.1: full `flutter test --no-pub` suite passed, 45 tests.
- `flutter analyze --no-pub`: no errors or new diagnostics; 31 pre-existing findings remain (3 warnings and 28 informational lints). The command returns exit code 1 because of those existing findings.
- `git diff --check` passed.
- Native test hooks initially failed because the SDK path contains spaces. Tests ran successfully through a temporary `subst` drive alias to the same pinned SDK; no dependency or SDK version change was needed.
- The SQL migration has not been applied or integration-tested against the hosted database. No production emergency notification was sent.
