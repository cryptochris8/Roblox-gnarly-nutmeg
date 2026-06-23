# Generates the Gnarls-features promo VO (Sports Guy narration + a Gnarls squeak)
# via ElevenLabs. Off-platform marketing audio only (no Roblox upload).
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$key = (Get-Content 'C:\Users\chris\elevenlabs.txt' -Raw).Trim()
$out = 'C:\Users\chris\Roblox-gnarly-nutmeg\tools\marketing_video\vo_gnarls'
New-Item -ItemType Directory -Force $out | Out-Null
$SPORTS = 'gnPxliFHTp6OK6tcoA6i'   # Sports Guy play-by-play
$GNARLS = 'fBD19tfE58bkETeiwUoC'   # Gnarls (Little Dude II)

$lines = @(
  @{ id = 'g1_hook';    voice = $SPORTS; style = 0.70; text = "Say hello to the newest superstar in Gnarly Nutmeg... GNARLS the squirrel!" },
  @{ id = 'g2_statue';  voice = $SPORTS; style = 0.60; text = "He's got his own giant statue, watching over the whole stadium." },
  @{ id = 'g3_celeb';   voice = $SPORTS; style = 0.88; text = "Score a goal, and Gnarls pops up to celebrate right alongside you!" },
  @{ id = 'g4_squeak';  voice = $GNARLS; style = 0.90; text = "Goooal! Woo hoo hoo! Nutmeg!" },
  @{ id = 'g5_costume'; voice = $SPORTS; style = 0.72; text = "And now, you can play AS Gnarls! Squirrel ears, a big fluffy tail, free in the locker." },
  @{ id = 'g6_cta';     voice = $SPORTS; style = 0.78; text = "Gnarly Nutmeg. Free on Roblox. Come play!" }
)

foreach ($l in $lines) {
  $body = @{
    text           = $l.text
    model_id       = 'eleven_multilingual_v2'
    voice_settings = @{ stability = 0.42; similarity_boost = 0.8; style = $l.style; use_speaker_boost = $true }
  } | ConvertTo-Json -Compress
  $uri = "https://api.elevenlabs.io/v1/text-to-speech/$($l.voice)"
  $dest = Join-Path $out "$($l.id).mp3"
  Invoke-RestMethod -Uri $uri -Method POST -Headers @{ 'xi-api-key' = $key; 'Accept' = 'audio/mpeg' } -ContentType 'application/json' -Body $body -OutFile $dest
  Write-Output ("{0,-12} {1,7} bytes  |  {2}" -f $l.id, (Get-Item $dest).Length, $l.text)
}
Write-Output 'VO DONE'
