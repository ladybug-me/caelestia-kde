#!/usr/bin/env bash
set -euo pipefail

copy_user_file() {
    local src="$1"
    local dest="$2"
    local max_bytes="$3"

    local dest_dir base read_tmp dest_tmp actual_size
    dest_dir="$(dirname -- "$dest")"
    base="$(basename -- "$dest")"

    install -d -o root -g root -m 0755 "$dest_dir"

    read_tmp="$(mktemp)"
    dest_tmp="$(mktemp "$dest_dir/.${base}.tmp.XXXXXX")"

    fail_cleanup() {
        rm -f -- "$read_tmp" "$dest_tmp"
        return 1
    }

    if ! sudo -H -u "$REAL_USER" test -f "$src" || \
        ! sudo -H -u "$REAL_USER" test -r "$src"; then
        fail_cleanup
        return
    fi

    if ! sudo -H -u "$REAL_USER" head -c "$((max_bytes + 1))" -- "$src" | cat > "$read_tmp"; then
        fail_cleanup
        return
    fi

    actual_size="$(stat -c '%s' "$read_tmp")"

    if [[ "$actual_size" -gt "$max_bytes" ]]; then
        echo "WARNING: Skipping oversized file: $src" >&2
        fail_cleanup
        return
    fi

    if ! install -o root -g root -m 0644 "$read_tmp" "$dest_tmp"; then
        fail_cleanup
        return
    fi

    if ! mv -f -- "$dest_tmp" "$dest"; then
        fail_cleanup
        return
    fi

    rm -f -- "$read_tmp"
    return 0
}

if [[ -n "${SUDO_USER:-}" ]]; then
    REAL_USER="$SUDO_USER"
else
    echo "ERROR: Cannot determine target user. Try running with sudo." >&2
    exit 1
fi

REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)
if [[ -z "$REAL_HOME" ]] || [[ "$REAL_HOME" = "/" ]]; then
    echo "ERROR: Could not determine a valid home directory for $REAL_USER." >&2
    exit 1
fi

CAEL_STATE="$REAL_HOME/.local/state/caelestia"

CAELESTIA_BIN=""
for candidate in "$REAL_HOME/.local/bin/caelestia" /usr/local/bin/caelestia /usr/bin/caelestia; do
    if [[ -x "$candidate" ]]; then
        CAELESTIA_BIN="$candidate"
        break
    fi
done
if [[ -z "$CAELESTIA_BIN" ]]; then
    CAELESTIA_BIN="$(command -v caelestia 2>/dev/null || true)"
fi

wallpaper_on_screen() {
    local target
    target="$(sudo -H -u "$REAL_USER" readlink -f "$CAEL_STATE/wallpaper/current" 2>/dev/null || true)"
    [[ -n "$target" ]] && sudo -H -u "$REAL_USER" test -f "$target"
}

FAILED=0
if [[ "${1:-}" = "--posthook" ]]; then
    : # Skip color generation when run as posthook (--posthook)
    echo "✓ Running as posthook, skipping color generation"
elif [[ -z "$CAELESTIA_BIN" ]]; then
    echo "Caelestia CLI not found, skipping color generation"
else
    mapfile -t SCHEME < <(sudo -H -u "$REAL_USER" "$CAELESTIA_BIN" scheme get --name --mode --variant 2>/dev/null)
    NAME="${SCHEME[0]:-}"
    MODE="${SCHEME[1]:-}"
    VARIANT="${SCHEME[2]:-}"
    if [[ -z "$NAME" || -z "$MODE" || -z "$VARIANT" ]]; then
        echo "Could not read Caelestia scheme, skipping color generation"
    elif [[ "$NAME" == "dynamic" ]] && ! wallpaper_on_screen; then
        echo "No wallpaper on screen yet, skipping color generation"
    elif regenerate="$(sudo -H -u "$REAL_USER" "$CAELESTIA_BIN" scheme set --name "$NAME" --mode "$MODE" --variant "$VARIANT" 2>&1)"; then
        echo "✓ Generated colors for scheme: $NAME/$MODE/$VARIANT"
    else
        echo "Could not regenerate the colors for $NAME/$MODE/$VARIANT:" >&2
        printf '%s\n' "$regenerate" | sed 's/^/  /' >&2
        FAILED=1
    fi
