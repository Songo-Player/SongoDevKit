#!/usr/bin/env bash
# Packages Songo #5 for PortMaster: a zip holding the Songo5.sh launcher and
# the songo5/ port directory. Run by songo.sh (songo_build_release portmaster),
# which builds the inputs and passes them in:
#
#   GODOT        Songodot Linux editor, to export the game with
#   PROJECT_DIR  the Songo-5 project to export (songo.sh's staged copy)
#   RUNTIME      Songodot SBC arm64 export template
#   ENGINE_LIB   SongoBGPlayer libsongo_engine.linux.arm64.so
#   DAEMON       SongoBGPlayer songo_bgplayer.linux.arm64
#   CHAI_DIR     chai_retrofit, copied into the port
#   ASSEMBLY     a scratch directory to assemble the port in
#   OUT          the zip to write
#   PRESET       optional, the export preset (default "Linux")
#
# Songo5.sh and songo5/ next to this script are the port's static files. The
# assembled port adds:
#   songo5/gamedata/<pck>        the game, from the preset
#   songo5/runtime/<runtime>     the SBC runtime, under the name Songo5.sh runs
#   songo5/runtime/libsongo_engine.linux.arm64.so, songo_bgplayer.linux.arm64
#                                next to it, where SongoPlayerHarness looks
#   songo5/chai_retrofit/        chai_retrofit, minus its git metadata
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRESET="${PRESET:-Linux}"
: "${GODOT:?}" "${PROJECT_DIR:?}" "${RUNTIME:?}" "${ENGINE_LIB:?}" "${DAEMON:?}" "${CHAI_DIR:?}" "${ASSEMBLY:?}" "${OUT:?}"

LAUNCHER="$SCRIPT_DIR/Songo5.sh"
for f in "$GODOT" "$RUNTIME" "$ENGINE_LIB" "$DAEMON" "$LAUNCHER" "$CHAI_DIR/chai_entry.sh"; do
    [ -f "$f" ] || { echo "!! Missing $f" >&2; exit 1; }
done

# The runtime and .pck names the launcher uses
RUNTIME_NAME="$(sed -n 's/^runtime="\(.*\)"$/\1/p' "$LAUNCHER" | head -n1)"
PCK_NAME="$(sed -n 's/^pck_filename="\(.*\)"$/\1/p' "$LAUNCHER" | head -n1)"
if [ -z "$RUNTIME_NAME" ] || [ -z "$PCK_NAME" ]; then
    echo "!! Couldn't read runtime=\"...\" / pck_filename=\"...\" from Songo5.sh." >&2
    exit 1
fi

# Captured first: grep -q stopping early would fail the pipe under pipefail
RUNTIME_STRINGS="$(strings "$RUNTIME")"
for class in TagLibLibrary SongoPlayerHarness; do
    grep -q "$class" <<< "$RUNTIME_STRINGS" \
        || { echo "!! $RUNTIME has no $class, is it a current Songodot SBC build?" >&2; exit 1; }
done

echo ">> Assembling the port in $ASSEMBLY"
rm -rf "$ASSEMBLY"
mkdir -p "$ASSEMBLY"
cp -a "$LAUNCHER" "$SCRIPT_DIR/songo5" "$ASSEMBLY/"
PORT_DIR="$ASSEMBLY/songo5"
mkdir -p "$PORT_DIR/gamedata" "$PORT_DIR/runtime"

echo ">> Exporting preset '$PRESET' -> songo5/gamedata/$PCK_NAME"
touch "$ASSEMBLY/.started"
"$GODOT" --headless --path "$PROJECT_DIR" --export-pack "$PRESET" "$PORT_DIR/gamedata/$PCK_NAME"
if [ ! "$PORT_DIR/gamedata/$PCK_NAME" -nt "$ASSEMBLY/.started" ]; then
    echo "!! Export didn't produce $PORT_DIR/gamedata/$PCK_NAME" >&2
    exit 1
fi
rm -f "$ASSEMBLY/.started"

echo ">> Adding the runtime, music engine and daemon -> songo5/runtime/"
cp -f "$RUNTIME" "$PORT_DIR/runtime/$RUNTIME_NAME"
cp -f "$ENGINE_LIB" "$PORT_DIR/runtime/libsongo_engine.linux.arm64.so"
cp -f "$DAEMON" "$PORT_DIR/runtime/songo_bgplayer.linux.arm64"
chmod +x "$PORT_DIR/runtime/$RUNTIME_NAME" "$PORT_DIR/runtime/songo_bgplayer.linux.arm64"

if git -C "$CHAI_DIR" rev-parse --git-dir > /dev/null 2>&1; then
    echo ">> Adding chai_retrofit ($(git -C "$CHAI_DIR" log -1 --format='%h %s'))"
else
    echo ">> Adding chai_retrofit"
fi
rsync -a --exclude=.git "$CHAI_DIR/" "$PORT_DIR/chai_retrofit/"

echo ">> Zipping -> $OUT"
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
# Python's zipfile, keeping Unix permissions (the runtime and scripts must stay
# executable). Device-side files (log.txt, conf/) are left out in case they
# were copied back off a device.
python3 - "$ASSEMBLY" "$OUT" <<'EOF'
import os, stat, sys, zipfile

base, out = sys.argv[1], sys.argv[2]
skip = {"songo5/log.txt", "songo5/conf"}

def add(zf, rel):
    path = os.path.join(base, rel)
    st = os.stat(path)
    if os.path.isdir(path):
        info = zipfile.ZipInfo(rel + "/")
        info.external_attr = (stat.S_IFDIR | 0o755) << 16
        zf.writestr(info, b"")
        for name in sorted(os.listdir(path)):
            child = rel + "/" + name
            if child not in skip and name != ".git":
                add(zf, child)
    else:
        info = zipfile.ZipInfo.from_file(path, rel)
        info.external_attr = (stat.S_IFREG | stat.S_IMODE(st.st_mode)) << 16
        info.compress_type = zipfile.ZIP_DEFLATED
        with open(path, "rb") as f:
            zf.writestr(info, f.read(), compresslevel=9)

with zipfile.ZipFile(out, "w") as zf:
    add(zf, "Songo5.sh")
    add(zf, "songo5")
EOF

echo ">> Done: $OUT ($(du -h "$OUT" | cut -f1))"
