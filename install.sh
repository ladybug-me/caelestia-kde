#!/bin/sh
# install.sh - bootstrap installer: clone or update the repo, then hand off to
# scripts/setup.sh, the single entry point for everything else.
#
#   curl -fsSL https://raw.githubusercontent.com/ladybug-me/caelestia-kde/main/install.sh | sh
#
# Environment:
#   CAELESTIA_REPO    repository URL (default: ladybug-me/caelestia-kde)
#   CAELESTIA_BRANCH  branch to install (default: main)
#   CAELESTIA_DIR     target directory (default: ~/caelestia-kde)

set -eu

{
# When piped (e.g. `curl ... | sh` or `cat install.sh | sh`), stdin is
# a pipe — not a TTY.  Re-open /dev/tty as stdin so that the interactive
# TUI installer can read keyboard input.
# This mirrors the approach used by rustup, Homebrew, and similar installers.
if [ ! -t 0 ]; then
    # Find the real pseudo-terminal (e.g. /dev/pts/0).
    REAL_TTY=""
    if [ -t 1 ]; then
        REAL_TTY=$(tty 0>&1 2>/dev/null || true)
    elif [ -t 2 ]; then
        REAL_TTY=$(tty 0>&2 2>/dev/null || true)
    fi

    # Fallback to ps if tty command didn't work (e.g. wrapper shell hiding fds)
    if [ -z "$REAL_TTY" ] || [ "$REAL_TTY" = "not a tty" ]; then
        _CTTY=$(ps -p $$ -o tty= 2>/dev/null | awk '{print $1}' || true)
        if [ -n "$_CTTY" ] && [ "$_CTTY" != "?" ]; then
            case "$_CTTY" in
                /*) REAL_TTY="$_CTTY" ;;
                *)  REAL_TTY="/dev/$_CTTY" ;;
            esac
        fi
    fi

    if [ -n "$REAL_TTY" ] && [ "$REAL_TTY" != "not a tty" ] && [ -c "$REAL_TTY" ]; then
        # Re-open all standard file descriptors to the real terminal
        exec 0<>"$REAL_TTY" 1<>"$REAL_TTY" 2<>"$REAL_TTY"
    elif [ -c /dev/tty ]; then
        # If we couldn't resolve the true pseudo-terminal path, fallback to
        # /dev/tty. The C++ TUI runs directly on /dev/tty without tmux.
        exec 0<>/dev/tty
    else
        echo "  [ERR]   stdin is not a terminal and no TTY is available." >&2
        echo "  [INFO]  Please run the installer directly: bash install.sh" >&2
        exit 1
    fi
fi

REPO="${CAELESTIA_REPO:-https://github.com/ladybug-me/caelestia-kde.git}"
BRANCH="${CAELESTIA_BRANCH:-main}"
DEST="${CAELESTIA_DIR:-$HOME/caelestia-kde}"

if ! command -v git >/dev/null 2>&1; then
    # Marker spacing must match scripts/lib/log.sh, which install.sh cannot
    # source because it has to stay POSIX sh for `curl | sh` bootstrapping.
    echo "  [ERR]   git is required but not installed." >&2
    exit 1
fi

# If run from an existing checkout (e.g. `sh install.sh` inside the repo),
# reuse it instead of cloning a fresh copy.
if [ -f "./scripts/setup.sh" ]; then
    if [ ! -t 0 ] && [ -c /dev/tty ]; then
        exec bash "$(pwd)/scripts/setup.sh" </dev/tty
    fi
    exec bash "$(pwd)/scripts/setup.sh"
fi

if [ -d "$DEST/.git" ]; then
    echo "  [INFO]  Updating existing checkout at $DEST"
    git -C "$DEST" pull --ff-only --recurse-submodules
elif [ -e "$DEST" ]; then
    echo "  [ERR]   $DEST already exists and is not a git checkout; aborting." >&2
    exit 1
else
    echo "  [INFO]  Cloning $REPO ($BRANCH) into $DEST"
    git clone -b "$BRANCH" --single-branch --depth 1 --recurse-submodules "$REPO" "$DEST"
fi

if [ ! -t 0 ] && [ -c /dev/tty ]; then
    exec bash "$DEST/scripts/setup.sh" </dev/tty
fi
exec bash "$DEST/scripts/setup.sh"
}
