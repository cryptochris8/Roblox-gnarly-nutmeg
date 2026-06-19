# Generates MORE two-man booth banter (banter7+): Sports Guy / Austin Knox, with
# Gnarls (the squeaky mouse guest) as the chaotic topper on a few. Same recipe as
# generate_banter.ps1. Output: eleven\banter<N>_a.mp3 + banter<N>_b.mp3.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$key = (Get-Content 'C:\Users\chris\elevenlabs.txt' -Raw).Trim()
$SG = 'gnPxliFHTp6OK6tcoA6i'   # Sports Guy
$AK = 'Bj9UqZbhQsanLzgalpEG'   # Austin Knox
$GN = 'fBD19tfE58bkETeiwUoC'   # Gnarls (squeaky mouse guest)
$outDir = Join-Path $PSScriptRoot 'eleven'
New-Item -ItemType Directory -Force $outDir | Out-Null

# each: a-voice/a-line (setup) -> b-voice/b-line (punchline). Numbered from 7.
$ex = @(
    @{ av=$SG; a="He's tracking all the way back to defend!"; bv=$AK; b="First fella I've seen run away from glory." },
    @{ av=$SG; a="Blistering pace down the wing!"; bv=$AK; b="I had pace like that once. Then I found the buffet." },
    @{ av=$SG; a="The defense is holding a high line tonight!"; bv=$AK; b="High line, low effort. Story of my softball league." },
    @{ av=$SG; a="Textbook slide tackle right there!"; bv=$AK; b="Textbook? I slide like that getting out of bed." },
    @{ av=$SG; a="Incredible vision to pick out that pass!"; bv=$AK; b="I've got vision too. Spotted the snack table from the parking lot." },
    @{ av=$SG; a="They are pressing high up the pitch!"; bv=$AK; b="Pressing high. I press snooze. We're different people." },
    @{ av=$SG; a="He's demanding the ball, calling for it!"; bv=$AK; b="My kids demand things like that. They don't get them either." },
    @{ av=$SG; a="Off the post! Inches away from a screamer!"; bv=$AK; b="The post. The only defender that never calls in sick." },
    @{ av=$SG; a="Brilliant footwork in the box!"; bv=$AK; b="I've got two left feet, and they are both confused." },
    @{ av=$SG; a="The manager is furious on the touchline!"; bv=$AK; b="Same face my wife makes when I organize the garage." },
    @{ av=$SG; a="What a recovery! He saved a certain goal!"; bv=$AK; b="Nothing's certain but taxes and my fantasy team losing." },
    @{ av=$SG; a="End to end stuff, what a match this is!"; bv=$AK; b="My eyes are tired just watching. Beautiful, though." },
    @{ av=$SG; a="The trophy is gleaming up in the stands!"; bv=$GN; b="Shiny! Can I hold it? Just for one second?!" },
    @{ av=$SG; a="Huge chance for the striker here!"; bv=$GN; b="Shoot it! Shoot it! Oh, I can't look. Okay, I'm looking!" },
    @{ av=$AK; a="Real quiet patch in the game right now."; bv=$GN; b="Not for long! I brought snacks AND chaos!" },
    @{ av=$SG; a="He nutmegs him clean!"; bv=$GN; b="Right through the legs! He lives down there now!" }
)

function Gen([string]$voice, [string]$text, [string]$path, [double]$style) {
    if (Test-Path $path) { Write-Output "SKIP $(Split-Path $path -Leaf)"; return }
    $body = @{ text=$text; model_id='eleven_multilingual_v2'; voice_settings=@{ stability=0.42; similarity_boost=0.8; style=$style } } | ConvertTo-Json -Compress
    Invoke-RestMethod -Uri "https://api.elevenlabs.io/v1/text-to-speech/$voice`?output_format=mp3_44100_128" `
        -Method POST -Headers @{ 'xi-api-key'=$key } -ContentType 'application/json' -Body $body -OutFile $path
    Write-Output ("GEN {0}: {1} KB" -f (Split-Path $path -Leaf), [math]::Round((Get-Item $path).Length/1KB))
    Start-Sleep -Milliseconds 500
}

$n = 7
foreach ($e in $ex) {
    $sa = if ($e.av -eq $GN) { 0.85 } else { 0.6 }
    $sb = if ($e.bv -eq $GN) { 0.85 } else { 0.55 }
    Gen $e.av $e.a (Join-Path $outDir ("banter{0}_a.mp3" -f $n)) $sa
    Gen $e.bv $e.b (Join-Path $outDir ("banter{0}_b.mp3" -f $n)) $sb
    $n++
}
Write-Output 'BANTER2 GENERATION DONE'
