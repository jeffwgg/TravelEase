# LibreTranslate for TravelEase

TravelEase has a Docker-based LibreTranslate service, but it is **not online at
all times**. If you need to use the existing service, contact the TravelEase
team and ask them to start it.

There is no permanently available public TravelEase translation endpoint. If
you need a service that you control or that remains available independently,
host your own LibreTranslate instance and connect your own (or an approved)
Supabase project to it.

## Run a local instance

You need Docker Desktop (or Docker Engine with Docker Compose) and a copy of
this project. From this directory, start LibreTranslate:

```powershell
docker compose up -d libretranslate
docker compose ps
docker compose logs -f libretranslate
```

The first start downloads the English, Bahasa Melayu, and Simplified Chinese
models, so it can take a few minutes. Check that it is ready with:

```powershell
curl.exe http://localhost:5000/languages
```

Create an API key for TravelEase to use:

```powershell
docker compose exec libretranslate ltmanage keys --api-keys-db-path /app/db/api_keys.db add 120 --char-limit 5000
```

Save the generated key securely. Do not put it in client code or commit it to
Git.

## Make a self-hosted instance reachable

Hosted Supabase Edge Functions cannot access `localhost` on your computer.
Your instance therefore needs a public HTTPS base URL, such as
`https://translate.example.com`.

For temporary development, the included Cloudflare Quick Tunnel can expose the
local service:

```powershell
docker compose --profile tunnel up -d
docker compose logs -f cloudflared
```

Copy the `https://...trycloudflare.com` URL from the logs. It changes when the
tunnel restarts, so it is not appropriate for an always-on service.

For a permanent service, host the Compose stack on a server that stays online
and expose it through HTTPS with your preferred domain, reverse proxy, and
firewall configuration. Keep the LibreTranslate API key private and do not
expose port 5000 directly to the internet.

## Connect it to Supabase

You need access to the Supabase project used by your TravelEase deployment.
From the `web` directory, sign in and link that project:

```powershell
npx supabase login
npx supabase link --project-ref YOUR_PROJECT_REF
```

Set the public **base URL** (without `/translate`) and the API key:

```powershell
npx supabase secrets set "LIBRETRANSLATE_URL=https://translate.example.com"
npx supabase secrets set "LIBRETRANSLATE_API_KEY=YOUR_GENERATED_KEY"
```

Enable LibreTranslate for announcement translation and deploy the functions if
you are setting up a new project:

```powershell
npx supabase secrets set "TRANSLATION_PROVIDER=libretranslate"
npx supabase functions deploy translate-announcement
npx supabase functions deploy translate-mobile-text
```

`translate-mobile-text` uses LibreTranslate whenever its URL and key are set.
`translate-announcement` uses Google by default, so it needs
`TRANSLATION_PROVIDER=libretranslate` to use your host.

Supabase secrets are project-wide. Do not change a shared TravelEase project's
translation URL to a personal machine without the team's approval. If the
Quick Tunnel URL changes, update `LIBRETRANSLATE_URL` again; the helper below
can do that after the project has been linked:

```powershell
powershell -ExecutionPolicy Bypass -File .\update-tunnel-secret.ps1
```
