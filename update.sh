#!/usr/bin/env bash
export PATH="$HOME/.local/bin:$PATH"

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/scripts/lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/scripts/lib/privileges.sh"
source "$(dirname "${BASH_SOURCE[0]}")/scripts/lib/install-fs.sh"
source "$(dirname "${BASH_SOURCE[0]}")/scripts/lib/submodules.sh"
source "$(dirname "${BASH_SOURCE[0]}")/scripts/lib/update-state.sh"

# Fork identity (#565 support): the owner of the git repositories cloned/pulled
# for source and updates, and the owner publishing release artifacts. Upstream
# defaults stay ladybug-me; a fork sets both to its own GitHub user.
: "${CAELESTIA_REPO_OWNER:=ladybug-me}"
: "${CAELESTIA_PREBUILT_OWNER:=ladybug-me}"

usage() {
    cat << 'EOF'
Usage: bash update.sh [--takeover] [main|dev]

Updates the shell from this checkout and rebuilds/deploys it.

Branch selection, in order:
  1. the branch given on the command line (main or dev)
  2. the channel recorded by the last update (~/.config/quickshell/caelestia/.update_branch)
  3. "main" - the documented default both update paths share

--takeover   Re-own the update state even if the CLI updater
             (caelestia-update, the Nexus Updates page) owns it. Without this
             flag update.sh refuses to clobber state that names a still-live
             CLI install, because the two mechanisms pull from different
             checkouts and would otherwise rewind each other (issue #565).

Forks: this script pulls from this checkout's own "origin" remote. The
CAELESTIA_REPO_OWNER and CAELESTIA_PREBUILT_OWNER environment variables
(default ladybug-me) name the GitHub owners used for fresh clones and
prebuilt release artifacts respectively; see README.md, "For forks".
EOF
}

TAKEOVER=0
BRANCH_ARG=""
for arg in "$@"; do
    case "$arg" in
        --takeover)
            TAKEOVER=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            if [[ -z "$BRANCH_ARG" ]]; then
                BRANCH_ARG="$arg"
            else
                die "Unexpected argument: $arg (see --help)"
            fi
            ;;
    esac
done

section() {
    local title="$1"
    echo
    echo "-------------------------------------------------------------"
    echo "  $title"
    echo "-------------------------------------------------------------"
}

export BUNDLE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$BUNDLE_DIR" || die "Could not enter $BUNDLE_DIR"

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
    if ! git -C "$BUNDLE_DIR" diff-index --quiet HEAD --; then
        warn "You have uncommitted changes in the repository."
        info "Stashing your local changes..."
        git -C "$BUNDLE_DIR" stash -m "Auto-stash before Caelestia update" || die "Failed to stash changes."
        STASHED=1
    fi

    if [ -n "$BRANCH_ARG" ]; then
        BRANCH="$BRANCH_ARG"
        if [[ "$BRANCH" != "main" && "$BRANCH" != "dev" ]]; then
            warn "Branch '$BRANCH' is not allowed. Falling back to main."
            BRANCH="main"
        fi
        info "Using provided branch: $BRANCH"
    elif [ -n "$(cat "$HOME/.config/quickshell/caelestia/.update_branch" 2>/dev/null || true)" ]; then
        # The channel the last update recorded, whatever mechanism wrote it:
        # both update paths honor it so they cannot disagree on the default.
        BRANCH="$(cat "$HOME/.config/quickshell/caelestia/.update_branch" 2>/dev/null)"
        info "Using the recorded update channel: $BRANCH"
    elif [ -t 1 ]; then
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

if [ -f "$HOME/.config/caelestia-kde/install.env" ]; then
    set -a
    # shellcheck disable=SC1091
    . "$HOME/.config/caelestia-kde/install.env"
    set +a
fi

trap 'caelestia_stop_sudo_keepalive' EXIT

# Ownership guard (#565): the CLI updater (caelestia-update / Nexus) deploys
# from its own shadow clone while this script deploys from this checkout. If
# its state is still live, rewriting it here would rewind the recorded
# revision; refuse instead unless --takeover was passed.
if ! update_state_allow_takeover "$HOME/.config/quickshell/caelestia" "tui" "$TAKEOVER"; then
    exit 1
fi

# Snapshot the deployed tree before this update overwrites it, so a bad
# deploy can be rolled back by hand. Kept next to the install, newest three
# retained - the build step takes its own snapshot as well, but only after
# the config deploy below has already mutated parts of the tree.
backup_deployed_tree() {
    local src="$HOME/.config/quickshell/caelestia"
    local root dest

    if [[ ! -d "$src" ]]; then
        return 0
    fi
    root="$(dirname -- "$src")/caelestia-backups"
    if ! dest="$(snapshot_dir "$src" "$root" "update" 3)"; then
        die "Could not back up the deployed tree into $root; refusing to update without a backup."
    fi
    info "Backed up the deployed tree to $dest"
}

backup_deployed_tree

bash "$BUNDLE_DIR/scripts/03-deploy-configs.sh" || die "Config deployment failed."

info "Building the Caelestia shell UI..."
bash "$BUNDLE_DIR/scripts/08-build-shell.sh" || die "Shell build failed."

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

if "$CAELESTIA_BIN" shell -k 2>/dev/null; then
    : # CLI succeeded
elif [[ -n "$SHELL_IPC" ]] && "$SHELL_IPC" quit 2>/dev/null; then
    : # IPC wrapper succeeded
else
    pkill -f "quickshell.*caelestia/shell.qml" 2>/dev/null || true
fi

STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia"
SCHEME_FILE="$STATE_DIR/scheme.json"

QUICKSHELL_PATH="$(command -v quickshell 2>/dev/null || command -v qs 2>/dev/null || echo quickshell)"
RESTART_SCRIPT="$BUNDLE_DIR/shell/scripts/restart_shell.sh"

if [[ -x "$RESTART_SCRIPT" ]] && bash "$RESTART_SCRIPT" 2>/dev/null; then
    : # Restarted via the KDE-managed autostart unit — env identical to login startup
elif [[ -n "$SHELL_IPC" ]]; then
    "$SHELL_IPC" start 2>/dev/null &
elif command -v systemd-run >/dev/null 2>&1; then
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
    export QML2_IMPORT_PATH="$HOME/.local/lib/qt6/qml:$HOME/.config/quickshell/caelestia"
    export CAELESTIA_LIB_DIR="$HOME/.local/lib/caelestia"
    export QS_NO_RELOAD_POPUP=1
    export QS_DROP_EXPENSIVE_FONTS=1
    export QS_DISABLE_CRASH_HANDLER=1
    export QSG_RENDER_LOOP=threaded
    export QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
    stdbuf -oL -eL "$QUICKSHELL_PATH" -n -p "$HOME/.config/quickshell/caelestia/shell.qml" >/dev/null 2>&1 &
fi

if ! wait_for_nonempty_file "$SCHEME_FILE" 15; then
    warn "The restarted shell has not written $SCHEME_FILE yet; the lock screen may fall back to its default colors."
fi

echo "Shell restarted successfully!"
echo
echo "If the shell doesn't start, restart it with the same wrapper the shell uses:"
echo "  bash \"\$HOME/.config/quickshell/caelestia/scripts/restart_shell.sh\""
echo "Check logs by running: $CAELESTIA_BIN shell -l"
