#!/usr/bin/env bash
# SongoDevKit: builds Songo's releases and editors from Songo-5, Songodot,
# SongoBGPlayer and chai_retrofit (the submodules in repos/, or local
# checkouts set in songo.conf), with every toolchain it needs. Each piece is
# only rebuilt when its own repo changed.
#
# Run it:
#   ./songo.sh songo_build_release windows
# or source it, for the commands in your shell:
#   source songo.sh
#   songo_build_release windows
#
# Commands:
#   songo_build_release <windows|linux_x86|portmaster|spruce|android>  -> out/release/
#   songo_build_editor <linux_x86|windows>             -> out/editor/
#   songo_update                                       pull every repo to its latest pushed version
#   songo_status                                       what's configured and built
#   songo_clean [--all]                                drop build stamps (--all: caches too)
#   songo_help
#
# --force on any build rebuilds everything it needs, changed or not.

SONGO_DEVKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Runs a command in a subshell with the devkit loaded, so a failed build never
# takes down the shell that sourced this
_songo_run() { # <function> [arguments...]
    (
        set -euo pipefail
        # shellcheck source=lib/common.sh
        source "$SONGO_DEVKIT_DIR/lib/common.sh"
        # shellcheck source=lib/components.sh
        source "$SONGO_DEVKIT_DIR/lib/components.sh"
        # shellcheck source=lib/release.sh
        source "$SONGO_DEVKIT_DIR/lib/release.sh"
        local fn="$1"
        shift
        local args=()
        local arg
        for arg in "$@"; do
            if [ "$arg" = "--force" ]; then
                export SONGO_FORCE=1
            else
                args+=("$arg")
            fi
        done
        # songo_update makes its own way through the config: it's what fixes
        # repos that aren't checked out yet, which songo_load_config refuses
        [ "$fn" = _songo_update ] || songo_load_config
        "$fn" "${args[@]+"${args[@]}"}"
    )
}

_songo_build_release() {
    local started=$SECONDS
    songo_compute_fingerprints
    case "${1:-}" in
        windows) songo_release_windows ;;
        linux_x86) songo_release_linux_x86 ;;
        portmaster) songo_release_portmaster ;;
        spruce) songo_release_spruce ;;
        android) songo_release_android ;;
        *) songo_die "Usage: songo_build_release <windows|linux_x86|portmaster|spruce|android> [--force]" ;;
    esac
    songo_log "Done in $((SECONDS - started))s: $(ls -d "$OUT_DIR/release/$1"/* | head -n1)"
}

_songo_build_editor() {
    local started=$SECONDS
    songo_compute_fingerprints
    case "${1:-}" in
        linux_x86) songo_editor_linux_x86 ;;
        windows) songo_editor_windows ;;
        *) songo_die "Usage: songo_build_editor <linux_x86|windows> [--force]" ;;
    esac
    songo_log "Done in $((SECONDS - started))s"
}

