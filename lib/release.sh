# Release packaging and editor bundles. Sourced by songo.sh after
# components.sh.

# ---- Staging Songo-5 ----

# Songo-5 is exported from a copy in .work/, so the devkit can drop in what it
# built (the Android plugin AAR, template paths in the presets) without
# touching the repo. Godot's import cache (.godot) is seeded from the repo's
# the first time and kept after, so exports don't reimport everything.
songo_stage_songo5() {
    SONGO5_STAGE="$WORK_DIR/songo5-stage"
    local first=0
    [ -d "$SONGO5_STAGE" ] || first=1
    mkdir -p "$SONGO5_STAGE"
    rsync -a --delete \
        --exclude=.git --exclude=/build --exclude=/build_platforms --exclude=/android --exclude=/.godot \
        "$SONGO5_DIR/" "$SONGO5_STAGE/"
    if [ "$first" = 1 ] && [ -d "$SONGO5_DIR/.godot" ]; then
        rsync -a --exclude=/editor "$SONGO5_DIR/.godot/" "$SONGO5_STAGE/.godot/"
    fi
    # Export credentials (the release keystore) always follow the repo's
    if [ -f "$SONGO5_DIR/.godot/export_credentials.cfg" ]; then
        mkdir -p "$SONGO5_STAGE/.godot"
        cp -f "$SONGO5_DIR/.godot/export_credentials.cfg" "$SONGO5_STAGE/.godot/"
    fi
}

# Sets an option of a named preset in the staged export_presets.cfg
songo_set_preset_option() { # <preset name> <key> <value>
    python3 - "$SONGO5_STAGE/export_presets.cfg" "$1" "$2" "$3" <<'PY'
import re, sys
path, preset, key, value = sys.argv[1:]
lines = open(path).read().split("\n")
section = None
for line in lines:
    m = re.match(r'^\[(preset\.\d+)\]$', line)
    if m:
        current = m.group(1)
    elif line == 'name="%s"' % preset:
        section = current
        break
if not section:
    sys.exit("No export preset named %r" % preset)
in_options = False
for i, line in enumerate(lines):
    if line.startswith("["):
        in_options = line == "[%s.options]" % section
    elif in_options and line.startswith(key + "="):
        lines[i] = '%s="%s"' % (key, value)
        break
else:
    sys.exit("Preset %r has no option %s" % (preset, key))
open(path, "w").write("\n".join(lines))
PY
}

# Songo's version from the staged project, eg: "v1.0.0 RC8"
songo5_version() {
    sed -n 's/^const VERSION = "\(.*\)"$/\1/p' "$SONGO5_STAGE/data/songo_data.gd" | head -n1
}

# The project icon (config/icon) as a path in the staged project
songo5_icon() {
    local res
    res="$(sed -n 's|^config/icon="res://\(.*\)"$|\1|p' "$SONGO5_STAGE/project.godot" | head -n1)"
    echo "$SONGO5_STAGE/${res:-icon.png}"
}

# ---- Releases ----

songo_release_portmaster() {
    songodot_editor_linuxbsd
    songodot_template_sbc
    bgplayer_linux_arm64
    local out="$OUT_DIR/release/portmaster/songo5.zip"
    local fingerprint="songo5:$FP_SONGO5 chai:$FP_CHAI_RETROFIT editor:$(songo_stamp songodot-editor-linuxbsd)"
    fingerprint+=" template:$(songo_stamp songodot-template-sbc) bgplayer:$(songo_stamp bgplayer-linux-arm64)"
    fingerprint+=" platform:$(songo_dir_fingerprint build_platforms/portmaster) docker:$(songo_dockerfile_hash linux-x86_64)"
    songo_step release-portmaster "$fingerprint" "$out" -- _songo_release_portmaster "$out"
}
_songo_release_portmaster() {
    songo_stage_songo5
    local bgplayer
    bgplayer="$(songo_component_dir bgplayer-linux-arm64)"
    songo_docker linux-x86_64 \
        -v "$CHAI_RETROFIT_DIR:$CHAI_RETROFIT_DIR:ro" \
        -e GODOT="$(songodot_linux_editor_path)" \
        -e PROJECT_DIR="$SONGO5_STAGE" \
        -e RUNTIME="$(songo_component_dir songodot-template-sbc)/godot.sbc.template_release.arm64.llvm" \
        -e ENGINE_LIB="$bgplayer/libsongo_engine.linux.arm64.so" \
        -e DAEMON="$bgplayer/songo_bgplayer.linux.arm64" \
        -e CHAI_DIR="$CHAI_RETROFIT_DIR" \
        -e ASSEMBLY="$WORK_DIR/portmaster" \
        -e OUT="$1" \
        -- bash "$SONGO_DEVKIT_DIR/build_platforms/portmaster/build_portmaster.sh"
}

