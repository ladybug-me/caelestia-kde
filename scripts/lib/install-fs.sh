#!/usr/bin/env bash
# install-fs.sh - filesystem helpers for the install/update step scripts.
#
#   atomic_replace_tree      Swap a directory for a new copy atomically
#   snapshot_dir             Timestamped copy of a directory, pruned to a limit
#   wait_for_nonempty_file   Block until a file the shell writes shows up
#
# Helpers never log; callers decide what to tell the user.

# atomic_replace_tree <src-dir> <dest-dir> [required-relative-path]
#
# Stages the copy beside <dest-dir> and validates it before swapping, so any
# failure leaves the existing destination untouched. A plain `rm -rf` first was
# the greeter bug: an interrupted copy deleted the live tree.
#
# Returns 0 on success, 1 on failure. On failure <dest-dir> is untouched.
atomic_replace_tree() {
    local src="$1" dest="$2" required="${3:-}"

    if [[ ! -d "$src" ]]; then
        return 1
    fi

    local parent base staging previous
    parent="$(dirname -- "$dest")"
    base="$(basename -- "$dest")"

    mkdir -p -- "$parent" || return 1

    # Stage beside the destination: the swap is then a same-filesystem rename.
    staging="$(mktemp -d -- "$parent/.$base.incoming.XXXXXX")" || return 1
    if ! cp -R -- "$src/." "$staging/"; then
        rm -rf -- "$staging"
        return 1
    fi

    if [[ -n "$required" && ! -e "$staging/$required" ]]; then
        rm -rf -- "$staging"
        return 1
    fi

    previous="$parent/.$base.previous.$$"
    rm -rf -- "$previous"

    local had_dest=0
    if [[ -e "$dest" ]]; then
        had_dest=1
        if ! mv -- "$dest" "$previous"; then
            rm -rf -- "$staging"
            return 1
        fi
    fi

    if ! mv -- "$staging" "$dest"; then
        rm -rf -- "$staging"
        if [[ "$had_dest" -eq 1 ]]; then
            mv -- "$previous" "$dest" || true
        fi
        return 1
    fi

    if [[ "$had_dest" -eq 1 ]]; then
        rm -rf -- "$previous"
    fi
    return 0
}

# snapshot_dir <src-dir> <dest-root> <name-prefix> <keep>
#
# Copy <src-dir> to <dest-root>/<name-prefix>-<timestamp> and prune older
# snapshots so at most <keep> remain. Echoes the snapshot path on success.
#
# Returns 1 without copying when <src-dir> does not exist - creating an empty
# snapshot would push a real one out of the retention window.
snapshot_dir() {
    local src="$1" root="$2" prefix="$3" keep="$4"

    [[ -d "$src" ]] || return 1
    mkdir -p -- "$root" || return 1

    # Same-second snapshots would collide and overwrite each other.
    local stamp dest counter
    stamp="$(date +%Y%m%d_%H%M%S)"
    dest="$root/$prefix-$stamp"
    counter=1
    while [[ -e "$dest" ]]; do
        counter=$((counter + 1))
        dest="$root/$prefix-$stamp-$(printf '%02d' "$counter")"
    done

    if ! cp -R -- "$src" "$dest"; then
        rm -rf -- "$dest"
        return 1
    fi

    # Zero-padded so names sort in creation order; the newest survive.
    local -a existing=()
    shopt -s nullglob
    existing=( "$root"/"$prefix"-* )
    shopt -u nullglob

    local total=${#existing[@]}
    local limit=$keep
    ((limit < 1)) && limit=1
    local index
    for ((index = 0; index < total - limit; index++)); do
        rm -rf -- "${existing[$index]}"
    done

    printf '%s\n' "$dest"
    return 0
}

# wait_for_nonempty_file <path> <timeout-seconds>
#
# Returns 0 as soon as <path> holds something, 1 once the timeout elapses.
# Emptiness counts as absent: a zero-byte file from an interrupted write would
# parse as empty, and a timeout of 0 makes the check once.
wait_for_nonempty_file() {
    local path="$1" timeout="$2" waited=0

    while :; do
        if [[ -s "$path" ]]; then
            return 0
        fi
        if (( waited >= timeout )); then
            return 1
        fi
        sleep 1
        waited=$((waited + 1))
    done
}
