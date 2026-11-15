# The pieces Songo is built from. Each is a songo_step: it only builds when
# its repo (or its build settings, or its Docker image) changed since it was
# last built, and leaves its results in out/components/<name>/. Sourced by
# songo.sh after common.sh.
#
#   songodot-editor-linuxbsd   Songodot Linux editor (linux-x86_64 image), also what exports
#   songodot-editor-windows    Songodot Windows editor (windows image)
#   songodot-template-sbc      Songodot SBC arm64 template (linux-arm64 image)
#   songodot-template-windows  Songodot Windows template (windows image)
#   songodot-template-android  Songodot Android templates + Gradle source (android image)
#   bgplayer-linux-x86_64      SongoBGPlayer engine + daemon (linux-x86_64 image)
#   bgplayer-linux-arm64       SongoBGPlayer engine + daemon (linux-arm64 image)
#   bgplayer-windows           SongoBGPlayer engine DLL (windows image)
#   bgplayer-android           SongoBGPlayer engine + plugin AAR (android image)

songo_component_dir() { echo "$OUT_DIR/components/$1"; }

# Copies the newest file matching a glob in a work copy's bin/ into a
# component's output dir, printing the copy's path
_songo_collect() { # <work copy> <glob> <component>
    local found
    # shellcheck disable=SC2086
    found="$(ls -t $1/$2 2>/dev/null | head -n1)"
    [ -n "$found" ] || songo_die "No $2 in $1 after building"
    local dest
    dest="$(songo_component_dir "$3")"
    mkdir -p "$dest"
    cp -f "$found" "$dest/"
    echo "$dest/$(basename "$found")"
}

# ---- Songodot ----

songodot_editor_linuxbsd() {
    local name=songodot-editor-linuxbsd
    local fingerprint="$FP_SONGODOT args:$SONGODOT_LINUX_EDITOR_ARGS docker:$(songo_dockerfile_hash linux-x86_64)"
    songo_step "$name" "$fingerprint" "$(songo_component_dir "$name")/.built" -- _songodot_editor_linuxbsd
}
_songodot_editor_linuxbsd() {
    local work="$WORK_DIR/songodot-editor-linuxbsd" dest
    dest="$(songo_component_dir songodot-editor-linuxbsd)"
    rm -rf "$dest"
    mkdir -p "$work"
    # shellcheck disable=SC2086
    songo_docker linux-x86_64 -v "$SONGODOT_DIR:/src:ro" -v "$work:/work" -- \
        bash /devkit/lib/sync_build.sh /src /work songodot -- \
        scons platform=linuxbsd target=editor $SONGODOT_LINUX_EDITOR_ARGS -j"$JOBS"
    _songo_collect "$work/src/bin" 'godot.linuxbsd.editor.x86_64*' songodot-editor-linuxbsd > /dev/null
    touch "$dest/.built"
}
# The Linux editor binary, after songodot_editor_linuxbsd
songodot_linux_editor_path() {
    ls "$(songo_component_dir songodot-editor-linuxbsd)"/godot.linuxbsd.editor.x86_64* | head -n1
}

songodot_editor_windows() {
    local name=songodot-editor-windows
    local fingerprint="$FP_SONGODOT docker:$(songo_dockerfile_hash windows)"
    songo_step "$name" "$fingerprint" "$(songo_component_dir "$name")/godot.windows.editor.x86_64.exe" -- _songodot_editor_windows
}
_songodot_editor_windows() {
    local work="$WORK_DIR/songodot-editor-windows"
    mkdir -p "$work"
    # No SCU build: it fails with MinGW (see Songodot's windows_profile.py)
    songo_docker windows -v "$SONGODOT_DIR:/src:ro" -v "$work:/work" -- \
        bash /devkit/lib/sync_build.sh /src /work songodot -- \
        scons platform=windows target=editor use_mingw=yes d3d12=no -j"$JOBS"
    _songo_collect "$work/src/bin" 'godot.windows.editor.x86_64.exe' songodot-editor-windows > /dev/null
    _songo_collect "$work/src/bin" 'godot.windows.editor.x86_64.console.exe' songodot-editor-windows > /dev/null
}

songodot_template_sbc() {
    local name=songodot-template-sbc
    local fingerprint="$FP_SONGODOT docker:$(songo_dockerfile_hash linux-arm64)"
    songo_step "$name" "$fingerprint" "$(songo_component_dir "$name")/godot.sbc.template_release.arm64.llvm" -- _songodot_template_sbc
}
_songodot_template_sbc() {
    local work="$WORK_DIR/songodot-sbc"
    mkdir -p "$work"
    songo_docker linux-arm64 -v "$SONGODOT_DIR:/src:ro" -v "$work:/work" -- \
        bash /devkit/lib/sync_build.sh /src /work songodot -- \
        scons profile=sbc_profile.py -j"$JOBS"
    _songo_collect "$work/src/bin" 'godot.sbc.template_release.arm64.llvm' songodot-template-sbc > /dev/null
}

songodot_template_windows() {
    local name=songodot-template-windows
    local fingerprint="$FP_SONGODOT docker:$(songo_dockerfile_hash windows)"
    songo_step "$name" "$fingerprint" "$(songo_component_dir "$name")/godot.windows.template_release.x86_64.exe" -- _songodot_template_windows
}
_songodot_template_windows() {
    local work="$WORK_DIR/songodot-windows-template"
    mkdir -p "$work"
    songo_docker windows -v "$SONGODOT_DIR:/src:ro" -v "$work:/work" -- \
        bash /devkit/lib/sync_build.sh /src /work songodot -- \
        scons profile=windows_profile.py -j"$JOBS"
    _songo_collect "$work/src/bin" 'godot.windows.template_release.x86_64.exe' songodot-template-windows > /dev/null
}

