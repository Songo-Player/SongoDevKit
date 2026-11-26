#!/usr/bin/env bash
# Packages Songo #5 for desktop Linux (x86_64): a tarball holding a Songo5/
# folder with the game and the music engine side by side. Run by songo.sh
# (songo_build_release linux_x86), which builds the inputs and passes them in:
#
#   GODOT         Songodot Linux editor, to export the game with
#   PROJECT_DIR   the Songo-5 project to export (songo.sh's staged copy)
#   TEMPLATE      Songodot Linux x86_64 export template
#   ENGINE_LIB    SongoBGPlayer libsongo_engine.linux.x86_64.so
#   DAEMON        SongoBGPlayer songo_bgplayer.linux.x86_64
#   LICENSE_FILE  Songo's license, shipped as LICENSE.txt
#   BGPLAYER_DIR, SONGODOT_DIR, SOURCES
#                 for the licenses, see ../licenses/add_licenses.sh
#   ASSEMBLY      a scratch directory to assemble the release in
#   OUT           the .tar.gz to write
#   PRESET        optional, the export preset (default "Linux x86_64")
#
# The tarball's Songo5/ folder:
#   Songo5.x86_64                    the template, run to start Songo
#   Songo5.pck                       the game, which Godot finds next to it
#   libsongo_engine.linux.x86_64.so  next to the executable, where
#   songo_bgplayer.linux.x86_64      SongoPlayerHarness looks first
#   LICENSE.txt
#   third_party/                     everything's licenses (../licenses/add_licenses.sh)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRESET="${PRESET:-Linux x86_64}"
: "${GODOT:?}" "${PROJECT_DIR:?}" "${TEMPLATE:?}" "${ENGINE_LIB:?}" "${DAEMON:?}" "${LICENSE_FILE:?}" "${ASSEMBLY:?}" "${OUT:?}"
: "${BGPLAYER_DIR:?}" "${SONGODOT_DIR:?}" "${SOURCES:?}"

for f in "$GODOT" "$TEMPLATE" "$ENGINE_LIB" "$DAEMON" "$LICENSE_FILE"; do
    [ -f "$f" ] || { echo "!! Missing $f" >&2; exit 1; }
done

# Captured first: grep -q stopping early would fail the pipe under pipefail
TEMPLATE_STRINGS="$(strings "$TEMPLATE")"
for class in TagLibLibrary SongoPlayerHarness; do
    grep -q "$class" <<< "$TEMPLATE_STRINGS" \
        || { echo "!! $TEMPLATE has no $class, is it a current Songodot Linux template?" >&2; exit 1; }
done

APP_DIR="$ASSEMBLY/Songo5"
echo ">> Assembling the release in $APP_DIR"
rm -rf "$ASSEMBLY"
mkdir -p "$APP_DIR"

echo ">> Exporting preset '$PRESET' -> Songo5/Songo5.pck"
touch "$ASSEMBLY/.started"
"$GODOT" --headless --path "$PROJECT_DIR" --export-pack "$PRESET" "$APP_DIR/Songo5.pck"
if [ ! "$APP_DIR/Songo5.pck" -nt "$ASSEMBLY/.started" ]; then
    echo "!! Export didn't produce $APP_DIR/Songo5.pck" >&2
    exit 1
fi
rm -f "$ASSEMBLY/.started"

echo ">> Adding the runtime, music engine and daemon"
cp -f "$TEMPLATE" "$APP_DIR/Songo5.x86_64"
cp -f "$ENGINE_LIB" "$APP_DIR/libsongo_engine.linux.x86_64.so"
cp -f "$DAEMON" "$APP_DIR/songo_bgplayer.linux.x86_64"
cp -f "$LICENSE_FILE" "$APP_DIR/LICENSE.txt"

THIRD_PARTY="$APP_DIR/third_party"
bash "$SCRIPT_DIR/../licenses/add_licenses.sh" "$THIRD_PARTY" ../LICENSE.txt
find "$THIRD_PARTY" -type d -exec chmod 755 {} +
find "$THIRD_PARTY" -type f -exec chmod 644 {} +

chmod 755 "$APP_DIR/Songo5.x86_64" "$APP_DIR/songo_bgplayer.linux.x86_64"
chmod 644 "$APP_DIR/Songo5.pck" "$APP_DIR/libsongo_engine.linux.x86_64.so" "$APP_DIR/LICENSE.txt"

echo ">> Packing -> $OUT"
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
tar -C "$ASSEMBLY" --owner=0 --group=0 -czf "$OUT" Songo5

echo ">> Done: $OUT ($(du -h "$OUT" | cut -f1))"
