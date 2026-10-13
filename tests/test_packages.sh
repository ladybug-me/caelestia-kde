#!/usr/bin/env bash
# The package layer: which distro this is, what is installed, and installing what is
# not. Every distro answer here comes from a fixture or a stub - a test that asserts
# what the machine it runs on happens to be is a test that fails somewhere else.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/log.sh"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/lib/packages.sh"

# detect_base_distro reads an os-release and then, only if that says nothing, whichever
# package manager exists. distro_for supplies the first from a fixture and removes the
# second from PATH (grep stays, because the ID_LIKE branch needs it), so the answer can
# only have come from the fixture.
distro_for() {
    local id="$1" id_like="${2:-}" tmp
    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/bin"
    cp "$(command -v grep)" "$tmp/bin/"
    printf 'ID=%s\nID_LIKE="%s"\n' "$id" "$id_like" > "$tmp/os-release"

    (
        unset BASE_DISTRO
        PATH="$tmp/bin"
        export CAELESTIA_OS_RELEASE="$tmp/os-release"
        detect_base_distro
    )
}

# Runs its command with a stub PATH, a named distro, and a scratch failure cache, so
# nothing outside the temp dir is read or written.
with_package_env() {
    local dir="$1" distro="$2"
    shift 2
    # Recording a failure shells out to mkdir, so the restricted PATH carries the real
    # one. No host package manager is on it, so only a stub can answer.
    mkdir -p "$dir/real-bin"
    cp "$(command -v mkdir)" "$dir/real-bin/"
    (
        PATH="$dir/bin:$dir/real-bin"
        BASE_DISTRO="$distro"
        export XDG_CACHE_HOME="$dir/cache"
        "$@"
    )
}

failed_packages() {
    local dir="$1"
    [[ -f "$dir/cache/caelestia-kde/failed_packages.txt" ]] &&
        tr '\n' ' ' < "$dir/cache/caelestia-kde/failed_packages.txt"
}

test_detect_base_distro_reads_the_id() {
    assert_eq "arch" "$(distro_for arch)" "arch should map to arch"
    assert_eq "arch" "$(distro_for cachyos)" "an arch derivative should map to arch"
    assert_eq "fedora" "$(distro_for nobara)" "a fedora derivative should map to fedora"
    assert_eq "debian" "$(distro_for ubuntu)" "ubuntu should map to debian"
}

test_detect_base_distro_falls_back_to_id_like() {
    assert_eq "arch" "$(distro_for someos arch)" "ID_LIKE=arch should map to arch"
    assert_eq "fedora" "$(distro_for someos 'fedora rhel')" "ID_LIKE=fedora should map to fedora"
    assert_eq "debian" "$(distro_for someos ubuntu)" "ID_LIKE=ubuntu should map to debian"
}

test_detect_base_distro_reports_unknown_when_nothing_matches() {
    assert_eq "unknown" "$(distro_for someos)" "an unrecognised id with no ID_LIKE is unknown"
    assert_eq "unknown" "$(distro_for someos suse)" "an unrecognised ID_LIKE is unknown"
}

test_detect_base_distro_prefers_the_environment_override() {
    local out
    out="$(BASE_DISTRO=fedora detect_base_distro)"
    assert_eq "fedora" "$out" "detect_base_distro should honor BASE_DISTRO override"
}

test_package_present_asks_the_distros_own_manager() {
    local tmp
    tmp="$(new_tmpdir)"
    # rpm says yes and dpkg says no: on a debian base the dpkg answer is the one that
    # counts, whatever else happens to be installed on the machine.
    recording_stub "$tmp/bin" rpm "$tmp/rpm.log"
    recording_stub "$tmp/bin" dpkg "$tmp/dpkg.log" 1

    if (BASE_DISTRO=debian; with_path "$tmp/bin" "" package_present bash); then
        fail "a package dpkg does not know about is not installed"
    fi
    assert_eq "" "$(calls_to "$tmp/rpm.log" rpm)" "rpm must not be consulted on a debian base"
    assert_contains "$(calls_to "$tmp/dpkg.log" dpkg)" "-s bash" "dpkg must be asked about the package"
}

