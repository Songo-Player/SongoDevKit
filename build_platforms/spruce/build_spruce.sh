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
# launch.sh runs, minus PortMaster's own metadata. Unlike PortMaster, it also
# ships the Spruce theme (SPRUCE_THEMES), in songo5/songo_themes/, and makes it
# the default theme (DEFAULT_THEME) in songo5/songo.conf.
set -euo pipefail

# Packaged themes, from the project's theme_dev/themes_packaged/, that every
# spruce build ships. PortMaster ships none.
SPRUCE_THEMES=(Spruce)
# songo.conf's "theme": what Songo uses until another theme is picked
DEFAULT_THEME=Spruce

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PORTMASTER_DIR="$SCRIPT_DIR/../portmaster"
: "${ASSEMBLY:?}" "${OUT:?}" "${PROJECT_DIR:?}"

# Checked before the (slower) assembly, so a missing theme fails fast
THEMES_DIR="$PROJECT_DIR/theme_dev/themes_packaged"
for theme in "${SPRUCE_THEMES[@]}"; do
    for f in theme.json theme.pck; do
        [ -f "$THEMES_DIR/$theme/$f" ] || { echo "!! Missing $THEMES_DIR/$theme/$f" >&2; exit 1; }
    done
done

APP_DIR="$ASSEMBLY/Songo#5"
rm -rf "$ASSEMBLY"
mkdir -p "$APP_DIR"
LAUNCHER="$SCRIPT_DIR/launch.sh" PORT_DIR="$APP_DIR/songo5" bash "$PORTMASTER_DIR/assemble_port.sh"

# Editor .import files are left out: the device only reads theme.json,
# theme.pck, theme.tres and preview.png. Permissions are set explicitly, as the
# packaged files' own can be anything (directories must stay listable)
for theme in "${SPRUCE_THEMES[@]}"; do
    echo ">> Adding theme $theme -> songo5/songo_themes/$theme"
    mkdir -p "$APP_DIR/songo5/songo_themes/$theme"
    rsync -r --exclude='*.import' --chmod=D755,F644 \
        "$THEMES_DIR/$theme/" "$APP_DIR/songo5/songo_themes/$theme/"
done
chmod 755 "$APP_DIR/songo5/songo_themes"

echo ">> Making $DEFAULT_THEME the default theme in songo5/songo.conf"
CONF="$APP_DIR/songo5/songo.conf"
grep -q '^theme=default$' "$CONF" || { echo "!! $CONF has no theme=default line to set" >&2; exit 1; }
sed -i "s|^theme=default\$|theme=$DEFAULT_THEME|" "$CONF"

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
