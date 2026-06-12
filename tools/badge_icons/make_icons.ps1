# Generates flat-design 512x512 badge icons with System.Drawing (PS 5.1).
# Output: first_goal.png, hat_trick.png, legend_slayer.png in this folder.

Add-Type -AssemblyName System.Drawing

$out = $PSScriptRoot

function New-Canvas([System.Drawing.Color]$top, [System.Drawing.Color]$bottom) {
    $bmp = New-Object System.Drawing.Bitmap 512, 512
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $rect = New-Object System.Drawing.Rectangle 0, 0, 512, 512
    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush $rect, $top, $bottom, 90
    $g.FillRectangle($brush, $rect)
    $brush.Dispose()
    return $bmp, $g
}

function Draw-Ball([System.Drawing.Graphics]$g, [float]$cx, [float]$cy, [float]$r, [System.Drawing.Color]$shell) {
    # shell
    $shellBrush = New-Object System.Drawing.SolidBrush $shell
    $g.FillEllipse($shellBrush, $cx - $r, $cy - $r, 2 * $r, 2 * $r)
    $shellBrush.Dispose()
    # clip everything panel-ish to the ball
    $clip = New-Object System.Drawing.Drawing2D.GraphicsPath
    $clip.AddEllipse($cx - $r, $cy - $r, 2 * $r, 2 * $r)
    $g.SetClip($clip)
    $black = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(25, 28, 34))
    # centre pentagon
    function PentaPoints([float]$px, [float]$py, [float]$pr, [float]$rot) {
        $pts = @()
        for ($i = 0; $i -lt 5; $i++) {
            $a = $rot + $i * 72
            $rad = $a * [Math]::PI / 180
            $pts += New-Object System.Drawing.PointF ($px + $pr * [Math]::Sin($rad)), ($py - $pr * [Math]::Cos($rad))
        }
        return $pts
    }
    $g.FillPolygon($black, (PentaPoints $cx $cy ($r * 0.34) 0))
    # five surrounding pentagons, partly outside the shell (clipped)
    for ($k = 0; $k -lt 5; $k++) {
        $a = $k * 72
        $rad = $a * [Math]::PI / 180
        $px = $cx + $r * 0.95 * [Math]::Sin($rad)
        $py = $cy - $r * 0.95 * [Math]::Cos($rad)
        $g.FillPolygon($black, (PentaPoints $px $py ($r * 0.30) ($a + 36)))
    }
    $black.Dispose()
    $g.ResetClip()
    # outline
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(25, 28, 34)), ([float]($r * 0.07))
    $g.DrawEllipse($pen, $cx - $r, $cy - $r, 2 * $r, 2 * $r)
    $pen.Dispose()
}

function Draw-Net([System.Drawing.Graphics]$g) {
    $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(140, 255, 255, 255)), 5
    for ($x = -64; $x -le 576; $x += 64) {
        $g.DrawLine($pen, [float]$x, 0, [float]($x + 40), 512)
        $g.DrawLine($pen, [float]($x + 40), 0, [float]$x, 512)
    }
    $pen.Dispose()
}

function Draw-Star([System.Drawing.Graphics]$g, [float]$cx, [float]$cy, [float]$rOuter, [float]$rInner, [System.Drawing.Color]$color) {
    $pts = @()
    for ($i = 0; $i -lt 10; $i++) {
        $r = if ($i % 2 -eq 0) { $rOuter } else { $rInner }
        $a = $i * 36 * [Math]::PI / 180
        $pts += New-Object System.Drawing.PointF ($cx + $r * [Math]::Sin($a)), ($cy - $r * [Math]::Cos($a))
    }
    $brush = New-Object System.Drawing.SolidBrush $color
    $g.FillPolygon($brush, $pts)
    $brush.Dispose()
}

# 1) FIRST GOAL: ball on a green pitch gradient behind a white net
$bmp, $g = New-Canvas ([System.Drawing.Color]::FromArgb(66, 160, 75)) ([System.Drawing.Color]::FromArgb(34, 105, 46))
Draw-Net $g
Draw-Ball $g 256 268 150 ([System.Drawing.Color]::White)
$g.Dispose(); $bmp.Save("$out\first_goal.png", [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()

# 2) HAT-TRICK HERO: three balls stacked diagonally on a fire gradient
$bmp, $g = New-Canvas ([System.Drawing.Color]::FromArgb(255, 150, 40)) ([System.Drawing.Color]::FromArgb(205, 55, 25))
Draw-Ball $g 165 165 92 ([System.Drawing.Color]::White)
Draw-Ball $g 345 205 92 ([System.Drawing.Color]::White)
Draw-Ball $g 250 360 100 ([System.Drawing.Color]::White)
$g.Dispose(); $bmp.Save("$out\hat_trick.png", [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()

# 3) LEGEND SLAYER: golden ball over a star on the LEGEND magenta gradient
$bmp, $g = New-Canvas ([System.Drawing.Color]::FromArgb(178, 60, 175)) ([System.Drawing.Color]::FromArgb(98, 25, 120))
Draw-Star $g 256 262 230 110 ([System.Drawing.Color]::FromArgb(255, 215, 90))
Draw-Ball $g 256 262 132 ([System.Drawing.Color]::FromArgb(250, 205, 80))
$g.Dispose(); $bmp.Save("$out\legend_slayer.png", [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()

Write-Output "DONE: $out\first_goal.png, hat_trick.png, legend_slayer.png"