# Brings every repo up to date with GitHub:
# - the submodules in repos/ move to the latest commit on their default branch
#   (merged, so commits made in one aren't dropped), and SongoBGPlayer's own
#   submodules (FFmpeg, mbedtls) to the commits SongoBGPlayer pins. The new
#   versions show as changes in the devkit, for you to commit.
# - each local checkout songo.conf points at is pulled (fast-forward only),
#   with its submodules updated to match. A checkout that can't be, such as
#   one on a detached HEAD or with diverged commits, is left as it is.
_songo_update() {
    local devkit="$SONGO_DEVKIT_DIR" failed=()
    [ -f "$devkit/songo.conf" ] || cp "$devkit/songo.conf.example" "$devkit/songo.conf"
    # shellcheck source=/dev/null
    source "$devkit/songo.conf"

    songo_log "Updating the submodules in repos/"
    local before after
    before="$(git -C "$devkit" submodule status)"
    if git -C "$devkit" submodule update --init --remote --merge \
        && git -C "$devkit" submodule foreach --quiet 'git submodule update --init --recursive'; then
        after="$(git -C "$devkit" submodule status)"
        _songo_update_report "$before" "$after"
    else
        failed+=("repos/ submodules")
    fi

    local entry var sub dir branch old
    for entry in SONGO5_DIR:Songo-5 SONGODOT_DIR:Songodot SONGOBGPLAYER_DIR:SongoBGPlayer CHAI_RETROFIT_DIR:chai_retrofit; do
        var="${entry%%:*}"
        sub="${entry#*:}"
        dir="${!var:-}"
        [ -n "$dir" ] || continue
        case "$dir" in /*) ;; *) dir="$devkit/$dir" ;; esac
        # songo.conf pointing at the submodule itself: done above
        [ "$(cd "$dir" 2> /dev/null && pwd -P)" = "$(cd "$devkit/repos/$sub" 2> /dev/null && pwd -P)" ] && continue
        songo_log "Pulling $sub ($dir, from songo.conf)"
        if ! git -C "$dir" rev-parse --git-dir > /dev/null 2>&1; then
            songo_note "not a git checkout, skipped"
            failed+=("$sub")
            continue
        fi
        branch="$(git -C "$dir" symbolic-ref --quiet --short HEAD || true)"
        if [ -z "$branch" ]; then
            songo_note "on a detached HEAD, skipped: check out a branch to pull it"
            failed+=("$sub")
            continue
        fi
        old="$(git -C "$dir" rev-parse --short HEAD)"
        if git -C "$dir" pull --ff-only --quiet && git -C "$dir" submodule update --init --recursive --quiet; then
            if [ "$old" = "$(git -C "$dir" rev-parse --short HEAD)" ]; then
                songo_note "$branch: already up to date ($old)"
            else
                songo_note "$branch: $old -> $(git -C "$dir" log -1 --format='%h %s' | cut -c1-70)"
            fi
            [ -z "$(git -C "$dir" status --porcelain --ignore-submodules=dirty)" ] \
                || songo_note "(it has uncommitted changes, which were kept)"
        else
            songo_note "couldn't pull $branch, left as it was (see above)"
            failed+=("$sub")
        fi
    done

    # Submodules now on a different commit than the devkit records
    if [ -n "$(git -C "$devkit" diff --name-only -- repos)" ]; then
        songo_log "New submodule versions to record in the devkit"
        git -C "$devkit" diff --name-only -- repos | sed 's/^/    /'
        songo_note "To record them: git add repos && git commit -m \"Update repos\""
    fi
    if [ ${#failed[@]} -gt 0 ]; then
        songo_die "Not updated: ${failed[*]}"
    fi
}

# Prints each submodule whose commit changed between two `git submodule status`
_songo_update_report() { # <before> <after>
    local line path sha old
    while read -r line; do
        sha="$(awk '{print $1}' <<< "$line" | tr -d 'U+-')"
        path="$(awk '{print $2}' <<< "$line")"
        old="$(awk -v p="$path" '$2 == p {print $1}' <<< "$1" | tr -d 'U+-')"
        if [ "$old" = "$sha" ]; then
            songo_note "$path: already up to date (${sha:0:7})"
        else
            songo_note "$path: ${old:0:7} -> $(git -C "$SONGO_DEVKIT_DIR/$path" log -1 --format='%h %s' | cut -c1-70)"
        fi
    done <<< "$2"
}

_songo_status() {
    songo_log "Repos"
    local name dir
    for name in SONGO5_DIR SONGODOT_DIR SONGOBGPLAYER_DIR CHAI_RETROFIT_DIR; do
        dir="${!name}"
        printf '    %-18s %s\n' "$name" "$dir"
        if git -C "$dir" rev-parse --git-dir > /dev/null 2>&1; then
            printf '    %-18s %s%s\n' "" "$(git -C "$dir" log -1 --format='%h %s' | cut -c1-70)" \
                "$([ -n "$(git -C "$dir" status --porcelain)" ] && echo "  (uncommitted changes)")"
        fi
    done
    songo_log "Built"
    local stamp
    for stamp in "$WORK_DIR"/stamps/*; do
        [ -e "$stamp" ] || { songo_note "nothing yet"; break; }
        printf '    %-28s %s\n' "$(basename "$stamp")" "$(date -r "$stamp" '+%Y-%m-%d %H:%M')"
    done
    songo_log "Outputs"
    find "$OUT_DIR/release" "$OUT_DIR/editor" -maxdepth 2 -type f 2>/dev/null | sed "s|$SONGO_DEVKIT_DIR/|    |" || true
}

_songo_clean() {
    rm -rf "$WORK_DIR/stamps"
    songo_note "Removed the build stamps: the next build of anything runs its build again (incrementally)"
    if [ "${1:-}" = "--all" ]; then
        rm -rf "$WORK_DIR" "$OUT_DIR"
        songo_note "Removed .work/ (work copies, caches) and out/: the next builds start from scratch"
    fi
}

_songo_help() {
    sed -n '2,/^$/{s/^# \{0,1\}//;p}' "$SONGO_DEVKIT_DIR/songo.sh"
}

songo_build_release() { _songo_run _songo_build_release "$@"; }
songo_build_editor() { _songo_run _songo_build_editor "$@"; }
songo_update() { _songo_run _songo_update "$@"; }
songo_status() { _songo_run _songo_status "$@"; }
songo_clean() { _songo_run _songo_clean "$@"; }
songo_help() { _songo_help; }

# Run directly: ./songo.sh <command> [arguments...]
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    command="${1:-songo_help}"
    shift || true
    case "$command" in
        songo_build_release | songo_build_editor | songo_update | songo_status | songo_clean | songo_help) "$command" "$@" ;;
        # Without the prefix too: ./songo.sh build_release windows
        build_release | build_editor | update | status | clean | help) "songo_$command" "$@" ;;
        *)
            echo "Unknown command: $command" >&2
            songo_help
            exit 1
            ;;
    esac
fi
