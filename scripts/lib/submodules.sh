#!/usr/bin/env bash
# submodules.sh - Shared helpers for git submodule maintenance.

# submodule_has_content DIR
#
# True when the submodule working tree at DIR exists and is not empty. An
# initialised-but-unfetched submodule is an empty directory, and the installer
# must notice that before it deploys anything from it.
submodule_has_content() {
    local dir="$1"
    [[ -d "$dir" ]] || return 1
    [[ -n "$(ls -A "$dir" 2>/dev/null)" ]]
}

# submodule_name_for_path DIR PATH
#
# Print the name .gitmodules gives the submodule at PATH, e.g. `caelestia` for
# `src/dots`. Reads the file, not the repository, so it works in a checkout that
# is not a git repository at all.
submodule_name_for_path() {
    local dir="$1" path="$2" key name recorded

    while IFS= read -r key; do
        [[ -n "$key" ]] || continue
        name="${key#submodule.}"
        name="${name%.path}"
        recorded="$(git -C "$dir" config --file .gitmodules --get "submodule.${name}.path" 2>/dev/null || true)"
        if [[ "$recorded" == "$path" ]]; then
            printf '%s\n' "$name"
            return 0
        fi
    done < <(git -C "$dir" config --file .gitmodules --name-only \
        --get-regexp '^submodule\..*\.path$' 2>/dev/null || true)

    return 1
}

# submodule_url DIR PATH
#
# Print the URL .gitmodules records for the submodule at PATH, empty when there
# is none to find.
submodule_url() {
    local dir="$1" path="$2" name

    name="$(submodule_name_for_path "$dir" "$path")" || return 0
    [[ -n "$name" ]] || return 0
    git -C "$dir" config --file .gitmodules --get "submodule.${name}.url" 2>/dev/null || true
}

# fetch_submodule_by_clone DIR PATH
#
# Put the submodule at PATH in place by cloning its URL, for the cases
# git-submodule cannot handle: not a repository, never registered, or a
# registration git refuses. The URL comes from .gitmodules, the one file that
# survives all three. The clone's .git is stripped so the result is content in
# the parent working tree rather than a nested repository.
fetch_submodule_by_clone() {
    local dir="$1" path="$2" url tmp

    url="$(submodule_url "$dir" "$path")"
    [[ -n "$url" ]] || return 1
    command -v git >/dev/null 2>&1 || return 1

    tmp="$(mktemp -d "${TMPDIR:-/tmp}/caelestia-submodule.XXXXXX")" || return 1
    if ! git clone --quiet --depth 1 -- "$url" "$tmp" >/dev/null 2>&1; then
        rm -rf "$tmp"
        return 1
    fi

    rm -rf "${dir:?}/${path:?}"
    mkdir -p "${dir:?}/${path:?}"
    if ! cp -a "$tmp/." "$dir/$path/"; then
        rm -rf "$tmp"
        return 1
    fi

    rm -rf "$dir/$path/.git" "$tmp"
    return 0
}

# ensure_submodule_content DIR PATH
#
# Make sure the submodule at PATH has its content. Returns 1 when it is still
# missing, so the caller can decide whether that is fatal.
#
# Each attempt covers a state the previous one cannot: a fetch that never ran, a
# URL cached in .git/config that moved upstream, a checkout whose module cache is
# in the way (force), and finally a checkout where git-submodule is unusable.
ensure_submodule_content() {
    local dir="$1" path="$2"

    submodule_has_content "$dir/$path" && return 0

    git -C "$dir" submodule update --init --recursive -- "$path" >/dev/null 2>&1 || true
    submodule_has_content "$dir/$path" && return 0

    git -C "$dir" submodule sync --recursive -- "$path" >/dev/null 2>&1 || true
    git -C "$dir" submodule update --init --recursive -- "$path" >/dev/null 2>&1 || true
    submodule_has_content "$dir/$path" && return 0

    git -C "$dir" submodule update --init --recursive --force -- "$path" >/dev/null 2>&1 || true
    submodule_has_content "$dir/$path" && return 0

    fetch_submodule_by_clone "$dir" "$path" >/dev/null 2>&1 || true
    submodule_has_content "$dir/$path"
}

# prune_removed_submodules DIR
#
# Remove every submodule still registered in .git/config but no longer listed in
# .gitmodules, i.e. deleted upstream.
#
# deinit fails once the .gitmodules entry is gone, so it is allowed to fail and
# the real cleanup is done explicitly: the .git/config section, the module cache
# under .git/modules/<name>, and the worktree directory (deinit only empties it).
prune_removed_submodules() {
    local dir="$1"

    while IFS= read -r -d '' key; do
        local submod="${key#submodule.}"
        submod="${submod%.url}"
        if ! git -C "$dir" config --file .gitmodules --get "submodule.${submod}.url" \
                >/dev/null 2>&1; then
            # Resolve the worktree path before deinit forgets it.
            local wt_path
            wt_path=$(git -C "$dir" config --get "submodule.${submod}.path" 2>/dev/null \
                || echo "$submod")

            # May fail once .gitmodules forgets the path; the manual steps below
            # do the real work.
            git -C "$dir" submodule deinit -f "$submod" >/dev/null 2>&1 || true

            git -C "$dir" config --remove-section "submodule.${submod}" \
                >/dev/null 2>&1 || true

            rm -rf "$dir/.git/modules/${submod}"

            # deinit only empties the worktree, never deletes it.
            rm -rf "${dir:?}/${wt_path:?}"
        fi
    done < <(git -C "$dir" config --name-only -z \
        --get-regexp '^submodule\..*\.url' 2>/dev/null || true)
}
