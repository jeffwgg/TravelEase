# TravelEase Translation Function Guide

This guide is for teammates who need to run, maintain, or call the automatic announcement translation used by Module 2.

## What the translation flow uses

The translation feature has three layers:

1. `supabase/libretranslate/docker-compose.yml` runs the self-hosted LibreTranslate server and an optional Cloudflare development tunnel.
2. `supabase/functions/translate-announcement/index.ts` is the authenticated Supabase Edge Function. It validates the institution account and forwards English text to LibreTranslate.
3. `src/repositories/announcementRepository.js` exposes `announcementRepository.translateAnnouncement(...)` for web pages.

The announcement form calls that repository method from `src/pages/CreateAnnouncementPage.jsx`.

Supported target language codes are:

- `ms` — Bahasa Melayu
- `zh` — Simplified Chinese

The Edge Function only accepts a signed-in user linked to an active institution through `institutions.account_user_id`. Do not use `institution_staff` for this feature.

## If you only need to use translation in web code

You do not need to install Docker when another teammate or server is already hosting LibreTranslate and the Supabase secrets are valid.

Import and call the existing repository method:

```javascript
import { announcementRepository } from '../repositories/announcementRepository'

const translations = await announcementRepository.translateAnnouncement({
  title: 'Gate change',
  message: 'Flight MH123 will now depart from Gate B12.',
  targetLanguages: ['ms', 'zh'],
})

console.log(translations.ms.title)
console.log(translations.ms.message)
console.log(translations.zh.title)
console.log(translations.zh.message)
```

Expected response shape:

```json
{
  "ms": {
    "title": "...",
    "message": "..."
  },
  "zh": {
    "title": "...",
    "message": "..."
  }
}
```

The Supabase JavaScript client automatically sends the current session when `supabase.functions.invoke(...)` is used. The user must therefore sign in with a linked institution account before calling the function.

## Install Docker Desktop on Windows

Docker is required only for the teammate hosting the local LibreTranslate service.

1. Confirm that hardware virtualization is enabled and WSL is available:

   ```powershell
   wsl --version
   ```

2. If WSL is missing, open PowerShell as administrator and run:

   ```powershell
   wsl --install
   ```

   Restart Windows when requested.

