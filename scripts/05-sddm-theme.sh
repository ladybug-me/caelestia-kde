#!/usr/bin/env bash
# 05-sddm-theme.sh  Install the Caelestia SDDM greeter theme.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/install-kind.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"
source "$(dirname "${BASH_SOURCE[0]}")/lib/privileges.sh"

BUNDLE_DIR="${BUNDLE_DIR:?BUNDLE_DIR not set}"
SRC_DIR="$BUNDLE_DIR/src/sddm"

if [[ "${INSTALL_SDDM:-true}" != "true" ]]; then
    skip "SDDM theme not selected."
    exit 0
fi

echo
echo ""
info "Installing Caelestia SDDM theme"
echo ""

THEME_NAME="caelestia"
INSTALL_DIR="/usr/share/sddm/themes/$THEME_NAME"
SYNC_SCRIPT="$INSTALL_DIR/scripts/sync.sh"

VARIANT="${SDDM_THEME_VARIANT:-full}"
case "$VARIANT" in
    full|mini) ;;
    *) die "Unknown SDDM theme variant: $VARIANT" ;;
esac

THEME_SOURCE="$SRC_DIR/themes/$VARIANT"
FONT_SOURCE="$BUNDLE_DIR/src/kde/shells/caelestia.desktop/contents/fonts/GoogleSansFlex.ttf"

# Where the theme's files come from. A checkout supplies them from src/sddm; a
# package already installed them under /usr/share/sddm, so all that is left here is
# what a package cannot do: pick the theme for this user and keep the greeter in
# step with the session.
if install_is_packaged; then
    THEME_SOURCE="$INSTALL_DIR"
    FONT_SOURCE="$INSTALL_DIR/assets/google-sans-flex/GoogleSansFlex.ttf"
    if [[ ! -f "$INSTALL_DIR/theme.conf" ]]; then
        die "The package's login screen theme is not installed at $INSTALL_DIR"
    fi
else
    if [[ ! -d "$THEME_SOURCE" ]]; then
        die "SDDM theme source not found at $THEME_SOURCE"
    fi
fi

ALL_OK=true

# Places the sync helper, the posthook that calls it, and the sudoers rule that
# lets the hook run it. Shared by both display managers: the helper decides what to
# do from the machine it runs on, not from where it was installed.
register_greeter_sync() {
    local label="${1:-Login screen configured.}"

    POSTHOOK_CMD="sudo $SYNC_SCRIPT --posthook"
    CLI_JSON="$HOME/.config/caelestia/cli.json"

    if command -v python3 &>/dev/null; then
        python3 - "$CLI_JSON" "$POSTHOOK_CMD" <<'PYEOF'
import json, os, re, sys

cli_path, hook_cmd = sys.argv[1], sys.argv[2]

config = {}
if os.path.exists(cli_path):
    with open(cli_path) as f:
        config = json.load(f)

# Assign rather than append: any posthook of ours comes out first, then the
# current one goes in once, so re-running does not stack copies and a path left by
# the other display manager's install does not survive. A hook the user wrote is
# kept in front of ours; every other key is untouched.
#
# Only the two helpers this installer owns are recognised, the pair
# uninstall.sh recognises too: matching any `--posthook` command would delete a
# posthook the user wrote for a tool of their own.
HELPERS = r"sudo\s+\S*(?:sync\.sh|caelestia-greeter-sync)\s+--posthook"
ours = re.compile(
    r"\s*&&\s*" + HELPERS
    + r"|" + HELPERS + r"\s*&&\s*"
    + r"|" + HELPERS
)

for section in ("wallpaper", "theme"):
    config.setdefault(section, {})
    existing = config[section].get("postHook", "")
    if isinstance(existing, str):
        cleaned = ours.sub("", existing).strip()
        config[section]["postHook"] = f"{cleaned} && {hook_cmd}" if cleaned else hook_cmd

os.makedirs(os.path.dirname(cli_path), exist_ok=True)
with open(cli_path, "w") as f:
    json.dump(config, f, indent=4)
    f.write("\n")
PYEOF
        ok "Posthook registered in cli.json"
    else
        warn "python3 not found, skipping posthook registration. Wallpaper and color changes will not auto-sync to the login screen."
        ALL_OK=false
    fi

    SUDOERS_FILE="/etc/sudoers.d/caelestia-sddm-sync"
    # Rewritten every run, not only when missing: an install that moved between
    # display managers or helper paths would otherwise leave a drop-in naming the
    # old path, and the login screen is somewhere sudo cannot prompt.
    echo "$USER ALL=(root) NOPASSWD: $SYNC_SCRIPT" | caelestia_sudo tee "$SUDOERS_FILE" >/dev/null
    caelestia_sudo chmod 440 "$SUDOERS_FILE"
    ok "Sudoers drop-in written for $SYNC_SCRIPT."

    if [[ "$ALL_OK" == "true" ]]; then
        ok "$label"
    else
        warn "Login screen installed with warnings. Review the output above."
    fi
}