test_package_present_is_false_on_an_unknown_base() {
    local tmp
    tmp="$(new_tmpdir)"
    recording_stub "$tmp/bin" pacman "$tmp/pacman.log"

    if (BASE_DISTRO=unknown; with_path "$tmp/bin" "" package_present bash); then
        fail "an unknown base has no package manager to ask"
    fi
    assert_eq "" "$(calls_to "$tmp/pacman.log" pacman)" "nothing should be asked without a known base"
}

test_filter_missing_keeps_only_what_is_absent() {
    local tmp out
    tmp="$(new_tmpdir)"
    stub_bin "$tmp/bin" pacman 'case "$2" in present) exit 0 ;; *) exit 1 ;; esac'

    out="$(with_package_env "$tmp" arch filter_missing present absent)"
    assert_eq "absent" "$out" "only the absent package should be reported"
}

test_filter_installed_keeps_only_what_is_present() {
    local tmp out
    tmp="$(new_tmpdir)"
    stub_bin "$tmp/bin" pacman 'case "$2" in present) exit 0 ;; *) exit 1 ;; esac'

    out="$(with_package_env "$tmp" arch filter_installed present absent)"
    assert_eq "present" "$out" "only the installed package should be reported"
}

test_install_if_missing_skips_what_is_already_there() {
    local tmp log status
    tmp="$(new_tmpdir)"
    log="$tmp/calls.log"
    stub_bin "$tmp/bin" pacman 'exit 0'
    recording_stub "$tmp/bin" yay "$log"
    recording_stub "$tmp/bin" caelestia_sudo "$log"

    with_package_env "$tmp" arch install_if_missing kvantum
    status=$?

    assert_status 0 "$status" "an installed package needs no work"
    assert_eq "" "$(calls_to "$log" yay)" "nothing should be installed when it is already there"
    assert_eq "" "$(failed_packages "$tmp")" "a package that needed no work is not a failure"
}

test_install_if_missing_falls_through_to_the_next_candidate() {
    local tmp log status
    tmp="$(new_tmpdir)"
    log="$tmp/calls.log"
    # -Qq is the "is it installed" probe, which answers no for both candidates. The
    # install only works for the second one, so the first has to fall through.
    stub_bin "$tmp/bin" pacman 'case "$1" in
-Qq) exit 1 ;;
-S) [[ "$3" == "yes" ]] && exit 0 || exit 1 ;;
esac
exit 1'
    recording_stub "$tmp/bin" yay "$log" 1
    stub_bin "$tmp/bin" caelestia_sudo "printf 'caelestia_sudo %s\n' \"\$*\" >> '$log'
\"\$@\""

    with_package_env "$tmp" arch install_if_missing nope yes
    status=$?

    assert_status 0 "$status" "the fallback candidate should satisfy the caller"
    assert_contains "$(calls_to "$log" caelestia_sudo)" "pacman -S --needed yes" \
        "the fallback candidate should be the one installed"
    assert_eq "" "$(failed_packages "$tmp")" "a package a fallback installed is not a failure"
}

test_install_if_missing_records_the_whole_failed_chain() {
    local tmp status
    tmp="$(new_tmpdir)"
    recording_stub "$tmp/bin" pacman "$tmp/calls.log" 1
    recording_stub "$tmp/bin" yay "$tmp/calls.log" 1
    recording_stub "$tmp/bin" caelestia_sudo "$tmp/calls.log" 1

    with_package_env "$tmp" arch install_if_missing one two
    status=$?

    assert_status 1 "$status" "no candidate installed means failure"
    assert_eq "one two " "$(failed_packages "$tmp")" "every candidate that failed should be recorded"
}

test_package_install_never_passes_an_empty_flag() {
    local tmp out
    tmp="$(new_tmpdir)"
    # One argument per line, bracketed: an empty CONFIRM_ARG would show up as [].
    stub_bin "$tmp/bin" yay 'for a in "$@"; do printf "[%s]\n" "$a"; done'
    stub_bin "$tmp/bin" caelestia_sudo 'exit 0'

    out="$(with_package_env "$tmp" arch package_install kvantum)"
    assert_eq "[-S]
[--needed]
[kvantum]" "$out" "an unset CONFIRM_ARG must vanish, not arrive as an empty argument"

    out="$(CONFIRM_ARG=--noconfirm with_package_env "$tmp" arch package_install kvantum)"
    assert_contains "$out" "[--noconfirm]" "a set CONFIRM_ARG should reach the package manager"
}

run_tests
