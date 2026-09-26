#!/usr/bin/env bash
# Single contract for the shell update state files.
#
# ~/.config/quickshell/caelestia/.current_commit  the revision the running
#                                                 shell was built from
# ~/.config/quickshell/caelestia/.update_branch  the tracked update channel
#                                                 (main or dev only)
# ~/.config/quickshell/caelestia/.current_version  the version.env of that
#                                                   revision
#
# Writers: record_installed_revision() names what is actually installed and
# is the only writer of the commit and version files. The branch file has
# exactly two more writers, both user intent: an explicit branch pick in the
# Nexus updates page, and the timer's self-heal when the tracked branch
# disappears from the remote. Everything reads the branch and commit through
# the helpers below so all callers agree on validation and defaults.

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

    # A checkout parked on a feature branch must not silently re-point the
    # update channel (issue #565): only a real channel is a fact worth
    # recording, anything else leaves the previously tracked branch alone.
    local branch
    branch="$(git -C "$bundle" rev-parse --abbrev-ref HEAD 2>/dev/null)" || branch=""
    update_state_set_branch "$config" "$branch" || true

    if [[ -f "$bundle/.github/version.env" ]]; then
        cp -- "$bundle/.github/version.env" "$config/.current_version" 2>/dev/null || true
    else
        git -C "$bundle" show HEAD:.github/version.env > "$config/.current_version" 2>/dev/null || true
    fi

    return 0
}

# Persists the tracked update channel. Only main and dev are channels; the
# callers above and below depend on that, so reject anything else rather
# than writing a branch no reader will honor.
update_state_set_branch() {
    local config="$1" branch="$2"

    case "$branch" in
        main | dev) ;;
        *) return 1 ;;
    esac

    mkdir -p -- "$config" || return 1
    printf '%s\n' "$branch" > "$config/.update_branch" || return 1
    return 0
}

# Reads the tracked update channel, falling back to main the same way every
# consumer of .update_branch does.
update_state_read_branch() {
    local config="$1" branch=""
    branch="$(cat "$config/.update_branch" 2>/dev/null)" || branch=""
    case "$branch" in
        main | dev)
            printf '%s\n' "$branch"
            ;;
        *)
            printf 'main\n'
            ;;
    esac
}

# Reads the installed revision, empty when nothing was recorded yet.
update_state_read_commit() {
    local config="$1"
    cat "$config/.current_commit" 2>/dev/null || true
}
