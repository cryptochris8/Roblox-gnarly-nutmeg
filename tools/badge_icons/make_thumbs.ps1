# Turns Chris's raw gameplay screenshots into clean 1920x1080 listing
# thumbnails: crops out the right-side camera-plugin debug panel, punches the
# colour, and adds a gold caption band (matching the key-art) that also hides
# the bottom control-hint strip.

Add-Type -AssemblyName System.Drawing
$srcDir = 'C:\Users\chris\Pictures\Screenshots'
$outDir = $PSScriptRoot + '\thumbs'
New-Item -ItemType Directory -Force $outDir | Out-Null

$jobs = @(
    @{ file = 'Screenshot 2026-06-12 221602.png'; out = 'thumb_goal.png';     p1 = 'SCORE BIG'; p2 = 'WIN THE CUP' },
    @{ file = 'Screenshot 2026-06-12 220946.png'; out = 'thumb_powerups.png'; p1 = 'GRAB ARCADE POWER-UPS'; p2 = '' },
    @{ file = 'Screenshot 2026-06-12 220728.png'; out = 'thumb_action.png';   p1 = 'FAST 6v6 ARCADE FUTBOL'; p2 = '' }
)

# saturation (+28%) and a touch of brightness; default ctor is identity
$s = 1.28; $lr = 0.3086; $lg = 0.6094; $lb = 0.0820
$cm = New-Object System.Drawing.Imaging.ColorMatrix
$cm.Matrix00 = $lr * (1 - $s) + $s; $cm.Matrix01 = $lr * (1 - $s); $cm.Matrix02 = $lr * (1 - $s)
$cm.Matrix10 = $lg * (1 - $s);      $cm.Matrix11 = $lg * (1 - $s) + $s; $cm.Matrix12 = $lg * (1 - $s)
$cm.Matrix20 = $lb * (1 - $s);      $cm.Matrix21 = $lb * (1 - $s); $cm.Matrix22 = $lb * (1 - $s) + $s
$cm.Matrix40 = 0.03; $cm.Matrix41 = 0.03; $cm.Matrix42 = 0.03
$ia = New-Object System.Drawing.Imaging.ImageAttributes
$ia.SetColorMatrix($cm)

$sep = '   ' + [char]0x2022 + '   '

foreach ($j in $jobs) {
    $src = New-Object System.Drawing.Bitmap (Join-Path $srcDir $j.file)
    $w = $src.Width; $h = $src.Height
    $cropW = [int]($h * 16 / 9)
    $rightCut = $w - 270                       # drop the debug panel
    $leftStart = [Math]::Max(0, $rightCut - $cropW)
    if ($leftStart + $cropW -gt $w) { $cropW = $w - $leftStart }

    $dst = New-Object System.Drawing.Bitmap 1920, 1080
    $g = [System.Drawing.Graphics]::FromImage($dst)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $dstRect = New-Object System.Drawing.Rectangle 0, 0, 1920, 1080
    $g.DrawImage($src, $dstRect, $leftStart, 0, $cropW, $h, [System.Drawing.GraphicsUnit]::Pixel, $ia)

    $band = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(235, 14, 18, 24))
    $g.FillRectangle($band, 0, 930, 1920, 150); $band.Dispose()
    $cap = if ($j.p2 -ne '') { $j.p1 + $sep + $j.p2 } else { $j.p1 }
    $tagFont = New-Object System.Drawing.Font('Arial Black', 42, [System.Drawing.FontStyle]::Bold)
    $tagBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(245, 196, 60))
    $fmt = New-Object System.Drawing.StringFormat
    $fmt.Alignment = [System.Drawing.StringAlignment]::Center
    $g.DrawString($cap, $tagFont, $tagBrush, 960, 978, $fmt)
    $tagFont.Dispose(); $tagBrush.Dispose()

    $g.Dispose()
    $dst.Save((Join-Path $outDir $j.out), [System.Drawing.Imaging.ImageFormat]::Png)
    $dst.Dispose(); $src.Dispose()
    Write-Output "DONE: $($j.out)"
}