fi

is_plasmalogin_active() {
    local target
    target="$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || true)"

    case "$target" in
        *plasmalogin*) return 0 ;;
        *sddm*) return 1 ;;
    esac

    if systemctl is-active plasmalogin.service &>/dev/null || \
       systemctl is-enabled plasmalogin.service &>/dev/null; then
        return 0
    fi
    if systemctl is-active sddm.service &>/dev/null || \
       systemctl is-enabled sddm.service &>/dev/null; then
        return 1
    fi
    if [[ -e /etc/plasmalogin.conf ]] && ! command -v sddm >/dev/null 2>&1; then
        return 0
    fi
    return 1
}

if is_plasmalogin_active; then
    PLASMALOGIN_HOME="$(getent passwd plasmalogin | cut -d: -f6)"
    if [[ -z "$PLASMALOGIN_HOME" || "$PLASMALOGIN_HOME" = "/" ]]; then
        PLASMALOGIN_HOME="/var/lib/plasmalogin"
    fi

    PLASMALOGIN_CONFIG="$PLASMALOGIN_HOME/.config"
    PLASMALOGIN_SCHEMES="$PLASMALOGIN_HOME/.local/share/color-schemes"
    PLASMALOGIN_WALLPAPERS="$PLASMALOGIN_HOME/wallpapers/caelestia"
    MAX_LOGIN_SCHEME_BYTES=$((1024 * 1024))
    MAX_LOGIN_WALLPAPER_BYTES=$((50 * 1024 * 1024))

    install -d -o root -g root -m 0755 "$PLASMALOGIN_CONFIG" "$PLASMALOGIN_SCHEMES" "$PLASMALOGIN_WALLPAPERS"

    for scheme in "$REAL_HOME"/.local/share/color-schemes/Matugen*.colors; do
        [[ -e "$scheme" ]] || continue
        copy_user_file "$scheme" "$PLASMALOGIN_SCHEMES/$(basename -- "$scheme")" "$MAX_LOGIN_SCHEME_BYTES" || true
    done

    for file in kdeglobals plasmarc kxkbrc kcminputrc plasma-localerc; do
        copy_user_file "$REAL_HOME/.config/$file" "$PLASMALOGIN_CONFIG/$file" "$((1024 * 1024))" || true
    done

    WALLPAPER_SOURCE="$(sudo -H -u "$REAL_USER" readlink -f "$CAEL_STATE/wallpaper/current" 2>/dev/null || true)"
    if [[ -n "$WALLPAPER_SOURCE" && -f "$WALLPAPER_SOURCE" ]]; then
        WALLPAPER_NAME="$(basename -- "$WALLPAPER_SOURCE")"
        if copy_user_file "$WALLPAPER_SOURCE" "$PLASMALOGIN_WALLPAPERS/$WALLPAPER_NAME" "$MAX_LOGIN_WALLPAPER_BYTES"; then
            for old in "$PLASMALOGIN_WALLPAPERS"/*; do
                [[ "$old" == "$PLASMALOGIN_WALLPAPERS/$WALLPAPER_NAME" ]] || rm -f -- "$old"
            done

            if command -v kwriteconfig6 >/dev/null 2>&1 \
                && kwriteconfig6 --file /etc/plasmalogin.conf --group Greeter --key WallpaperPluginId "org.kde.image" \
                && kwriteconfig6 --file /etc/plasmalogin.conf --group Greeter --group Wallpaper --group org.kde.image --group General --key Image "file://$PLASMALOGIN_WALLPAPERS/$WALLPAPER_NAME"; then
                echo "✓ Synced the login screen wallpaper"
            else
                echo "WARNING: could not write /etc/plasmalogin.conf, the wallpaper is where the greeter expects but is not selected" >&2
            fi
        else
            echo "No readable wallpaper found, leaving the login screen wallpaper unchanged."
        fi
    else
        echo "No readable wallpaper found, leaving the login screen wallpaper unchanged."
    fi

    chown -R plasmalogin:plasmalogin "$PLASMALOGIN_CONFIG" "$PLASMALOGIN_SCHEMES" "$PLASMALOGIN_WALLPAPERS" 2>/dev/null || true

    exit "$FAILED"
fi

echo "No Plasma Login on this machine: its login screen takes nothing from Caelestia."
exit 0
