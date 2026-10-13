#!/usr/bin/env bash
# js_string escapes everything outside [A-Za-z0-9/._:-] as \uXXXX, giving a
if [[ -z "${CAELESTIA_JS_SOURCED:-}" ]]; then
CAELESTIA_JS_SOURCED=1

js_string() {
    local text="$1" out="" i ch code

    for ((i = 0; i < ${#text}; i++)); do
        ch="${text:i:1}"
        case "$ch" in
            [A-Za-z0-9/._:-]) out+="$ch" ;;
            *)
                printf -v code '%d' "'$ch"
                if ((code > 0xFFFF)); then
                    local value=$((code - 0x10000))
                    printf -v out '%s\\u%04x\\u%04x' "$out" "$((0xD800 + (value >> 10)))" "$((0xDC00 + (value & 0x3FF)))"
                else
                    printf -v out '%s\\u%04x' "$out" "$code"
                fi
                ;;
        esac
    done

    printf '%s' "$out"
}
fi