# Plasma Login is a fork of SDDM but reads no SDDM themes at all: a theme package
# would sit unused under /usr/share/sddm, which is what a login screen ignoring the
# theme looks like. Its wallpaper comes from /etc/plasmalogin.conf and the rest of
# its look from the plasmalogin user's Plasma config - the same thing KDE's Login
# Screen settings writes - and the sync helper keeps the two in step afterwards.
DISPLAY_MANAGER="sddm"
if command -v plasmalogin >/dev/null 2>&1 || [[ -e /etc/plasmalogin.conf ]]; then
    DISPLAY_MANAGER="plasmalogin"
fi

if [[ "$DISPLAY_MANAGER" == "plasmalogin" ]]; then
    if install_is_packaged; then
        # Ships with the theme at the same path a checkout's install uses, so both
        # display managers run one file and neither writes into /usr/local behind
        # the package manager's back.
        SYNC_SCRIPT="$INSTALL_DIR/scripts/sync.sh"
        if [[ ! -x "$SYNC_SCRIPT" ]]; then
            die "The package's login screen helper is not installed at $SYNC_SCRIPT"
        fi
    else
        SYNC_SCRIPT="/usr/local/bin/caelestia-greeter-sync"

        caelestia_sudo install -d -m 0755 /usr/local/bin
        caelestia_sudo install -m 0755 "$SRC_DIR/sync.sh" "$SYNC_SCRIPT"
        ok "Login screen sync helper installed to $SYNC_SCRIPT"
    fi

    # The helper's work is identical on both display managers, so it configures
    # here rather than this script writing the same keys twice.
    if sync_output="$(caelestia_sudo "$SYNC_SCRIPT" 2>&1)"; then
        ok "Initial login screen sync complete."
    else
        warn "Initial login screen sync had warnings (non-fatal):"
        if [[ -n "$sync_output" ]]; then
            printf '%s\n' "$sync_output" | sed -e 's/\[WARN\]/warning:/g' -e 's/\[ERR\]/error:/g' -e 's/^/  /'
        fi
        ALL_OK=false
    fi

    register_greeter_sync "Login screen configured for Plasma Login."
    exit 0
fi

if install_is_packaged; then
    skip "The display manager's dependencies belong to the package."
