#!/usr/bin/env bash
export PATH="$HOME/.local/bin:$PATH"
# update.sh - update the shell, then re-apply the configuration.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/scripts/lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/scripts/lib/privileges.sh"
source "$(dirname "${BASH_SOURCE[0]}")/scripts/lib/install-fs.sh"
source "$(dirname "${BASH_SOURCE[0]}")/scripts/lib/submodules.sh"

section() {
    local title="$1"
    echo
    echo "-------------------------------------------------------------"
    echo "  $title"
    echo "-------------------------------------------------------------"
}

export BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$BUNDLE_DIR" || die "Could not enter $BUNDLE_DIR"

# Prevent concurrent update runs from racing on git/CMake/config writes.
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/caelestia-update.lock"
flock -n 9 || { echo "Another Caelestia update is already running."; exit 1; }

section "Step 1 - Source Code Update"

info "Checking dependencies..."
for cmd in git cmake make; do
    if ! command -v "$cmd" &> /dev/null; then
        die "Required command '$cmd' is missing. Please install it first."
    fi
done

if [ -d "$BUNDLE_DIR/.git" ]; then
    info "Fetching remote branches..."
    git -C "$BUNDLE_DIR" fetch origin || warn "Failed to fetch from origin. Network issue?"

    STASHED=0
    # Safely stash uncommitted changes to avoid merge conflicts
    if ! git -C "$BUNDLE_DIR" diff-index --quiet HEAD --; then
        warn "You have uncommitted changes in the repository."
        info "Stashing your local changes..."
        git -C "$BUNDLE_DIR" stash -m "Auto-stash before Caelestia update" || die "Failed to stash changes."
        STASHED=1
    fi

    if [ -n "${1:-}" ]; then
        BRANCH="$1"
        if [[ "$BRANCH" != "main" && "$BRANCH" != "dev" ]]; then
            warn "Branch '$BRANCH' is not allowed. Falling back to main."
            BRANCH="main"
        fi
        info "Using provided branch: $BRANCH"
    else
        if [ -t 1 ]; then
            BRANCHES="main dev"
            echo
            info "Available remote branches (default: main):"
            select BRANCH in $BRANCHES; do
                if [ -z "$REPLY" ]; then
                    BRANCH="main"
                    info "Defaulted to branch: $BRANCH"
                    break
                elif [ -n "$BRANCH" ]; then
                    info "Selected branch: $BRANCH"
                    break
                else
                    warn "Invalid selection. Please enter a valid number or press Enter for main."
                fi
            done
        else
            BRANCH=$(git -C "$BUNDLE_DIR" rev-parse --abbrev-ref HEAD)
            if [ -z "$BRANCH" ] || [ "$BRANCH" == "HEAD" ]; then
                BRANCH="main"
            fi
            info "Auto-detected branch: $BRANCH (GUI Mode)"
        fi
    fi

    if [[ "$BRANCH" != "main" && "$BRANCH" != "dev" ]]; then
        warn "Branch '$BRANCH' is not allowed. Falling back to main."
        BRANCH="main"
    elif ! git -C "$BUNDLE_DIR" ls-remote --exit-code --heads origin "$BRANCH" >/dev/null 2>&1; then
        warn "Remote branch '$BRANCH' not found. Falling back to main."
        BRANCH="main"
    fi

    info "Checking out $BRANCH..."
    git -C "$BUNDLE_DIR" checkout "$BRANCH" || die "Failed to checkout $BRANCH"

    info "Pulling latest changes for $BRANCH..."
    git -C "$BUNDLE_DIR" pull origin "$BRANCH" || die "Failed to pull from origin/$BRANCH"

    if [[ -f "$BUNDLE_DIR/.gitmodules" ]]; then
        info "Syncing submodules..."
        prune_removed_submodules "$BUNDLE_DIR"
        git -C "$BUNDLE_DIR" submodule sync --recursive >/dev/null 2>&1 || true
        git -C "$BUNDLE_DIR" submodule update --init --recursive || \
            die "Failed to initialize submodules"
    fi

    if [ "$STASHED" -eq 1 ]; then
        echo
        warn "Your local uncommitted changes were backed up to the git stash to allow a clean update."
        warn "If you need to recover them, you can manually run 'git stash pop' later."
    fi
else
    warn "Not a git repository. Skipping source code update."
fi

section "Step 2 - Core Updates"

if [ ! -f "$BUNDLE_DIR/scripts/03-deploy-configs.sh" ] || [ ! -f "$BUNDLE_DIR/scripts/08-build-shell.sh" ]; then
    die "Critical internal scripts are missing from $BUNDLE_DIR/scripts/"
fi

