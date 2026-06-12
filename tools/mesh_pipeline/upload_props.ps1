# Trickle-uploads QC-passed Meshy prop FBX files to Roblox as Model assets.
# Same account-safety rules as the audio pipeline (post-2026-06-10 discipline):
# ONE asset per 8 minutes, poll moderation per asset, STOP the run on any
# rejection (exit 2). Every prop's thumbnail must have had a VISUAL QC pass
# before it appears in this list. Resumable via props_uploaded.json.

param([string[]] $Props = @())

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Net.Http

$key = $env:ROBLOX_OPEN_CLOUD_KEY
if (-not $key) { Write-Output 'FATAL: ROBLOX_OPEN_CLOUD_KEY not set'; exit 3 }
$creatorId = 7230402132
$gapSeconds = 480
$outDir = Join-Path $PSScriptRoot 'output'
$manifestPath = Join-Path $PSScriptRoot 'props_uploaded.json'

$manifest = @()
if (Test-Path $manifestPath) {
    $manifest = @(Get-Content $manifestPath -Raw | ConvertFrom-Json)
}
function Save-Manifest {
    $script:manifest | ConvertTo-Json -Depth 4 | Set-Content -Path $manifestPath -Encoding utf8
}

$client = New-Object System.Net.Http.HttpClient
$client.Timeout = [TimeSpan]::FromSeconds(180)
$client.DefaultRequestHeaders.Add('x-api-key', $key)

function Get-Json($url) {
    $r = $client.GetAsync($url).Result
    $body = $r.Content.ReadAsStringAsync().Result
    if (-not $r.IsSuccessStatusCode) { throw "GET $url -> $([int]$r.StatusCode): $body" }
    return $body | ConvertFrom-Json
}

foreach ($prop in $Props) {
    $existing = $manifest | Where-Object { $_.name -eq $prop -and $_.assetId }
    if ($existing) { Write-Output "SKIP (uploaded): $prop assetId=$($existing.assetId)"; continue }
    $fbx = Join-Path $outDir "$prop.fbx"
    if (-not (Test-Path $fbx)) { Write-Output "MISSING FBX: $fbx"; continue }

    $uploadStart = Get-Date
    Write-Output "UPLOADING: $prop"
    $reqJson = @{
        assetType       = 'Model'
        displayName     = "GN Stadium - $prop"
        description     = 'Stadium prop for Gnarly Nutmeg (Athlete Domains), generated art.'
        creationContext = @{ creator = @{ userId = $creatorId } }
    } | ConvertTo-Json -Compress -Depth 5

    $mp = New-Object System.Net.Http.MultipartFormDataContent
    $mp.Add((New-Object System.Net.Http.StringContent($reqJson)), 'request')
    $bytes = [IO.File]::ReadAllBytes($fbx)
    $bc = New-Object System.Net.Http.ByteArrayContent(@(, $bytes))
    $bc.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::new('model/fbx')
    $mp.Add($bc, 'fileContent', "$prop.fbx")

    $resp = $client.PostAsync('https://apis.roblox.com/assets/v1/assets', $mp).Result
    $respBody = $resp.Content.ReadAsStringAsync().Result
    if (-not $resp.IsSuccessStatusCode) {
        Write-Output "UPLOAD FAILED ($([int]$resp.StatusCode)): $respBody"
        Save-Manifest
        exit 2
    }
    $opPath = ($respBody | ConvertFrom-Json).path
    Write-Output "  operation: $opPath"

    $assetId = $null
    for ($i = 0; $i -lt 36; $i++) {
        Start-Sleep -Seconds 5
        try {
            $op = Get-Json "https://apis.roblox.com/assets/v1/$opPath"
            if ($op.done) { $assetId = $op.response.assetId; break }
        } catch { Write-Output "  op poll error (retrying): $($_.Exception.Message)" }
    }
    if (-not $assetId) {
        Write-Output '  NO assetId after 3 min - stopping'
        $script:manifest += [pscustomobject]@{ name = $prop; assetId = $null; op = $opPath; state = 'OP_TIMEOUT' }
        Save-Manifest
        exit 2
    }
    Write-Output "  assetId: $assetId"

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
    $script:manifest += [pscustomobject]@{ name = $prop; assetId = "$assetId"; state = "$state" }
    Save-Manifest
    if ($state -like '*Rejected*') {
        Write-Output 'REJECTION - stopping the whole run per account-safety rule'
        exit 2
    }

    $elapsed = (Get-Date) - $uploadStart
    $remaining = $gapSeconds - [int]$elapsed.TotalSeconds
    if ($remaining -gt 0 -and $prop -ne $Props[-1]) {
        Write-Output "  gap: waiting $remaining s"
        Start-Sleep -Seconds $remaining
    }
}
Write-Output 'PROP UPLOADS DONE'
$manifest | ForEach-Object { Write-Output ("RESULT: {0} = {1} ({2})" -f $_.name, $_.assetId, $_.state) }