songo_release_windows() {
    songodot_editor_linuxbsd
    songodot_template_windows
    bgplayer_windows
    local out="$OUT_DIR/release/windows/Songo5-Setup.exe"
    local fingerprint="songo5:$FP_SONGO5 editor:$(songo_stamp songodot-editor-linuxbsd)"
    fingerprint+=" template:$(songo_stamp songodot-template-windows) bgplayer:$(songo_stamp bgplayer-windows)"
    fingerprint+=" platform:$(songo_dir_fingerprint build_platforms/windows) docker:$(songo_dockerfile_hash windows)"
    songo_step release-windows "$fingerprint" "$out" -- _songo_release_windows "$out"
}
_songo_release_windows() {
    songo_stage_songo5
    local work="$WORK_DIR/windows"
    mkdir -p "$work"
    songo_log "Exporting Songo5.pck (windows image)"
    rm -f "$work/Songo5.pck"
    songo_docker windows -- "$(songodot_linux_editor_path)" --headless --path "$SONGO5_STAGE" --export-pack "Windows Desktop" "$work/Songo5.pck"
    [ -f "$work/Songo5.pck" ] || songo_die "Export didn't produce $work/Songo5.pck"
    songo_log "Packaging the installer (windows image)"
    songo_docker windows \
        -e TEMPLATE="$(songo_component_dir songodot-template-windows)/godot.windows.template_release.x86_64.exe" \
        -e PCK="$work/Songo5.pck" \
        -e ENGINE_DLL="$(songo_component_dir bgplayer-windows)/libsongo_engine.windows.x86_64.dll" \
        -e ICON_SRC="$(songo5_icon)" \
        -e VERSION="$(songo5_version)" \
        -e LICENSE_FILE="$SONGO_DEVKIT_DIR/build_platforms/portmaster/songo5/license/LICENSE.txt" \
        -e STAGE="$work/installer" \
        -e SETUP="$1" \
        -e WINEPREFIX="$WORK_DIR/wineprefix" \
        -- bash "$SONGO_DEVKIT_DIR/build_platforms/windows/build_windows.sh"
}

songo_release_android() {
    songodot_editor_linuxbsd
    songodot_template_android
    bgplayer_android
    local out="$OUT_DIR/release/android/songo5.apk"
    local fingerprint="songo5:$FP_SONGO5 editor:$(songo_stamp songodot-editor-linuxbsd)"
    fingerprint+=" template:$(songo_stamp songodot-template-android) bgplayer:$(songo_stamp bgplayer-android)"
    fingerprint+=" platform:$(songo_dir_fingerprint build_platforms/android) docker:$(songo_dockerfile_hash android)"
    songo_step release-android "$fingerprint" "$out" -- _songo_release_android "$out"
}
_songo_release_android() {
    songo_stage_songo5
    # SongoBGPlayer's AAR (with the music engine inside) and the Android
    # source template this devkit built
    mkdir -p "$SONGO5_STAGE/addons/songo_player_harness/android"
    cp -f "$(songo_component_dir bgplayer-android)/songo_harness-release.aar" \
        "$SONGO5_STAGE/addons/songo_player_harness/android/songo_harness-release.aar"
    songo_set_preset_option Android gradle_build/android_source_template \
        "$(songo_component_dir songodot-template-android)/android_source.zip"
    songo_android_keystores
    # Godot reads the SDK and JDK paths from ANDROID_HOME / JAVA_HOME (the
    # image's), as the editor settings in the container are fresh
    songo_android_docker "${ANDROID_DOCKER_KEYSTORE_ARGS[@]}" \
        -e GODOT="$(songodot_linux_editor_path)" \
        -e PROJECT_DIR="$SONGO5_STAGE" \
        -e OUT="$1" \
        -- bash "$SONGO_DEVKIT_DIR/build_platforms/android/build_android.sh"
}

# ---- Editors ----

# An editor with the engine library and daemon next to it, where Songodot's
# SongoPlayerHarness looks first, so it plays music running Songo-5 from its
# project folder.

songo_editor_linux_x86() {
    songodot_editor_linuxbsd
    bgplayer_linux_x86_64
    local dest="$OUT_DIR/editor/linux_x86"
    mkdir -p "$dest"
    cp -f "$(songodot_linux_editor_path)" "$(songo_component_dir bgplayer-linux-x86_64)"/* "$dest/"
    songo_log "Editor ready in $dest"
    ls -lh "$dest"
}

songo_editor_windows() {
    songodot_editor_windows
    bgplayer_windows
    local dest="$OUT_DIR/editor/windows"
    mkdir -p "$dest"
    cp -f "$(songo_component_dir songodot-editor-windows)"/*.exe "$(songo_component_dir bgplayer-windows)"/*.dll "$dest/"
    songo_log "Editor ready in $dest"
    ls -lh "$dest"
}
