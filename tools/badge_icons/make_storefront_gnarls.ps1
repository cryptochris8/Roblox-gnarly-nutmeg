# Storefront thumbnail with GNARLS (the soccer-squirrel mascot) as the hero
# character: gameplay bg + Gnarls big on the left, wordmark + "6v6 ARCADE SOCCER"
# on the right, FREE burst. Reuses the make_listing_art helpers.
Add-Type -AssemblyName System.Drawing
$dir = $PSScriptRoot
$bgPath = Join-Path $dir 'hero\bg_graded.png'
$gnarlsPath = Join-Path $dir 'gnarls_canon\canon_cut.png'  # canon Gnarls, bg removed (real PNG/alpha)
$trophyPath = Join-Path (Split-Path $dir -Parent) 'mesh_pipeline\output\trophy_thumb.png'

function New-Gfx([System.Drawing.Bitmap]$bmp) {
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    return $g
}
function Load-Transparent([string]$path) {
    $file = New-Object System.Drawing.Bitmap $path
    $src = New-Object System.Drawing.Bitmap $file.Width, $file.Height, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $gg = [System.Drawing.Graphics]::FromImage($src); $gg.DrawImage($file, 0, 0, $file.Width, $file.Height); $gg.Dispose(); $file.Dispose()
    for ($y = 0; $y -lt $src.Height; $y++) { for ($x = 0; $x -lt $src.Width; $x++) {
        $c = $src.GetPixel($x, $y)
        if ($c.R -lt 58 -and $c.G -lt 58 -and $c.B -lt 58) { $src.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(0, 0, 0, 0)) }
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

# bg gameplay
$bg = New-Object System.Drawing.Bitmap $bgPath; $g.DrawImage($bg, 0, 0, $W, $H); $bg.Dispose()
# global darken so the character + text pop
$ov = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(96, 6, 12, 9)); $g.FillRectangle($ov, 0, 0, $W, $H); $ov.Dispose()
# bottom vignette
$rectB = New-Object System.Drawing.Rectangle 0, ([int]($H * 0.55)), $W, ([int]($H * 0.45))
$gradB = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rectB, ([System.Drawing.Color]::FromArgb(0, 0, 0, 0)), ([System.Drawing.Color]::FromArgb(205, 5, 11, 9)), [single]90)
$g.FillRectangle($gradB, $rectB); $gradB.Dispose()

# small trophy accent, upper-right behind the wordmark, with a soft glow
$glowPath = New-Object System.Drawing.Drawing2D.GraphicsPath; $glowPath.AddEllipse(1560, 20, 360, 360)
$glow = New-Object System.Drawing.Drawing2D.PathGradientBrush($glowPath)
$glow.CenterColor = [System.Drawing.Color]::FromArgb(120, 255, 208, 92); $glow.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 255, 208, 92))
$g.FillPath($glow, $glowPath); $glowPath.Dispose(); $glow.Dispose()
$trophy = Load-Transparent $trophyPath; $g.DrawImage($trophy, 1610, 28, 300, 300); $trophy.Dispose()

# GNARLS hero (canon cutout, already transparent), big full-body on the left
$gn = New-Object System.Drawing.Bitmap $gnarlsPath
$g.DrawImage($gn, -35, 8, 810, 1080); $gn.Dispose()

# wordmark on the right (stacked)
Draw-Wordmark $g 1370 360 140
# hook
$gold = [System.Drawing.Color]::FromArgb(245, 200, 64); $ink = [System.Drawing.Color]::FromArgb(16, 20, 26)
Draw-Outlined $g '6v6 ARCADE SOCCER' 46 $gold $ink 9 1370 800

# FREE burst, top-left over Gnarls' corner
$red = [System.Drawing.Color]::FromArgb(232, 64, 64); $yellow = [System.Drawing.Color]::FromArgb(255, 210, 70); $white = [System.Drawing.Color]::FromArgb(248, 250, 255)
Draw-Burst $g 195 165 118 84 12 $red $yellow
Draw-Outlined $g 'FREE' 38 $white $ink 7 195 134

$g.Dispose()
$bmp.Save((Join-Path $dir 'storefront_gnarls.png'), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Write-Output 'DONE: storefront_gnarls.png'
