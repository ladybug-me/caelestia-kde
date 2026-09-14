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
