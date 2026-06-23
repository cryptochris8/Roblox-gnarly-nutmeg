# Attention-grabbing 1920x1080 storefront thumbnail: a real gameplay action shot
# under the GNARLY NUTMEG wordmark + hero trophy + a bright burst. Reuses the
# wordmark / transparent-trophy helpers from make_listing_art.ps1.
Add-Type -AssemblyName System.Drawing
$dir = $PSScriptRoot
$bgPath = Join-Path $dir 'hero\bg_graded.png'
$trophyPath = Join-Path (Split-Path $dir -Parent) 'mesh_pipeline\output\trophy_thumb.png'

function New-Gfx([System.Drawing.Bitmap]$bmp) {
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    return $g
}
function Load-TrophyTransparent([string]$path) {
    $file = New-Object System.Drawing.Bitmap $path
    $src = New-Object System.Drawing.Bitmap $file.Width, $file.Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gg = [System.Drawing.Graphics]::FromImage($src); $gg.DrawImage($file, 0, 0, $file.Width, $file.Height); $gg.Dispose(); $file.Dispose()
    for ($y = 0; $y -lt $src.Height; $y++) { for ($x = 0; $x -lt $src.Width; $x++) {
        $c = $src.GetPixel($x, $y)
        if ($c.R -lt 60 -and $c.G -lt 60 -and $c.B -lt 60) { $src.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(0, 0, 0, 0)) }
    } }
    return $src
}
function Draw-Wordmark([System.Drawing.Graphics]$g, [float]$cx, [float]$y, [float]$size) {
    $fontBig = New-Object System.Drawing.Font('Arial Black', $size, [System.Drawing.FontStyle]::Bold)
    $outline = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(16, 20, 26)), ([float]($size * 0.17))
    $outline.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $volt = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(190, 255, 60))
    $white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(245, 247, 252))
    $fmt = New-Object System.Drawing.StringFormat; $fmt.Alignment = [System.Drawing.StringAlignment]::Center
    foreach ($row in @(@('GNARLY', $volt, 0), @('NUTMEG', $white, 1))) {
        $path = New-Object System.Drawing.Drawing2D.GraphicsPath
        $path.AddString($row[0], $fontBig.FontFamily, [int]$fontBig.Style, $g.DpiY * $fontBig.Size / 72, (New-Object System.Drawing.PointF $cx, ($y + $row[2] * $size * 1.62)), $fmt)
        $g.DrawPath($outline, $path); $g.FillPath($row[1], $path); $path.Dispose()
    }
    $outline.Dispose(); $volt.Dispose(); $white.Dispose(); $fontBig.Dispose()
}
function Draw-Outlined([System.Drawing.Graphics]$g, [string]$text, [float]$size, $fill, $outlineCol, [float]$outlineW, [float]$cx, [float]$y) {
    $font = New-Object System.Drawing.Font('Arial Black', $size, [System.Drawing.FontStyle]::Bold)
    $fmt = New-Object System.Drawing.StringFormat; $fmt.Alignment = [System.Drawing.StringAlignment]::Center
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddString($text, $font.FontFamily, [int]$font.Style, $g.DpiY * $font.Size / 72, (New-Object System.Drawing.PointF $cx, $y), $fmt)
    $pen = New-Object System.Drawing.Pen($outlineCol, $outlineW); $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $g.DrawPath($pen, $path); $br = New-Object System.Drawing.SolidBrush($fill); $g.FillPath($br, $path)
    $path.Dispose(); $pen.Dispose(); $br.Dispose(); $font.Dispose()
}
function Draw-Burst([System.Drawing.Graphics]$g, [float]$cx, [float]$cy, [float]$ro, [float]$ri, [int]$pts, $fill, $edge) {
    $arr = @()
    for ($i = 0; $i -lt $pts * 2; $i++) {
        $r = $ri; if ($i % 2 -eq 0) { $r = $ro }
        $a = [math]::PI * $i / $pts - [math]::PI / 2
        $arr += New-Object System.Drawing.PointF (($cx + $r * [math]::Cos($a)), ($cy + $r * [math]::Sin($a)))
    }
    $br = New-Object System.Drawing.SolidBrush($fill); $pen = New-Object System.Drawing.Pen($edge, 7); $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $g.FillPolygon($br, $arr); $g.DrawPolygon($pen, $arr); $br.Dispose(); $pen.Dispose()
}

