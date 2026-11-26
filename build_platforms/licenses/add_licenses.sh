#!/usr/bin/env bash
# Adds the licenses of everything in a release, shared by every platform's build:
#
#   add_licenses.sh <dir> <path to Songo's LICENSE.txt, from dir> [extra.md...]
#
# The extra .md files, next to this script, are added to THIRD_PARTY.md. Inputs:
#   BGPLAYER_DIR, SONGODOT_DIR  SongoBGPlayer and Songodot
#   PROJECT_DIR                 the Songo-5 project
#   SOURCES                     the source repos and commits built from
#
# Every file is checked before anything is written: a release never goes out
# without its licenses.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST="${1:?}"
LICENSE_PATH="${2:?}"
shift 2
: "${BGPLAYER_DIR:?}" "${SONGODOT_DIR:?}" "${PROJECT_DIR:?}" "${SOURCES:?}"

# source file:where it goes in DEST
FILES=(
    "$SONGODOT_DIR/LICENSE.txt:godot/LICENSE.txt"
    "$SONGODOT_DIR/COPYRIGHT.txt:godot/COPYRIGHT.txt"
    "$SONGODOT_DIR/thirdparty/taglib/COPYING.LGPL:taglib/COPYING.LGPL"
    "$SONGODOT_DIR/thirdparty/taglib/3rdparty/utfcpp/LICENSE:utfcpp/LICENSE"
    "$BGPLAYER_DIR/licenses/ffmpeg/COPYING.LGPLv3:ffmpeg/COPYING.LGPLv3"
    "$BGPLAYER_DIR/licenses/ffmpeg/COPYING.GPLv3:ffmpeg/COPYING.GPLv3"
    "$BGPLAYER_DIR/licenses/ffmpeg/COPYING.LGPLv2.1:ffmpeg/COPYING.LGPLv2.1"
    "$BGPLAYER_DIR/licenses/ffmpeg/building.md:ffmpeg/building.md"
    "$BGPLAYER_DIR/licenses/mbedtls/LICENSE:mbedtls/LICENSE"
    "$PROJECT_DIR/THIRD_PARTY.md:songo5/THIRD_PARTY.md"
)
for font in CourierPrime Knewave NotoSansCJK; do
    FILES+=("$PROJECT_DIR/licenses/fonts/$font-OFL.txt:songo5/licenses/fonts/$font-OFL.txt")
done
EXTRAS=()
for extra in "$@"; do EXTRAS+=("$SCRIPT_DIR/$extra"); done
for f in "${FILES[@]%%:*}" "$SCRIPT_DIR/THIRD_PARTY.md" ${EXTRAS[@]+"${EXTRAS[@]}"}; do
    [ -f "$f" ] || { echo "!! Missing license file $f" >&2; exit 1; }
done

echo ">> Adding third-party licenses -> $DEST"
mkdir -p "$DEST"
for entry in "${FILES[@]}"; do
    install -D -m 644 "${entry%%:*}" "$DEST/${entry#*:}"
done
{
    sed "s|@LICENSE@|$LICENSE_PATH|" "$SCRIPT_DIR/THIRD_PARTY.md"
    for extra in ${EXTRAS[@]+"${EXTRAS[@]}"}; do
        echo
        cat "$extra"
    done
} > "$DEST/THIRD_PARTY.md"
printf 'Source code for this release, as built:\n\n%s\n' "$SOURCES" > "$DEST/SOURCES.txt"
chmod 644 "$DEST/THIRD_PARTY.md" "$DEST/SOURCES.txt"
