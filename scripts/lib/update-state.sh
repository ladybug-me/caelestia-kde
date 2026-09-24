#!/usr/bin/env bash
# Shared installed-revision state for the two update mechanisms (#565).
#
# Two updaters deploy the shell: "tui" (the checkout-based path - install.sh,
# update.sh and the installer TUI run the step scripts from the user's checkout)
# and "cli" (src/bin/caelestia-update, which deploys from its own shadow clone
# at ~/.config/caelestia-update/repo). Both record into the same state
# directory; .update_source names the writer, .update_repo the checkout it
# deployed from. The other updater refuses to clobber state belonging to a
# still-live owner unless it is passed --takeover (see update_state_allow_takeover).

# Where the CLI updater keeps its shadow clone. Tests redirect this to sandbox
# the auto-detection of which mechanism is recording the state.
caelestia_shadow_repo_dir() {
    printf '%s\n' "${CAELESTIA_UPDATE_REPO_DIR:-$HOME/.config/caelestia-update/repo}"
}

# state_write_atomic <file> <content>
#
# Write one state file via mktemp + mv so a reader never sees a truncated
# value, and a failed write cannot leave a half-written file behind. The
# temporary file is removed on every failure path, so the state directory is
# never left littered with .tmp.* leftovers.
state_write_atomic() {
    local dest="$1" content="$2"
    local dir tmp
    dir="$(dirname -- "$dest")"
    tmp="$(mktemp "$dir/.tmp.XXXXXX")" || return 1

    if ! printf '%s\n' "$content" > "$tmp"; then
        rm -f -- "$tmp"
        return 1
    fi
    # mktemp creates 0600; the previous writers produced plain 0644 files that
    # kscreenlocker_greet and other same-user readers can read.
    chmod 644 -- "$tmp" 2>/dev/null || true
    if ! mv -f -- "$tmp" "$dest"; then
        rm -f -- "$tmp"
        return 1
    fi
    return 0
}

# record_installed_revision <bundle> <config> [source] [branch]
#
# Records the revision the shell was built from into <config>:
#   .current_commit  the deployed commit
#   .update_branch   the channel it came from (given, else the checked-out branch)
#   .current_version the checkout's .github/version.env
#   .update_source   "tui" or "cli" - which updater deployed it
#   .update_repo     the absolute path of the checkout it was deployed from
#
# <source> is auto-detected when omitted: recording from the CLI updater's
# shadow clone means "cli", anything else is the checkout-based "tui" path.
# An explicit <branch> is how src/bin/caelestia-update records the channel it
# fetched: its shadow clone sits on whatever branch "git init" picked, so its
# checked-out branch would name the wrong channel.
record_installed_revision() {
    local bundle="$1" config="$2" source="${3:-}" branch="${4:-}"

    if [[ "${CAELESTIA_SKIP_BUILD:-0}" == "1" ]]; then
        return 1
    fi

    if ! git -C "$bundle" rev-parse --git-dir >/dev/null 2>&1; then
        return 1
    fi

    local commit bundle_real
    commit="$(git -C "$bundle" rev-parse HEAD 2>/dev/null)" || return 1
    bundle_real="$(cd -- "$bundle" 2>/dev/null && pwd -P || true)"

    mkdir -p -- "$config" || return 1

    if [[ -z "$source" ]]; then
        local shadow shadow_real
        shadow="$(caelestia_shadow_repo_dir)"
        shadow_real="$(cd -- "$shadow" 2>/dev/null && pwd -P || true)"
        if [[ -n "$bundle_real" && -n "$shadow_real" && "$bundle_real" == "$shadow_real" ]]; then
            source="cli"
        else
            source="tui"
        fi
    fi

    if [[ -z "$branch" ]]; then
        branch="$(git -C "$bundle" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    fi

    state_write_atomic "$config/.current_commit" "$commit" || return 1
    state_write_atomic "$config/.update_source" "$source" || true
    state_write_atomic "$config/.update_repo" "$bundle_real" || true

    if [[ -n "$branch" ]]; then
        state_write_atomic "$config/.update_branch" "$branch" || true
    fi

    local version=""
    if [[ -f "$bundle/.github/version.env" ]]; then
        version="$(cat -- "$bundle/.github/version.env" 2>/dev/null || true)"
    else
        version="$(git -C "$bundle" show HEAD:.github/version.env 2>/dev/null || true)"
    fi
    if [[ -n "$version" ]]; then
        state_write_atomic "$config/.current_version" "$version" || true
    fi

    return 0
}

# update_state_owner_conflict <config> <me>
#
# Returns 0 when the state in <config> was written by a different updater
# whose checkout is still alive - the case where clobbering it would rewind
# .current_commit and make the checker mis-report the install (#565). A
# missing state, an unknown source, or an owner whose checkout is gone hands
# ownership over silently.
update_state_owner_conflict() {
    local config="$1" me="$2"
    local owner repo

    [[ -f "$config/.update_source" ]] || return 1
    owner="$(head -n1 -- "$config/.update_source" 2>/dev/null || true)"
    [[ "$owner" == "tui" || "$owner" == "cli" ]] || return 1
    [[ "$owner" != "$me" ]] || return 1

    repo="$(head -n1 -- "$config/.update_repo" 2>/dev/null || true)"
    if [[ -n "$repo" ]] && ! git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
        # The other owner's checkout is gone; nothing is left to defend.
        return 1
    fi
    return 0
}

# update_state_allow_takeover <config> <me> <takeover>
#
# The ownership gate both updaters call before deploying. Prints the refusal
# to stderr and returns 1 when <me> would clobber state owned by a still-live
# other updater and <takeover> is not "1"; returns 0 otherwise.
update_state_allow_takeover() {
    local config="$1" me="$2" takeover="${3:-0}"

    if [[ "$takeover" == "1" ]]; then
        return 0
    fi
    update_state_owner_conflict "$config" "$me" || return 0

    local owner repo
    owner="$(head -n1 -- "$config/.update_source" 2>/dev/null || true)"
    repo="$(head -n1 -- "$config/.update_repo" 2>/dev/null || true)"

    case "$me" in
        cli)
            echo "[FATAL] This install is managed by the checkout-based updater (update.sh / installer TUI)" >&2
            if [[ -n "$repo" ]]; then
                echo "         at $repo." >&2
                echo "         Run 'bash $repo/update.sh' there, or re-run with --takeover to let the CLI updater take over." >&2
            else
                echo "         whose checkout is not recorded. Re-run with --takeover to let the CLI updater take over." >&2
            fi
            ;;
        *)
            echo "[FATAL] This install is managed by the CLI updater (caelestia-update, the Nexus Updates page)." >&2
            echo "         Run 'caelestia-update' from a terminal (or use Nexus -> Updates), or re-run with" >&2
            echo "         --takeover to let update.sh take over." >&2
            ;;
    esac
    return 1
}