$W = 1920; $H = 1080
$bmp = New-Object System.Drawing.Bitmap $W, $H
$g = New-Gfx $bmp

# 1) gameplay action background (cover)
$bg = New-Object System.Drawing.Bitmap $bgPath
$g.DrawImage($bg, 0, 0, $W, $H); $bg.Dispose()

# 2) left dark gradient for text legibility
$rectL = New-Object System.Drawing.Rectangle 0, 0, ([int]($W * 0.64)), $H
$gradL = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rectL, ([System.Drawing.Color]::FromArgb(232, 7, 16, 11)), ([System.Drawing.Color]::FromArgb(0, 7, 16, 11)), [single]0)
$g.FillRectangle($gradL, $rectL); $gradL.Dispose()
# bottom vignette (also hides the faint HUD remnants)
$rectB = New-Object System.Drawing.Rectangle 0, ([int]($H * 0.50)), $W, ([int]($H * 0.50))
$gradB = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rectB, ([System.Drawing.Color]::FromArgb(0, 0, 0, 0)), ([System.Drawing.Color]::FromArgb(225, 5, 11, 9)), [single]90)
$g.FillRectangle($gradB, $rectB); $gradB.Dispose()
# top gradient: recedes the in-game "BLUE GOAL!" text + chrome behind the wordmark
$rectT = New-Object System.Drawing.Rectangle 0, 0, $W, ([int]($H * 0.46))
$gradT = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rectT, ([System.Drawing.Color]::FromArgb(180, 6, 12, 9)), ([System.Drawing.Color]::FromArgb(0, 6, 12, 9)), [single]90)
$g.FillRectangle($gradT, $rectT); $gradT.Dispose()

# 3) gold radial glow behind the trophy
$glowPath = New-Object System.Drawing.Drawing2D.GraphicsPath
$glowPath.AddEllipse(1150, 110, 760, 760)
$glow = New-Object System.Drawing.Drawing2D.PathGradientBrush($glowPath)
$glow.CenterColor = [System.Drawing.Color]::FromArgb(165, 255, 208, 92)
$glow.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 255, 208, 92))
$g.FillPath($glow, $glowPath); $glowPath.Dispose(); $glow.Dispose()

# 4) trophy hero (right)
$trophy = Load-TrophyTransparent $trophyPath
$g.DrawImage($trophy, 1285, 165, 600, 600); $trophy.Dispose()

# 5) wordmark (left-centre)
Draw-Wordmark $g 565 235 150

# 6) hook line under the wordmark
$gold = [System.Drawing.Color]::FromArgb(245, 200, 64)
$ink = [System.Drawing.Color]::FromArgb(16, 20, 26)
Draw-Outlined $g ('BEAT THE BOTS ' + [char]0x2022 + ' LIFT THE CUP') 40 $gold $ink 9 565 700

# 7) bright FREE burst (top-left)
$red = [System.Drawing.Color]::FromArgb(230, 64, 64)
$yellow = [System.Drawing.Color]::FromArgb(255, 210, 70)
$white = [System.Drawing.Color]::FromArgb(248, 250, 255)
Draw-Burst $g 200 175 122 86 12 $red $yellow
Draw-Outlined $g 'FREE' 40 $white $ink 7 200 142

$g.Dispose()
$bmp.Save((Join-Path $dir 'storefront_v1.png'), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Write-Output 'DONE: storefront_v1.png'
