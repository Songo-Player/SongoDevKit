#!/usr/bin/env bash
# Packages Songo #5 as a spruce app: a "Songo#5" folder to drop in place of
# /mnt/SDCARD/App/Songo#5. Not zipped. Run by songo.sh (songo_build_release
# spruce), which builds the inputs and passes them in:
#
#   GODOT, PROJECT_DIR, RUNTIME, ENGINE_LIB, DAEMON, CHAI_DIR, PRESET
#                as for the PortMaster release (see assemble_port.sh)
#   ASSEMBLY     a scratch directory to assemble the app in
#   OUT          the Songo#5 folder to write (replaced)
#
# The app is spruce's files next to this script (config.json, launch.sh,
# songo.png) and the PortMaster release's songo5/ port directory, which
# launch.sh runs, minus PortMaster's own metadata.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORTMASTER_DIR="$SCRIPT_DIR/../portmaster"
: "${ASSEMBLY:?}" "${OUT:?}"

APP_DIR="$ASSEMBLY/Songo#5"
rm -rf "$ASSEMBLY"
mkdir -p "$APP_DIR"
LAUNCHER="$SCRIPT_DIR/launch.sh" PORT_DIR="$APP_DIR/songo5" bash "$PORTMASTER_DIR/assemble_port.sh"

echo ">> Adding spruce's config.json, launch.sh and songo.png"
cp -a "$SCRIPT_DIR/config.json" "$SCRIPT_DIR/launch.sh" "$SCRIPT_DIR/songo.png" "$APP_DIR/"
chmod +x "$APP_DIR/launch.sh"

# PortMaster's metadata and gptokeyb mapping, unused under spruce
rm -f "$APP_DIR/songo5/port.json" "$APP_DIR/songo5/gameinfo.xml" \
    "$APP_DIR/songo5/cover.png" "$APP_DIR/songo5/screenshot.png" "$APP_DIR/songo5/songo5.gptk"

echo ">> Writing $OUT"
rm -rf "$OUT"
mkdir -p "$(dirname "$OUT")"
cp -a "$APP_DIR" "$OUT"

echo ">> Done: $OUT ($(du -sh "$OUT" | cut -f1))"
