#!/usr/bin/env bash
# Helpers for handing a value to another language. A value that came from the
# filesystem — a wallpaper path, a font name — is not safe to paste into a script
# or a sed expression as-is, so each target gets one escaper here rather than a
# recipe beside the call site.
if [[ -z "${CAELESTIA_ESCAPE_SOURCED:-}" ]]; then
CAELESTIA_ESCAPE_SOURCED=1

# js_string escapes everything outside [A-Za-z0-9/._:-] as \uXXXX, giving a
# JavaScript string literal that is safe inside a QML script.
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

# sed_replacement escapes a value for the replacement half of a sed expression.
# A line break cannot be escaped — sed reads it as the start of another command,
# and GNU's `e` flag would then run it — so such a value is refused and the caller
# is expected to skip the edit.
sed_replacement() {
    local value="$1"
    if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
        return 1
    fi
    value="${value//\\/\\\\}"
    value="${value//&/\\&}"
    value="${value//|/\\|}"
    printf '%s' "$value"
}

fi
