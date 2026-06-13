# Generates the two-man booth banter: Sports Guy sets it up, Austin Knox
# (warm Texas color man) lands the punchline. Keys/voices from Chris's
# ElevenLabs library; key read at call time, never committed.
# Output: eleven\banter<N>_a.mp3 (Sports Guy) + banter<N>_b.mp3 (Austin).

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$key = (Get-Content 'C:\Users\chris\elevenlabs.txt' -Raw).Trim()
$VOICE_PLAY = 'gnPxliFHTp6OK6tcoA6i'  # Sports Guy
$VOICE_COLOR = 'Bj9UqZbhQsanLzgalpEG' # Austin Knox - Texas color man
$outDir = Join-Path $PSScriptRoot 'eleven'
New-Item -ItemType Directory -Force $outDir | Out-Null

$exchanges = @(
    @{ a = "He's got a cannon for a left foot!"; b = "Shame he keeps it in the garage most weeks." },
    @{ a = "The keeper's out there organizing his defense!"; b = "So that's what all the yellin' is. I figured he lost his car keys." },
    @{ a = "Beautiful one-two down the wing!"; b = "I tried a one-two once. Both passes went to the other team." },
    @{ a = "Lovely bit of possession football here, folks!"; b = "My grandma keeps possession like this. Ain't nobody gettin' that TV remote." },
    @{ a = "The striker is making clever runs off the ball!"; b = "I make clever runs too, partner. Mostly to the snack table at halftime." },
    @{ a = "Great shape from the back four tonight!"; b = "Well, round is a shape." }
)

function Gen([string]$voice, [string]$text, [string]$path) {
    if (Test-Path $path) { Write-Output "SKIP $(Split-Path $path -Leaf)"; return }
    $body = @{
        text = $text
        model_id = 'eleven_multilingual_v2'
        voice_settings = @{ stability = 0.45; similarity_boost = 0.8; style = 0.6 }
    } | ConvertTo-Json -Compress
    Invoke-RestMethod -Uri "https://api.elevenlabs.io/v1/text-to-speech/$voice`?output_format=mp3_44100_128" `
        -Method POST -Headers @{ 'xi-api-key' = $key } -ContentType 'application/json' `
        -Body $body -OutFile $path
    Write-Output ("GEN {0}: {1} bytes" -f (Split-Path $path -Leaf), (Get-Item $path).Length)
    Start-Sleep -Milliseconds 600
}

for ($i = 1; $i -le $exchanges.Count; $i++) {
    $e = $exchanges[$i - 1]
    Gen $VOICE_PLAY $e.a (Join-Path $outDir ("banter{0}_a.mp3" -f $i))
    Gen $VOICE_COLOR $e.b (Join-Path $outDir ("banter{0}_b.mp3" -f $i))
}
Write-Output 'BANTER GENERATION DONE'
