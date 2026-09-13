#!/usr/bin/env bash
# js.sh - Put a value inside JavaScript source safely.
#
# Plasma evaluates a script that arrives as text, so a user-supplied value (a
# wallpaper path, usually) gets interpolated into source. A quote ends the string
# early, a newline breaks the statement, and a backslash changes what follows it.
#
# js_string escapes everything outside [A-Za-z0-9/._:-] as \uXXXX, giving a
# literal that means the same thing to JavaScript, the shell and a single-quoted
# string. Pure bash on purpose: needing an installed interpreter because a
# wallpaper path contains an apostrophe is the kind of dependency that becomes a
# bug.
#
#   js_string "file://$HOME/a'b.jpg"   # -> file:///home/u/a\u0027b.jpg
#
# Guard is an if so a false test cannot trip `set -e` in the sourcing script.
if [[ -z "${CAELESTIA_JS_SOURCED:-}" ]]; then
CAELESTIA_JS_SOURCED=1

# js_string <value>
js_string() {
    local text="$1" out="" i ch code

    for ((i = 0; i < ${#text}; i++)); do
        ch="${text:i:1}"
        case "$ch" in
            [A-Za-z0-9/._:-]) out+="$ch" ;;
            *)
                printf -v code '%d' "'$ch"
                if ((code > 0xFFFF)); then
                    # Above the basic plane one \u escape cannot carry it, so
                    # JavaScript spells it as a surrogate pair.
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
