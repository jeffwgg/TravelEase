# Copies the current Cloudflare Quick Tunnel URL into the LIBRETRANSLATE_URL
# Supabase secret. Quick Tunnel URLs change every time the cloudflared
# container restarts, so run this script after every tunnel restart.
#
# Usage (from anywhere):
#   powershell -ExecutionPolicy Bypass -File web\supabase\libretranslate\update-tunnel-secret.ps1

$ErrorActionPreference = 'Stop'

Set-Location $PSScriptRoot

$log = docker compose logs cloudflared 2>$null
if ($LASTEXITCODE -ne 0) {
    throw 'Could not read cloudflared logs. Is Docker Desktop running?'
}

$url = $log |
    Select-String -Pattern 'https://[a-z0-9-]+\.trycloudflare\.com' -AllMatches |
    ForEach-Object { $_.Matches.Value } |
    Select-Object -Last 1

if (-not $url) {
    throw 'No trycloudflare.com URL found in the cloudflared logs. Start the tunnel first: docker compose --profile tunnel up -d'
}

Write-Host "Current tunnel URL: $url"

try {
    $probe = Invoke-WebRequest -Uri "$url/languages" -UseBasicParsing -TimeoutSec 20
    if ($probe.StatusCode -ne 200) { throw "HTTP $($probe.StatusCode)" }
    Write-Host 'LibreTranslate answered through the tunnel.'
} catch {
    throw "The tunnel URL did not respond ($($_.Exception.Message)). Check 'docker compose logs cloudflared' and retry."
}

# The supabase CLI must run from the web directory, where supabase/ is linked.
Set-Location (Join-Path $PSScriptRoot '..\..')
npx supabase secrets set "LIBRETRANSLATE_URL=$url"
if ($LASTEXITCODE -ne 0) { throw 'supabase secrets set failed.' }

Write-Host "LIBRETRANSLATE_URL is now set to $url"