# Restore the install-time menu choices (default shell, lockscreen plugin,
# fish config, ...) that setup.sh persisted to install.env. A fresh update
# process has none of these set, so the deploy/tweak scripts would otherwise
# fall back to hardcoded defaults and silently revert the user's explicit
# install-time decisions.
if [ -f "$HOME/.config/caelestia-kde/install.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$HOME/.config/caelestia-kde/install.env"
    set +a
fi

# Root credentials are no longer requested up front. Every step that can need
# them now checks first, so an update with nothing to install asks for nothing;
# the first step that does need root prompts once, and the helper keeps that
# credential warm for the rest of the run - including GUI launches with no
# terminal, through an askpass helper.
trap 'caelestia_stop_sudo_keepalive' EXIT

# Apply config updates and rebuild the shell UI.  The native C++ plugin
# backend talks directly to KWin/Wayland — no Python daemon or mock
# hyprctl binary is involved.
bash "$BUNDLE_DIR/scripts/03-deploy-configs.sh" || die "Config deployment failed."

info "Building the Caelestia shell UI..."
bash "$BUNDLE_DIR/scripts/08-build-shell.sh" || die "Shell build failed."

# Re-apply idempotent system tweaks (KDE settings, CLI patches, etc.)
# so they survive package upgrades that may have overwritten patches.
info "Re-applying system tweaks..."
bash "$BUNDLE_DIR/scripts/09-system-tweaks.sh" || warn "System tweaks step reported errors (non-fatal)."

caelestia_stop_sudo_keepalive

section "Update Completed Successfully"
echo
info "The core shell and bridge scripts have been updated."
info "System tweaks (OSD, desktops, CLI patches) have been re-applied to keep KDE in sync."
echo
echo "Restarting bridge and shell to apply changes..."

if command -v caelestia >/dev/null 2>&1; then
    CAELESTIA_BIN=$(command -v caelestia)
elif [[ -x "$HOME/.local/bin/caelestia" ]]; then
    CAELESTIA_BIN="$HOME/.local/bin/caelestia"
elif [[ -x "/usr/local/bin/caelestia" ]]; then
    CAELESTIA_BIN="/usr/local/bin/caelestia"
elif [[ -x "/usr/bin/caelestia" ]]; then
    CAELESTIA_BIN="/usr/bin/caelestia"
else
    CAELESTIA_BIN="caelestia"
fi

SHELL_IPC=""
if [[ -x "$HOME/.local/bin/caelestia-shell-ipc" ]]; then
    SHELL_IPC="$HOME/.local/bin/caelestia-shell-ipc"
fi

# Kill the running shell – try CLI first, then the IPC wrapper, then pkill.
if "$CAELESTIA_BIN" shell -k 2>/dev/null; then
    : # CLI succeeded
elif [[ -n "$SHELL_IPC" ]] && "$SHELL_IPC" quit 2>/dev/null; then
    : # IPC wrapper succeeded
else
    pkill -f "quickshell.*caelestia/shell.qml" 2>/dev/null || true
fi

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia"
SCHEME_FILE="$STATE_DIR/scheme.json"

# Start the shell. Prefer the shared wrapper so there is one definition of how
# the shell is restarted - it carries the issue #402 rationale for never using
# the CLI's `shell -d` (see shell/scripts/restart_shell.sh). It only knows how
# to talk to the KDE-managed autostart unit, so the start chain below stays as
# the fallback for a machine that does not have that unit.

QUICKSHELL_PATH="$(command -v quickshell 2>/dev/null || command -v qs 2>/dev/null || echo quickshell)"
RESTART_SCRIPT="$BUNDLE_DIR/shell/scripts/restart_shell.sh"

if [[ -x "$RESTART_SCRIPT" ]] && bash "$RESTART_SCRIPT" 2>/dev/null; then
    : # Restarted via the KDE-managed autostart unit — env identical to login startup
elif [[ -n "$SHELL_IPC" ]]; then
    "$SHELL_IPC" start 2>/dev/null &
elif command -v systemd-run >/dev/null 2>&1; then
    # Pass the same environment variables that caelestia-autostart.sh sets so
    # the shell starts in an identical state to a normal login.
    systemd-run --user --quiet --collect --unit=caelestia-shell \
        --description="Caelestia Shell" \
        --setenv=QML2_IMPORT_PATH="$HOME/.local/lib/qt6/qml:$HOME/.config/quickshell/caelestia" \
        --setenv=CAELESTIA_LIB_DIR="$HOME/.local/lib/caelestia" \
        --setenv=QS_NO_RELOAD_POPUP=1 \
        --setenv=QS_DROP_EXPENSIVE_FONTS=1 \
        --setenv=QS_DISABLE_CRASH_HANDLER=1 \
        --setenv=QSG_RENDER_LOOP=threaded \
        --setenv=QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000 \
        -- "$QUICKSHELL_PATH" -n -p "$HOME/.config/quickshell/caelestia/shell.qml" &
else
    # No systemd available — run directly; stdout stays on the terminal rather
    # than going to /dev/null, which is the safest option without a service manager.
    export QML2_IMPORT_PATH="$HOME/.local/lib/qt6/qml:$HOME/.config/quickshell/caelestia"
    export CAELESTIA_LIB_DIR="$HOME/.local/lib/caelestia"
    export QS_NO_RELOAD_POPUP=1
    export QS_DROP_EXPENSIVE_FONTS=1
    export QS_DISABLE_CRASH_HANDLER=1
    export QSG_RENDER_LOOP=threaded
    export QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
    stdbuf -oL -eL "$QUICKSHELL_PATH" -n -p "$HOME/.config/quickshell/caelestia/shell.qml" >/dev/null 2>&1 &
fi

# The lock screen reads scheme.json before any user session exists, so it has
# to be on disk for the greeter to render with the right colors. Wait for the
# shell that was just started to write it.
#
# This wait used to sit between the kill and the start, polling for a file to
# be produced by a process that had already been killed: it either returned
# instantly on the previous run's file, or spent the full 15s waiting for
# something that could not happen (#666). With the file normally already
# present the common case still returns immediately; the wait only bites on a
# fresh install or a wiped state directory, which is when it matters.
if ! wait_for_nonempty_file "$SCHEME_FILE" 15; then
    warn "The restarted shell has not written $SCHEME_FILE yet; the lock screen may fall back to its default colors."
fi

echo "Shell restarted successfully!"
echo
echo "If the shell doesn't start, restart it with the same wrapper the shell uses:"
echo "  bash \"\$HOME/.config/quickshell/caelestia/scripts/restart_shell.sh\""
echo "Check logs by running: $CAELESTIA_BIN shell -l"
