#!/usr/bin/env bash
# Assembles the songo5/ port directory, shared by the PortMaster and Spruce
# releases (build_portmaster.sh, build_platforms/spruce/build_spruce.sh), which
# package it differently. Inputs:
#
#   GODOT        Songodot Linux editor, to export the game with
#   PROJECT_DIR  the Songo-5 project to export (songo.sh's staged copy)
#   RUNTIME      Songodot SBC arm64 export template
#   ENGINE_LIB   SongoBGPlayer libsongo_engine.linux.arm64.so
#   DAEMON       SongoBGPlayer songo_bgplayer.linux.arm64
#   CHAI_DIR     chai_retrofit, copied into the port
#   LAUNCHER     the launch script that runs this port, which names the
#                runtime and .pck (runtime="..." and pck_filename="...")
#   PORT_DIR     where to assemble songo5/ (replaced)
#   PRESET       optional, the export preset (default "Linux")
#
# songo5/ next to this script holds the port's static files. The assembled
# port adds:
#   gamedata/<pck>        the game, from the preset
#   runtime/<runtime>     the SBC runtime, under the name the launcher runs
#   runtime/libsongo_engine.linux.arm64.so, songo_bgplayer.linux.arm64
#                         next to it, where SongoPlayerHarness looks
#   chai_retrofit/        chai_retrofit, minus its git metadata
#   songo_plugins/<name>  every plugin in the project's
#                         plugin_dev/plugins_packaged/ (its plugin.json and
#                         plugin.pck), with no list to keep up: packaging a
#                         plugin with plugin_packer.gd is enough to ship it.
#                         Songo starts every plugin disabled until it's enabled.
#
# No external themes are bundled here: PortMaster ships Songo's internal themes
# only. The spruce build adds the Spruce theme itself (build_spruce.sh).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRESET="${PRESET:-Linux}"
: "${GODOT:?}" "${PROJECT_DIR:?}" "${RUNTIME:?}" "${ENGINE_LIB:?}" "${DAEMON:?}" "${CHAI_DIR:?}" "${LAUNCHER:?}" "${PORT_DIR:?}"

for f in "$GODOT" "$RUNTIME" "$ENGINE_LIB" "$DAEMON" "$LAUNCHER" "$CHAI_DIR/chai_entry.sh"; do
    [ -f "$f" ] || { echo "!! Missing $f" >&2; exit 1; }
done

# Every packaged plugin ships. A folder that's missing either file is a
# half-packaged plugin, which would fail to load on the device, so stop.
PLUGINS_DIR="$PROJECT_DIR/plugin_dev/plugins_packaged"
PLUGINS=()
if [ -d "$PLUGINS_DIR" ]; then
    for plugin_dir in "$PLUGINS_DIR"/*/; do
        [ -d "$plugin_dir" ] || continue
        plugin="$(basename "$plugin_dir")"
        for f in plugin.json plugin.pck; do
            [ -f "$plugin_dir/$f" ] || { echo "!! Missing $PLUGINS_DIR/$plugin/$f" >&2; exit 1; }
        done
        PLUGINS+=("$plugin")
    done
fi

# The runtime and .pck names the launcher uses
RUNTIME_NAME="$(sed -n 's/^runtime="\(.*\)"$/\1/p' "$LAUNCHER" | head -n1)"
PCK_NAME="$(sed -n 's/^pck_filename="\(.*\)"$/\1/p' "$LAUNCHER" | head -n1)"
if [ -z "$RUNTIME_NAME" ] || [ -z "$PCK_NAME" ]; then
    echo "!! Couldn't read runtime=\"...\" / pck_filename=\"...\" from $LAUNCHER." >&2
    exit 1
fi

# Captured first: grep -q stopping early would fail the pipe under pipefail
RUNTIME_STRINGS="$(strings "$RUNTIME")"
for class in TagLibLibrary SongoPlayerHarness; do
    grep -q "$class" <<< "$RUNTIME_STRINGS" \
        || { echo "!! $RUNTIME has no $class, is it a current Songodot SBC build?" >&2; exit 1; }
done

echo ">> Assembling the port in $PORT_DIR"
rm -rf "$PORT_DIR"
mkdir -p "$(dirname "$PORT_DIR")"
# Device-side files (log.txt, conf/, songo_configs_built) are left out in case
# they were copied back off a device: shipping songo_configs_built would skip
# the launcher's first-launch songo.conf setup
rsync -a --exclude=/log.txt --exclude=/conf --exclude=/songo_configs_built --exclude=.git \
    "$SCRIPT_DIR/songo5/" "$PORT_DIR/"
mkdir -p "$PORT_DIR/gamedata" "$PORT_DIR/runtime"

echo ">> Exporting preset '$PRESET' -> gamedata/$PCK_NAME"
STARTED="$PORT_DIR/.started"
touch "$STARTED"
"$GODOT" --headless --path "$PROJECT_DIR" --export-pack "$PRESET" "$PORT_DIR/gamedata/$PCK_NAME"
if [ ! "$PORT_DIR/gamedata/$PCK_NAME" -nt "$STARTED" ]; then
    echo "!! Export didn't produce $PORT_DIR/gamedata/$PCK_NAME" >&2
    exit 1
fi
rm -f "$STARTED"

echo ">> Adding the runtime, music engine and daemon -> runtime/"
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

# Only plugin.json and plugin.pck: that's all PluginManager reads. Permissions
# are set explicitly, as the packaged files' own can be anything (directories
# must stay listable)
if [ "${#PLUGINS[@]}" -eq 0 ]; then
    echo ">> No packaged plugins in $PLUGINS_DIR"
fi
for plugin in "${PLUGINS[@]}"; do
    echo ">> Adding plugin $plugin -> songo_plugins/$plugin"
    install -d -m 755 "$PORT_DIR/songo_plugins/$plugin"
    install -m 644 "$PLUGINS_DIR/$plugin/plugin.json" "$PLUGINS_DIR/$plugin/plugin.pck" \
        "$PORT_DIR/songo_plugins/$plugin/"
done
[ -d "$PORT_DIR/songo_plugins" ] && chmod 755 "$PORT_DIR/songo_plugins"
true
