# Builds the store-listing art kit with System.Drawing:
#   logo.png            - transparent GNARLY NUTMEG wordmark (2000x520)
#   icon_512.png        - the Meshy trophy + wordmark on a pitch gradient
#   thumb_keyart.png    - 1920x1080 key-art splash (logo + trophy + tagline)

Add-Type -AssemblyName System.Drawing
$out = $PSScriptRoot
$trophyPath = Join-Path (Split-Path $out -Parent) 'mesh_pipeline\output\trophy_thumb.png'

function New-Gfx([System.Drawing.Bitmap]$bmp) {
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    return $g
}

# chroma-key the Meshy render's near-black backing to transparent.
# NOTE: must clone to 32bppArgb first - a file-loaded Bitmap is 24bpp and
# SetPixel with alpha silently turns into black on it.
function Load-TrophyTransparent([string]$path) {
    $file = New-Object System.Drawing.Bitmap $path
    $src = New-Object System.Drawing.Bitmap $file.Width, $file.Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gg = [System.Drawing.Graphics]::FromImage($src)
    $gg.DrawImage($file, 0, 0, $file.Width, $file.Height)
    $gg.Dispose(); $file.Dispose()
    for ($y = 0; $y -lt $src.Height; $y++) {
        for ($x = 0; $x -lt $src.Width; $x++) {
            $c = $src.GetPixel($x, $y)
            if ($c.R -lt 60 -and $c.G -lt 60 -and $c.B -lt 60) {
                $src.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(0, 0, 0, 0))
            }
        }
    }
    return $src
}

function Draw-Wordmark([System.Drawing.Graphics]$g, [float]$cx, [float]$y, [float]$size) {
    # GNARLY in volt green, NUTMEG in white, heavy outline - reads at any scale
    $fontBig = New-Object System.Drawing.Font('Arial Black', $size, [System.Drawing.FontStyle]::Bold)
    $outline = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(18, 22, 28)), ([float]($size * 0.16))
    $outline.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $volt = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(190, 255, 60))
    $white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(245, 247, 252))
    $fmt = New-Object System.Drawing.StringFormat
    $fmt.Alignment = [System.Drawing.StringAlignment]::Center
    foreach ($row in @(@('GNARLY', $volt, 0), @('NUTMEG', $white, 1))) {
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $path.AddString($row[0], $fontBig.FontFamily, [int]$fontBig.Style, $g.DpiY * $fontBig.Size / 72, `
            (New-Object System.Drawing.PointF $cx, ($y + $row[2] * $size * 1.65)), $fmt)
        $g.DrawPath($outline, $path)
        $g.FillPath($row[1], $path)
        $path.Dispose()
    }
    $outline.Dispose(); $volt.Dispose(); $white.Dispose(); $fontBig.Dispose()
}

# 1) transparent wordmark
$bmp = New-Object System.Drawing.Bitmap 2000, 560
$g = New-Gfx $bmp
Draw-Wordmark $g 1000 30 130
$g.Dispose(); $bmp.Save("$out\logo.png", [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()

# 2) icon: trophy hero on a deep pitch gradient + compact wordmark
$bmp = New-Object System.Drawing.Bitmap 512, 512
$g = New-Gfx $bmp
$rect = New-Object System.Drawing.Rectangle 0, 0, 512, 512
$bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, `
    ([System.Drawing.Color]::FromArgb(40, 120, 60)), ([System.Drawing.Color]::FromArgb(12, 40, 24)), 90
$g.FillRectangle($bg, $rect); $bg.Dispose()
$trophy = Load-TrophyTransparent $trophyPath
$g.DrawImage($trophy, 76, 16, 360, 360)
$trophy.Dispose()
Draw-Wordmark $g 256 368 44
$g.Dispose(); $bmp.Save("$out\icon_512.png", [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()

# 3) 1920x1080 key-art: logo + trophy + tagline band
$bmp = New-Object System.Drawing.Bitmap 1920, 1080
$g = New-Gfx $bmp
$rect = New-Object System.Drawing.Rectangle 0, 0, 1920, 1080
$bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, `
    ([System.Drawing.Color]::FromArgb(36, 110, 58)), ([System.Drawing.Color]::FromArgb(8, 28, 18)), 65
$g.FillRectangle($bg, $rect); $bg.Dispose()
# mowed stripes
$stripe = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(22, 255, 255, 255))
for ($x = -200; $x -lt 2200; $x += 320) {
    $pts = @(
        (New-Object System.Drawing.PointF ([float]$x), 1080),
        (New-Object System.Drawing.PointF ([float]($x + 160)), 1080),
        (New-Object System.Drawing.PointF ([float]($x + 420)), 0),
        (New-Object System.Drawing.PointF ([float]($x + 260)), 0)
    )
    $g.FillPolygon($stripe, $pts)
}
$stripe.Dispose()
$trophy = Load-TrophyTransparent $trophyPath
$g.DrawImage($trophy, 1230, 180, 660, 660)
$trophy.Dispose()
Draw-Wordmark $g 660 300 145
# tagline band (ASCII separators: PS 5.1 reads unsigned .ps1 as ANSI)
$band = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(165, 14, 18, 24))
$g.FillRectangle($band, 0, 880, 1920, 120); $band.Dispose()
$tagFont = New-Object System.Drawing.Font('Arial Black', 34, [System.Drawing.FontStyle]::Bold)
$tagBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(245, 196, 60))
$fmt = New-Object System.Drawing.StringFormat
$fmt.Alignment = [System.Drawing.StringAlignment]::Center
$sep = '  ' + [char]0x2022 + '  '
$g.DrawString('ARCADE FUTBOL' + $sep + 'REAL COMMENTARY' + $sep + 'HOST CUPS WITH FRIENDS', $tagFont, $tagBrush, 960, 908, $fmt)
$tagFont.Dispose(); $tagBrush.Dispose()
$g.Dispose(); $bmp.Save("$out\thumb_keyart.png", [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()

Write-Output "DONE: logo.png, icon_512.png, thumb_keyart.png in $out"
