#!/usr/bin/env bash
if [[ -z "${CAELESTIA_DOWNLOAD_SOURCED:-}" ]]; then
CAELESTIA_DOWNLOAD_SOURCED=1

file_sha256() {
    sha256sum "$1" | cut -d' ' -f1
}

fetch_asset() {
    local url="$1" dest="$2"
    shift 2
    curl -fsSL --connect-timeout 10 "$@" "$url" -o "$dest"
}

# 0 when the artifact matches the checksum published beside it, 1 when it does not
# match, 2 when the release publishes none. What that means for the artifact is the
# caller's decision: an executable has to match, an archive may be allowed through
# with a warning.
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

# A release asset this project publishes itself. The archive is ours, so a missing published
# checksum is the expected case for it rather than something to report; any other URL is a third
# party's, where the absence of a hash is what the warning is for. The path is anchored to
# `releases/download` so that a repository or tag page under the same account does not qualify.
is_own_release() {
    local url="$1"
    case "$url" in
        https://github.com/ladybug-me/*/releases/download/*) return 0 ;;
        *) return 1 ;;
    esac
}

# Refuse an archive that could escape where it is unpacked or leave a setuid binary
# behind. Extraction runs as root for the SDK, and tar restores the mode and the owner
# from the archive, so the entries are the thing to check when no hash is published.
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
