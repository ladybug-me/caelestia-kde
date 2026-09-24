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
# match, 2 when the release publishes none. Callers refuse the artifact on either
# failure: the sidecar comes from the same channel as the artifact, so letting one
# through unverified defeats even the corruption check.
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

# tar_member_unsafe <member>
#
# True when a member name can escape the directory tar unpacks into: an absolute
# path, or any ".." component. Those are the two shapes a crafted archive needs
# to write outside its extraction root.
tar_member_unsafe() {
    local member="$1" part
    local -a parts

    member="${member#./}"
    [[ -n "$member" ]] || return 1
    case "$member" in
        /*) return 0 ;;
    esac

    IFS='/' read -r -a parts <<< "$member"
    for part in "${parts[@]}"; do
        [[ "$part" == ".." ]] && return 0
    done
    return 1
}

# tar_symlink_escapes <member> <target>
#
# True when a link member <member> -> <target> resolves outside the archive: an
# absolute target, or a relative one whose ".." components climb above the
# directory the link lives in, and so above the extraction root.
tar_symlink_escapes() {
    local member="$1" target="$2" dir part depth=0
    local -a dir_parts target_parts

    case "$target" in
        /*) return 0 ;;
    esac

    member="${member#./}"
    dir="${member%/*}"
    [[ "$dir" == "$member" ]] && dir=""

    IFS='/' read -r -a dir_parts <<< "$dir"
    for part in "${dir_parts[@]}"; do
        [[ -n "$part" && "$part" != "." ]] && depth=$((depth + 1))
    done

    IFS='/' read -r -a target_parts <<< "$target"
    for part in "${target_parts[@]}"; do
        case "$part" in
            ""|".") ;;
            "..")
                if (( depth == 0 )); then
                    return 0
                fi
                depth=$((depth - 1))
                ;;
        esac
    done
    return 1
}

# archive_is_safe <archive> [prefix...]
#
# Audits a tar archive's listing before it is unpacked, so a crafted archive is
# refused instead of written wherever it wants: any member with an absolute
# path, a ".." component, or a link pointing outside the archive makes the whole
# archive unsafe. When prefixes are given (the top-level trees the archive is
# expected to hold, "include" and "lib" for the CAVA SDK), a member outside them
# is refused too. Names every offender on stderr; returns 1 for an archive that
# must not be unpacked, 0 for one that may.
archive_is_safe() {
    local archive="$1"
    shift || true
    local -a prefixes=()
    local prefix member listing verbose line left target name perms top unsafe=0

    for prefix in "$@"; do
        prefix="${prefix#/}"
        prefix="${prefix%/}"
        [[ -n "$prefix" ]] && prefixes+=("$prefix")
    done

    if ! listing="$(tar -tf "$archive" 2>/dev/null)"; then
        echo "cannot list the members of $archive - refusing to unpack it" >&2
        return 1
    fi
    if ! verbose="$(tar -tvf "$archive" 2>/dev/null)"; then
        echo "cannot inspect $archive for links - refusing to unpack it" >&2
        return 1
    fi

    while IFS= read -r member; do
        [[ -n "$member" ]] || continue
        if tar_member_unsafe "$member"; then
            echo "archive member escapes the extraction root: $member" >&2
            unsafe=1
        fi
        if (( ${#prefixes[@]} > 0 )); then
            top="${member#./}"
            top="${top%%/*}"
            # The archive's own root entry ("." / "./") carries no tree name
            # and extracts nothing; every other member must name one.
            [[ -n "$top" ]] || continue
            for prefix in "${prefixes[@]}"; do
                [[ "$top" == "$prefix" ]] && continue 2
            done
            echo "archive member outside the expected trees (${prefixes[*]}): $member" >&2
            unsafe=1
        fi
    done <<< "$listing"

    # Link targets only appear in the verbose listing: GNU tar prints
    # "name -> target" for symlinks and "name link to target" for hard links.
    # Either can name a file outside the archive, so both are checked.
    while IFS= read -r line; do
        if [[ "$line" == *" -> "* ]]; then
            perms="${line%%[[:space:]]*}"
            [[ "$perms" == l* ]] || continue
            left="${line%% -> *}"
            target="${line#* -> }"
        elif [[ "$line" == *" link to "* ]]; then
            left="${line%% link to *}"
            target="${line#* link to }"
        else
            continue
        fi
        name="${left##*[[:space:]]}"
        [[ -n "$name" ]] || continue
        if tar_symlink_escapes "$name" "$target"; then
            echo "link escapes the extraction root: $name -> $target" >&2
            unsafe=1
        fi
    done <<< "$verbose"

    (( unsafe == 0 ))
}

fi
