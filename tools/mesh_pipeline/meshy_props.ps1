# meshy_props.ps1 - generate Gnarly Nutmeg stadium hero props via Meshy
# text-to-3D (two stage: preview mesh -> refine adds texture), resumably.
#
# - manifest.json records { prop: { previewId, refineId, status, fbx, thumb } }
#   after every change; rerunning resumes/skips.
# - Key from HKCU:\Environment MESHY_API_KEY (never printed). TLS rule: .NET only.
# - Output: output\<prop>.fbx + output\<prop>_thumb.png
#   (thumbnails get a VISUAL QC pass before any Roblox upload - house rule
#   after the 2026-06-10 moderation false positive.)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$root = $PSScriptRoot
$outDir = Join-Path $root 'output'
$manifestPath = Join-Path $root 'manifest.json'
New-Item -ItemType Directory -Force $outDir | Out-Null

$key = (Get-ItemProperty 'HKCU:\Environment' -Name MESHY_API_KEY).MESHY_API_KEY
$headers = @{ Authorization = "Bearer $key" }
$base = 'https://api.meshy.ai/openapi/v2/text-to-3d'

# (entrance_arch was generated twice and failed visual QC twice - architecture
# is a text-to-3D weak spot. Dropped; add new prop prompts here as needed.)
$props = [ordered]@{
    trophy        = 'A gleaming golden soccer trophy: a tall polished gold cup with two elegant curved handles, on a small round golden base, original design, game asset'
    tv_camera     = 'A professional broadcast television camera on a sturdy tripod, dark gray body with a large round lens and a small side monitor, stadium TV camera, game asset'
    mascot_statue = 'A cheerful cartoon squirrel mascot statue holding a soccer ball under one arm, warm bronze metal statue standing on a simple stone pedestal, family friendly, game asset'
}

$manifest = @{}
if (Test-Path $manifestPath) {
    $json = Get-Content $manifestPath -Raw | ConvertFrom-Json
    foreach ($p in $json.PSObject.Properties) { $manifest[$p.Name] = $p.Value }
}
function Save-Manifest {
    $obj = New-Object PSObject
    foreach ($k in ($manifest.Keys | Sort-Object)) { $obj | Add-Member NoteProperty $k $manifest[$k] }
    $obj | ConvertTo-Json -Depth 5 | Out-File $manifestPath -Encoding utf8
}

function Wait-Task([string] $taskId) {
    while ($true) {
        Start-Sleep -Seconds 20
        $t = Invoke-RestMethod -Uri "$base/$taskId" -Headers $headers
        if ($t.status -eq 'SUCCEEDED') { return $t }
        if ($t.status -eq 'FAILED' -or $t.status -eq 'CANCELED') {
            throw "task $taskId ended $($t.status): $($t.task_error.message)"
        }
        Write-Output ("  {0}: {1} ({2}%)" -f $taskId.Substring(0, 8), $t.status, $t.progress)
    }
}

foreach ($name in $props.Keys) {
    $m = $manifest[$name]
    if ($m -and $m.status -eq 'done') { Write-Output "SKIP $name (done)"; continue }
    Write-Output "PROP: $name"

    # stage 1: preview (geometry)
    $previewId = if ($m -and $m.previewId) { $m.previewId } else {
        $body = @{
            mode = 'preview'; prompt = $props[$name]
            art_style = 'realistic'; should_remesh = $true
            topology = 'triangle'; target_polycount = 9000
        } | ConvertTo-Json -Compress
        $r = Invoke-RestMethod -Uri $base -Method POST -Headers $headers -ContentType 'application/json' -Body $body
        $r.result
    }
    $manifest[$name] = [pscustomobject]@{ previewId = $previewId; refineId = $null; status = 'preview'; fbx = $null; thumb = $null }
    Save-Manifest
    Write-Output "  preview task: $previewId"
    [void](Wait-Task $previewId)

    # stage 2: refine (texture)
    $refineId = if ($m -and $m.refineId) { $m.refineId } else {
        $body = @{ mode = 'refine'; preview_task_id = $previewId; enable_pbr = $false } | ConvertTo-Json -Compress
        $r = Invoke-RestMethod -Uri $base -Method POST -Headers $headers -ContentType 'application/json' -Body $body
        $r.result
    }
    $manifest[$name].refineId = $refineId
    $manifest[$name].status = 'refine'
    Save-Manifest
    Write-Output "  refine task: $refineId"
    $t = Wait-Task $refineId

    # download fbx + thumbnail
    $fbxPath = Join-Path $outDir "$name.fbx"
    $thumbPath = Join-Path $outDir "${name}_thumb.png"
    Invoke-WebRequest -Uri $t.model_urls.fbx -OutFile $fbxPath -UseBasicParsing
    if ($t.thumbnail_url) {
        Invoke-WebRequest -Uri $t.thumbnail_url -OutFile $thumbPath -UseBasicParsing
    }
    $manifest[$name].status = 'done'
    $manifest[$name].fbx = $fbxPath
    $manifest[$name].thumb = $thumbPath
    Save-Manifest
    Write-Output "  DONE: $fbxPath"
}

Write-Output 'ALL PROPS GENERATED'
foreach ($k in $manifest.Keys) { Write-Output ("RESULT: {0} = {1}" -f $k, $manifest[$k].status) }
