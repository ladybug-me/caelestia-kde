#!/usr/bin/env bash
# update-state.sh - Record which revision of the shell is actually installed.
#
#   record_installed_revision   Write .current_commit/.update_branch/.current_version
#
# Helpers never log; callers decide what to tell the user.

# record_installed_revision <bundle-dir> <config-dir>
#
# Record the revision the installed shell artifacts came from, so the Updates
# page and caelestia-check-updates describe what the user is actually running:
#
#   .current_commit   commit the artifacts were built from
#   .update_branch    branch that commit came from
#   .current_version  VERSION from that commit's .github/version.env
#
# Returns 1 without writing when there is nothing truthful to record:
#
#   - CAELESTIA_SKIP_BUILD=1 stopped the build, so the checkout moved but the
#     shell on screen did not. Recording the new revision would make every
#     version readout claim a state the user cannot see (#651).
#   - <bundle-dir> is not a git checkout, so there is no revision to name.
#
# The version comes from the working tree first and the commit second, because
# the updater's sparse checkout omits .github/version.env. It is recorded at all
# because the Updates page resolves unrecognized commits through a bare cache
# repo mirroring origin only: a local-only commit would show as "unknown".
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
