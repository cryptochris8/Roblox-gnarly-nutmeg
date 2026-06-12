# Trickle-uploads the licensed Hytopia commentator lines to Roblox via Open Cloud.
# ACCOUNT-SAFETY RULES (account had a false-positive flag on 2026-06-10, appeal granted):
#   - ONE asset at a time, 8 minutes between uploads
#   - poll moderation per asset; STOP THE WHOLE RUN on any rejection (exit 2)
# Resumable: skips files already recorded in uploaded.json.
# PowerShell 5.1 compatible (.NET HttpClient multipart; TLS 1.2 explicitly).

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Net.Http

$key = $env:ROBLOX_OPEN_CLOUD_KEY
if (-not $key) { Write-Output 'FATAL: ROBLOX_OPEN_CLOUD_KEY not set'; exit 3 }
$creatorId = 7230402132
$gapSeconds = 480

$audioRoot = 'C:\Users\chris\Hytopia-games\Gnarley\assets\audio\sfx\crowd\announcer'
$files = @(
    @{ path = "$audioRoot\Notable Voices - Soccer Commentator - Game Start.wav";                          name = 'GN Commentator - Game Start' },
    @{ path = "$audioRoot\Notable Voices - Soccer Commentator - What a Goal Excited.wav";                 name = 'GN Commentator - What A Goal' },
    @{ path = "$audioRoot\Notable Voices - Soccer Commentator - What a Beauty.wav";                       name = 'GN Commentator - What A Beauty' },
    @{ path = "$audioRoot\Notable Voices - Soccer Commentator - Crowd Goes Wild.wav";                     name = 'GN Commentator - Crowd Goes Wild' },
    @{ path = "$audioRoot\Notable Voices - Soccer Commentator - Reaction Beautiful Save.wav";             name = 'GN Commentator - Beautiful Save' },
    @{ path = "$audioRoot\Notable Voices - Soccer Commentator - Reaction Near Miss.wav";                  name = 'GN Commentator - Near Miss' },
    @{ path = "$audioRoot\Notable Voices - Soccer Commentator - So Close Frustrated .wav";                name = 'GN Commentator - So Close' },
    @{ path = "$audioRoot\Apple Hill Studios - Sports Announcer - Play By Play What A Shot .wav";         name = 'GN Commentator - What A Shot' },
    @{ path = "$audioRoot\Apple Hill Studios - Sports Announcer - Play By Play Hes On Fire Now.wav";      name = 'GN Commentator - On Fire' },
    @{ path = "$audioRoot\Apple Hill Studios - Sports Announcer - Play By Play Its All Over .wav";        name = 'GN Commentator - Full Time' }
)

$manifestPath = Join-Path $PSScriptRoot 'uploaded.json'
$manifest = @()
if (Test-Path $manifestPath) {
    $manifest = @(Get-Content $manifestPath -Raw | ConvertFrom-Json)
}

function Save-Manifest {
    $script:manifest | ConvertTo-Json -Depth 4 | Set-Content -Path $manifestPath -Encoding utf8
}

$client = New-Object System.Net.Http.HttpClient
$client.Timeout = [TimeSpan]::FromSeconds(120)
$client.DefaultRequestHeaders.Add('x-api-key', $key)

function Get-Json($url) {
    $r = $client.GetAsync($url).Result
    $body = $r.Content.ReadAsStringAsync().Result
    if (-not $r.IsSuccessStatusCode) { throw "GET $url -> $([int]$r.StatusCode): $body" }
    return $body | ConvertFrom-Json
}

foreach ($f in $files) {
    $existing = $manifest | Where-Object { $_.name -eq $f.name -and $_.assetId }
    if ($existing) { Write-Output "SKIP (already uploaded): $($f.name) assetId=$($existing.assetId)"; continue }
    if (-not (Test-Path $f.path)) { Write-Output "MISSING FILE: $($f.path)"; continue }

    $uploadStart = Get-Date
    Write-Output "UPLOADING: $($f.name)"

    $reqJson = @{
        assetType       = 'Audio'
        displayName     = $f.name
        description     = 'Licensed match commentary line for Gnarly Nutmeg (Athlete Domains).'
        creationContext = @{ creator = @{ userId = $creatorId } }
    } | ConvertTo-Json -Compress -Depth 5

    $mp = New-Object System.Net.Http.MultipartFormDataContent
    $sc = New-Object System.Net.Http.StringContent($reqJson)
    $mp.Add($sc, 'request')
    $bytes = [IO.File]::ReadAllBytes($f.path)
    $bc = New-Object System.Net.Http.ByteArrayContent(@(, $bytes))
    $bc.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new('audio/wav')
    $cleanName = ($f.name -replace '[^A-Za-z0-9 \-]', '') + '.wav'
    $mp.Add($bc, 'fileContent', $cleanName)

    $resp = $client.PostAsync('https://apis.roblox.com/assets/v1/assets', $mp).Result
    $respBody = $resp.Content.ReadAsStringAsync().Result
    if (-not $resp.IsSuccessStatusCode) {
        Write-Output "UPLOAD FAILED ($([int]$resp.StatusCode)): $respBody"
        if ([int]$resp.StatusCode -eq 401 -or [int]$resp.StatusCode -eq 403) { exit 3 }
        Save-Manifest
        exit 2
    }
    $opPath = ($respBody | ConvertFrom-Json).path
    Write-Output "  operation: $opPath"

    # poll the operation for the assetId
    $assetId = $null
    for ($i = 0; $i -lt 36; $i++) {
        Start-Sleep -Seconds 5
        try {
            $op = Get-Json "https://apis.roblox.com/assets/v1/$opPath"
            if ($op.done) { $assetId = $op.response.assetId; break }
        } catch { Write-Output "  op poll error (retrying): $($_.Exception.Message)" }
    }
    if (-not $assetId) {
        Write-Output "  NO assetId after 3 min of polling - recording as pending-op and stopping"
        $script:manifest += [pscustomobject]@{ name = $f.name; assetId = $null; op = $opPath; state = 'OP_TIMEOUT' }
        Save-Manifest
        exit 2
    }
    Write-Output "  assetId: $assetId"

    # poll moderation until approved/rejected (within the trickle gap)
    $state = 'Reviewing'
    for ($i = 0; $i -lt 18; $i++) {
        try {
            $asset = Get-Json "https://apis.roblox.com/assets/v1/assets/$assetId`?readMask=moderationResult"
            $state = $asset.moderationResult.moderationState
            if ($state -like '*Approved*' -or $state -like '*Rejected*') { break }
        } catch { Write-Output "  moderation poll error (retrying): $($_.Exception.Message)" }
        Start-Sleep -Seconds 20
    }
    Write-Output "  moderation: $state"
    $script:manifest += [pscustomobject]@{ name = $f.name; assetId = "$assetId"; state = "$state" }
    Save-Manifest

    if ($state -like '*Rejected*') {
        Write-Output 'REJECTION - stopping the whole run per account-safety rule'
        exit 2
    }

    # honor the 8-minute trickle gap (moderation polling time counts toward it)
    $elapsed = (Get-Date) - $uploadStart
    $remaining = $gapSeconds - [int]$elapsed.TotalSeconds
    if ($remaining -gt 0 -and $f -ne $files[-1]) {
        Write-Output "  gap: waiting $remaining s before the next upload"
        Start-Sleep -Seconds $remaining
    }
}

Write-Output 'ALL UPLOADS DONE'
$manifest | ForEach-Object { Write-Output ("RESULT: {0} = {1} ({2})" -f $_.name, $_.assetId, $_.state) }
