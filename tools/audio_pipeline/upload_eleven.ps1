# Trickle-uploads the ElevenLabs announcer pack (same account-safety rules:
# one per 8 min, poll moderation, stop on rejection). Resumable via
# eleven_uploaded.json.

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Net.Http

$key = $env:ROBLOX_OPEN_CLOUD_KEY
if (-not $key) { Write-Output 'FATAL: no key'; exit 3 }
$creatorId = 7230402132
# trickle gap between uploads (account safety). Default 8 min; override with
# GN_UPLOAD_GAP for a clean-record audio batch. Still stops on any rejection.
$gapSeconds = if ($env:GN_UPLOAD_GAP) { [int]$env:GN_UPLOAD_GAP } else { 480 }
$dir = Join-Path $PSScriptRoot 'eleven'
$manifestPath = Join-Path $PSScriptRoot 'eleven_uploaded.json'
$manifest = @()
if (Test-Path $manifestPath) {
    $manifest = @((Get-Content $manifestPath -Raw | ConvertFrom-Json) | ForEach-Object { $_ })
}
function Save-Manifest { $script:manifest | ConvertTo-Json -Depth 4 | Set-Content $manifestPath -Encoding utf8 }

$client = New-Object System.Net.Http.HttpClient
$client.Timeout = [TimeSpan]::FromSeconds(120)
$client.DefaultRequestHeaders.Add('x-api-key', $key)
function Get-Json($url) {
    $r = $client.GetAsync($url).Result
    $body = $r.Content.ReadAsStringAsync().Result
    if (-not $r.IsSuccessStatusCode) { throw "GET -> $([int]$r.StatusCode): $body" }
    return $body | ConvertFrom-Json
}

$files = Get-ChildItem $dir -Filter *.mp3 | Sort-Object Name
foreach ($f in $files) {
    $name = 'GN Announcer - ' + $f.BaseName
    if ($manifest | Where-Object { $_.name -eq $name -and $_.assetId }) { Write-Output "SKIP $name"; continue }
    $start = Get-Date
    Write-Output "UPLOADING: $name"
    $reqJson = @{
        assetType = 'Audio'; displayName = $name
        description = 'Generated announcer line for Gnarly Nutmeg (Athlete Domains).'
        creationContext = @{ creator = @{ userId = $creatorId } }
    } | ConvertTo-Json -Compress -Depth 5
    $mp = New-Object System.Net.Http.MultipartFormDataContent
    $mp.Add((New-Object System.Net.Http.StringContent($reqJson)), 'request')
    $bytes = [IO.File]::ReadAllBytes($f.FullName)
    $bc = New-Object System.Net.Http.ByteArrayContent(@(, $bytes))
    $bc.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new('audio/mpeg')
    $mp.Add($bc, 'fileContent', $f.Name)
    $resp = $client.PostAsync('https://apis.roblox.com/assets/v1/assets', $mp).Result
    $respBody = $resp.Content.ReadAsStringAsync().Result
    if (-not $resp.IsSuccessStatusCode) { Write-Output "UPLOAD FAILED: $respBody"; Save-Manifest; exit 2 }
    $opPath = ($respBody | ConvertFrom-Json).path
    $assetId = $null
    for ($i = 0; $i -lt 36; $i++) {
        Start-Sleep -Seconds 5
        try { $op = Get-Json "https://apis.roblox.com/assets/v1/$opPath"; if ($op.done) { $assetId = $op.response.assetId; break } } catch {}
    }
    if (-not $assetId) { Write-Output 'OP TIMEOUT'; Save-Manifest; exit 2 }
    Write-Output "  assetId: $assetId"
    $state = 'Reviewing'
    for ($i = 0; $i -lt 18; $i++) {
        try {
            $a = Get-Json "https://apis.roblox.com/assets/v1/assets/$assetId`?readMask=moderationResult"
            $state = $a.moderationResult.moderationState
            if ($state -like '*Approved*' -or $state -like '*Rejected*') { break }
        } catch {}
        Start-Sleep -Seconds 20
    }
    Write-Output "  moderation: $state"
    $script:manifest += [pscustomobject]@{ name = $name; file = $f.BaseName; assetId = "$assetId"; state = "$state" }
    Save-Manifest
    if ($state -like '*Rejected*') { Write-Output 'REJECTED - stopping'; exit 2 }
    $remaining = $gapSeconds - [int]((Get-Date) - $start).TotalSeconds
    if ($remaining -gt 0 -and $f.Name -ne $files[-1].Name) { Start-Sleep -Seconds $remaining }
}
Write-Output 'ELEVEN UPLOADS DONE'
$manifest | ForEach-Object { Write-Output ("RESULT: {0} = {1} ({2})" -f $_.file, $_.assetId, $_.state) }
