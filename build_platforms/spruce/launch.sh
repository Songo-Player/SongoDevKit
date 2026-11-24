#!/bin/bash
# Songo #5 for spruce: App/Songo#5/launch.sh, run by spruce's menu (config.json).
# The same songo5/ port as the PortMaster release, launched without PortMaster.
#
# The app folder's name has a "#" in it, so quote every path built from it.

. /mnt/SDCARD/spruce/scripts/helperFunctions.sh

set_smart

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
GAMEDIR="$SCRIPT_DIR/songo5"

runtime="sbc_4_3_rcv12"
pck_filename="Songo5.pck"

# Logging. Process substitution needs /dev/fd, which BaseOS on the Anbernic XX
# line doesn't have: bash prints "cannot open /dev/fd/63" and carries on with
# stdout unchanged, leaving an empty log. Fall back to a plain redirect.
> "$GAMEDIR/log.txt"
if [ -e /dev/fd ]; then
	exec > >(tee "$GAMEDIR/log.txt") 2>&1
else
	exec >> "$GAMEDIR/log.txt" 2>&1
fi

# PortMaster's CFW_NAME and DEVICE_NAME aren't set under spruce. spruce's
# PLATFORM stands in for DEVICE_NAME, which Songo and the checks below read.
export DEVICE_NAME="${DEVICE_NAME:-$PLATFORM}"
echo "spruce platform: ${PLATFORM}"

# Create directory for save files
CONFDIR="$GAMEDIR/conf/"
mkdir -p "${CONFDIR}"

# songo_conf_set / songo_conf_default, for writing to songo.conf (which Songo
# reads from beside its runtime)
source "${GAMEDIR}/runtime/songo_conf.sh"

# The strategy folder the controls runtime scripts use
SONGO_CFW_NAME="Spruce"
export SONGO_CFW_NAME

# CHAI: makes sure "chai" is a command, spruce's own or the retrofit for it.
# Godot (DeviceOS) uses it for brightness, battery and idle suppression.
# CHAI_RETRO_DIR tells it where it is, which it can't work out itself outside bash.
if [ -f "${GAMEDIR}/chai_retrofit/chai_entry.sh" ]; then
	CHAI_RETRO_DIR="${GAMEDIR}/chai_retrofit"
	source "${GAMEDIR}/chai_retrofit/chai_entry.sh"
fi

# Volume indicator: chai runs the subscriber on every volume change, and it
# passes the volume to Godot's listener, which Songo starts when songo.conf's
# volume_tcp_server is 1. Off on twig. The subscriber is added every launch;
# songo.conf only records the result on the first (see songo_conf.sh).
SONGO_VOL_SUBSCRIBER="${GAMEDIR}/runtime/chai_volume_subscriber.sh"
if [ ! -f /mnt/SDCARD/spruce/twig ] && chai add-volume-subscriber "$SONGO_VOL_SUBSCRIBER" 2>/dev/null; then
	songo_conf_set volume_tcp_server 1
else
	songo_conf_set volume_tcp_server 0
fi

# Screen fades need a brightness chai can read back, otherwise Songo fades an
# overlay instead (songo.conf's no_bright_fade_available, first launch only)
if songo_conf_building; then
	case "$(chai get-brightness 2>/dev/null)" in
		'' | *[!0-9]*) songo_conf_set no_bright_fade_available 1 ;;
		*) songo_conf_set no_bright_fade_available 0 ;;
	esac
fi

# Find a music player left playing by "Quit with Music" for Songo to pick back
# up, and set up the next one
source "${GAMEDIR}/runtime/background_play/setup_env.sh"

# Set up controls
source "${GAMEDIR}/runtime/controls/setup_env.sh"

# songo.conf's values are all written: don't work them out again on later
# launches (delete songo_configs_built to)
songo_conf_mark_built

cd "$GAMEDIR"

# Set the XDG environment variables for config & savefiles
export XDG_DATA_HOME="$CONFDIR"

# The Anbernic XX line isn't in SDL's built-in mapping database (every H700
# model reports the same GUID as "ANBERNIC-keys"), so spruce's cfg carries the
# map. Positional, as the runtime speaks SDL's vocabulary where "a" is the
# South button, matching spruce's other apps.
case "$PLATFORM" in
	"Anbernic"*) export_sdl_gamecontroller_map positional ;;
esac

echo "XDG_DATA_HOME"
echo "$XDG_DATA_HOME"

export SONGO_DIR_TIP="On Spruce I suggest making a MUSIC folder in /mnt/SDCARD/"

# On KMSDRM only: rotates touch input on GLES3 (the picture is left alone), and
# both the picture and touch on Vulkan. Devices without touch are unaffected
export SONGODOT_KMSDRM_ROTATION="270"

# Compatibility on GLES3, which the sbc runtime's "opengl3" driver creates. Its
# "opengl3_es" sets up no GL context and segfaults.
GODOT_OPTS="$GODOT_OPTS --rendering-method gl_compatibility --rendering-driver opengl3"
"$GAMEDIR/runtime/$runtime" $GODOT_OPTS --main-pack "gamedata/$pck_filename"

# Cleanup

chai remove-volume-subscriber "$SONGO_VOL_SUBSCRIBER" 2>/dev/null

# Undo the retrofit's setup (volume listener). Nothing to undo with native chai.
if command -v chai_retrofit_teardown >/dev/null 2>&1; then
	chai_retrofit_teardown
fi

# Turn idle suppression off in case Songo crashed while music was playing.
# Always, even after "Quit with Music" left the music player running: it's
# only on while Songo is open, and Songo turns it back on when it picks the
# player up again.
chai set-idle-suppression 0 2>/dev/null

# Fix brightness if app crashed when at 0
if [ "$(chai get-brightness 2>/dev/null)" = "0" ]; then
	echo "Backlight left at 0, restoring to half brightness"
	chai set-brightness 128 2>/dev/null
fi
