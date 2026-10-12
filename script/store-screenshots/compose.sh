#!/bin/bash
# Lays out the raw captures from capture.sh as the nine App Store screenshots: 2880 x 1800, opaque PNG.
# Headlines are the ones in docs/release/app-store-listing.md. Gradients use the website palette (DESIGN.md in the spacepane-web repository).
#
#   script/store-screenshots/compose.sh [output directory]   (default: docs/release/store-listing/screenshots)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WORK="$ROOT/.build/store-screenshots"
RAW="$WORK/raw"
OUT="${1:-$ROOT/docs/release/store-listing/screenshots}"
TOOL="$WORK/shots"
mkdir -p "$OUT"
/usr/bin/xcrun swiftc -O -o "$TOOL" "$ROOT/script/compose_store_screenshot.swift"

at() { awk -F"\t" -v name="$1" '$1==name {print $2 ":" $3}' "$RAW/geometry.tsv"; }
shot() { # shot <file> <eyebrow> <headline> <note> <colors> <capture> [<capture> ...]
  local file="$1" eyebrow="$2" headline="$3" note="$4" colors="$5"; shift 5
  local captures=() extra=()
  for name in "$@"; do captures+=("$RAW/$name.png:$(at "$name")"); done
  [[ -n "$note" ]] && extra=(--note "$note")
  "$TOOL" compose --background gradient --colors "$colors" --angle -35 --bleed --eyebrow "$eyebrow" \
    --headline "$headline" ${extra[@]+"${extra[@]}"} --output "$OUT/$file" "${captures[@]}" | sed "s|$OUT/||"
}

shot 01-press-space.png      "Quick Look in Finder" "Press Space.|See what's really inside."   "" "#4b3cff,#a64dff,#ff4f9a,#ffb547" 1-finder 1-panel
shot 02-secrets-concealed.png "Privacy"             "Likely secrets concealed,|and counted."   "" "#3a2be6,#7b43ff,#c44dff"         2-panel
shot 03-notebooks.png        "Jupyter notebooks"    "Notebooks as saved.|Never run."            "" "#d6307f,#ff5b6e,#ff9a4a"         3-panel
shot 04-database.png         "SQLite"               "A database at a glance.|Read-only."        "" "#3a2be6,#2f7de1,#32c8c0"         4-panel-table
shot 05-archives.png         "Archives"             "Look inside.|Nothing is extracted."        "" "#7b43ff,#d44fd0,#ff4f9a"         5-panel
shot 06-markdown.png         "Markdown"             "Markdown, ready to read."                  "" "#1f5fd6,#2a9fd6,#3fd3b5"         6-panel
shot 07-models.png           "3D models"            "Models you can turn."  "STEP and IGES are off until you switch them on." "#1a1466,#4b3cff,#a64dff" 7-panel
shot 08-file-types.png       "File Types"           "A switch for every file type."             "" "#e0358a,#a64dff,#4b3cff"         8-app
shot 09-theme.png            "Theme"                "Your colors. Your type."                   "" "#4b3cff,#a64dff,#ff4f9a,#ffb547" 9-app

for file in "$OUT"/*.png; do
  /usr/bin/sips -g pixelWidth -g pixelHeight -g hasAlpha "$file" | awk -v f="$(basename "$file")" 'NR>1 {printf "%s ", $2} END {print f}'
done
