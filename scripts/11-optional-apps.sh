#!/usr/bin/env bash
# editor integrations, Spicetify, Discord/Equibop, Todoist and Firefox theming.
# INSTALL_SPICETIFY, INSTALL_DISCORD, INSTALL_TODOIST, INSTALL_FIREFOX_THEME),

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"

BUNDLE_DIR="${BUNDLE_DIR:?BUNDLE_DIR not set}"
SRC_DIR="$BUNDLE_DIR/src"
DOTS_DIR="$SRC_DIR/dots"
EXTRA_DIR="$SRC_DIR/dots-extra"

echo
echo "  Optional Components"
echo ""

install_if_missing() {
    local pkg="$1"
    if [[ "$BASE_DISTRO" == "arch" ]]; then
        if pacman -Qi "$pkg" >/dev/null 2>&1; then
            skip "$pkg already installed."
            return 0
        fi
        info "Installing $pkg..."
        yay -S --needed ${CONFIRM_ARG:-} "$pkg" 2>/dev/null || \
        sudo pacman -S --needed ${CONFIRM_ARG:-} "$pkg" 2>/dev/null || {
            warn "Could not install $pkg, skipping."
            return 1
        }
        ok "$pkg installed."
    elif [[ "$BASE_DISTRO" == "fedora" ]]; then
        if dnf list --installed "$pkg" >/dev/null 2>&1; then
            skip "$pkg already installed."
            return 0
        fi
        info "Installing $pkg..."
        sudo dnf install -y "$pkg" 2>/dev/null || {
            warn "Could not install $pkg, skipping."
            return 1
        }
        ok "$pkg installed."
    elif [[ "$BASE_DISTRO" == "debian" ]]; then
        if dpkg -s "$pkg" >/dev/null 2>&1; then
            skip "$pkg already installed."
            return 0
        fi
        info "Installing $pkg..."
        sudo apt-get install -y "$pkg" 2>/dev/null || {
            warn "Could not install $pkg, skipping."
            return 1
        }
        ok "$pkg installed."
    fi
}

deploy_file() {
    local src="$1" dst="$2"
    if [[ -f "$src" ]]; then
        mkdir -p "$(dirname "$dst")"
        cp "$src" "$dst"
        echo "    Deployed: $dst"
    else
        echo "    [WARN] Missing optional file: $src"
    fi
}

if [[ "${INSTALL_VSCODE:-false}" == "true" ]]; then
    echo "  Setting up VSCode/VSCodium integration..."
    install_if_missing code || install_if_missing visual-studio-code-bin || true
    install_if_missing codium || install_if_missing vscodium-bin || true

    deploy_vscode() {
        local cfgdir="$1" bin="$2"
        if command -v "$bin" >/dev/null 2>&1; then
            deploy_file "$DOTS_DIR/vscode/settings.json" "$HOME/.config/$cfgdir/User/settings.json"
            deploy_file "$DOTS_DIR/vscode/keybindings.json" "$HOME/.config/$cfgdir/User/keybindings.json"
            local vsix="$DOTS_DIR/vscode/caelestia-vscode-integration/caelestia-vscode-integration-1.2.0.vsix"
            if [[ -f "$vsix" ]]; then
                "$bin" --install-extension "$vsix" >/dev/null 2>&1 || true
                echo "    Installed caelestia-vscode-integration into $bin"
            else
                echo "    [WARN] caelestia-vscode-integration .vsix not found"
            fi
        fi
    }
    deploy_vscode "Code" "code"
    deploy_vscode "VSCodium" "codium"
fi

if [[ "${INSTALL_ZED:-false}" == "true" ]]; then
    echo "  Setting up Zed..."
    if [[ "$BASE_DISTRO" == "arch" ]]; then
        install_if_missing zed || install_if_missing zed-editor || true
    else
        install_if_missing zed || true
    fi
    deploy_file "$DOTS_DIR/zed/keymap.json" "$HOME/.config/zed/keymap.json"
    deploy_file "$DOTS_DIR/zed/settings.json" "$HOME/.config/zed/settings.json"
fi

if [[ "${INSTALL_SPICETIFY:-false}" == "true" ]]; then
    echo "  Setting up Spicetify..."
    install_if_missing spicetify-cli || true

    theme_css="$EXTRA_DIR/spicetify/Themes/caelestia/user.css"
    [[ -f "$theme_css" ]] || theme_css="$DOTS_DIR/spicetify/Themes/caelestia/user.css"
    deploy_file "$theme_css" "$HOME/.config/spicetify/Themes/caelestia/user.css"

    if command -v spicetify >/dev/null 2>&1; then
        spicetify apply >/dev/null 2>&1 || warn "spicetify apply failed"
    else
        warn "spicetify not found; theme deployed but not applied"
    fi
fi

if [[ "${INSTALL_DISCORD:-false}" == "true" ]]; then
    echo "  Installing Discord/Equibop..."
    if [[ "$BASE_DISTRO" == "arch" ]]; then
        install_if_missing discord || install_if_missing equibop-bin || true
    else
        install_if_missing discord || true
    fi
fi

# Todoist (AppImage)
if [[ "${INSTALL_TODOIST:-false}" == "true" ]]; then
    echo "  Installing Todoist AppImage..."
    appimage="$HOME/.local/bin/todoist.AppImage"
    if [[ -x "$appimage" ]]; then
        skip "Todoist already installed."
    else
        mkdir -p "$HOME/.local/bin"
        echo "  Downloading Todoist AppImage..."
        if curl -L --fail -o "$appimage" "https://todoist.com/linux_app/appimage" 2>/dev/null; then
            chmod +x "$appimage"
            ok "Todoist installed to $appimage"
        else
            warn "Todoist download failed (network?). Skipping."
        fi
    fi
fi

if [[ "${INSTALL_FIREFOX_THEME:-false}" == "true" ]]; then
    echo "  Setting up Firefox theming..."
    install_if_missing firefox || true

    profiles_dir="$HOME/.mozilla/firefox"
    if [[ ! -d "$profiles_dir" ]]; then
        warn "No Firefox profile directory yet. Launch Firefox once, then re-run."
    else
        deployed=0
        for profile in "$profiles_dir"/*.default "$profiles_dir"/*.default-release "$profiles_dir"/*.default-esr; do
            [[ -d "$profile" ]] || continue
            deployed=1
            deploy_file "$DOTS_DIR/firefox/user.js" "$profile/user.js"
            deploy_file "$DOTS_DIR/firefox/userChrome.css" "$profile/chrome/userChrome.css"
        done
        if [[ "$deployed" -eq 0 ]]; then
            warn "No Firefox profile found. Launch Firefox once, then re-run."
        fi
    fi

fi

ok "Optional components done."
