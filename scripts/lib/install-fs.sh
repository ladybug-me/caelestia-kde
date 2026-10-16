#!/usr/bin/env bash

validate_install_manifest() {
    local manifest="$1" root="$2" path

    if [[ ! -f "$manifest" ]]; then
        printf 'install manifest not found: %s\n' "$manifest" >&2
        return 1
    fi

    while IFS= read -r path || [[ -n "$path" ]]; do
        case "$path" in
            */.git|*/.git/*|*/.github|*/.github/*|*/.gitignore|*/.gitmodules|*/.gitattributes)
                printf 'install manifest contains VCS metadata: %s\n' "$path" >&2
                return 1
                ;;
        esac
        if [[ ! -e "$root$path" ]]; then
            printf 'install manifest references a missing path: %s%s\n' "$root" "$path" >&2
            return 1
        fi
    done < "$manifest"
}