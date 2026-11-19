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
# songo5/ is assembled by assemble_port.sh (which also checks the inputs) and
# zipped with the Songo5.sh launcher next to this script.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ASSEMBLY:?}" "${OUT:?}"

LAUNCHER="$SCRIPT_DIR/Songo5.sh"
rm -rf "$ASSEMBLY"
mkdir -p "$ASSEMBLY"
LAUNCHER="$LAUNCHER" PORT_DIR="$ASSEMBLY/songo5" bash "$SCRIPT_DIR/assemble_port.sh"
cp -a "$LAUNCHER" "$ASSEMBLY/"

echo ">> Zipping -> $OUT"
mkdir -p "$(dirname "$OUT")"
rm -f "$OUT"
# Python's zipfile, keeping Unix permissions (the runtime and scripts must stay
# executable). assemble_port.sh already leaves out device-side files (log.txt,
# conf/); skipped here too in case the assembly is reused.
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
