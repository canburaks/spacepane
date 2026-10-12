#!/bin/bash
# Captures the raw windows for the App Store screenshots from the running Mac: real Finder Quick Look panels
# and the companion's own window. Nothing is drawn or retouched here; compose.sh lays the captures out.
#
#   script/store-screenshots/capture.sh [SpacePane.app]
#
# Needs: a Retina display mode, Screen Recording and Accessibility permission for the calling app, the demo
# files from script/generate_store_demo_files.py, and SpacePane's extensions enabled. It takes over Finder and
# SpacePane for about two minutes; keep hands off. Finder's view settings are restored at the end.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HERE="$ROOT/script/store-screenshots"
WORK="$ROOT/.build/store-screenshots"
RAW="$WORK/raw"
DEMO="$WORK/Harbor"
APP="${1:-$ROOT/.build/xcode/Build/Products/Release/SpacePane.app}"
TOOL="$WORK/shots"
mkdir -p "$RAW"
/usr/bin/xcrun swiftc -O -o "$TOOL" "$ROOT/script/compose_store_screenshot.swift"
: > "$RAW/geometry.tsv"

window() { "$TOOL" windows | awk -F"\t" -v owner="$1" -v title="$2" -v floating="$3" \
  '$2==owner && $4==title && ((floating=="yes" && $5!="0") || (floating!="yes" && $5=="0")) {print; exit}'; }
grab() { # grab <name> <window line>
  local id frame
  id="$(printf '%s' "$2" | cut -f1)"; frame="$(printf '%s' "$2" | cut -f3)"
  [[ -n "$id" ]] || { echo "No window for $1" >&2; return 1; }
  /usr/sbin/screencapture -x -o -l "$id" "$RAW/$1.png"
  printf '%s\t%s\t%s\n' "$1" "$(echo "$frame" | cut -d, -f1)" "$(echo "$frame" | cut -d, -f2)" >> "$RAW/geometry.tsv"
}
panel() { /usr/bin/osascript "$HERE/panel.applescript" Harbor "$1" "$2" "${@:3}" >/dev/null; sleep 1.2; }
# The zoom shortcut only lands when the panel has the keyboard; compare captures and try again if nothing moved.
zoom() {
  local id attempt before="$RAW/zoom-before.png" after="$RAW/zoom-after.png"
  id="$(window Finder "" yes | cut -f1)"
  /usr/sbin/screencapture -x -o -l "$id" "$before"
  [[ -s "$before" ]] || { echo "Could not capture the panel before zooming." >&2; return 1; }
  for attempt in 1 2 3; do
    # shellcheck disable=SC2046
    "$TOOL" click $(/usr/bin/osascript "$HERE/zoom.applescript" point); sleep 0.4
    /usr/bin/osascript "$HERE/zoom.applescript" "$1" >/dev/null; sleep 0.9
    /usr/sbin/screencapture -x -o -l "$id" "$after"
    if [[ -s "$after" ]] && ! cmp -s "$before" "$after"; then rm -f "$before" "$after"; return 0; fi
  done
  rm -f "$before" "$after"
  echo "Zoom did not change the preview." >&2; return 1
}
restore() { /usr/bin/osascript "$HERE/restore.applescript" Harbor >/dev/null 2>&1 || true; }
trap restore EXIT

# Dark previews use GitHub Dark, the scheme chosen for the store images. The tile needs a real mouse click.
/usr/bin/open "$APP"; sleep 2.5
/usr/bin/osascript -e 'tell application "System Events" to tell process "SpacePane"' -e 'set frontmost to true' \
  -e 'set position of window 1 to {380, 200}' -e 'set size of window 1 to {1290, 820}' -e 'end tell' >/dev/null
TILE="$(/usr/bin/osascript "$HERE/theme.applescript" 7)"
[[ -n "$TILE" ]] || { echo "The GitHub Dark tile was not found." >&2; exit 1; }
# shellcheck disable=SC2086
"$TOOL" click $TILE; sleep 1

/usr/bin/osascript "$HERE/stage.applescript" "$DEMO" >/dev/null
/usr/bin/osascript -e 'tell application "Finder"
set w to first Finder window whose name is "Harbor"
set text size of list view options of w to 14
set bounds of w to {60, 80, 1060, 700}
end tell' >/dev/null

# 1. Finder with the Quick Look panel on a JSON file, Outline view.
panel README.md "" 330 150 1040 720
panel settings.json Outline 330 150 1040 720
/usr/bin/osascript "$HERE/expand.applescript" service database features >/dev/null; sleep 0.6
grab 1-finder "$(window Finder Harbor no)"
grab 1-panel "$(window Finder "" yes)"

# 2-7. The panel alone, one file each.
FRAME=(380 230 1290 780)
panel settings.json Source "${FRAME[@]}"; zoom 3;        grab 2-panel "$(window Finder "" yes)"
panel tide-analysis.ipynb Rendered "${FRAME[@]}"; zoom 2; grab 3-panel "$(window Finder "" yes)"
panel stations.sqlite Table "${FRAME[@]}";       grab 4-panel-table "$(window Finder "" yes)"
panel stations.sqlite Summary "${FRAME[@]}"
/usr/bin/osascript "$HERE/expand.applescript" Schema Table >/dev/null; sleep 0.6
grab 4-panel-summary "$(window Finder "" yes)"
panel release-1.4.zip Tree "${FRAME[@]}";        grab 5-panel "$(window Finder "" yes)"
panel README.md Rendered "${FRAME[@]}"; zoom 2;  grab 6-panel "$(window Finder "" yes)"
# The model sits in the middle of its panel, so this one is short enough to show whole.
panel winch-gear.step "" 380 230 1290 600; sleep 2; grab 7-panel "$(window Finder "" yes)"
restore
trap - EXIT

# 8-9. The companion's File Types and Theme pages.
/usr/bin/open "$APP"; sleep 1.5
for PAGE in "File Types:8-app" "Theme:9-app"; do
  /usr/bin/osascript -e 'on run argv' -e 'tell application "System Events" to tell process "SpacePane"' -e 'set frontmost to true' \
    -e 'click menu item (item 1 of argv) of menu "View" of menu bar 1' -e 'set position of window 1 to {380, 200}' \
    -e 'set size of window 1 to {1290, 820}' -e 'delay 1.2' -e 'end tell' -e 'end run' "${PAGE%%:*}" >/dev/null
  grab "${PAGE##*:}" "$("$TOOL" windows | awk -F"\t" '$2=="SpacePane" && $5=="0" {print; exit}')"
done
/usr/bin/osascript -e 'tell application "SpacePane" to quit' >/dev/null 2>&1 || true
ls "$RAW"
