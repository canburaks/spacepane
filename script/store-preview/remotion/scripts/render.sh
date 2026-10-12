#!/bin/bash
# Renders the SpacePane Mac App Store app preview.
#   1. Remotion renders the composition to a ProRes 422 HQ intermediate (outside the repo tree's tracked files).
#   2. ffmpeg encodes the final H.264 High@4.0 / AAC file to Apple's app preview specification and muxes the
#      synthesised stereo soundtrack.
#   3. Remotion exports the poster still.
# Run from script/store-preview/remotion:  npm run render
set -euo pipefail
cd "$(dirname "$0")/.."
repo="$(cd ../../.. && pwd)"
work="$repo/.build/store-preview/remotion"
dest="$repo/docs/release/store-listing/app-preview/remotion"
mkdir -p "$work" "$dest"

node scripts/make-assets.mjs
node scripts/make-audio.mjs

if [ "${SKIP_REMOTION:-0}" != "1" ]; then
npx remotion render src/index.ts SpacePanePreview "$work/intermediate.mov" \
  --codec=prores --prores-profile=hq --pixel-format=yuv422p10le --image-format=png --color-space=bt709 --muted --concurrency=6
fi

# H.264 High profile level 4.0, 30 fps progressive, ~11 Mbps (Apple: 10-12 Mbps), AAC-LC stereo 256 kbps 48 kHz. aac_at (AudioToolbox, macOS) is used because ffmpeg's native aac encoder
# ignores the 256 kbps target on quiet material (measured ~41 kbps).
common=(-c:v libx264 -preset slow -profile:v high -level:v 4.0 -pix_fmt yuv420p -r 30
  -b:v 11M -maxrate 12M -bufsize 20M -g 60 -bf 2
  -x264-params "aq-mode=3:aq-strength=1.1:deblock=-1,-1:psy-rd=1.0,0.0"
  -colorspace bt709 -color_primaries bt709 -color_trc bt709 -color_range tv)
# Two-pass so the average lands inside Apple's 10-12 Mbps target.
ffmpeg -y -v error -i "$work/intermediate.mov" "${common[@]}" -pass 1 -passlogfile "$work/x264" -an -f null /dev/null
ffmpeg -y -v error -i "$work/intermediate.mov" -i public/audio/score.wav -map 0:v:0 -map 1:a:0 \
  "${common[@]}" -pass 2 -passlogfile "$work/x264" \
  -c:a aac_at -b:a 256k -ar 48000 -ac 2 -shortest \
  -movflags +faststart -tag:v avc1 \
  "$dest/spacepane-preview.mp4"

poster=$(node -e "import('./src/theme/timing.ts').then(m=>console.log(m.POSTER_FRAME))")
npx remotion still src/index.ts SpacePanePreview "$dest/poster.png" --frame="$poster"
ffprobe -v error -show_entries format=duration,size,bit_rate:stream=codec_name,profile,level,width,height,r_frame_rate,pix_fmt,sample_rate,channels,bit_rate -of default=nw=1 "$dest/spacepane-preview.mp4"
