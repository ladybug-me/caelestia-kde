#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC_SCRIPT="$REPO_ROOT/src/greeter/sync.sh"

build_world() {
    local root="$1"
    local me
    me="$(id -un)"
    local home="$root/home"
    local login_home="$root/var/lib/plasmalogin"
    local stub="$root/bin"

    mkdir -p "$home/.local/share/color-schemes" "$login_home" "$stub"
    printf 'SECRET\n' > "$root/secret.txt"
    printf 'GOOD\n' > "$home/.local/share/color-schemes/MatugenGood.colors"
    ln -s "$root/secret.txt" "$home/.local/share/color-schemes/MatugenEvil.colors"

    stub_bin "$stub" getent "
case \"\$2\" in
    $me) printf '%s\n' '$me:x:1000:1000::$home:/bin/bash' ;;
    plasmalogin) printf '%s\n' 'plasmalogin:x:968:968::$login_home:/usr/bin/nologin' ;;
    *) exit 1 ;;
esac"

    stub_bin "$stub" systemctl 'exit 0'
    stub_bin "$stub" kwriteconfig6 'exit 0'
    stub_bin "$stub" chown 'exit 0'

    stub_bin "$stub" sudo "
for arg in \"\$@\"; do
    case \"\$arg\" in
        *MatugenEvil*) exit 1 ;;
    esac
done
args=()
while [ \"\$#\" -gt 0 ]; do
    case \"\$1\" in
        -H) shift ;;
        -u) shift 2 ;;
        *) args+=(\"\$1\"); shift ;;
    esac
done
exec \"\${args[@]}\""

    stub_bin "$stub" install "
mode=copy
while [ \"\$#\" -gt 0 ]; do
    case \"\$1\" in
        -d) mode=mkdir; shift ;;
        -o|-g|-m) shift 2 ;;
        -*) shift ;;
        *) break ;;
    esac
done
if [ \"\$mode\" = mkdir ]; then
    mkdir -p \"\$@\"
else
    cp -- \"\$1\" \"\$2\"
fi"

    printf '%s\n' "$root"
}

run_sync() {
    local root="$1" status=0
    (
        PATH="$root/bin:$PATH"
        SUDO_USER="$(id -un)" HOME="$root/home" bash "$SYNC_SCRIPT" --posthook
    ) > "$root/sync.log" 2>&1 || status=$?
    if [[ "$status" -ne 0 ]]; then
        fail_with_output "the sync script must run to completion (exited $status)" \
            "$(cat "$root/sync.log" 2>/dev/null)"
    fi
}

test_only_the_readable_scheme_reaches_the_greeter() {
    local tmp root
    tmp="$(new_tmpdir)"
    root="$(build_world "$tmp/world")"

    run_sync "$root"

    local schemes="$root/var/lib/plasmalogin/.local/share/color-schemes"
    assert_file_exists "$schemes/MatugenGood.colors"
    assert_file_missing "$schemes/MatugenEvil.colors" \
        "a scheme the user cannot read must not be copied into the greeter's state"
}

test_a_readable_scheme_still_reaches_the_greeter() {
    local tmp root
    tmp="$(new_tmpdir)"
    root="$(build_world "$tmp/world")"

    run_sync "$root"

    local copied="$root/var/lib/plasmalogin/.local/share/color-schemes/MatugenGood.colors"
    assert_file_exists "$copied"
    if [[ -f "$copied" ]]; then
        assert_eq "GOOD" "$(cat "$copied")" "the copied scheme should be the user's file"
    fi
}

run_tests
