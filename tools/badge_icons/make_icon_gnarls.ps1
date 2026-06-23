# Matching 512x512 game icon: Gnarls hero on a pitch gradient (reads at small size).
Add-Type -AssemblyName System.Drawing
$dir = $PSScriptRoot
$gnarlsPath = Join-Path $dir 'gnarls_canon\canon_cut.png'  # canon Gnarls (bg removed)
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
function Draw-Outlined([System.Drawing.Graphics]$g, [string]$text, [float]$size, $fill, $outlineCol, [float]$outlineW, [float]$cx, [float]$y) {
    $font = New-Object System.Drawing.Font('Arial Black', $size, [System.Drawing.FontStyle]::Bold)
    $fmt = New-Object System.Drawing.StringFormat; $fmt.Alignment = [System.Drawing.StringAlignment]::Center
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddString($text, $font.FontFamily, [int]$font.Style, $g.DpiY * $font.Size / 72, (New-Object System.Drawing.PointF $cx, $y), $fmt)
    $pen = New-Object System.Drawing.Pen($outlineCol, $outlineW); $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round
    $g.DrawPath($pen, $path); $br = New-Object System.Drawing.SolidBrush($fill); $g.FillPath($br, $path)
    $path.Dispose(); $pen.Dispose(); $br.Dispose(); $font.Dispose()
}

$S = 512
$bmp = New-Object System.Drawing.Bitmap $S, $S
$g = New-Gfx $bmp
# pitch-green gradient
$rect = New-Object System.Drawing.Rectangle 0, 0, $S, $S
$bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, ([System.Drawing.Color]::FromArgb(46, 132, 70)), ([System.Drawing.Color]::FromArgb(10, 38, 22)), [single]90)
$g.FillRectangle($bg, $rect); $bg.Dispose()
# mowed stripes
$stripe = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(24, 255, 255, 255))
for ($x = -120; $x -lt 640; $x += 96) {
    $pts = @((New-Object System.Drawing.PointF ([float]$x), 512), (New-Object System.Drawing.PointF ([float]($x + 48)), 512), (New-Object System.Drawing.PointF ([float]($x + 150)), 0), (New-Object System.Drawing.PointF ([float]($x + 102)), 0))
    $g.FillPolygon($stripe, $pts)
}
$stripe.Dispose()
# soft gold glow centre
$glowPath = New-Object System.Drawing.Drawing2D.GraphicsPath; $glowPath.AddEllipse(80, 40, 360, 360)
$glow = New-Object System.Drawing.Drawing2D.PathGradientBrush($glowPath)
$glow.CenterColor = [System.Drawing.Color]::FromArgb(95, 255, 220, 120); $glow.SurroundColors = @([System.Drawing.Color]::FromArgb(0, 255, 220, 120))
$g.FillPath($glow, $glowPath); $glowPath.Dispose(); $glow.Dispose()
# Gnarls big (canon cutout; head near the top, legs run under the brand bar)
$gn = New-Object System.Drawing.Bitmap $gnarlsPath
$g.DrawImage($gn, -18, -22, 560, 746); $gn.Dispose()
# small trophy accent, top-right
$trophy = Load-Transparent $trophyPath
$g.DrawImage($trophy, 372, 8, 150, 150); $trophy.Dispose()
# tiny brand bar at the very bottom
$band = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(175, 10, 16, 12))
$g.FillRectangle($band, 0, 452, $S, 60); $band.Dispose()
$volt = [System.Drawing.Color]::FromArgb(190, 255, 60); $ink = [System.Drawing.Color]::FromArgb(16, 20, 26)
Draw-Outlined $g 'GNARLY NUTMEG' 30 $volt $ink 6 256 458

$g.Dispose()
$bmp.Save((Join-Path $dir 'icon_gnarls_512.png'), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
Write-Output 'DONE: icon_gnarls_512.png'
