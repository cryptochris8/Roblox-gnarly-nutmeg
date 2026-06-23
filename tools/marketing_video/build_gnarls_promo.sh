#!/usr/bin/env bash
# Vertical (1080x1920) hype promo for the NEW Gnarls features, fully via ffmpeg.
# Composites the canon Gnarls cutouts/poses onto a graded gameplay frame, burns
# captions, muxes the Sports-Guy + Gnarls VO. No external footage needed.
set -e
ROOT=/c/Users/chris/Roblox-gnarly-nutmeg/tools/marketing_video
ART=/c/Users/chris/Roblox-gnarly-nutmeg/tools/badge_icons
VO=$ROOT/vo_gnarls
WORK=$ROOT/work_gnarls
mkdir -p "$WORK"
cd "$ROOT"
cp -f /c/Windows/Fonts/ariblk.ttf "$ROOT/capfont.ttf"
FONT="capfont.ttf"                              # colon-free relative path (drawtext parser)
dur(){ ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }
ENC="-r 30 -c:v libx264 -preset veryfast -pix_fmt yuv420p -c:a aac -ar 44100 -ac 2"

# full image, letterboxed sharp over a blurred fill (brand hero / pose sheet)
seg_img(){ # out img vo cap
  local out=$1 img=$2 vo=$3 cap=$4
  local t; t=$(awk "BEGIN{print $(dur "$vo")+0.4}")
  local capf=""
  [ -n "$cap" ] && capf=",drawtext=fontfile=$FONT:text='$cap':fontcolor=white:fontsize=78:borderw=6:bordercolor=black@0.92:box=1:boxcolor=black@0.45:boxborderw=22:x=(w-text_w)/2:y=h*0.085"
  ffmpeg -y -hide_banner -loglevel error -loop 1 -i "$img" -i "$vo" -filter_complex \
"[0:v]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=30:4,eq=brightness=-0.45:saturation=1.10[bg];\
[0:v]scale=1044:-1[fg];\
[bg][fg]overlay=(W-w)/2:(H-h)/2[bs];\
[bs]format=yuv420p${capf}[v]" \
    -map "[v]" -map 1:a -t "$t" $ENC "$out"
  echo "img  $out (${t}s) [$cap]"
}

# gameplay-frame backdrop + a transparent Gnarls cutout composited on the pitch
seg_hero(){ # out bg fg vo cap fgH yoff flip
  local out=$1 bg=$2 fg=$3 vo=$4 cap=$5 fgH=${6:-1320} yoff=${7:-70} flip=${8:-0}
  local t; t=$(awk "BEGIN{print $(dur "$vo")+0.4}")
  local flipf=""; [ "$flip" = "1" ] && flipf=",hflip"
  ffmpeg -y -hide_banner -loglevel error -loop 1 -i "$bg" -loop 1 -i "$fg" -i "$vo" -filter_complex \
"[0:v]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,eq=brightness=-0.10:saturation=1.12,boxblur=1.4:1[bgv];\
[1:v]format=rgba${flipf},scale=-1:${fgH}[fgv];\
[bgv][fgv]overlay=(W-w)/2:(H-h)/2+${yoff}[bs];\
[bs]format=yuv420p,drawtext=fontfile=$FONT:text='$cap':fontcolor=white:fontsize=76:borderw=6:bordercolor=black@0.92:box=1:boxcolor=black@0.5:boxborderw=22:x=(w-text_w)/2:y=h*0.075[v]" \
    -map "[v]" -map 2:a -t "$t" $ENC "$out"
  echo "hero $out (${t}s) [$cap]"
}

# pitch-green outro + centred logo + gold caption
seg_logo(){ # out logo vo cap
  local out=$1 logo=$2 vo=$3 cap=$4
  local t; t=$(awk "BEGIN{print $(dur "$vo")+0.5}")
  ffmpeg -y -hide_banner -loglevel error -f lavfi -t "$t" -i color=c=0x0E2A1B:s=1080x1920:r=30 -loop 1 -i "$logo" -i "$vo" -filter_complex \
"[1:v]scale=940:-1[lg];\
[0:v][lg]overlay=(W-w)/2:(H-h)/2-120[bs];\
[bs]format=yuv420p,drawtext=fontfile=$FONT:text='$cap':fontcolor=0xF5C43C:fontsize=84:borderw=6:bordercolor=black@0.92:x=(w-text_w)/2:y=h*0.60[v]" \
    -map "[v]" -map 2:a -t "$t" $ENC "$out"
  echo "logo $out (${t}s) [$cap]"
}

BG="$ART/hero/bg_graded.png"
seg_img  "$WORK/s1.mp4" "$ART/storefront_canon.png"                 "$VO/g1_hook.mp3"    ""
seg_hero "$WORK/s2.mp4" "$BG" "$ART/gnarls_canon/canon_cut.png"      "$VO/g2_statue.mp3"  "A STADIUM STATUE"        1380 80
seg_hero "$WORK/s3.mp4" "$BG" "$ART/gnarls_canon/cheer_cut.png"      "$VO/g3_celeb.mp3"   "CELEBRATES YOUR GOALS"   1300 60
seg_hero "$WORK/s4.mp4" "$BG" "$ART/gnarls_canon/cheer_cut.png"      "$VO/g4_squeak.mp3"  "GOOOAL!"                 1500 130
seg_hero "$WORK/s5.mp4" "$BG" "$ART/gnarls_canon/canon_cut.png"      "$VO/g5_costume.mp3" "PLAY AS GNARLS"          1320 70 1
seg_logo "$WORK/s6.mp4" "$ART/logo.png"                             "$VO/g6_cta.mp3"     "FREE ON ROBLOX"

printf "file '%s'\n" s1.mp4 s2.mp4 s3.mp4 s4.mp4 s5.mp4 s6.mp4 > "$WORK/list.txt"
cd "$WORK"
ffmpeg -y -hide_banner -loglevel error -f concat -safe 0 -i list.txt -c copy "$ROOT/gnarly_gnarls_promo.mp4"
echo "=== FINAL ==="
ffprobe -v error -show_entries format=duration:stream=width,height -of default=noprint_wrappers=1 "$ROOT/gnarly_gnarls_promo.mp4"
ls -la "$ROOT/gnarly_gnarls_promo.mp4"
