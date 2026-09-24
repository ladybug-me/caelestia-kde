#!/usr/bin/env bash

submodule_has_content() {
    local dir="$1"
    [[ -d "$dir" ]] || return 1
    [[ -n "$(ls -A "$dir" 2>/dev/null)" ]]
}

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

submodule_url() {
    local dir="$1" path="$2" name

    name="$(submodule_name_for_path "$dir" "$path")" || return 0
    [[ -n "$name" ]] || return 0
    git -C "$dir" config --file .gitmodules --get "submodule.${name}.url" 2>/dev/null || true
}

# recorded_gitlink <dir> <path>
#
# The commit the superproject pins for the submodule at <path> - its gitlink -
# or nothing when the tree is not a git checkout that records one. Callers pass
# this to fetch_submodule_by_clone so the fallback lands on the pinned revision.
recorded_gitlink() {
    local dir="$1" path="$2" line mode type sha

    if ! line="$(git -C "$dir" ls-tree HEAD -- "$path" 2>/dev/null)" || [[ -z "$line" ]]; then
        return 1
    fi
    read -r mode type sha _ <<< "$line"
    [[ "$type" == "commit" && "$sha" =~ ^[0-9a-f]{40,64}$ ]] || return 1
    printf '%s\n' "$sha"
}

# fetch_submodule_by_clone <dir> <path> [recorded-sha]
#
# Last-resort fetch for a submodule that submodule update cannot provide: clone
# the URL .gitmodules records and copy the tree into place. When the recorded
# gitlink sha is given, the clone is checked out at exactly that revision - a
# clone that cannot reach it fails loudly instead of silently drifting the
# submodule to the default branch tip, which the tree never recorded. Without a
# sha (a tree with no git history has no pin to honor) the tip is used as
# before.
fetch_submodule_by_clone() {
    local dir="$1" path="$2" recorded="${3:-}" url tmp

    url="$(submodule_url "$dir" "$path")"
    [[ -n "$url" ]] || return 1
    command -v git >/dev/null 2>&1 || return 1

    tmp="$(mktemp -d "${TMPDIR:-/tmp}/caelestia-submodule.XXXXXX")" || return 1
    if ! git clone --quiet --depth 1 -- "$url" "$tmp" >/dev/null 2>&1; then
        rm -rf "$tmp"
        return 1
    fi

    if [[ -n "$recorded" ]]; then
        if ! git -C "$tmp" checkout --quiet "$recorded" >/dev/null 2>&1; then
            # A shallow clone only holds the tip; the pinned revision is
            # usually further back. Ask for it directly, then for the full
            # history, before giving up on the pin.
            git -C "$tmp" fetch --quiet origin "$recorded" >/dev/null 2>&1 || true
            if ! git -C "$tmp" checkout --quiet "$recorded" >/dev/null 2>&1; then
                git -C "$tmp" fetch --quiet --unshallow origin >/dev/null 2>&1 || true
                git -C "$tmp" checkout --quiet "$recorded" >/dev/null 2>&1 || {
                    echo "submodule $path: pinned revision $recorded is unavailable at $url" >&2
                    rm -rf "$tmp"
                    return 1
                }
            fi
        fi
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

ensure_submodule_content() {
    local dir="$1" path="$2"
    local recorded=""
    recorded="$(recorded_gitlink "$dir" "$path" || true)"

    submodule_has_content "$dir/$path" && return 0

    git -C "$dir" submodule update --init --recursive -- "$path" >/dev/null 2>&1 || true
    submodule_has_content "$dir/$path" && return 0

    git -C "$dir" submodule sync --recursive -- "$path" >/dev/null 2>&1 || true
    git -C "$dir" submodule update --init --recursive -- "$path" >/dev/null 2>&1 || true
    submodule_has_content "$dir/$path" && return 0

    git -C "$dir" submodule update --init --recursive --force -- "$path" >/dev/null 2>&1 || true
    submodule_has_content "$dir/$path" && return 0

    # stderr is left open: the clone fallback's refusal to drift past the
    # pinned revision is the one message worth surfacing from all of this.
    fetch_submodule_by_clone "$dir" "$path" "$recorded" >/dev/null || true
    submodule_has_content "$dir/$path"
}

prune_removed_submodules() {
    local dir="$1"

    while IFS= read -r -d '' key; do
        local submod="${key#submodule.}"
        submod="${submod%.url}"
        if ! git -C "$dir" config --file .gitmodules --get "submodule.${submod}.url" \
                >/dev/null 2>&1; then
            local wt_path
            wt_path=$(git -C "$dir" config --get "submodule.${submod}.path" 2>/dev/null \
                || echo "$submod")

            git -C "$dir" submodule deinit -f "$submod" >/dev/null 2>&1 || true

            git -C "$dir" config --remove-section "submodule.${submod}" \
                >/dev/null 2>&1 || true

            rm -rf "$dir/.git/modules/${submod}"

            rm -rf "${dir:?}/${wt_path:?}"
        fi
    done < <(git -C "$dir" config --name-only -z \
        --get-regexp '^submodule\..*\.url' 2>/dev/null || true)
}
