#!/usr/bin/env bash

atomic_replace_tree() {
    local src="$1" dest="$2" required="${3:-}"

    if [[ ! -d "$src" ]]; then
        return 1
    fi

    local parent base staging previous
    parent="$(dirname -- "$dest")"
    base="$(basename -- "$dest")"

    mkdir -p -- "$parent" || return 1

    staging="$(mktemp -d -- "$parent/.$base.incoming.XXXXXX")" || return 1
    if ! cp -R -- "$src/." "$staging/"; then
        rm -rf -- "$staging"
        return 1
    fi

    if [[ -n "$required" && ! -e "$staging/$required" ]]; then
        rm -rf -- "$staging"
        return 1
    fi

    previous="$parent/.$base.previous.$$"
    rm -rf -- "$previous"

    local had_dest=0
    if [[ -e "$dest" ]]; then
        had_dest=1
        if ! mv -- "$dest" "$previous"; then
            rm -rf -- "$staging"
            return 1
        fi
    fi

    if ! mv -- "$staging" "$dest"; then
        rm -rf -- "$staging"
        if [[ "$had_dest" -eq 1 ]]; then
            mv -- "$previous" "$dest" || true
        fi
        return 1
    fi

    if [[ "$had_dest" -eq 1 ]]; then
        rm -rf -- "$previous"
    fi
    return 0
}

snapshot_dir() {
    local src="$1" root="$2" prefix="$3" keep="$4"

    [[ -d "$src" ]] || return 1
    mkdir -p -- "$root" || return 1

    local stamp dest counter
    stamp="$(date +%Y%m%d_%H%M%S)"
    dest="$root/$prefix-$stamp"
    counter=1
    while [[ -e "$dest" ]]; do
        counter=$((counter + 1))
        dest="$root/$prefix-$stamp-$(printf '%02d' "$counter")"
    done

    if ! cp -R -- "$src" "$dest"; then
        rm -rf -- "$dest"
        return 1
    fi

    local -a existing=()
    shopt -s nullglob
    existing=( "$root"/"$prefix"-* )
    shopt -u nullglob

    local total=${#existing[@]}
    local limit=$keep
    ((limit < 1)) && limit=1
    local index
    for ((index = 0; index < total - limit; index++)); do
        rm -rf -- "${existing[$index]}"
    done

    printf '%s\n' "$dest"
    return 0
}

wait_for_nonempty_file() {
    local path="$1" timeout="$2" waited=0

    while :; do
        if [[ -s "$path" ]]; then
            return 0
        fi
        if (( waited >= timeout )); then
            return 1
        fi
        sleep 1
        waited=$((waited + 1))
    done
}

prune_install_root() {
    local root="${1%/}" listing="$2" prefix="${3%/}"
    shift 3

    [[ -d "$root" ]] || return 0
    [[ -f "$listing" && -n "$prefix" ]] || return 1

    local -A shipped=()
    local -a keep=("$@")
    local line rel kept found status=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ "$line" == "$prefix"/* ]] || continue
        line="${line#"$prefix"/}"
        line="${line%/}"
        [[ -n "$line" ]] || continue
        shipped["$line"]=1
    done < "$listing"

    found="$(mktemp)" || return 1
    if ! find "$root" -mindepth 1 -depth -print0 > "$found"; then
        rm -f -- "$found"
        return 1
    fi

    while IFS= read -r -d '' rel; do
        rel="${rel#"$root"/}"
        if [[ -n "${shipped[$rel]:-}" ]]; then
            continue
        fi

        kept=0
        for line in "${keep[@]}"; do
            if [[ "$rel" == "$line" || "$rel" == "$line"/* ]]; then
                kept=1
                break
            fi
        done
        if [[ "$kept" -eq 1 ]]; then
            continue
        fi

        if [[ -d "$root/$rel" && ! -L "$root/$rel" ]]; then
            rmdir -- "$root/$rel" 2>/dev/null || true
        elif rm -f -- "$root/$rel"; then
            printf '%s\n' "$rel"
        else
            status=1
        fi
    done < "$found"

    rm -f -- "$found"
    return "$status"
}

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
