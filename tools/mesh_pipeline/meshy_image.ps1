# meshy_image.ps1 - IMAGE-to-3D for Gnarly Nutmeg (the consistent/on-model route).
# Reads crops\<name>.png (a clean reference image of the subject), submits to Meshy
# image-to-3D, downloads output\img23\<name>.fbx + _thumb.png. Resumable via
# img23_manifest.json. Key from HKCU:\Environment MESHY_API_KEY (never printed).
param([string[]] $Only = @(), [int] $PollSeconds = 20)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$root = $PSScriptRoot
$cropDir = Join-Path $root 'crops'
$outDir = Join-Path $root 'output\img23'
$manifestPath = Join-Path $root 'img23_manifest.json'
New-Item -ItemType Directory -Force $outDir | Out-Null
$key = (Get-ItemProperty 'HKCU:\Environment' -Name MESHY_API_KEY).MESHY_API_KEY
$headers = @{ Authorization = "Bearer $key" }
$base = 'https://api.meshy.ai/openapi/v1/image-to-3d'

$manifest = @{}
if (Test-Path $manifestPath) { (Get-Content $manifestPath -Raw | ConvertFrom-Json).PSObject.Properties | ForEach-Object { $manifest[$_.Name] = $_.Value } }
function Save-Manifest { $o = New-Object PSObject; foreach ($k in ($manifest.Keys | Sort-Object)) { $o | Add-Member NoteProperty $k $manifest[$k] }; $o | ConvertTo-Json -Depth 5 | Out-File $manifestPath -Encoding utf8 }

$names = Get-ChildItem $cropDir -Filter *.png | ForEach-Object { $_.BaseName } | Sort-Object
if ($Only.Count -gt 0) { $names = $names | Where-Object { $Only -contains $_ } }

foreach ($name in $names) {
    if ($manifest[$name] -and $manifest[$name].status -eq 'done') { Write-Output "SKIP $name (done)"; continue }
    Write-Output "IMAGE-TO-3D: $name"
    $png = Join-Path $cropDir "$name.png"
    $dataUri = 'data:image/png;base64,' + [Convert]::ToBase64String([IO.File]::ReadAllBytes($png))
    $body = @{ image_url = $dataUri; enable_pbr = $false; should_remesh = $true; should_texture = $true; topology = 'triangle'; target_polycount = 12000; symmetry_mode = 'auto' } | ConvertTo-Json -Compress
    $taskId = if ($manifest[$name] -and $manifest[$name].taskId) { $manifest[$name].taskId } else { (Invoke-RestMethod -Uri $base -Method POST -Headers $headers -ContentType 'application/json' -Body $body).result }
    $manifest[$name] = [pscustomobject]@{ taskId = $taskId; status = 'submitted'; fbx = $null; thumb = $null; credits = $null }
    Save-Manifest
    Write-Output "  task: $taskId"
    while ($true) {
        Start-Sleep -Seconds $PollSeconds
        $t = Invoke-RestMethod -Uri "$base/$taskId" -Headers $headers -Method GET
        if ($t.status -eq 'SUCCEEDED') {
            $fbx = Join-Path $outDir "$name.fbx"; $thumb = Join-Path $outDir "${name}_thumb.png"
            Invoke-WebRequest -Uri $t.model_urls.fbx -OutFile $fbx -UseBasicParsing
            if ($t.thumbnail_url) { Invoke-WebRequest -Uri $t.thumbnail_url -OutFile $thumb -UseBasicParsing }
            $manifest[$name] = [pscustomobject]@{ taskId = $taskId; status = 'done'; fbx = $fbx; thumb = $thumb; credits = $t.consumed_credits }
            Save-Manifest; Write-Output ("  DONE ({0} credits)" -f $t.consumed_credits); break
        }
        if ($t.status -eq 'FAILED' -or $t.status -eq 'CANCELED') { $manifest[$name].status = 'failed'; Save-Manifest; Write-Output "  $($t.status)"; break }
        Write-Output ("  {0}%" -f $t.progress)
    }
}
Write-Output 'IMAGE-TO-3D DONE'
try { $bal = Invoke-RestMethod -Uri 'https://api.meshy.ai/openapi/v1/balance' -Headers $headers; Write-Output ("credits remaining: {0}" -f $bal.balance) } catch {}
