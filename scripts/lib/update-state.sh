#!/usr/bin/env bash

record_installed_revision() {
    local bundle="$1" config="$2"

    if [[ "${CAELESTIA_SKIP_BUILD:-0}" == "1" ]]; then
        return 1
    fi

    if [[ ! -d "$bundle/.git" ]]; then
        return 1
    fi

    mkdir -p -- "$config" || return 1

    git -C "$bundle" rev-parse HEAD > "$config/.current_commit" 2>/dev/null || {
        rm -f -- "$config/.current_commit"
        return 1
    }
    git -C "$bundle" rev-parse --abbrev-ref HEAD > "$config/.update_branch" 2>/dev/null || true

    if [[ -f "$bundle/.github/version.env" ]]; then
        cp -- "$bundle/.github/version.env" "$config/.current_version" 2>/dev/null || true
    else
        git -C "$bundle" show HEAD:.github/version.env > "$config/.current_version" 2>/dev/null || true
    fi

    return 0
}
