#!/bin/bash
# Outputs JSON array: [{"id":"..","path":"..","source":"bundled"|"user"}, ...]
BUNDLED="${1:-${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/caelestia/modules/plugins}"
USER="${2:-${XDG_CONFIG_HOME:-$HOME/.config}/caelestia/plugins}"

# A directory name is the only thing here that is not a literal, and it becomes a JSON
# string. A quote or a newline in one would otherwise end the string and let the name
# write the rest of the document - including the path the shell would then load from.
json_string() {
    local s="$1" out="" ch i
    for ((i = 0; i < ${#s}; i++)); do
        ch="${s:i:1}"
        case "$ch" in
            '"') out+='\"' ;;
            '\') out+='\\' ;;
            $'\n') out+='\n' ;;
            $'\r') out+='\r' ;;
            $'\t') out+='\t' ;;
            *)
                if [[ "$ch" < $'\x20' ]]; then
                    printf -v ch '\\u%04x' "'$ch"
                fi
                out+="$ch"
                ;;
        esac
    done
    printf '%s' "$out"
}

echo "["
first=1
for source_type in bundled user; do
    [ "$source_type" = "bundled" ] && dir="$BUNDLED" || dir="$USER"
    [ -d "$dir" ] || continue
    for p in "$dir"/*/; do
        [ -f "${p}metadata.json" ] || continue
        name=$(basename "$p")
        path="${p%/}"
        [ $first -eq 1 ] && first=0 || printf ","
        printf '\n  {"id":"%s","path":"%s","source":"%s"}' \
            "$(json_string "$name")" "$(json_string "$path")" "$source_type"
    done
done
echo ""
echo "]"
