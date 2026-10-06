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
    for absent in 00a-system-update.sh 01-ensure-prereqs.sh 02-all-packages.sh 02a-submodules.sh 07-kde-apps.sh 11-optional-apps.sh; do
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

    local cmake pkgbuild
    cmake="$(cat "$REPO_ROOT/shell/CMakeLists.txt")"
    pkgbuild="$(cat "$REPO_ROOT/packaging/aur/caelestia-kde/PKGBUILD")"
    assert_contains "$cmake" 'usr/share/sddm/themes/caelestia' "CMake should install the theme the posthook re-syncs"
    assert_contains "$cmake" 'src/sddm/sync.sh' "and the helper the posthook runs"
    assert_contains "$pkgbuild" 'etc/sddm.conf.d/zz-caelestia.conf' "and the drop-in that selects it"
    assert_contains "$pkgbuild" 'usr/lib/udev/rules.d/70-uinput.rules' "and the udev rule the system block writes for a checkout"
}

test_shared_runtime_files_have_one_cmake_owner() {
    local cmake pkgbuild build_script workflow
    cmake="$(cat "$REPO_ROOT/shell/CMakeLists.txt")"
    pkgbuild="$(cat "$REPO_ROOT/packaging/aur/caelestia-kde/PKGBUILD")"
    build_script="$(cat "$REPO_ROOT/scripts/08-build-shell.sh")"
    workflow="$(cat "$REPO_ROOT/.github/workflows/version-release.yml")"

    assert_contains "$cmake" 'set(INSTALL_BINDIR "usr/bin"' \
        "CMake should define the executable install root"
    assert_contains "$cmake" 'install(PROGRAMS ${CAELESTIA_BIN_FILES} DESTINATION "${INSTALL_BINDIR}")' \
        "CMake should own the CLI wrappers"
    assert_contains "$cmake" '"${CAELESTIA_ROOT_DIR}/src/matugen"' \
        "CMake should own the matugen data"
    assert_contains "$cmake" '"${CAELESTIA_ROOT_DIR}/src/schemes"' \
        "CMake should own the shipped schemes"
    assert_contains "$cmake" '"${CAELESTIA_ROOT_DIR}/scripts/[0-9]*.sh"' \
        "CMake should own the installer step scripts"
    assert_contains "$cmake" '"${CAELESTIA_ROOT_DIR}/src/dots"' \
        "CMake should own the deployed dotfiles"
    assert_contains "$cmake" '"${CAELESTIA_ROOT_DIR}/shell/assets/wallpaper.webp"' \
        "CMake should own the fallback wallpaper"
    assert_contains "$cmake" '"${CAELESTIA_ROOT_DIR}/assets/org.quickshell.desktop"' \
        "CMake should own the desktop integration asset"
    assert_contains "$cmake" 'PATTERN ".git*" EXCLUDE' \
        "CMake must not install the checkout's VCS metadata"
    assert_contains "$cmake" 'option(CAELESTIA_PACKAGE' \
        "CMake should own package-only repository assets"
    assert_contains "$cmake" 'if(NOT CAELESTIA_BIN_FILES)' \
        "CMake should refuse a configure where the CLI glob matched nothing"
    assert_contains "$cmake" 'if(NOT CAELESTIA_STEP_SCRIPTS)' \
        "CMake should refuse a configure where the step-script glob matched nothing"
    assert_contains "$pkgbuild" '-DCAELESTIA_PACKAGE=ON' \
        "the package should enable package-only CMake assets"
    assert_contains "$pkgbuild" 'install_manifest.txt' \
        "the package should validate CMake's install manifest"
    assert_contains "$pkgbuild" 'validate_install_manifest' \
        "the package should reuse the shared manifest validator"
    assert_not_contains "$pkgbuild" 'caelestia-install-manifest' \
        "the package must not ship a second, hand-maintained manifest"
    assert_not_contains "$pkgbuild" 'usr/share/caelestia/src/dots' \
        "the package must not re-declare CMake-owned data paths"
    assert_not_contains "$pkgbuild" 'usr/share/caelestia/scripts/03-deploy-configs.sh' \
        "the package must not re-declare CMake-owned installer scripts"
    assert_not_contains "$pkgbuild" 'usr/share/sddm/themes/caelestia' \
        "the package must not re-declare the CMake-owned SDDM theme"
    assert_not_contains "$pkgbuild" 'etc/xdg/quickshell/caelestia/assets/icons' \
        "the package must not re-declare the CMake-owned icon tree"
    assert_not_contains "$pkgbuild" 'install -m755 src/bin/*' \
        "the package must not copy CLI wrappers outside CMake"
    assert_not_contains "$pkgbuild" 'cp -r src/matugen src/schemes' \
        "the package must not copy color data outside CMake"
    assert_not_contains "$pkgbuild" 'install -m755 scripts/[0-9]*.sh' \
        "the package must not copy installer scripts outside CMake"
    assert_not_contains "$pkgbuild" 'cp -r src/dots src/dots-extra' \
        "the package must not copy deployed dotfiles outside CMake"
    assert_not_contains "$pkgbuild" 'cp -r shell/assets/wallpaper.webp' \
        "the package must not copy the wallpaper outside CMake"
    assert_not_contains "$pkgbuild" 'cp -r assets/org.quickshell.desktop' \
        "the package must not copy desktop integration outside CMake"
    assert_not_contains "$build_script" 'install -m 755 "$BUNDLE_DIR/src/bin/' \
        "the source installer must not copy CLI wrappers outside CMake"
    assert_not_contains "$build_script" 'cp -r "$BUNDLE_DIR/src/matugen"' \
        "the source installer must not copy color data outside CMake"
    assert_contains "$build_script" 'tar -tzf "$tmp_archive" bin/' \
        "prebuilt installs should require the CMake-owned CLI tree"
    assert_contains "$build_script" 'tar -tzf "$tmp_archive" lib/caelestia/' \
        "prebuilt installs should require the source data tree"
    assert_contains "$build_script" 'tar -C "$HOME/.local" -xzf "$tmp_archive" bin' \
        "prebuilt installs should extract the CMake-owned CLI tree"
    assert_not_contains "$build_script" 'bin share' \
        "prebuilt installs should not introduce a second data layout"
    assert_contains "$build_script" 'falling back to a local build' \
        "legacy prebuilt artifacts should not claim a complete install"
    assert_contains "$workflow" 'cp -a stage/usr/bin/. dist/root/bin/' \
        "release staging should include the CMake-owned CLI tree"
}

