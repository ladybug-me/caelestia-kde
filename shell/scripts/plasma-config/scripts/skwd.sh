#!/usr/bin/env bash
# skwd Wallpaper & Configuration Helper

apply_skwd_wallpaper() {
    if [[ -z "${CAELESTIA_TEST_MODE:-}" && "$USER_CONFIG_DIR" != "/tmp/"* ]] && command -v skwd-helm >/dev/null 2>&1; then
        local curr_wall
        curr_wall="$(skwd-helm current 2>/dev/null | cut -f2- || true)"
        if [[ -z "$curr_wall" ]]; then
            local cache_json="${XDG_CACHE_HOME:-$HOME/.cache}/skwd-wall-v2/last-applied.json"
            if [[ -f "$cache_json" ]]; then
                curr_wall="$(python3 -c "import json; print(json.load(open('$cache_json')).get('any', {}).get('path', ''))" 2>/dev/null || true)"
            fi
        fi
        if [[ -n "$curr_wall" && -f "$curr_wall" ]]; then
            skwd-helm apply "$curr_wall" >/dev/null 2>&1 || true
        fi
    fi
}

export_skwd() {
    echo "Exporting skwd-wall-v2 configuration..."
    mkdir -p "$USER_CONFIG_DIR/skwd-wall-v2"
    cp "$CONFIG_DIR/skwd-wall-v2/config.json" "$USER_CONFIG_DIR/skwd-wall-v2/config.json"
    echo "✓ skwd-wall-v2 config exported to $USER_CONFIG_DIR/skwd-wall-v2/config.json"
}

handle_skwd_command() {
    local action="${1:-export}"
    shift || true

    case "$action" in
        export|sync)
            export_skwd
            apply_skwd_wallpaper
            ;;
        apply)
            apply_skwd_wallpaper
            ;;
        *)
            export_skwd
            apply_skwd_wallpaper
            ;;
    esac
}
