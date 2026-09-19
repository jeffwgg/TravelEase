# TravelEase

TravelEase is an accessibility travel platform that helps travellers with disabilities navigate public venues such as airports. Travellers use the Flutter mobile app for sign-language translation, two-way communication with staff, emergency SOS, venue announcements, queue tracking, and assistance requests. Institution staff use the React web dashboard to respond to SOS and assistance requests, manage staff and queue lines, publish translated announcements, and review accessibility analytics.

The backend is a hosted [Supabase](https://supabase.com) project (Postgres, Auth, Realtime, Edge Functions). The translation feature runs on a self-hosted LibreTranslate instance that you start with Docker.

## Repository layout

| Directory | What it is |
|---|---|
| `mobile/` | Flutter app for travellers (Android/iOS). |
| `web/` | React + Vite dashboard for institution staff. |
| `server/supabase/` | Emergency-contact edge functions (SOS contact, OTP). |
| `web/supabase/` | Web-owned edge functions (translation, queue lines, venue search) and the LibreTranslate Docker setup. |

## Prerequisites

- **Node.js 18+** — for the web dashboard.
- **Flutter 3.47.1 via FVM** — for the mobile app. See [Mobile toolchain](#mobile-toolchain) below.
- **JDK 17** — for Android builds.
- **Docker** — only required if you run the self-hosted translation service (LibreTranslate).
- A **Supabase project** — use the shared team project, or any project where the TravelEase schema is already applied.

## Environment variables

Each app has its own `.env` file. Copy the committed `.env.example` in each directory and fill in your values. Never commit `.env`.

| Variable | File | Purpose |
|---|---|---|
| `VITE_SUPABASE_URL` | `web/.env` | Supabase project URL (Dashboard → Project Settings → API). |
| `VITE_SUPABASE_ANON_KEY` | `web/.env` | Supabase anon (public) API key. |
| `VITE_GOOGLE_MAPS_API_KEY` | `web/.env` | Google Maps Geocoding API key for address search on staff pages. |
| `SUPABASE_URL` | `mobile/.env` | Supabase project URL. |
| `SUPABASE_ANON_KEY` | `mobile/.env` | Supabase anon (public) API key. |
| `GOOGLE_MAPS_API_KEY` | `mobile/.env` | Google Maps Geocoding API key for reverse geocoding in assistance features. |
| `HMS_API_KEY` | `mobile/.env` (optional) | Huawei AppGallery Connect API key for Mandarin speech services. |

Secrets used only by Supabase Edge Functions (`LIBRETRANSLATE_URL`, `LIBRETRANSLATE_API_KEY`, `RESEND_API_KEY`) are stored with `supabase secrets set`, not in any `.env` file. See the translation guide linked below.

## Running the web dashboard

```bash
cd web
cp .env.example .env        # then fill in the three values
npm install
npm run dev                 # dev server on http://localhost:5173
```

Other scripts: `npm run build` (production build into `web/dist`), `npm run preview`, `npm run lint`.

## Running the mobile app

```bash
cd mobile
cp .env.example .env        # then fill in SUPABASE_URL, SUPABASE_ANON_KEY, GOOGLE_MAPS_API_KEY
fvm install                 # installs the pinned Flutter SDK once
fvm flutter pub get
fvm flutter run             # or: fvm flutter build apk --debug
```

The mobile `.env` is bundled as a Flutter asset (declared in `pubspec.yaml`) and loaded at startup with `flutter_dotenv`, so you must rebuild the app after changing it.

## Mobile toolchain

All Android builds use the versions checked into this repository:

- Flutter 3.47.1 (Dart 3.13.1), defined in `mobile/.fvmrc`
- JDK 17
- Gradle 9.1.0, Android Gradle Plugin 9.0.1, and Kotlin 2.3.20, supplied by the checked-in Android project

Install [FVM](https://fvm.app/) once, then run these commands from `mobile/`:

```powershell
dart pub global activate fvm
fvm install
fvm flutter pub get
fvm flutter build apk --debug
```

Use `fvm flutter` for Flutter commands, or use the Windows wrapper described below when SDK paths contain spaces. Do not use a globally installed Flutter SDK to build it.

### Windows: SDK version mismatch

If `flutter pub get` reports Dart 3.11.5 but requires `>=3.13.1`, your terminal is using an older global Flutter installation. Keep the SDK constraints and lockfile; install and use the version in `.fvmrc` instead.

If PowerShell cannot find `fvm` after installation, these commands work without changing PATH. Run them from `mobile/`:

```powershell
dart pub global run fvm:main install
dart pub global run fvm:main flutter --version
dart pub global run fvm:main flutter pub get
```

To enable the shorter `fvm` command for the current PowerShell session (with the default Pub cache location):

```powershell
$env:Path += ";$env:LOCALAPPDATA\Pub\Cache\bin"
```

For VS Code opened at the repository root, set `dart.flutterSdkPath` to `mobile/.fvm/flutter_sdk` in workspace settings after installation. If only `mobile/` is open, use `.fvm/flutter_sdk`. Reload VS Code so the Dart extension uses the project SDK.

### Windows: SDK paths with spaces

On Windows, use `.\flutterw.cmd` instead of `fvm flutter` if the SDK path contains spaces. From `mobile/`, run `.\flutterw.cmd build apk --debug` or `.\flutterw.cmd run`. The wrapper invokes the pinned FVM SDK using Windows short names. If short names are unavailable, install the pinned SDK in a path without spaces.

For IDE builds, `dart.flutterSdkPath` must also point to a space-free absolute SDK path instead of the relative path above. Configure this in local VS Code settings and reload VS Code after changing the setting.

### Dependency policy

`mobile/pubspec.lock` is committed and is part of the build configuration. Use `fvm flutter pub get` after pulling changes; do not run `pub upgrade` unless deliberately updating dependencies and committing both `pubspec.yaml` and `pubspec.lock`.

The app previously pinned `video_player` 2.8.2, which selected `video_player_android` 2.4.17. That Android plugin still referenced Flutter's removed `PluginRegistry.Registrar` API, so builds failed on newer Flutter SDKs. The tested `video_player` 2.14.0 resolution selects `video_player_android` 2.12.2 instead.

Use these same Flutter and Java versions for local builds.

## Supabase backend

The database schema is managed directly in the hosted Supabase project. Edge Functions are deployed with the Supabase CLI:

```bash
# from web/ for web-owned functions
supabase functions deploy translate-announcement
supabase functions deploy translate-mobile-text
supabase functions deploy create-queue-line
supabase functions deploy search-venues

# from server/ for emergency-contact functions
supabase functions deploy send-sos-contact
supabase functions deploy request-emergency-contact-otp
```

Server-side secrets are configured once per project and never appear in client code:

```bash
supabase secrets set LIBRETRANSLATE_URL=<your-libretranslate-url>
supabase secrets set LIBRETRANSLATE_API_KEY=<your-libretranslate-key>
supabase secrets set RESEND_API_KEY=<your-resend-key>
```

## Docker: self-hosted translation service (LibreTranslate)

Announcement translation (English → Malay / Chinese) runs through a self-hosted LibreTranslate server so no third-party translation API key is needed in the clients. Start it with Docker from `web/supabase/libretranslate`:

```bash
cd web/supabase/libretranslate
docker compose up -d
```

First startup takes several minutes while the language models download. After it is healthy, create an API key and store it as the `LIBRETRANSLATE_API_KEY` Supabase secret. For local development you can expose LibreTranslate to the hosted edge functions with the opt-in Cloudflare tunnel profile (`docker compose --profile tunnel up -d`).

Full step-by-step instructions, including key creation, the tunnel workflow, and production hosting, are in:

- [web/supabase/libretranslate/README.md](web/supabase/libretranslate/README.md) — Docker setup and secrets.
- [web/supabase/TRANSLATION_FUNCTION_GUIDE.md](web/supabase/TRANSLATION_FUNCTION_GUIDE.md) — how the translation flow works end to end.

If someone else already hosts LibreTranslate and the Supabase secrets are set, you do not need Docker at all.