test_a_failing_step_stops_the_run() {
    stub_steps "04-deploy-kde.sh"
    CAELESTIA_DATA_DIR="$DATA" CAELESTIA_INSTALL_KIND=package "$CLI" install > "$DIR/out.txt" 2>&1
    local status=$?

    assert_status 1 "$status" "a failing step should fail the run"
    assert_contains "$(cat "$DIR/out.txt")" "04-deploy-kde.sh failed" "the failure should name the step"
    assert_not_contains "$(cat "$CALLS")" "06-services.sh" "nothing after the failing step should run"
}

test_every_packaged_step_failure_stops_before_the_next_step() {
    local index failing next status calls
    for index in "${!EXPECTED_STEPS[@]}"; do
        failing="${EXPECTED_STEPS[$index]}"
        stub_steps "$failing"

        CAELESTIA_DATA_DIR="$DATA" CAELESTIA_INSTALL_KIND=package "$CLI" install > "$DIR/out.txt" 2>&1
        status=$?
        assert_status 1 "$status" "$failing should fail the packaged run"

        calls="$(cat "$CALLS")"
        assert_contains "$calls" "$failing" "$failing should be reached before failure"
        if (( index + 1 < ${#EXPECTED_STEPS[@]} )); then
            next="${EXPECTED_STEPS[$((index + 1))]}"
            assert_not_contains "$calls" "$next" "a failure in $failing must stop before $next"
        fi
    done
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

    assert_not_contains "$workflow" 'submodules: recursive' "the checkout must not recurse over every gitlink"
    assert_contains "$workflow" 'git config -f .gitmodules --get-regexp' "the job should read the submodule paths from .gitmodules"
    assert_contains "$workflow" 'git submodule update --init --recursive --depth 1 --force "$path"' "and inline each declared submodule"
    assert_contains "$workflow" 'is declared in .gitmodules but is not a submodule' "while an entry with no gitlink is reported, not fatal"
    assert_contains "$workflow" 'is empty; the PKGBUILD refuses a tarball without it' "failing instead of shipping a tarball prepare() rejects"

    assert_contains "$workflow" "--exclude '/dist'" "the staging directory must stay out of itself"
    assert_contains "$workflow" 'git rev-parse HEAD > "dist/$ROOT/REVISION"' "and write the revision"

    assert_contains "$workflow" 'bash scripts/fetch-dependencies.sh' "the release build should prepare pinned dependencies"
    assert_contains "$workflow" 'rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/caelestia-kde"' "the release build should start with a clean dependency cache"
    assert_contains "$workflow" 'cmake --preset release' "the release build should take its configuration from the preset"
    assert_contains "$workflow" 'tar -C dist/root -czf "$ARTIFACT" bin lib quickshell' "the prebuilt artifact should carry all CMake-owned runtime files"
    assert_contains "$workflow" 'http_proxy: http://127.0.0.1:9' "the release build should exercise the offline path"

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

test_the_package_does_not_prune_cmake_owned_paths() {
    local pkgbuild
    pkgbuild="$(cat "$REPO_ROOT/packaging/aur/caelestia-kde/PKGBUILD")"

    assert_not_contains "$pkgbuild" 'cp -r src/sddm/themes/full' \
        "CMake should own the SDDM theme tree"
    assert_not_contains "$pkgbuild" 'cp -r src/yet-another-monochrome-icon-set' \
        "CMake should own the icon tree"
    assert_not_contains "$pkgbuild" 'cp -r src/kde/shells/caelestia.desktop' \
        "CMake should own the Plasma shell tree"
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
