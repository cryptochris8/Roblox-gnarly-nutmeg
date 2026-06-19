# Batch 3: 18 more booth exchanges (banter23-40) + GNARLS live-reaction clips
# (copies the 6 demo reactions into eleven\ + generates variants for variety).
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$key = (Get-Content 'C:\Users\chris\elevenlabs.txt' -Raw).Trim()
$SG='gnPxliFHTp6OK6tcoA6i'; $AK='Bj9UqZbhQsanLzgalpEG'; $GN='fBD19tfE58bkETeiwUoC'
$out = Join-Path $PSScriptRoot 'eleven'
New-Item -ItemType Directory -Force $out | Out-Null

function Gen([string]$voice,[string]$text,[string]$path,[double]$style){
    if (Test-Path $path){ Write-Output "SKIP $(Split-Path $path -Leaf)"; return }
    $body = @{ text=$text; model_id='eleven_multilingual_v2'; voice_settings=@{ stability=0.42; similarity_boost=0.8; style=$style } } | ConvertTo-Json -Compress
    Invoke-RestMethod -Uri "https://api.elevenlabs.io/v1/text-to-speech/$voice`?output_format=mp3_44100_128" -Method POST -Headers @{ 'xi-api-key'=$key } -ContentType 'application/json' -Body $body -OutFile $path
    Write-Output ("GEN {0}: {1} KB" -f (Split-Path $path -Leaf), [math]::Round((Get-Item $path).Length/1KB)); Start-Sleep -Milliseconds 450
}

$ex = @(
  @{av=$SG;a="He's screaming for offside!";bv=$AK;b="He screams like that when the pizza's late, too."},
  @{av=$SG;a="What a delivery from the corner!";bv=$AK;b="My mailman delivers like that. Ends up three houses down."},
  @{av=$SG;a="The captain is rallying his troops!";bv=$AK;b="Rally the troops? I can't rally my kids for dinner."},
  @{av=$SG;a="He's got acres of space out wide!";bv=$AK;b="Acres of space. Like my dream of a quiet Sunday."},
  @{av=$SG;a="Sublime first touch to control it!";bv=$AK;b="My first touch usually lands in the neighbor's yard."},
  @{av=$SG;a="He buys the foul cleverly there!";bv=$AK;b="I buy fouls too. Mostly at the concession stand."},
  @{av=$SG;a="The wall lines up for the free kick!";bv=$AK;b="Most organized thing I've seen all day."},
  @{av=$SG;a="He's chasing back like his life depends on it!";bv=$AK;b="I run like that when the ice cream truck leaves."},
  @{av=$SG;a="Tremendous engine on that midfielder!";bv=$AK;b="I've got an engine too. Check engine light's been on for years."},
  @{av=$SG;a="He dummies it and lets it run!";bv=$AK;b="I let it run all the time. We call that a miss."},
  @{av=$SG;a="The keeper claims the cross with authority!";bv=$AK;b="Authority. I had that once. Then I had kids."},
  @{av=$SG;a="Lovely disguised pass, nobody saw it!";bv=$AK;b="I disguise passes too. Mostly as turnovers."},
  @{av=$SG;a="He's firing up the crowd, pumping his fists!";bv=$AK;b="I pump my fists when I find the remote."},
  @{av=$SG;a="Magnificent recovery pace!";bv=$AK;b="Recovery pace? I need a recovery nap."},
  @{av=$SG;a="The atmosphere in here is electric!";bv=$GN;b="I touched the electric! I'm fine! Mostly!"},
  @{av=$SG;a="He's dancing past defenders!";bv=$GN;b="Teach me! Teach me the dance! I have little feet!"},
  @{av=$AK;a="Real slow burn of a game, this one.";bv=$GN;b="I can't do slow! I've had eleven snacks!"},
  @{av=$SG;a="What a save to keep them level!";bv=$GN;b="No goal?! Aw. Do it again so I can watch better!"}
)
$n = 23
foreach ($e in $ex){
  $sa = if ($e.av -eq $GN){0.85}else{0.6}; $sb = if ($e.bv -eq $GN){0.85}else{0.55}
  Gen $e.av $e.a (Join-Path $out ("banter{0}_a.mp3" -f $n)) $sa
  Gen $e.bv $e.b (Join-Path $out ("banter{0}_b.mp3" -f $n)) $sb
  $n++
}

# GNARLS live reactions: copy the 6 demo clips in as gnarls_<event>.mp3
$demo = Join-Path $PSScriptRoot 'marketing_demo\ingame_gnarls'
$mapCopy = @{ 'ig_goal'='gnarls_goal'; 'ig_nutmeg'='gnarls_nutmeg'; 'ig_save'='gnarls_save'; 'ig_near'='gnarls_near'; 'ig_trophy'='gnarls_trophy'; 'ig_hype'='gnarls_hype' }
foreach ($k in $mapCopy.Keys){
  $src = Join-Path $demo ($k + '.mp3'); $dst = Join-Path $out ($mapCopy[$k] + '.mp3')
  if ((Test-Path $src) -and -not (Test-Path $dst)){ Copy-Item $src $dst; Write-Output "COPY $($mapCopy[$k]).mp3" }
}
# + variants so he doesn't repeat the same line each goal/nutmeg/save/trophy
Gen $GN "Goal! That's what I'm squeaking about!"      (Join-Path $out 'gnarls_goal2.mp3') 0.85
Gen $GN "Through the legs! Bye-bye! See you never!"    (Join-Path $out 'gnarls_nutmeg2.mp3') 0.85
Gen $GN "The keeper said no! A big, fluffy no!"        (Join-Path $out 'gnarls_save2.mp3') 0.85
Gen $GN "The shiny cup! It's happening! I need it!"    (Join-Path $out 'gnarls_trophy2.mp3') 0.85
Write-Output 'BATCH3 GENERATION DONE'
