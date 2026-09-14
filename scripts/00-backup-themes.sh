#!/usr/bin/env bash

set -euo pipefail

BUNDLE_DIR="${BUNDLE_DIR:?BUNDLE_DIR not set}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde"
BACKUP_DIR_FILE="$CACHE_DIR/backup-dir.txt"
PROFILE_NAME="caelestia-preinstall"
USER_KONSAVE_CONF="$HOME/.config/konsave/conf.yaml"
USER_KONSAVE_CONF_BACKUP="$CACHE_DIR/konsave-conf.yaml.backup"
KONSAVE_VENV_DIR="$CACHE_DIR/konsave-venv"
KONSAVE_BIN=""
HAD_USER_KONSAVE_CONF=false

source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"

ensure_konsave() {
    if command -v konsave >/dev/null 2>&1; then
        KONSAVE_BIN="$(command -v konsave)"
        return 0
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        die "python3 is required to install konsave."
    fi

    info "Installing konsave for KDE profile backups..."
    if [[ ! -x "$KONSAVE_VENV_DIR/bin/konsave" ]]; then
        python3 -m venv "$KONSAVE_VENV_DIR" >/dev/null 2>&1 ||
            die "Failed to create a local virtual environment for konsave."
        "$KONSAVE_VENV_DIR/bin/python" -m pip install --upgrade pip >/dev/null 2>&1 || true
        "$KONSAVE_VENV_DIR/bin/python" -m pip install --upgrade konsave >/dev/null 2>&1 ||
            die "Failed to install konsave."
    fi

    KONSAVE_BIN="$KONSAVE_VENV_DIR/bin/konsave"

    [[ -x "$KONSAVE_BIN" ]] || die "konsave is still unavailable after installation."
}

restore_user_konsave_conf() {
    if [[ -f "$USER_KONSAVE_CONF_BACKUP" ]]; then
        mkdir -p "$(dirname "$USER_KONSAVE_CONF")"
        cp "$USER_KONSAVE_CONF_BACKUP" "$USER_KONSAVE_CONF"
        return 0
    fi

    if [[ "$HAD_USER_KONSAVE_CONF" != "true" ]]; then
        rm -f "$USER_KONSAVE_CONF"
    fi
}

if [[ -f "$USER_KONSAVE_CONF" ]]; then
    HAD_USER_KONSAVE_CONF=true
fi

trap restore_user_konsave_conf EXIT
info "Backing up current KDE configuration with konsave..."

mkdir -p "$CACHE_DIR"
BACKUP_DIR="$BUNDLE_DIR/backups/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"
printf '%s\n' "$BACKUP_DIR" > "$BACKUP_DIR_FILE"

if command -v kreadconfig6 >/dev/null 2>&1; then
    prev_lnf="$(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage 2>/dev/null || true)"
    if [[ -n "$prev_lnf" ]]; then
        printf '%s\n' "$prev_lnf" > "$BACKUP_DIR/previous_lookandfeel.txt"
    fi
fi

ensure_konsave

if [[ -f "$USER_KONSAVE_CONF" ]]; then
    cp "$USER_KONSAVE_CONF" "$USER_KONSAVE_CONF_BACKUP"
    HAD_USER_KONSAVE_CONF=true
fi

mkdir -p "$(dirname "$USER_KONSAVE_CONF")"
cat > "$USER_KONSAVE_CONF" <<'EOF'
---
save:
    caelestia-preinstall:
        location: "$CONFIG_DIR"
        entries:
            - plasmarc
            - kdeglobals
            - kwinrc
            - kcminputrc
            - plasmanotifyrc
            - powerdevilrc
            - kglobalshortcutsrc
            - kmixrc
            - ksplashrc
            - plasma-org.kde.plasma.desktop-appletsrc
            - konsolerc
export:
    caelestia-preinstall:
        location: "$SHARE_DIR"
        entries:
            - konsole
...
EOF

"$KONSAVE_BIN" -r "$PROFILE_NAME" -f >/dev/null 2>&1 || true

info "Saving konsave profile '$PROFILE_NAME'..."
"$KONSAVE_BIN" -s "$PROFILE_NAME" -f >/dev/null 2>&1 || die "Failed to save the current KDE profile."

info "Exporting konsave profile to $BACKUP_DIR..."
"$KONSAVE_BIN" -e "$PROFILE_NAME" -d "$BACKUP_DIR" -n "$PROFILE_NAME" -f >/dev/null 2>&1 ||
    die "Failed to export the KDE profile backup."

archive_path="$(find "$BACKUP_DIR" -maxdepth 1 -type f -name '*.knsv' | head -n 1)"
if [[ -z "$archive_path" ]]; then
    die "konsave completed but no .knsv archive was produced."
fi

ok "KDE settings backed up to $(basename "$archive_path")"
