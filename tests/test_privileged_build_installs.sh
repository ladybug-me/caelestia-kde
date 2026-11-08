#!/usr/bin/env bash
# suite: fast
#
# Two rules the installer has to keep. Root never runs install logic out of a directory this
# user can write, so build systems install into a staging prefix as the user and root only
# copies the result. And nothing that needs escalation is resolved through a PATH this user
# controls, or downloaded to a temp path another user can name.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Every file that either runs a build system or escalates on its behalf.
BUILDERS=(
    scripts/08-build-shell.sh
    scripts/lib/matugen.sh
    scripts/lib/plasma-audio-visualizer.sh
    scripts/lib/skwd-wall.sh
    installer/distro/arch/packages.sh
    installer/distro/debian/packages.sh
    installer/distro/fedora/packages.sh
)

# The post-install steps of the distro scripts, where binaries downloaded from the network
# are put in place as root.
DISTRO_SCRIPTS=(
    installer/distro/arch/packages.sh
    installer/distro/debian/packages.sh
    installer/distro/fedora/packages.sh
)

test_no_build_system_installs_as_root_from_its_build_directory() {
    local file
    for file in "${BUILDERS[@]}"; do
        file="$REPO_ROOT/$file"
        assert_file_not_contains "$file" 'caelestia_sudo cmake --install' \
            "a cmake install must be staged, not run as root"
        assert_file_not_contains "$file" 'caelestia_sudo meson install' \
            "a meson install must be staged, not run as root"
        assert_file_not_contains "$file" 'caelestia_sudo make install' \
            "a make install must be staged, not run as root"
        assert_file_not_contains "$file" 'caelestia_sudo ./install.sh' \
            "a cloned install script must not be handed to root"
    done
}

test_every_staged_install_reaches_the_one_copy_helper() {
    local file
    for file in "${BUILDERS[@]}"; do
        file="$REPO_ROOT/$file"
        if grep -qF 'install_staged_tree' "$file"; then
            assert_file_contains "$file" 'lib/install-fs.sh' \
                "a file that stages an install should source the helper it calls"
        fi
    done
}

test_the_privileged_copy_is_the_one_place_that_writes_as_root() {
    local helper="$REPO_ROOT/scripts/lib/install-fs.sh"

    assert_file_contains "$helper" 'privileged_copy_tree() {' "the copy helper should be defined once"
    assert_file_contains "$helper" 'install_staged_tree() {' "and the staging wrapper beside it"
    assert_file_contains "$helper" '-type l' "the helper has to look at the links in the tree"
    assert_file_contains "$helper" 'iflag=nofollow' "and open each file without following a link"
}

test_nothing_is_escalated_from_a_path_this_user_controls() {
    local file
    for file in "${BUILDERS[@]}"; do
        assert_file_not_contains "$REPO_ROOT/$file" 'caelestia_sudo "$(command -v' \
            "a binary resolved through PATH must not be elevated"
    done
}

test_downloaded_archives_do_not_land_in_a_predictable_temp_path() {
    local file
    for file in "${DISTRO_SCRIPTS[@]}"; do
        file="$REPO_ROOT/$file"
        assert_file_not_contains "$file" '"/tmp/CascadiaCode.zip"' \
            "the font archive needs a directory only this user can name"
        assert_file_not_contains "$file" '"/tmp/JetBrainsMono.zip"' \
            "the font archive needs a directory only this user can name"
    done
}

test_matugen_installs_a_pinned_release() {
    local helper="$REPO_ROOT/scripts/lib/matugen.sh"

    assert_file_matches "$helper" '^MATUGEN_VERSION="[0-9]+\.[0-9]+\.[0-9]+"$' \
        "the matugen release should be named by a version constant"
    assert_file_not_contains "$helper" 'releases/latest' \
        "a release page that moves is not something root should follow"
    assert_file_contains "$helper" 'verify_download' \
        "and whatever checksum the release publishes should be checked"
}

test_krohnkite_checks_the_release_asset_it_installs() {
    local script="$REPO_ROOT/shell/scripts/krohnkite_setup.sh"

    assert_file_contains "$script" '.sha256' \
        "the install should look for a published checksum beside the asset"
    assert_file_contains "$script" 'no published checksum' \
        "and say so when the release publishes none"
    assert_file_contains "$script" 'checksum mismatch' \
        "while refusing an asset whose checksum disagrees"
}

run_tests
