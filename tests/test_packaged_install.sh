#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$REPO_ROOT/src/bin/caelestia"

EXPECTED_STEPS=(03-deploy-configs.sh 03a-wallpapers.sh 04-deploy-kde.sh 04a-window-rules.sh 05-sddm-theme.sh 06-services.sh 08-build-shell.sh 09-system-tweaks.sh 10-autostart.sh)

DIR=""
CALLS=""
DATA=""

stub_steps() {
    local failing="$1" step
    DIR="$(new_tmpdir)"
    DATA="$DIR/data"
    CALLS="$DIR/calls.log"
    mkdir -p "$DATA/scripts"
    : > "$CALLS"

    for step in "${EXPECTED_STEPS[@]}"; do
        {
            printf 'printf "%%s|%%s|%%s\\n" "%s" "$BUNDLE_DIR" "$CAELESTIA_INSTALL_KIND" >> "%s"\n' "$step" "$CALLS"
            [[ "$step" == "$failing" ]] && printf 'exit 3\n'
            printf 'exit 0\n'
        } > "$DATA/scripts/$step"
    done
}

run_install() {
    local env_prefix=()
    while [[ $# -gt 0 ]]; do
        env_prefix+=("$1")
        shift
    done
    env "${env_prefix[@]}" "$CLI" install > "$DIR/out.txt" 2>&1
    RUN_STATUS=$?
}

RUN_STATUS=0
RUN_OUTPUT=""

test_a_checkout_install_is_still_the_installer() {
    DIR="$(new_tmpdir)"
    mkdir -p "$DIR/checkout"
    printf '#!/bin/sh\necho "checkout installer ran"\n' > "$DIR/checkout/install.sh"

    CAELESTIA_DIR="$DIR/checkout" "$CLI" install > "$DIR/out.txt" 2>&1
    assert_status 0 "$?" "a checkout install should succeed"
    assert_contains "$(cat "$DIR/out.txt")" "checkout installer ran" "install should run the checkout's own installer"
}

test_a_checkout_that_is_not_named_is_refused_with_its_installer() {
    stub_steps ""
    CAELESTIA_DATA_DIR="$REPO_ROOT" "$CLI" install > "$DIR/out.txt" 2>&1
    local status=$?

    assert_status 1 "$status" "a checkout with no CAELESTIA_DIR should be refused"
    assert_contains "$(cat "$DIR/out.txt")" "is a checkout, not a package install" "the refusal should say which install it found"
    assert_contains "$(cat "$DIR/out.txt")" "$REPO_ROOT/install.sh" "the refusal should name the installer to run instead"
    assert_eq "" "$(cat "$CALLS")" "no step should have run"
}

test_the_packaged_half_runs_the_user_steps_in_order() {
    stub_steps ""
    CAELESTIA_DATA_DIR="$DATA" CAELESTIA_INSTALL_KIND=package "$CLI" install > "$DIR/out.txt" 2>&1
    local status=$?
    assert_status 0 "$status" "the packaged half should succeed"

    local expected="" step
    for step in "${EXPECTED_STEPS[@]}"; do
        [[ -n "$expected" ]] && expected+=$'\n'
        expected+="$step|$DATA|package"
    done
    assert_eq "$expected" "$(cat "$CALLS")" "every user-half step should run once, in order, told which install it is part of"
}

test_the_machine_steps_stay_out_of_a_packaged_install() {
    stub_steps ""
    CAELESTIA_DATA_DIR="$DATA" CAELESTIA_INSTALL_KIND=package "$CLI" install > "$DIR/out.txt" 2>&1

    local calls
    calls="$(cat "$CALLS")"
    local absent
    for absent in 00-refresh-mirrors.sh 00a-system-update.sh 01-ensure-prereqs.sh 02-all-packages.sh 02a-submodules.sh 07-kde-apps.sh 11-optional-apps.sh; do
        assert_not_contains "$calls" "$absent" "$absent belongs to the package, not to the user's half"
    done
}

test_the_greeter_step_selects_without_installing_the_theme() {
    local script
    script="$(cat "$REPO_ROOT/scripts/05-sddm-theme.sh")"

    assert_contains "$script" 'skip "The theme files belong to the package."' "the theme copy should be skipped"
    assert_contains "$script" 'skip "The theme selection belongs to the package."' "the selection under /etc should be skipped"
    assert_contains "$script" "skip \"The display manager's dependencies belong to the package.\"" "the distro dependencies should be skipped"
    assert_contains "$script" 'register_greeter_sync "SDDM theme installed."' "while the posthook is still registered for both kinds"

    local pkgbuild
    pkgbuild="$(cat "$REPO_ROOT/packaging/aur/caelestia-kde/PKGBUILD")"
    assert_contains "$pkgbuild" 'usr/share/sddm/themes/caelestia' "the package should install the theme"
    assert_contains "$pkgbuild" 'scripts/sync.sh' "and the helper the posthook runs"
    assert_contains "$pkgbuild" 'etc/sddm.conf.d/zz-caelestia.conf' "and the drop-in that selects it"
    assert_contains "$pkgbuild" 'usr/lib/udev/rules.d/70-uinput.rules' "and the udev rule the system block writes for a checkout"
}

test_a_failing_step_stops_the_run() {
    stub_steps "04-deploy-kde.sh"
    CAELESTIA_DATA_DIR="$DATA" CAELESTIA_INSTALL_KIND=package "$CLI" install > "$DIR/out.txt" 2>&1
    local status=$?

    assert_status 1 "$status" "a failing step should fail the run"
    assert_contains "$(cat "$DIR/out.txt")" "04-deploy-kde.sh failed" "the failure should name the step"
    assert_not_contains "$(cat "$CALLS")" "06-services.sh" "nothing after the failing step should run"
}

test_missing_scripts_say_where_they_come_from() {
    DIR="$(new_tmpdir)"
    mkdir -p "$DIR/bin"
    cp "$CLI" "$DIR/bin/caelestia"

    env -u CAELESTIA_DATA_DIR -u CAELESTIA_LIB_DIR HOME="$DIR/home" "$DIR/bin/caelestia" install > "$DIR/out.txt" 2>&1
    local status=$?

    assert_status 1 "$status" "no scripts should be an error"
    assert_contains "$(cat "$DIR/out.txt")" "no installer scripts found" "the error should say what is missing"
    assert_contains "$(cat "$DIR/out.txt")" "/usr/share/caelestia" "the error should say where a package keeps them"
}

test_the_package_sources_and_their_hashes_stay_in_step() {
    local pkgbuild_dir="$REPO_ROOT/packaging/aur/caelestia-kde"
    local out
    out="$(
        bash -c '
            set -u
            cd "$1" || exit 1
            source ./PKGBUILD
            printf "counts %s %s\n" "${#source[@]}" "${#sha256sums[@]}"
            printf "source %s\n" "${source[@]}"
            printf "sum %s\n" "${sha256sums[@]}"
        ' bash "$pkgbuild_dir"
    )"

    local counts sources sums
    counts="$(printf '%s\n' "$out" | awk '/^counts / { print $2, $3 }')"
    sources="$(printf '%s\n' "$out" | awk '/^source / { $1 = ""; print substr($0, 2) }')"
    sums="$(printf '%s\n' "$out" | awk '/^sum / { print $2 }')"

    local source_count hash_count
    source_count="$(printf '%s\n' "$counts" | cut -d' ' -f1)"
    hash_count="$(printf '%s\n' "$counts" | cut -d' ' -f2)"
    assert_ne "0" "$source_count" "the PKGBUILD should declare sources"
    assert_eq "$source_count" "$hash_count" "every source needs exactly one hash entry"

    local i path hash actual
    for i in $(seq 1 "$source_count"); do
        path="$(printf '%s\n' "$sources" | sed -n "${i}p" | sed 's/^[^:]*:://')"
        hash="$(printf '%s\n' "$sums" | sed -n "${i}p")"
        [[ "$hash" == "SKIP" ]] && continue
        actual="$(sha256sum "$pkgbuild_dir/$path" | cut -d' ' -f1)"
        assert_eq "$hash" "$actual" "the hash of $path should match the file beside the PKGBUILD"
    done
}
test_the_release_tarball_is_the_thing_the_package_sources() {
    local workflow pkgbuild
    workflow="$(cat "$REPO_ROOT/.github/workflows/version-release.yml")"
    pkgbuild="$(cat "$REPO_ROOT/packaging/aur/caelestia-kde/PKGBUILD")"

    assert_contains "$workflow" 'ARTIFACT="caelestia-kde-v$PKGVER.tar.gz"' "the release job should build the versioned tarball"
    assert_contains "$pkgbuild" '$pkgname-v$pkgver.tar.gz' "and the PKGBUILD should source that same name"
    assert_contains "$pkgbuild" 'releases/download/v$pkgver' "from the release the tag publishes"

    assert_contains "$workflow" 'echo "PKGVER=${VERSION#v}" >> "$GITHUB_ENV"' "the tag's v should be stripped once, where the version is read"
    assert_not_contains "$workflow" 'caelestia-kde-v$VERSION' "the asset name must not double the tag's v"
    assert_not_contains "$workflow" 'caelestia-kde-$VERSION' "and the directory must not carry it at all"

    assert_contains "$workflow" 'tar -C dist -czf "$ARTIFACT" "caelestia-kde-$PKGVER"' "the archive should carry the directory makepkg extracts to"

    # The checkout must not fan out over every gitlink: one that has no .gitmodules
    # entry stopped the whole job at v2.4.3 and the release went out without its
    # source, so the job takes the submodule paths from .gitmodules itself and
    # refuses to tar a tree whose submodules did not land.
    assert_not_contains "$workflow" 'submodules: recursive' "the checkout must not recurse over every gitlink"
    assert_contains "$workflow" 'git config -f .gitmodules --get-regexp' "the job should read the submodule paths from .gitmodules"
    assert_contains "$workflow" 'git submodule update --init --recursive --depth 1 --force "$path"' "and inline each declared submodule"
    assert_contains "$workflow" 'is declared in .gitmodules but is not a submodule' "while an entry with no gitlink is reported, not fatal"
    assert_contains "$workflow" 'is empty; the PKGBUILD refuses a tarball without it' "failing instead of shipping a tarball prepare() rejects"

    assert_contains "$workflow" "--exclude '/dist'" "the staging directory must stay out of itself"
    assert_contains "$workflow" 'git rev-parse HEAD > "dist/$ROOT/REVISION"' "and write the revision"

    assert_contains "$workflow" 'sha256sum "$ARTIFACT" | tee "$ARTIFACT.sha256"' "the job should publish the hash the PKGBUILD needs"
    assert_contains "$workflow" '>> "$GITHUB_STEP_SUMMARY"' "and put it where the release steps say to read it"
}

test_the_revision_survives_a_tree_without_git() {
    local cmake
    cmake="$(cat "$REPO_ROOT/shell/CMakeLists.txt")"

    assert_contains "$cmake" '${CMAKE_SOURCE_DIR}/../REVISION' "the build should read REVISION beside version.env"
    assert_contains "$cmake" 'file(STRINGS "${_REVISION_FILE}" GIT_REVISION' "and take the revision from it"
}

test_the_checkout_build_script_builds_the_same_tarball() {
    local script
    script="$(cat "$REPO_ROOT/packaging/aur/makepkg-from-checkout.sh")"

    assert_contains "$script" 'git clone --quiet --depth 1 --recurse-submodules --shallow-submodules "file://$repo" "$tree"' "it should stage a fresh clone, so build output cannot leak in and the submodules are materialized"
    assert_contains "$script" 'git -C "$tree" rev-parse HEAD > "$tree/REVISION"' "and write the revision"
    assert_contains "$script" '_source_url=' "and point the staged PKGBUILD at the local tarball"
    assert_contains "$script" '_source_sum=' "with its hash, rather than a SKIP"

    assert_contains "$script" 'stage="${CAELESTIA_AUR_STAGE:-$HOME/.cache/caelestia-aur}"' 'it should stage under $HOME, not /tmp'

    local pkgbuild
    pkgbuild="$(cat "$REPO_ROOT/packaging/aur/caelestia-kde/PKGBUILD")"
    assert_contains "$pkgbuild" '_source_url="${_source_url:-' "the PKGBUILD should default the source URL"
    assert_contains "$pkgbuild" '_source_sum="${_source_sum:-' "and the sum, so the script can override both"
}

test_the_payload_carries_no_version_control_metadata() {
    local pkgbuild
    pkgbuild="$(cat "$REPO_ROOT/packaging/aur/caelestia-kde/PKGBUILD")"

    assert_contains "$pkgbuild" "-name '.git' -o -name '.github' -o -name '.gitignore'" "the package should strip version control metadata"
}

test_the_install_says_how_to_start_the_shell_now() {
    local cli
    cli="$(cat "$CLI")"

    assert_contains "$cli" 'systemctl --user start caelestia-shell.service' "install should name the command that starts the shell without a logout"
    assert_not_contains "$cli" 'Log out and back in to start the shell with the new configuration.' "and not only tell them to log out"
}

test_install_help_describes_the_user_half() {
    local out
    out="$("$CLI" install --help 2>&1)"
    assert_contains "$out" "this user's half" "install should describe what it now does"
    assert_contains "$out" "idempotently" "and that it can be run again"
}

run_tests
