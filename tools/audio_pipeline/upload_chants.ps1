# Trickle-uploads the licensed crowd chant beds (same account-safety rules as
# upload_commentary.ps1: one per 8 min, poll moderation, stop on rejection).
# Resumable via chants_uploaded.json.

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Net.Http

$key = $env:ROBLOX_OPEN_CLOUD_KEY
if (-not $key) { Write-Output 'FATAL: no key'; exit 3 }
$creatorId = 7230402132
$gapSeconds = 480
$root = 'C:\Users\chris\Hytopia-games\Gnarley\assets\audio\sfx\crowd'
$files = @(
    @{ path = "$root\chants\EVG Sound FX - Loyal Fans - Soccer Fans Melodic Chanting.wav"; name = 'GN Crowd - Melodic Chant' },
    @{ path = "$root\chants\Stringer Sound - Ultras - Crowd Chanting Ecstatic.wav";        name = 'GN Crowd - Ultras' }
)
$manifestPath = Join-Path $PSScriptRoot 'chants_uploaded.json'
$manifest = @()
if (Test-Path $manifestPath) {
    $manifest = @((Get-Content $manifestPath -Raw | ConvertFrom-Json) | ForEach-Object { $_ })
}
function Save-Manifest { $script:manifest | ConvertTo-Json -Depth 4 | Set-Content $manifestPath -Encoding utf8 }

$client = New-Object System.Net.Http.HttpClient
$client.Timeout = [TimeSpan]::FromSeconds(180)
$client.DefaultRequestHeaders.Add('x-api-key', $key)
function Get-Json($url) {
    $r = $client.GetAsync($url).Result
    $body = $r.Content.ReadAsStringAsync().Result
    if (-not $r.IsSuccessStatusCode) { throw "GET -> $([int]$r.StatusCode): $body" }
    return $body | ConvertFrom-Json
}

foreach ($f in $files) {
    if ($manifest | Where-Object { $_.name -eq $f.name -and $_.assetId }) { Write-Output "SKIP $($f.name)"; continue }
    if (-not (Test-Path $f.path)) { Write-Output "MISSING: $($f.path)"; continue }
    $start = Get-Date
    Write-Output "UPLOADING: $($f.name)"
    $reqJson = @{
        assetType = 'Audio'; displayName = $f.name
        description = 'Licensed crowd chant bed for Gnarly Nutmeg (Athlete Domains).'
        creationContext = @{ creator = @{ userId = $creatorId } }
    } | ConvertTo-Json -Compress -Depth 5
    $mp = New-Object System.Net.Http.MultipartFormDataContent
    $mp.Add((New-Object System.Net.Http.StringContent($reqJson)), 'request')
    $bytes = [IO.File]::ReadAllBytes($f.path)
    $bc = New-Object System.Net.Http.ByteArrayContent(@(, $bytes))
    $bc.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new('audio/wav')
    $mp.Add($bc, 'fileContent', 'chant.wav')
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
    $script:manifest += [pscustomobject]@{ name = $f.name; assetId = "$assetId"; state = "$state" }
    Save-Manifest
    if ($state -like '*Rejected*') { Write-Output 'REJECTED - stopping'; exit 2 }
    $remaining = $gapSeconds - [int]((Get-Date) - $start).TotalSeconds
    if ($remaining -gt 0 -and $f.name -ne $files[-1].name) { Start-Sleep -Seconds $remaining }
}
Write-Output 'CHANT UPLOADS DONE'
$manifest | ForEach-Object { Write-Output ("RESULT: {0} = {1} ({2})" -f $_.name, $_.assetId, $_.state) }
