#!/usr/bin/env bash
if [[ -z "${CAELESTIA_DOWNLOAD_SOURCED:-}" ]]; then
CAELESTIA_DOWNLOAD_SOURCED=1

file_sha256() {
    sha256sum "$1" | cut -d' ' -f1
}

# Curl exit codes worth retrying: DNS, connect, timeout, TLS handshake, truncated transfer.
# An HTTP error such as 404 is an answer rather than an outage, and is not retried.
download_is_transient() {
    case "$1" in
        6 | 7 | 18 | 28 | 35 | 52 | 55 | 56) return 0 ;;
        *) return 1 ;;
    esac
}

fetch_asset() {
    local url="$1" dest="$2"
    shift 2
    local attempt=0 status=1 delay=1
    while (( attempt < 3 )); do
        curl -fsSL --connect-timeout 10 "$@" "$url" -o "$dest" && return 0
        status=$?
        attempt=$((attempt + 1))
        download_is_transient "$status" || return "$status"
        if (( attempt < 3 )); then
            sleep "$delay"
            delay=$((delay * 2))
        fi
    done
    return "$status"
}

verify_download() {
    local url="$1" file="$2" sidecar expected
    sidecar="$(mktemp)"
    if ! fetch_asset "$url.sha256" "$sidecar" 2>/dev/null; then
        rm -f "$sidecar"
        return 2
    fi
    expected="$(cut -d' ' -f1 < "$sidecar")"
    rm -f "$sidecar"
    [[ -n "$expected" ]] || return 2
    [[ "$expected" == "$(file_sha256 "$file")" ]]
}

is_own_release() {
    local url="$1"
    case "$url" in
        https://github.com/ladybug-me/*/releases/download/*) return 0 ;;
        *) return 1 ;;
    esac
}

archive_entries_are_safe() {
    local archive="$1" listing line mode name
    listing="$(tar -tvzf "$archive" 2>/dev/null)" || return 1

    while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        mode="${line%% *}"
        name="${line##* }"
        case "$mode" in
            *s*|*S*) return 1 ;;
        esac
        case "$name" in
            /*|../*|*/../*|*/..) return 1 ;;
        esac
    done <<< "$listing"
    return 0
}

fi