songodot_template_android() {
    local name=songodot-template-android
    local fingerprint="$FP_SONGODOT docker:$(songo_dockerfile_hash android)"
    songo_step "$name" "$fingerprint" "$(songo_component_dir "$name")/android_source.zip" -- _songodot_template_android
}
_songodot_template_android() {
    local work="$WORK_DIR/songodot-android"
    mkdir -p "$work"
    # Debug first, so the release build's Gradle step packs both into
    # android_source.zip
    songo_android_docker -v "$SONGODOT_DIR:/src:ro" -v "$work:/work" -- \
        bash -c 'bash /devkit/lib/sync_build.sh /src /work songodot -- scons profile=android_profile.py target=template_debug -j"$JOBS" \
            && cd /work/src && scons profile=android_profile.py -j"$JOBS"'
    local file
    for file in android_source.zip godot-lib.template_release.aar godot-lib.template_debug.aar; do
        _songo_collect "$work/src/bin" "$file" songodot-template-android > /dev/null
    done
}

# ---- SongoBGPlayer ----

bgplayer_linux_x86_64() {
    local name=bgplayer-linux-x86_64
    local fingerprint="$FP_SONGOBGPLAYER docker:$(songo_dockerfile_hash linux-x86_64)"
    local dest
    dest="$(songo_component_dir "$name")"
    songo_step "$name" "$fingerprint" "$dest/libsongo_engine.linux.x86_64.so" "$dest/songo_bgplayer.linux.x86_64" -- _bgplayer_linux_x86_64
}
_bgplayer_linux_x86_64() {
    local work="$WORK_DIR/bgplayer-linux-x86_64"
    mkdir -p "$work"
    songo_docker linux-x86_64 -v "$SONGOBGPLAYER_DIR:/src:ro" -v "$work:/work" -- \
        bash /devkit/lib/sync_build.sh /src /work bgplayer -- scripts/build_x86_64.sh
    _songo_collect "$work/src/bin" libsongo_engine.linux.x86_64.so bgplayer-linux-x86_64 > /dev/null
    _songo_collect "$work/src/bin" songo_bgplayer.linux.x86_64 bgplayer-linux-x86_64 > /dev/null
}

bgplayer_linux_arm64() {
    local name=bgplayer-linux-arm64
    local fingerprint="$FP_SONGOBGPLAYER docker:$(songo_dockerfile_hash linux-arm64)"
    local dest
    dest="$(songo_component_dir "$name")"
    songo_step "$name" "$fingerprint" "$dest/libsongo_engine.linux.arm64.so" "$dest/songo_bgplayer.linux.arm64" -- _bgplayer_linux_arm64
}
_bgplayer_linux_arm64() {
    local work="$WORK_DIR/bgplayer-linux-arm64"
    mkdir -p "$work"
    songo_docker linux-arm64 -e CROSS_PREFIX=aarch64-linux-gnu- -v "$SONGOBGPLAYER_DIR:/src:ro" -v "$work:/work" -- \
        bash /devkit/lib/sync_build.sh /src /work bgplayer -- scripts/build_arm64.sh
    _songo_collect "$work/src/bin" libsongo_engine.linux.arm64.so bgplayer-linux-arm64 > /dev/null
    _songo_collect "$work/src/bin" songo_bgplayer.linux.arm64 bgplayer-linux-arm64 > /dev/null
}

bgplayer_windows() {
    local name=bgplayer-windows
    local fingerprint="$FP_SONGOBGPLAYER docker:$(songo_dockerfile_hash windows)"
    songo_step "$name" "$fingerprint" "$(songo_component_dir "$name")/libsongo_engine.windows.x86_64.dll" -- _bgplayer_windows
}
_bgplayer_windows() {
    local work="$WORK_DIR/bgplayer-windows"
    mkdir -p "$work"
    songo_docker windows -v "$SONGOBGPLAYER_DIR:/src:ro" -v "$work:/work" -- \
        bash /devkit/lib/sync_build.sh /src /work bgplayer -- scripts/build_windows.sh
    _songo_collect "$work/src/bin" libsongo_engine.windows.x86_64.dll bgplayer-windows > /dev/null
}

bgplayer_android() {
    local name=bgplayer-android
    local fingerprint="$FP_SONGOBGPLAYER docker:$(songo_dockerfile_hash android)"
    local dest
    dest="$(songo_component_dir "$name")"
    songo_step "$name" "$fingerprint" "$dest/libsongo_engine.android.arm64.so" "$dest/songo_harness-release.aar" -- _bgplayer_android
}
_bgplayer_android() {
    local work="$WORK_DIR/bgplayer-android"
    mkdir -p "$work"
    songo_android_docker -v "$SONGOBGPLAYER_DIR:/src:ro" -v "$work:/work" -- \
        bash /devkit/lib/sync_build.sh /src /work bgplayer -- scripts/build_android.sh
    _songo_collect "$work/src/bin" libsongo_engine.android.arm64.so bgplayer-android > /dev/null
    _songo_collect "$work/src/android/plugin/build/outputs/aar" songo_harness-release.aar bgplayer-android > /dev/null
}
