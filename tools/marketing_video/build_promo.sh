#!/usr/bin/env bash
# Renders a vertical (1080x1920) TikTok/X promo from the listing art + the
# ElevenLabs VO, fully via ffmpeg. No external footage needed.
set -e
ART=/c/Users/chris/Roblox-gnarly-nutmeg/tools/badge_icons
VO=/c/Users/chris/Roblox-gnarly-nutmeg/tools/audio_pipeline/marketing_demo/hype_reel
ROOT=/c/Users/chris/Roblox-gnarly-nutmeg/tools/marketing_video
WORK="$ROOT/work"
mkdir -p "$WORK"
cd "$ROOT"                                  # ffmpeg CWD -> so a colon-free relative font path works
cp -f /c/Windows/Fonts/ariblk.ttf "$ROOT/capfont.ttf"
FONT="capfont.ttf"                          # relative (no drive colon to trip ffmpeg's drawtext parser)

dur() { ffprobe -v error -show_entries format=duration -of csv=p=0 "$1"; }

# image segment: blurred-fill bg + sharp centred image + lower-third caption, muxed with its VO
seg_img() {
  local out=$1 img=$2 vo=$3 cap=$4
  local t; t=$(awk "BEGIN{print $(dur "$vo")+0.35}")
  ffmpeg -y -hide_banner -loglevel error -loop 1 -i "$img" -i "$vo" -filter_complex \
"[0:v]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=22:3,eq=brightness=-0.30:saturation=1.15[bg];\
[0:v]scale=1044:-1[fg];\
[bg][fg]overlay=(W-w)/2:(H-h)/2[bs];\
[bs]drawtext=fontfile=$FONT:text='$cap':fontcolor=white:fontsize=80:borderw=6:bordercolor=black@0.92:box=1:boxcolor=black@0.42:boxborderw=24:x=(w-text_w)/2:y=h*0.745[v]" \
    -map "[v]" -map 1:a -t "$t" -r 30 -c:v libx264 -preset veryfast -pix_fmt yuv420p -c:a aac -ar 44100 -ac 2 "$out"
  echo "built $out (${t}s)"
}

# logo outro: solid pitch-green bg + centred logo + caption
seg_logo() {
  local out=$1 logo=$2 vo=$3 cap=$4
  local t; t=$(awk "BEGIN{print $(dur "$vo")+0.5}")
  ffmpeg -y -hide_banner -loglevel error -f lavfi -t "$t" -i color=c=0x0E2A1B:s=1080x1920:r=30 -loop 1 -i "$logo" -i "$vo" -filter_complex \
"[1:v]scale=940:-1[lg];\
[0:v][lg]overlay=(W-w)/2:(H-h)/2-130[bs];\
[bs]drawtext=fontfile=$FONT:text='$cap':fontcolor=0xF5C43C:fontsize=86:borderw=6:bordercolor=black@0.92:x=(w-text_w)/2:y=h*0.60[v]" \
    -map "[v]" -map 2:a -t "$t" -r 30 -c:v libx264 -preset veryfast -pix_fmt yuv420p -c:a aac -ar 44100 -ac 2 "$out"
  echo "built $out (${t}s)"
}

seg_img  "$WORK/s1.mp4" "$ART/thumb_keyart.png"        "$VO/01_hook.mp3"          "GNARLY NUTMEG"
seg_img  "$WORK/s2.mp4" "$ART/thumbs/thumb_action.png" "$VO/02_nutmeg.mp3"        "NUTMEG!"
seg_img  "$WORK/s3.mp4" "$ART/thumbs/thumb_action.png" "$VO/08_gnarls_shadow.mp3" "HE LIVES THERE NOW"
seg_img  "$WORK/s4.mp4" "$ART/thumbs/thumb_goal.png"   "$VO/06_topbins.mp3"       "TOP CORNER!"
seg_img  "$WORK/s5.mp4" "$ART/thumbs/thumb_powerups.png" "$VO/09_austin_close.mp3" "FREE ON ROBLOX"
seg_logo "$WORK/s6.mp4" "$ART/logo.png"                "$VO/10_cta.mp3"           "PLAY NOW - FREE"

# concat (identical params -> stream copy)
# bare filenames: the concat demuxer resolves them relative to the list file's own folder
printf "file '%s'\n" s1.mp4 s2.mp4 s3.mp4 s4.mp4 s5.mp4 s6.mp4 > "$WORK/list.txt"
ffmpeg -y -hide_banner -loglevel error -f concat -safe 0 -i "$WORK/list.txt" -c copy "$ROOT/gnarly_nutmeg_promo_v1.mp4"
echo "=== FINAL ==="
ffprobe -v error -show_entries format=duration:stream=width,height,codec_type -of default=noprint_wrappers=1 "$ROOT/gnarly_nutmeg_promo_v1.mp4"
ls -la "$ROOT/gnarly_nutmeg_promo_v1.mp4"
