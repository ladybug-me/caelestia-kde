#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESOLVER="$REPO_ROOT/scripts/lib/installer-bin.sh"

seed_bundle() {
    local dir="$1"
    mkdir -p "$dir/installer/data" "$dir/.github" "$dir/scripts/lib"
    printf '0.1.0\n' > "$dir/installer/data/tui.version"
    printf 'VERSION=v2.5.1\n' > "$dir/.github/version.env"
}

stub_curl() {
    local dir="$1" behaviour="$2"
    mkdir -p "$dir"
    cat > "$dir/curl" <<EOF
#!/bin/sh
record="$dir/record"
dest=""
url=""
while [ "\$#" -gt 0 ]; do
    case "\$1" in
        -o) shift; dest="\$1" ;;
        http*) url="\$1" ;;
    esac
    shift
done
if [ "$behaviour" = "fail" ]; then
    exit 22
fi
case "\$url" in
    *.sha256)
        if [ "$behaviour" = "mismatch" ]; then
            printf '%064d\n' 0 > "\$dest"
        else
            sha256sum "\$(cat "\$record")" | cut -d' ' -f1 > "\$dest"
        fi
        ;;
    *)
        printf '#!/bin/sh\nexit 0\n' > "\$dest"
        printf '%s' "\$dest" > "\$record"
        ;;
esac
exit 0
EOF
    chmod +x "$dir/curl"
}

resolver() {
    local bundle="$1" home="$2" path="$3"
    shift 3
    HOME="$home" XDG_CACHE_HOME="$home/.cache" BUNDLE_DIR="$bundle" PATH="$path" \
        bash -c "source '$RESOLVER'; $*" 2>"$home/stderr"
}

cache_path() {
    printf '%s\n' "$1/.cache/caelestia/caelestia-install-v0.1.0"
}

test_a_binary_in_the_bundle_wins() {
    local dir bundle fake out
    dir="$(new_tmpdir)"
    bundle="$dir/bundle"
    seed_bundle "$bundle"
    mkdir -p "$dir/home"
    fake="$bundle/caelestia-install"
    printf '#!/bin/sh\nexit 0\n' > "$fake"
    chmod +x "$fake"

    out="$(resolver "$bundle" "$dir/home" "$PATH" caelestia_installer_bin)"
    assert_eq "$fake" "$out" "the checkout's own binary is used"
    assert_file_missing "$(cache_path "$dir/home")"
}

test_the_published_url_names_the_release_and_the_arch() {
    local dir bundle url
    dir="$(new_tmpdir)"
    bundle="$dir/bundle"
    seed_bundle "$bundle"
    mkdir -p "$dir/home"

    url="$(resolver "$bundle" "$dir/home" "$PATH" caelestia_installer_url)"
    assert_contains "$url" "/releases/download/v2.5.1/" "the release tag comes from version.env"
    assert_contains "$url" "caelestia-install-$(uname -m)-v0.1.0" "the asset name carries the arch and the installer version"
}

test_the_binary_is_fetched_into_the_cache_when_none_is_local() {
    local dir bundle out cached
    dir="$(new_tmpdir)"
    bundle="$dir/bundle"
    seed_bundle "$bundle"
    mkdir -p "$dir/home"
    stub_curl "$dir/bin" ok

    out="$(resolver "$bundle" "$dir/home" "$dir/bin:$PATH" caelestia_installer_bin)"
    cached="$(cache_path "$dir/home")"
    assert_eq "$cached" "$out" "the cached copy is returned"
    assert_file_exists "$cached"
}

test_a_checksum_mismatch_is_refused() {
    local dir bundle out cached
    dir="$(new_tmpdir)"
    bundle="$dir/bundle"
    seed_bundle "$bundle"
    mkdir -p "$dir/home"
    stub_curl "$dir/bin" mismatch

    out="$(resolver "$bundle" "$dir/home" "$dir/bin:$PATH" caelestia_installer_bin)"
    cached="$(cache_path "$dir/home")"
    assert_eq "" "$out" "a mismatch yields no binary"
    assert_file_missing "$cached"
    assert_file_contains "$dir/home/stderr" "failed its checksum" "the refusal is explained"
}

test_an_unreachable_release_is_not_fatal() {
    local dir bundle out
    dir="$(new_tmpdir)"
    bundle="$dir/bundle"
    seed_bundle "$bundle"
    mkdir -p "$dir/home"
    stub_curl "$dir/bin" fail

    out="$(resolver "$bundle" "$dir/home" "$dir/bin:$PATH" caelestia_installer_bin)"
    assert_eq "" "$out" "no binary is reported"
}

