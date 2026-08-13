# Self-hosted LibreTranslate for TravelEase

## Local development

From this directory, run:

```powershell
docker compose up -d
```

If an older TravelEase volume fails with a permission error under
`/home/libretranslate/.local`, recreate the empty model volume once:

```powershell
docker compose down -v
docker compose up -d
```

This deletes only the locally downloaded LibreTranslate model cache. It does
not affect TravelEase or Supabase data.

Confirm the service is ready:

```powershell
curl.exe http://localhost:5000/languages
```

The first startup can take several minutes while the English, Malay, and Chinese
models are downloaded. Model files are retained in the Docker volume.

## Create the TravelEase API key

Anonymous translation requests are disabled. Create a persistent key after the
container is running:

```powershell
docker compose exec libretranslate ltmanage keys --api-keys-db-path /app/db/api_keys.db add 120 --char-limit 5000
```

Store the generated value as the Supabase Edge Function secret
`LIBRETRANSLATE_API_KEY`. Do not add it to either client app or commit it to Git.

## Temporary public HTTPS URL for development

Start the opt-in Cloudflare Quick Tunnel profile:

```powershell
docker compose --profile tunnel up -d
docker compose logs cloudflared
```

Copy the generated `https://...trycloudflare.com` URL and store it as the
Supabase Edge Function secret `LIBRETRANSLATE_URL`. Quick Tunnel URLs change
when the tunnel container is recreated and are intended only for testing.

## Hosted Supabase requirement

A hosted Supabase Edge Function cannot access `localhost` on your computer.
For production, deploy this Compose service to an internet-accessible server,
put it behind HTTPS, and set this Edge Function secret:

```text
LIBRETRANSLATE_URL=https://translate.your-domain.com
```

`LIBRETRANSLATE_API_KEY` is optional. Leave it unset unless API-key enforcement
is enabled on your self-hosted LibreTranslate instance.

After setting the URL, deploy `supabase/functions/translate-announcement` with
JWT verification enabled.
