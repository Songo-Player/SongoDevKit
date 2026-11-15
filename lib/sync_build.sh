#!/usr/bin/env bash
# Syncs a repo into a work copy and runs a build command there, so builds never
# write into the repos themselves, and each build target keeps its own objects
# (Songodot regenerates headers per build profile, so sharing one tree between
# targets would mean near-full rebuilds on every switch).
#
#   sync_build.sh <repo dir> <work dir> <songodot|bgplayer> -- <command...>
#
# The copy is <work dir>/src. Only sources are synced: the repo's own build
# products (Songodot's objects, SongoBGPlayer's FFmpeg/mbedTLS) are left
# behind, since they may come from a different toolchain than the image's, and
# the copy's own build products are kept between builds. Runs inside the
# devkit's images.
set -euo pipefail

SRC="$1"
WORK="$2"
KIND="$3"
shift 3
[ "${1:-}" = "--" ] && shift
DEST="$WORK/src"

COMMON=(--exclude=.git --exclude=__pycache__)
case "$KIND" in
    songodot)
        BUILD_PRODUCTS=(
            --exclude=/bin --exclude=/.sconf_temp --exclude=/config.log --exclude=.sconsign.dblite
            --exclude='*.o' --exclude='*.a' --exclude='*.os' --exclude='*.obj' --exclude='*.gen.*'
            --exclude=/platform/android/java/lib/libs --exclude='/platform/android/java/**/build' --exclude=.gradle
        )
        ;;
    bgplayer)
        BUILD_PRODUCTS=(
            --exclude=/bin --exclude=/build --exclude=.sconsign.dblite --exclude='*.o' --exclude='*.a'
            --exclude=/android/plugin/build --exclude=.gradle
            --exclude=/tests/godot/.godot --exclude=/tests/godot/addons --exclude=/tests/godot/audio
        )
        ;;
    *)
        echo "!! sync_build.sh: unknown kind '$KIND'" >&2
        exit 1
        ;;
esac

mkdir -p "$DEST"
# Excluded paths are also kept from --delete, which is what protects the copy's
# own build products
rsync -a --delete "${COMMON[@]}" "${BUILD_PRODUCTS[@]}" "$SRC/" "$DEST/"

cd "$DEST"
exec "$@"