elif [[ "${BASE_DISTRO:-}" == "arch" ]]; then
    SDDM_DEPS=(sddm qt6-declarative qt6-5compat qt6-svg qt6-multimedia)
    MISSING=()
    for pkg in "${SDDM_DEPS[@]}"; do
        if ! pacman -Qq "$pkg" &>/dev/null; then
            MISSING+=("$pkg")
        fi
    done
    if [[ ${#MISSING[@]} -gt 0 ]]; then
        info "Installing SDDM dependencies: ${MISSING[*]}"
        caelestia_sudo pacman -S --noconfirm "${MISSING[@]}"
    fi
    ok "Dependencies met."
elif [[ "${BASE_DISTRO:-}" == "fedora" ]]; then
    SDDM_DEPS=(sddm qt6-qtdeclarative qt6-qt5compat qt6-qtsvg qt6-qtmultimedia)
    MISSING=()
    for pkg in "${SDDM_DEPS[@]}"; do
        if ! rpm -q "$pkg" &>/dev/null; then
            MISSING+=("$pkg")
        fi
    done
    if [[ ${#MISSING[@]} -gt 0 ]]; then
        info "Installing SDDM dependencies: ${MISSING[*]}"
        caelestia_sudo dnf install -y "${MISSING[@]}"
    fi
    ok "Dependencies met."
elif [[ "${BASE_DISTRO:-}" == "debian" ]]; then
    SDDM_DEPS=(sddm qml6-module-qtquick qt6-5compat-dev libqt6svg6 qt6-multimedia-dev)
    MISSING=()
    for pkg in "${SDDM_DEPS[@]}"; do
        if ! dpkg -s "$pkg" &>/dev/null 2>&1; then
            MISSING+=("$pkg")
        fi
    done
    if [[ ${#MISSING[@]} -gt 0 ]]; then
        info "Installing SDDM dependencies: ${MISSING[*]}"
        caelestia_sudo apt-get install -y "${MISSING[@]}"
    fi
    ok "Dependencies met."
else
    warn "Unsupported distribution ($BASE_DISTRO). SDDM Qt6 dependencies must be installed manually."
    ALL_OK=false
fi

# Copies the checkout's theme into place and nothing else: a package owns its copy
# of these files, and rewriting them would be undone by the next upgrade anyway.
install_theme_files() {
    if [[ -d "$INSTALL_DIR" ]]; then
        caelestia_sudo rm -rf "$INSTALL_DIR"
    fi

    caelestia_sudo mkdir -p "$INSTALL_DIR/scripts"
    caelestia_sudo cp -r "$THEME_SOURCE"/* "$INSTALL_DIR/"
    caelestia_sudo cp "$SRC_DIR/sync.sh" "$INSTALL_DIR/scripts/"

    caelestia_sudo mkdir -p "$INSTALL_DIR/assets/google-sans-flex"
    if [[ -f "$FONT_SOURCE" ]]; then
        caelestia_sudo cp "$FONT_SOURCE" "$INSTALL_DIR/assets/google-sans-flex/GoogleSansFlex.ttf"
    else
        warn "GoogleSansFlex.ttf not found at $FONT_SOURCE, theme text may not render correctly."
        ALL_OK=false
    fi

    # mini reuses full's shape components (coupled by design, keep in sync)
    if [[ "$VARIANT" == "mini" ]]; then
        if [[ -d "$SRC_DIR/themes/full/components/shapes" ]]; then
            caelestia_sudo mkdir -p "$INSTALL_DIR/components/shapes"
            caelestia_sudo cp -r "$SRC_DIR/themes/full/components/shapes"/* "$INSTALL_DIR/components/shapes/"
        else
            warn "Shape components not found at $SRC_DIR/themes/full/components/shapes, mini theme will not render correctly."
            ALL_OK=false
        fi
    fi

    caelestia_sudo find "$INSTALL_DIR" -type d -exec chmod 755 {} +
    caelestia_sudo find "$INSTALL_DIR" -type f -exec chmod 644 {} +
    caelestia_sudo chmod 755 "$SYNC_SCRIPT"
    ok "Theme files installed to $INSTALL_DIR ($VARIANT variant)"
}

if install_is_packaged; then
    skip "The theme files belong to the package."
else
    install_theme_files
fi

# A theme without theme.conf is not a theme to SDDM: it silently falls back to the
# distribution default, which is indistinguishable from the install never running.
for required in theme.conf metadata.desktop Main.qml; do
    if [[ ! -e "/usr/share/sddm/themes/$THEME_NAME/$required" ]]; then
        warn "$INSTALL_DIR/$required is missing: SDDM will ignore this theme and show the default."
        ALL_OK=false
    fi
done

mkdir -p "$HOME/.config/caelestia/templates"
if [[ -f "$THEME_SOURCE/theme.conf.template" ]]; then
    cp "$THEME_SOURCE/theme.conf.template" "$HOME/.config/caelestia/templates/sddm-theme.conf"
    ok "Template config created."
fi

# Choosing the theme is two writes into /etc, which a package owns: it ships the
# drop-in that sorts last, and the theme is already selected. A checkout writes them.
if install_is_packaged; then
    skip "The theme selection belongs to the package."
else
caelestia_sudo mkdir -p /etc/sddm.conf.d
# Named to sort last on purpose: SDDM reads /etc/sddm.conf.d/*.conf alphabetically
# and the last assignment of a key wins, while distributions and sddm-kcm ship
# drop-ins that set [Theme] Current themselves (kde_settings.conf, for one). A file
# named after this project loses to all of them, which looks exactly like no theme
# being installed: a stock Breeze login screen with no trace of the deployed theme.
cat <<'DROPIN' | caelestia_sudo tee /etc/sddm.conf.d/zz-caelestia.conf >/dev/null
[General]
GreeterEnvironment=QML_XHR_ALLOW_FILE_READ=1

[Theme]
Current=caelestia
DROPIN
caelestia_sudo rm -f /etc/sddm.conf.d/caelestia.conf
ok "SDDM config drop-in created."

# The drop-in is one of two places the theme can be picked. /etc/sddm.conf is the
# other, and a `Current=` sitting there - which is where KDE's own Login Screen
# settings module writes, and where a distribution may ship one - is read after the
# drop-in directory by some SDDM versions and before it by others. Setting the key
# in both places means which one wins stops mattering.
#
# Keep whatever was there first: it is the user's selection, not ours to lose, and
# uninstall.sh puts it back. Copied once, so a second install does not record our own
# value as the user's.
SDDM_CONF_BACKUP="${XDG_STATE_HOME:-$HOME/.local/state}/caelestia/sddm.conf.theme-current"
if command -v kwriteconfig6 >/dev/null 2>&1; then
    # Only when the value can be read back. Without kreadconfig6 a backup saying
    # "nothing was here" would make uninstall delete a selection it could not see;
    # uninstall's fallback removes the key only while it still names this theme.
    if [[ ! -f "$SDDM_CONF_BACKUP" ]] && command -v kreadconfig6 >/dev/null 2>&1; then
        mkdir -p "$(dirname -- "$SDDM_CONF_BACKUP")"
        PREVIOUS_CURRENT="$(kreadconfig6 --file /etc/sddm.conf --group Theme --key Current 2>/dev/null || true)"
        # `#none` is a value SDDM cannot be given, so it can stand for "nothing to put back".
        printf '%s\n' "${PREVIOUS_CURRENT:-#none}" > "$SDDM_CONF_BACKUP"
    fi
    caelestia_sudo kwriteconfig6 --file /etc/sddm.conf --group Theme --key Current "$THEME_NAME" 2>/dev/null \
        && ok "Theme selected in /etc/sddm.conf as well." \
        || warn "Could not write to /etc/sddm.conf; the drop-in is the only selection."
fi
fi

# Every file SDDM reads that picks a theme, ours included, so a conflict is visible
# rather than guessed at. Ours is meant to win.
for conf in /usr/lib/sddm/sddm.conf.d/*.conf /etc/sddm.conf /etc/sddm.conf.d/*.conf; do
    [[ -f "$conf" ]] || continue
    CURRENT_LINE="$(grep -E '^[[:space:]]*Current[[:space:]]*=' "$conf" 2>/dev/null | tail -n 1 || true)"
    [[ -n "$CURRENT_LINE" ]] || continue
    info "${conf}: ${CURRENT_LINE// /}"
done

register_greeter_sync "SDDM theme installed."
