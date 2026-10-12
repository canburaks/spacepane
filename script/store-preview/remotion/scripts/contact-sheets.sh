#!/bin/bash
# Usage: contact-sheets.sh video.mp4 outdir [step_seconds] — tiles frames (2 x 3 per sheet, in time order, left to right) for review.
set -euo pipefail
video="$1"; out="$2"; step="${3:-1}"
mkdir -p "$out"; rm -f "$out"/sheet*.png
ffmpeg -v error -i "$video" -vf "fps=1/$step,scale=960:-1,tile=2x3" "$out/sheet%02d.png"
ls "$out"