3. Download and install [Docker Desktop for Windows](https://docs.docker.com/desktop/setup/install/windows-install/). Use the WSL 2 backend.
4. Launch Docker Desktop and wait until the Docker engine reports that it is running.
5. Open a new PowerShell window and verify the installation:

   ```powershell
   docker --version
   docker compose version
   ```

If PowerShell still says that `docker` is not recognized, close and reopen PowerShell after Docker Desktop starts. Restart Windows if the installation changed WSL or PATH settings.

## Start LibreTranslate

From the repository:

```powershell
cd C:\Users\jieer\Documents\GitHub\TravelEase\web\supabase\libretranslate
docker compose up -d libretranslate
docker compose logs -f libretranslate
```

The first startup downloads the English, Malay, and Chinese models and may take several minutes. Wait for the log to report that Gunicorn is listening on port `5000`, then press `Ctrl+C` to stop following the logs. The container continues running.

Check the local service:

```powershell
curl.exe http://localhost:5000/languages
```

Useful container commands:

```powershell
docker compose ps
docker compose restart libretranslate
docker compose logs --tail 100 libretranslate
docker compose stop
```

Do not run `docker compose down -v` during normal use. The `-v` option deletes the local model and API-key volumes.

## Create a LibreTranslate API key

Only do this when the current Docker volume does not already contain a valid key:

```powershell
docker compose exec libretranslate ltmanage keys --api-keys-db-path /app/db/api_keys.db add 120 --char-limit 5000
```

The command prints a key. Store it securely as the Supabase secret `LIBRETRANSLATE_API_KEY`. Never put it in React, Flutter, Git, screenshots, or chat messages.

To test the local service without displaying the key in the command history:

```powershell
$libreKey = Read-Host "LibreTranslate API key"
$requestBody = @{
  q = @('Gate change', 'Proceed to Gate B12.')
  source = 'en'
  target = 'ms'
  format = 'text'
  api_key = $libreKey
} | ConvertTo-Json

Invoke-RestMethod `
  -Uri 'http://localhost:5000/translate' `
  -Method Post `
  -ContentType 'application/json' `
  -Body $requestBody

Remove-Variable libreKey, requestBody
```

## Expose the local service for hosted Supabase

A hosted Supabase Edge Function cannot reach `localhost` on a teammate's computer. For development, start the included Cloudflare Quick Tunnel:

```powershell
cd C:\Users\jieer\Documents\GitHub\TravelEase\web\supabase\libretranslate
docker compose --profile tunnel up -d
docker compose logs --tail 100 cloudflared
```

Copy the generated base URL, for example:

```text
https://random-words.trycloudflare.com
```

Do not add `/translate` to the secret; the Edge Function adds it.

Quick Tunnel URLs are temporary and change when the tunnel is recreated. Cloudflare documents them as development/testing tunnels without an uptime guarantee. A DNS error containing an old `trycloudflare.com` hostname usually means that tunnel stopped and a new URL must be generated. For a shared or production environment, use a named Cloudflare Tunnel or deploy LibreTranslate to a stable HTTPS server.

See the official [Cloudflare Quick Tunnels documentation](https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/trycloudflare/).

## Configure the Supabase Edge Function

From the `web` directory, authenticate and link the correct Supabase project if it is not already linked:

```powershell
cd C:\Users\jieer\Documents\GitHub\TravelEase\web
npx supabase login
npx supabase link --project-ref YOUR_PROJECT_REF
```

Set the tunnel base URL:

```powershell
$translationUrl = Read-Host "LibreTranslate base URL"
npx supabase secrets set "LIBRETRANSLATE_URL=$translationUrl"
Remove-Variable translationUrl
```

Set the API key securely:

```powershell
$libreKey = Read-Host "LibreTranslate API key"
npx supabase secrets set "LIBRETRANSLATE_API_KEY=$libreKey"
Remove-Variable libreKey
```

List secret names to verify they exist:

```powershell
npx supabase secrets list
```

Deploy the function whenever `supabase/functions/translate-announcement/index.ts` changes:

```powershell
npx supabase functions deploy translate-announcement
```

According to the [Supabase secrets documentation](https://supabase.com/docs/guides/functions/secrets), changing a hosted secret takes effect without redeploying the function. Deploying is still required after changing the TypeScript function itself. See also the official [Edge Function deployment guide](https://supabase.com/docs/guides/functions/deploy).

## End-to-end test

1. Keep Docker Desktop, `travelease-libretranslate`, and `travelease-translation-tunnel` running.
2. Confirm the current Quick Tunnel URL is stored as `LIBRETRANSLATE_URL`.
3. Start the web application:

   ```powershell
   cd C:\Users\jieer\Documents\GitHub\TravelEase\web
   npm install
   npm run dev
   ```

4. Sign in using an institution account linked through `institutions.account_user_id`.
5. Open **Announcements → Create Announcement**.
6. Enter an English title and message.
7. Enable **Automatically translate this announcement**.
8. Select Bahasa Melayu and/or Simplified Chinese.
9. Select **Generate & Preview Translations**.
10. Confirm translated title/message fields appear and remain editable.

## Troubleshooting

### DNS error for a `trycloudflare.com` URL

The Quick Tunnel URL expired or the `cloudflared` container stopped:

```powershell
docker compose --profile tunnel up -d
docker compose logs --tail 100 cloudflared
```

Copy the new base URL and update `LIBRETRANSLATE_URL`.

### `docker` is not recognized

Launch Docker Desktop, wait for its engine to start, and open a new PowerShell window. Verify with `docker --version`.

### Translation service is not ready

```powershell
docker compose ps
docker compose logs --tail 100 libretranslate
curl.exe http://localhost:5000/languages
```

The initial language-model download must complete before the container becomes healthy.

### Authentication or institution-access error

Confirm the browser has a valid Supabase session and the signed-in user's ID equals `institutions.account_user_id` for an active institution.

### Invalid Chinese target language

Use the application code `zh`. The Edge Function deliberately sends `zh` to this LibreTranslate deployment.

## Security rules

- Never commit or expose `LIBRETRANSLATE_API_KEY`.
- Never place the key in web or Flutter client code.
- Do not use the Supabase service-role key in either client application.
- Do not log full secrets.
- Only the teammate currently hosting the development tunnel should update `LIBRETRANSLATE_URL`.
- Use a stable hosted endpoint instead of a Quick Tunnel for production.
