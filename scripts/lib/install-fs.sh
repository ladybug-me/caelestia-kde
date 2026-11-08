#!/usr/bin/env bash

# Whether `$1` is a regular file this user pointed at directly rather than a symlink
# to somewhere else. Privileged installs copy from user-writable directories, and
# `install` follows a link: checking this first is what keeps a planted link from
# being copied as root.
regular_file() {
    [[ -f "$1" && ! -L "$1" ]]
}

# Whether a tree can be copied as root unchanged: a symlink anywhere inside it is either
# followed - which puts whatever it points at into a world-readable place - or left as a
# link root later opens. Neither is content the tree actually carried.
tree_has_no_symlinks() {
    local dir="$1" found

    [[ -d "$dir" && ! -L "$dir" ]] || return 1
    found="$(find "$dir" -type l -print -quit 2>/dev/null)"
    [[ -z "$found" ]]
}

# Copies "$1" to "$2" as root with mode "$3". The source is opened with O_NOFOLLOW, so a
# link planted between a check and the copy is refused by the kernel rather than followed;
# that is what a check-then-copy cannot promise.
privileged_copy_file() {
    local src="$1" dest="$2" mode="${3:-0644}"

    regular_file "$src" || return 1
    caelestia_sudo dd if="$src" of="$dest" iflag=nofollow status=none 2>/dev/null || return 1
    caelestia_sudo chmod "$mode" "$dest" || return 1
}

# Where a staged build may write, as the first directory component of a relative path. A
# build that installs into /usr stages usr/..., and one that installs into a home prefix
# stages share/ or lib/. Anything else - etc/sudoers.d, etc/systemd, a PAM stack - is a
# path no build here produces, and a build tree this user can write must not be able to
# name one.
staged_path_is_installable() {
    local rel="$1"

    case "$rel" in
        *//*|*/../*|*/..) return 1 ;;
        # Paths that make something else run, or change how it authenticates. No build here
        # installs one, and each is a way to turn a file write into a different privilege.
        usr/lib/systemd/*|usr/lib64/systemd/*) return 1 ;;
        usr/share/dbus-1/system.d/*|usr/share/dbus-1/system-services/*) return 1 ;;
        usr/lib/tmpfiles.d/*|usr/lib64/tmpfiles.d/*) return 1 ;;
        usr/lib/sysctl.d/*|usr/lib64/sysctl.d/*) return 1 ;;
        usr/lib/binfmt.d/*|usr/lib64/binfmt.d/*) return 1 ;;
        usr/*|share/*|lib/*|lib64/*|bin/*|sbin/*) return 0 ;;
        # A generated configuration file belongs under a directory the project owns.
        etc/xdg/*|etc/fonts/*) return 0 ;;
    esac
    return 1
}

# Installs the tree at "$1" under "$2", which must already exist, as root. The tree comes
# from a build this user ran, so root copies what it holds rather than executing anything
# from it, and the only link allowed across is one staying in its own directory - a
# versioned library or a command alias - which root recreates from the same relative
# target. One privileged step, because a prompt per file is not something a build can ask
# for.
privileged_copy_tree() {
    local src="${1%/}" dest="$2" escaping status=0

    [[ -d "$src" && ! -L "$src" && -d "$dest" ]] || return 1

    # Two things a build has no business staging: a link that leaves its own directory,
    # which would let the build pick a path root later opens, and a setuid or setgid file,
    # which would arrive as root's. Both fail here, before the prompt; the privileged side
    # checks the first again and drops the bits of the second.
    escaping="$(find "$src" -type l \( -lname '*/*' -o -lname . -o -lname .. \) -print -quit 2>/dev/null || true)"
    [[ -z "$escaping" ]] || return 1
    escaping="$(find "$src" -type f \( -perm -4000 -o -perm -2000 \) -print -quit 2>/dev/null || true)"
    [[ -z "$escaping" ]] || return 1

    # And a tree may only put files where an install of this project puts them. Without
    # this, a build tool that staged etc/sudoers.d/… would have root write it: the copy
    # below trusts the tree's own layout, and the tree is this user's to shape.
    local entry
    while IFS= read -r entry; do
        staged_path_is_installable "${entry#"$src"/}" || return 1
    done < <(find "$src" -mindepth 1 \( -type f -o -type l \) -print 2>/dev/null)

    caelestia_sudo bash -s -- "$src" "$dest" << 'EOF' || status=$?
src="$1"
dest="${2%/}"
status=0
copied=0

while IFS= read -r -d "" path; do
    rel="${path#"$src"/}"
    if ! mkdir -p -- "$dest/$(dirname -- "$rel")"; then
        status=1
        continue
    fi

    if [[ -L "$path" ]]; then
        target="$(readlink -- "$path" 2>/dev/null)" || { status=1; continue; }
        case "$target" in
            ""|*/*|.|..) status=1; continue ;;
        esac
        ln -sfn -- "$target" "$dest/$rel" || status=1
        continue
    fi

    if [[ ! -f "$path" ]]; then
        status=1
        continue
    fi
    if ! raw="$(stat -c %a -- "$path" 2>/dev/null)"; then
        status=1
        continue
    fi
    # The tree is this user's, so a file they made setuid would arrive as root's setuid
    # binary; only the read, write and execute bits are carried across.
    printf -v mode '%o' "$(( 8#$raw & 0777 ))"
    if ! dd if="$path" of="$dest/$rel" iflag=nofollow status=none 2>/dev/null; then
        status=1
        continue
    fi
    chmod "$mode" "$dest/$rel" || status=1
    copied=$((copied + 1))
done < <(find "$src" \( -type f -o -type l \) -print0 2>/dev/null)

[[ "$copied" -gt 0 ]] || status=1
exit "$status"
EOF

    return "$status"
}

# Installs what "$@" writes into "$1" as root. Build systems install by running scripts out
# of a directory this user can write, so they only ever run unprivileged here: DESTDIR
# points them at a prefix of ours, and the tree that lands there is what root copies.
install_staged_tree() {
    local dest="$1" stage status=0
    shift

    stage="$(mktemp -d)" || return 1
    if ! DESTDIR="$stage" "$@" >/dev/null; then
        rm -rf -- "$stage"
        return 1
    fi
    privileged_copy_tree "$stage" "$dest" || status=$?
    rm -rf -- "$stage"
    return "$status"
}

# Where the helpers the shell is allowed to elevate live: a directory root owns, so that
# a polkit prompt can only ever run a file nobody else can rewrite.
privileged_helper_dir() {
    printf '%s\n' /usr/lib/caelestia/scripts
}

# Installs "$1" there as root and prints the path. Copying next to the shell is not
# enough: a source install keeps the shell in the user's home, and pkexec given a path
# from there would run whatever this user had put behind it.
install_privileged_helper() {
    local src="$1" dest_dir name dest

    regular_file "$src" || return 1
    name="$(basename -- "$src")"
    dest_dir="$(privileged_helper_dir)"
    dest="$dest_dir/$name"

    caelestia_sudo install -d -m 0755 -o root -g root "$dest_dir" || return 1
    caelestia_sudo dd if="$src" of="$dest" iflag=nofollow status=none 2>/dev/null || return 1
    caelestia_sudo chmod 0755 "$dest" || return 1
    caelestia_sudo chown root:root "$dest" || return 1

    printf '%s\n' "$dest"
}

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