test_fetching_can_be_switched_off() {
    local dir bundle out
    dir="$(new_tmpdir)"
    bundle="$dir/bundle"
    seed_bundle "$bundle"
    mkdir -p "$dir/home"
    stub_curl "$dir/bin" ok

    out="$(CAELESTIA_NO_INSTALLER_FETCH=1 resolver "$bundle" "$dir/home" "$dir/bin:$PATH" caelestia_installer_bin)"
    assert_eq "" "$out" "the fetch is skipped"
    assert_file_missing "$(cache_path "$dir/home")"
}

test_a_cached_binary_from_another_version_is_not_used() {
    local dir bundle out stale
    dir="$(new_tmpdir)"
    bundle="$dir/bundle"
    seed_bundle "$bundle"
    mkdir -p "$dir/home/.cache/caelestia"
    stub_curl "$dir/bin" ok

    stale="$dir/home/.cache/caelestia/caelestia-install-v0.0.9"
    printf '#!/bin/sh\nexit 0\n' > "$stale"
    chmod +x "$stale"

    out="$(resolver "$bundle" "$dir/home" "$dir/bin:$PATH" caelestia_installer_bin)"
    assert_eq "$(cache_path "$dir/home")" "$out" "the declared version is fetched, not the stale copy"
    assert_file_missing "$stale" "and the superseded copy is retired"
}

test_a_cached_binary_of_the_declared_version_is_reused() {
    local dir bundle out cached
    dir="$(new_tmpdir)"
    bundle="$dir/bundle"
    seed_bundle "$bundle"
    mkdir -p "$dir/home/.cache/caelestia"

    cached="$(cache_path "$dir/home")"
    printf '#!/bin/sh\nexit 0\n' > "$cached"
    chmod +x "$cached"

    out="$(resolver "$bundle" "$dir/home" "$PATH" caelestia_installer_bin)"
    assert_eq "$cached" "$out" "a cache of this very version is used as it is"
}

test_a_binary_elsewhere_on_the_path_does_not_win() {
    local dir bundle out
    dir="$(new_tmpdir)"
    bundle="$dir/bundle"
    seed_bundle "$bundle"
    mkdir -p "$dir/home" "$dir/bin"
    printf '#!/bin/sh\nexit 0\n' > "$dir/bin/caelestia-install"
    chmod +x "$dir/bin/caelestia-install"

    out="$(CAELESTIA_NO_INSTALLER_FETCH=1 resolver "$bundle" "$dir/home" "$dir/bin:$PATH" caelestia_installer_bin)"
    assert_eq "" "$out" "an unversioned guess from the path is not run"
}

test_a_copy_in_the_users_own_bin_does_not_win() {
    local dir bundle out
    dir="$(new_tmpdir)"
    bundle="$dir/bundle"
    seed_bundle "$bundle"
    mkdir -p "$dir/home/.local/bin"
    printf '#!/bin/sh\nexit 0\n' > "$dir/home/.local/bin/caelestia-install"
    chmod +x "$dir/home/.local/bin/caelestia-install"

    out="$(CAELESTIA_NO_INSTALLER_FETCH=1 resolver "$bundle" "$dir/home" "$PATH" caelestia_installer_bin)"
    assert_eq "" "$out" "the user's own bin directory is not searched"
}

test_the_named_override_is_honoured() {
    local dir bundle out override
    dir="$(new_tmpdir)"
    bundle="$dir/bundle"
    seed_bundle "$bundle"
    mkdir -p "$dir/home"
    override="$dir/mine"
    printf '#!/bin/sh\nexit 0\n' > "$override"
    chmod +x "$override"

    out="$(CAELESTIA_INSTALL_BIN="$override" resolver "$bundle" "$dir/home" "$PATH" caelestia_installer_bin)"
    assert_eq "$override" "$out" "CAELESTIA_INSTALL_BIN names the binary to run"
}

test_a_step_with_no_binary_to_run_it_says_so() {
    local dir bundle status
    dir="$(new_tmpdir)"
    bundle="$dir/bundle"
    seed_bundle "$bundle"
    mkdir -p "$dir/home"

    CAELESTIA_NO_INSTALLER_FETCH=1 resolver "$bundle" "$dir/home" "$PATH" 'caelestia_run_step 09-system-tweaks' > "$dir/out" 2>&1
    status=$?
    assert_status 127 "$status" "a step with nothing to run is reported as unrunnable"
    assert_file_contains "$dir/home/stderr" "cannot run the 09-system-tweaks step" "the message names the step"
}

run_tests
