# Shared by songo.sh: config, logging, Docker, and skipping work that's
# already done. Sourced; expects SONGO_DEVKIT_DIR.

songo_log() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
songo_note() { printf '    %s\n' "$*"; }
songo_die() {
    printf '\033[31m!! %s\033[0m\n' "$*" >&2
    exit 1
}

# ---- Config ----

# The repo dir for a config value: the value if set (relative to the devkit),
# else the submodule in repos/
songo_repo_dir() { # <configured value> <submodule name> <file that must exist>
    local dir="${1:-repos/$2}"
    case "$dir" in /*) ;; *) dir="$SONGO_DEVKIT_DIR/$dir" ;; esac
    if [ ! -e "$dir/$3" ]; then
        if [ -z "$1" ]; then
            songo_die "$2 isn't checked out in repos/$2. Run: git submodule update --init --recursive"
        fi
        songo_die "$2 not found at $dir (from songo.conf): no $3 there"
    fi
    (cd "$dir" && pwd)
}

songo_load_config() {
    local conf="$SONGO_DEVKIT_DIR/songo.conf"
    if [ ! -f "$conf" ]; then
        cp "$SONGO_DEVKIT_DIR/songo.conf.example" "$conf"
        songo_note "Made songo.conf from songo.conf.example (builds from the submodules in repos/)"
    fi
    # shellcheck source=/dev/null
    source "$conf"
    SONGO5_DIR="$(songo_repo_dir "${SONGO5_DIR:-}" Songo-5 project.godot)"
    SONGODOT_DIR="$(songo_repo_dir "${SONGODOT_DIR:-}" Songodot modules/songo_player_harness/config.py)"
    SONGOBGPLAYER_DIR="$(songo_repo_dir "${SONGOBGPLAYER_DIR:-}" SongoBGPlayer engine/include/songo_engine.h)"
    CHAI_RETROFIT_DIR="$(songo_repo_dir "${CHAI_RETROFIT_DIR:-}" chai_retrofit chai_entry.sh)"
    [ -f "$SONGOBGPLAYER_DIR/third_party/ffmpeg/configure" ] \
        || songo_die "SongoBGPlayer's FFmpeg submodule is empty. Run: git -C '$SONGOBGPLAYER_DIR' submodule update --init --recursive"
    JOBS="${JOBS:-$(nproc)}"
    SONGODOT_LINUX_EDITOR_ARGS="${SONGODOT_LINUX_EDITOR_ARGS-use_llvm=yes}"
    OUT_DIR="$SONGO_DEVKIT_DIR/out"
    WORK_DIR="$SONGO_DEVKIT_DIR/.work"
    mkdir -p "$OUT_DIR" "$WORK_DIR/stamps"
}

# Runs a command in the android image, with Gradle's cache kept in .work/ (so
# only the first build downloads Gradle's dependencies)
songo_android_docker() { # [docker run arguments...] -- <command...>
    mkdir -p "$WORK_DIR/gradle"
    songo_docker android -e GRADLE_USER_HOME="$WORK_DIR/gradle" "$@"
}

# Sets ANDROID_DOCKER_KEYSTORE_ARGS: docker run arguments giving the Android
# export its keystores. The debug one is songo.conf's ANDROID_DEBUG_KEYSTORE
# (Godot's own by default, so APKs keep the signature earlier ones had), or
# one generated in .work/ when there's none. The release one, if set in
# songo.conf, goes in through GODOT_ANDROID_KEYSTORE_RELEASE_*.
songo_android_keystores() {
    ANDROID_DOCKER_KEYSTORE_ARGS=()
    local debug="${ANDROID_DEBUG_KEYSTORE:-}"
    if [ -z "$debug" ] || [ ! -f "$debug" ]; then
        debug="$WORK_DIR/android/debug.keystore"
        if [ ! -f "$debug" ]; then
            songo_note "No debug keystore at ${ANDROID_DEBUG_KEYSTORE:-(unset)}, generating one in .work/android"
            mkdir -p "$WORK_DIR/android"
            songo_docker android -- keytool -genkeypair -keystore "$debug" -storepass android \
                -alias androiddebugkey -keypass android -keyalg RSA -validity 10000 \
                -dname "CN=Android Debug,O=Android,C=US" > /dev/null
        fi
        ANDROID_DEBUG_KEYSTORE_USER=androiddebugkey
        ANDROID_DEBUG_KEYSTORE_PASSWORD=android
    fi
    ANDROID_DOCKER_KEYSTORE_ARGS+=(
        -v "$debug:$debug:ro"
        -e DEBUG_KEYSTORE="$debug"
        -e DEBUG_KEYSTORE_USER="${ANDROID_DEBUG_KEYSTORE_USER:-androiddebugkey}"
        -e DEBUG_KEYSTORE_PASS="${ANDROID_DEBUG_KEYSTORE_PASSWORD:-android}"
    )
    if [ -n "${ANDROID_RELEASE_KEYSTORE:-}" ]; then
        [ -f "$ANDROID_RELEASE_KEYSTORE" ] || songo_die "ANDROID_RELEASE_KEYSTORE in songo.conf doesn't exist: $ANDROID_RELEASE_KEYSTORE"
        ANDROID_DOCKER_KEYSTORE_ARGS+=(
            -v "$ANDROID_RELEASE_KEYSTORE:$ANDROID_RELEASE_KEYSTORE:ro"
            -e GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$ANDROID_RELEASE_KEYSTORE"
            -e GODOT_ANDROID_KEYSTORE_RELEASE_USER="${ANDROID_RELEASE_KEYSTORE_USER:-}"
            -e GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="${ANDROID_RELEASE_KEYSTORE_PASSWORD:-}"
        )
    fi
}

# ---- Docker ----

# Builds docker/<name> (cached by Docker, so quick when unchanged), prints its tag
songo_docker_image() {
    local tag="songodevkit-$1"
    docker build -q -t "$tag" "$SONGO_DEVKIT_DIR/docker/$1" > /dev/null \
        || songo_die "Couldn't build the $1 Docker image (docker/$1/Dockerfile)"
    echo "$tag"
}

songo_dockerfile_hash() {
    sha1sum "$SONGO_DEVKIT_DIR/docker/$1/Dockerfile" | cut -c1-12
}

# Runs a command in a devkit image as the calling user, with the devkit at
# /devkit (read-only) and at its own path, and out/ and .work/ writable at
# their own paths too, so host paths work unchanged inside.
songo_docker() { # <image> [docker run arguments...] -- <command...>
    local image="$1"
    shift
    local args=()
    while [ $# -gt 0 ] && [ "$1" != "--" ]; do
        args+=("$1")
        shift
    done
    shift
    local tag
    tag="$(songo_docker_image "$image")"
    local tty=()
    if [ -t 0 ] && [ -t 1 ]; then
        tty=(-t)
    fi
    docker run --rm "${tty[@]}" \
        --user "$(id -u):$(id -g)" \
        -e HOME=/tmp \
        -e JOBS="$JOBS" \
        -v "$SONGO_DEVKIT_DIR:/devkit:ro" \
        -v "$SONGO_DEVKIT_DIR:$SONGO_DEVKIT_DIR:ro" \
        -v "$OUT_DIR:$OUT_DIR" \
        -v "$WORK_DIR:$WORK_DIR" \
        "${args[@]}" \
        "$tag" "$@"
}

# ---- Only building what changed ----

# What a repo holds right now: its commit, uncommitted changes, untracked
# files, and the same for its submodules. Changes whenever the source does,
# and only then.
# Sets FP_SONGO5, FP_SONGODOT, FP_SONGOBGPLAYER and FP_CHAI_RETROFIT, once
# per command, for the steps to build their fingerprints from
songo_compute_fingerprints() {
    FP_SONGO5="$(_songo_repo_fingerprint "$SONGO5_DIR")"
    FP_SONGODOT="$(_songo_repo_fingerprint "$SONGODOT_DIR")"
    FP_SONGOBGPLAYER="$(_songo_repo_fingerprint "$SONGOBGPLAYER_DIR")"
    FP_CHAI_RETROFIT="$(_songo_repo_fingerprint "$CHAI_RETROFIT_DIR")"
}

_songo_repo_fingerprint() {
    local dir="$1"
    if ! git -C "$dir" rev-parse --git-dir > /dev/null 2>&1; then
        # Not a git checkout: no cheap way to tell, so it always counts as changed
        echo "unversioned-$(date +%s%N)"
        return
    fi
    {
        git -C "$dir" rev-parse HEAD
        git -C "$dir" diff HEAD --binary --no-ext-diff --ignore-submodules=all
        (cd "$dir" && git ls-files --others --exclude-standard -z | xargs -0 -r sha1sum)
        git -C "$dir" submodule status --recursive 2>/dev/null
        git -C "$dir" submodule foreach --quiet --recursive \
            'git diff HEAD --binary --no-ext-diff; git ls-files --others --exclude-standard -z | xargs -0 -r sha1sum' 2>/dev/null
    } | sha1sum | cut -c1-16
}

# Hash of every file in a devkit directory (eg: a build_platforms/ platform)
songo_dir_fingerprint() {
    (cd "$SONGO_DEVKIT_DIR/$1" && find . -type f -print0 | sort -z | xargs -0 sha1sum) | sha1sum | cut -c1-16
}

# A step's stamp: the fingerprint it was last built from, then an id for that
# build. Steps that use another's output put its whole stamp in their own
# fingerprint, so any rebuild of it (--force included, which can rebuild from
# an unchanged fingerprint) makes them rebuild too. "" if never built.
songo_stamp() {
    tr '\n' ' ' < "$WORK_DIR/stamps/$1" 2>/dev/null || true
}

# Runs <command> unless the step's outputs exist and were built from the same
# fingerprint. SONGO_FORCE=1 (--force) always runs it.
songo_step() { # <name> <fingerprint> <output...> -- <command...>
    local name="$1" fingerprint="$2"
    shift 2
    local outputs=()
    while [ $# -gt 0 ] && [ "$1" != "--" ]; do
        outputs+=("$1")
        shift
    done
    shift
    local stamp="$WORK_DIR/stamps/$name"
    if [ -z "${SONGO_FORCE:-}" ] && [ "$(head -n1 "$stamp" 2>/dev/null)" = "$fingerprint" ]; then
        local missing=0 output
        for output in "${outputs[@]}"; do
            [ -e "$output" ] || missing=1
        done
        if [ "$missing" = 0 ]; then
            songo_log "$name: up to date"
            return 0
        fi
    fi
    songo_log "$name: building"
    rm -f "$stamp"
    "$@"
    local output
    for output in "${outputs[@]}"; do
        [ -e "$output" ] || songo_die "$name didn't produce $output"
    done
    printf '%s\nbuild %s\n' "$fingerprint" "$(date +%s%N)" > "$stamp"
}
