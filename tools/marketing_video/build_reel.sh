#!/usr/bin/env bash
# Cuts Chris's gameplay recording into a clean vertical TikTok/X reel:
#   - crops out the Roblox title bar (top) + the left menu column (chrome-free)
#   - blurred-fill 9:16, burned captions, commentary VO synced to the goals
#   - original audio MUTED (the game's own Sports-Guy commentary would clash with ours)
#   - clean logo outro
set -e
ROOT=/c/Users/chris/Roblox-gnarly-nutmeg/tools/marketing_video
REC="/c/Users/chris/Roblox-gnarly-nutmeg/Recording 2026-06-16 235952.mp4"
VO="$ROOT/vo"
HY=/c/Users/chris/Roblox-gnarly-nutmeg/tools/audio_pipeline/marketing_demo/hype_reel
GN=/c/Users/chris/Roblox-gnarly-nutmeg/tools/audio_pipeline/marketing_demo/ingame_gnarls
ART=/c/Users/chris/Roblox-gnarly-nutmeg/tools/badge_icons
WORK="$ROOT/work_reel"
mkdir -p "$WORK"
cd "$ROOT"
FONT=capfont.ttf
CROP="crop=1650:976:250:28"   # drop title bar (top ~28) + left menu (left ~250)

# gameplay beat: OUT SRC DUR VO CAPTION [VO_DELAY_MS]
beat() {
  local out=$1 src=$2 dur=$3 vo=$4 cap=$5 vod=${6:-0}
  ffmpeg -y -hide_banner -loglevel error -ss "$src" -t "$dur" -i "$REC" -i "$vo" -filter_complex \
"[0:v]$CROP,split[c1][c2];\
[c1]scale=1080:1920:force_original_aspect_ratio=increase,crop=1080:1920,boxblur=26:4,eq=brightness=-0.34:saturation=1.05[bg];\
[c2]scale=1080:-1[fg];\
[bg][fg]overlay=(W-w)/2:(H-h)/2[bs];\
[bs]drawtext=fontfile=$FONT:text='$cap':fontcolor=white:fontsize=84:borderw=7:bordercolor=black@0.92:box=1:boxcolor=black@0.42:boxborderw=26:x=(w-text_w)/2:y=h*0.70[v];\
[1:a]adelay=${vod}|${vod},apad[aout]" \
    -map "[v]" -map "[aout]" -t "$dur" -r 30 -c:v libx264 -preset veryfast -pix_fmt yuv420p -c:a aac -ar 44100 -ac 2 "$out"
  echo "beat $(basename "$out")  src=${src}s dur=${dur}s vod=${vod}ms  [$cap]"
}

# logo outro: solid pitch-green + centred logo + caption
logo_beat() {
  local out=$1 dur=$2 vo=$3 cap=$4
  ffmpeg -y -hide_banner -loglevel error -f lavfi -t "$dur" -i color=c=0x0E2A1B:s=1080x1920:r=30 -loop 1 -i "$ART/logo.png" -i "$vo" -filter_complex \
"[1:v]scale=960:-1[lg];[0:v][lg]overlay=(W-w)/2:(H-h)/2-120[bs];\
[bs]drawtext=fontfile=$FONT:text='$cap':fontcolor=0xF5C43C:fontsize=88:borderw=6:bordercolor=black@0.92:x=(w-text_w)/2:y=h*0.60[v];\
[2:a]apad[aout]" \
    -map "[v]" -map "[aout]" -t "$dur" -r 30 -c:v libx264 -preset veryfast -pix_fmt yuv420p -c:a aac -ar 44100 -ac 2 "$out"
  echo "beat $(basename "$out")  LOGO  [$cap]"
}

# goal 1 net ~32.5s, goal 2 net ~51.5s -> delay the VO so the call lands on the net
beat "$WORK/b1.mp4" 24.0 6.6 "$VO/nh_hook.mp3"   "GNARLY NUTMEG"
beat "$WORK/b2.mp4" 31.0 5.5 "$VO/nh_goal1.mp3"  "GOAL!"            1500
beat "$WORK/b3.mp4" 36.5 3.0 "$GN/ig_goal.mp3"   "GNARLS LOVES IT"
beat "$WORK/b4.mp4" 44.0 3.6 "$VO/nh_austin.mp3" "RED IN TROUBLE"
beat "$WORK/b5.mp4" 49.5 5.5 "$VO/nh_goal2.mp3"  "AND ANOTHER!"     1300
logo_beat "$WORK/b6.mp4" 3.9 "$HY/10_cta.mp3"    "FREE ON ROBLOX"

printf "file '%s'\n" b1.mp4 b2.mp4 b3.mp4 b4.mp4 b5.mp4 b6.mp4 > "$WORK/list.txt"
ffmpeg -y -hide_banner -loglevel error -f concat -safe 0 -i "$WORK/list.txt" -c copy "$ROOT/gnarly_gameplay_reel_v2.mp4"
echo "=== FINAL ==="
ffprobe -v error -show_entries format=duration -of csv=p=0 "$ROOT/gnarly_gameplay_reel_v2.mp4"
ls -la "$ROOT/gnarly_gameplay_reel_v2.mp4"
