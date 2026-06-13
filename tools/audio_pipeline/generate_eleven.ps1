# Generates the big-moments announcer pack via ElevenLabs TTS.
# Voice: "Sports Guy - Excited and fast, play by play" (Chris's library pick).
# Key read at call time from C:\Users\chris\elevenlabs.txt - NEVER committed.
# Output: eleven\<id>.mp3 (44.1kHz 128k), ready for the trickle uploader.

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$key = (Get-Content 'C:\Users\chris\elevenlabs.txt' -Raw).Trim()
$voice = 'gnPxliFHTp6OK6tcoA6i'
$outDir = Join-Path $PSScriptRoot 'eleven'
New-Item -ItemType Directory -Force $outDir | Out-Null

$lines = [ordered]@{
    shootout_intro  = 'It all comes down to penalties! Hold your breath, folks!'
    shootout_save   = 'Saved! What a stop! Absolutely heroic!'
    shootout_score  = 'He buries it! Ice cold!'
    golden_goal     = 'Golden goal! Next one wins it all!'
    halftime        = "And that's halftime! What a half of football, folks!"
    final_intro     = 'Welcome to the final! The trophy is in the building!'
    champions       = "They've done it! Champions! Lift that trophy!"
    goal_topcorner  = 'Top corner! Absolutely unstoppable!'
    goal_nochance   = 'What a strike! The keeper had no chance!'
    save_fingertips = 'Denied! Fingertips! Incredible reflexes!'
    nutmeg_call     = "Oh! Right through the legs! That's a nutmeg!"
    underway        = "And we're underway at the Nutmeg Arena!"
}

foreach ($id in $lines.Keys) {
    $path = Join-Path $outDir "$id.mp3"
    if (Test-Path $path) { Write-Output "SKIP $id (exists)"; continue }
    $body = @{
        text = $lines[$id]
        model_id = 'eleven_multilingual_v2'
        voice_settings = @{ stability = 0.45; similarity_boost = 0.8; style = 0.65 }
    } | ConvertTo-Json -Compress
    Invoke-RestMethod -Uri "https://api.elevenlabs.io/v1/text-to-speech/$voice`?output_format=mp3_44100_128" `
        -Method POST -Headers @{ 'xi-api-key' = $key } -ContentType 'application/json' `
        -Body $body -OutFile $path
    $size = (Get-Item $path).Length
    Write-Output ("GEN {0}: {1} bytes" -f $id, $size)
    Start-Sleep -Milliseconds 600
}
Write-Output 'GENERATION DONE'
