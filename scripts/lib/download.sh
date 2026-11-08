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

# 0 when the file matches the digest the release API reported for it, 1 when it does not,
# 2 when there is no digest to compare against or it names an algorithm this cannot check.
# GitHub reports a sha256 for each asset in the same response that names it, which is what
# makes a pinned download checkable on its own.
asset_matches_digest() {
    local file="$1" digest="$2"

    case "$digest" in
        sha256:*) ;;
        *) return 2 ;;
    esac
    [[ "${digest#sha256:}" == "$(file_sha256 "$file")" ]]
}

# A release asset this project publishes itself. The archive is ours, so the caller can name
# it in its message; it is not a reason to install anything unverified. The path is anchored
# to `releases/download` so that a repository or tag page under the same account does not
# qualify.
is_own_release() {
    local url="$1"
    case "$url" in
        https://github.com/ladybug-me/*/releases/download/*) return 0 ;;
        *) return 1 ;;
    esac
}

# Whether an artifact with no published checksum may be installed. A hash someone else
# publishes is the only thing tying the bytes to a build, so installing without one is a
# decision this user has to make out loud, once, by name.
unverified_download_allowed() {
    [[ "${CAELESTIA_ALLOW_UNVERIFIED_DOWNLOAD:-0}" == "1" ]]
}

# Fetches "$1" into "$2" and decides whether those bytes may be used. Returns 0 when they
# may, and 1 - having said why - when they may not.
#
# This is the one place that answers "may this be installed". `$3` is the digest the
# release reported for the asset, when its resolver had one; without it the `.sha256`
# sidecar beside the URL is tried instead. `$4` names the action for the messages, because
# an archive is unpacked and a package is installed.
#
# Every caller used to spell this out, which meant one policy written five times and four
# chances to forget a change. The rule is short enough to state once: the bytes have to
# match what a release published, and a release that publishes nothing is the user's
# decision rather than a silent default.
fetch_verified_asset() { # url dest [digest] [verb]
    local url="$1" dest="$2" digest="${3:-}" verb="${4:-install}" status=0

    if ! fetch_asset "$url" "$dest" 2>/dev/null; then
        err "Failed to download $url."
        return 1
    fi

    asset_matches_digest "$dest" "$digest" || status=$?
    if [[ "$status" -eq 2 ]]; then
        verify_download "$url" "$dest" || status=$?
    fi

    case "$status" in
        0)
            info "Checksum for $url matches the release."
            return 0
            ;;
        1)
            err "Checksum mismatch for $url - not ${verb}ing it."
            return 1
            ;;
        2) ;; # nothing published a hash, so the block below decides
    esac

    # Nothing published a hash for these bytes. The project's own releases are named as
    # such because "no published checksum" reads like a third party's omission, and here it
    # is this project that has not published one.
    if is_own_release "$url"; then
        warn "Our release publishes no checksum for $url (SHA-256 $(file_sha256 "$dest"))."
    else
        warn "No published checksum for $url (SHA-256 $(file_sha256 "$dest"))."
    fi
    if ! unverified_download_allowed; then
        err "Refusing to $verb $url unverified; set CAELESTIA_ALLOW_UNVERIFIED_DOWNLOAD=1 to accept it."
        return 1
    fi
    warn "${verb^}ing $url unverified because CAELESTIA_ALLOW_UNVERIFIED_DOWNLOAD=1 is set."
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
