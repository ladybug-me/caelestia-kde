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

# A clone's own build and install run as root, so the tree has to be one this project
# chose. Every clone in these files names its revision with --branch, which is what a tag
# pin looks like when it is fetched shallowly.
test_every_cloned_build_tree_is_pinned() {
    local file
    for file in \
        installer/distro/debian/packages.sh \
        installer/distro/fedora/packages.sh \
        scripts/lib/plasma-audio-visualizer.sh \
        scripts/lib/skwd-wall.sh; do
        assert_file_not_contains "$REPO_ROOT/$file" 'git clone --depth 1 https://' \
            "$file clones a tree without naming the revision it builds"
        assert_file_not_contains "$REPO_ROOT/$file" 'git clone --depth 1 "' \
            "$file clones a tree without naming the revision it builds"
    done

    assert_file_contains "$REPO_ROOT/installer/distro/debian/packages.sh" 'APP2UNIT_REF="v' \
        "the app2unit tag should be a named constant"
    assert_file_contains "$REPO_ROOT/installer/distro/fedora/packages.sh" 'APP2UNIT_REF="v' \
        "on both distros that build it"
    assert_file_contains "$REPO_ROOT/installer/distro/debian/packages.sh" 'WL_CLIP_PERSIST_REF="v' \
        "the wl-clip-persist tag should be a named constant too"
    assert_file_contains "$REPO_ROOT/installer/distro/fedora/packages.sh" '--branch "$GPU_SCREEN_RECORDER_REF"' \
        "the Fedora gpu-screen-recorder build should use the same pinned ref as Debian"
    assert_file_contains "$REPO_ROOT/scripts/lib/plasma-audio-visualizer.sh" 'PLASMA_AUDIO_VISUALIZER_REF="v' \
        "the audio visualizer tag should be a named constant"
    assert_file_contains "$REPO_ROOT/scripts/lib/skwd-wall.sh" 'SKWD_PAPER_PLASMA_REF="v' \
        "and the wallpaper plugin's tag as well"
}

test_darkly_gtk_is_built_from_a_pinned_commit() {
    local helper="$REPO_ROOT/scripts/lib/darkly.sh"

    assert_file_matches "$helper" '^DARKLY_GTK_COMMIT="[0-9a-f]{40}"$' \
        "upstream publishes no tags, so a commit is the pin it can offer"
    assert_file_contains "$helper" 'fetch --depth 1 origin "$DARKLY_GTK_COMMIT"' \
        "and a commit is fetched by its id rather than by a branch name"
}

test_the_darkly_package_is_resolved_from_a_pinned_release() {
    local file
    for file in installer/distro/debian/packages.sh installer/distro/fedora/packages.sh; do
        assert_file_matches "$REPO_ROOT/$file" '^DARKLY_VERSION="[0-9]+\.[0-9]+\.[0-9]+"$' \
            "$file should name the Darkly release it installs"
        assert_file_not_contains "$REPO_ROOT/$file" 'releases/latest' \
            "a release page that moves is not something root should follow"
        assert_file_contains "$REPO_ROOT/$file" 'releases/tags/v${DARKLY_VERSION}' \
            "the asset has to come from that tag"
        assert_file_contains "$REPO_ROOT/$file" 'verify_download' \
            "and its checksum has to be checked before a package manager runs it"
        assert_file_contains "$REPO_ROOT/$file" 'asset_matches_digest' \
            "the digest the release reports is what the download is measured against"
        assert_file_contains "$REPO_ROOT/$file" 'unverified_download_allowed' \
            "an artifact with no published checksum is the user's call, not a default"
    done

    assert_file_not_contains "$REPO_ROOT/installer/distro/debian/packages.sh" 'releases/latest' \
        "the cliphist binary is pinned the same way"
    assert_file_contains "$REPO_ROOT/installer/distro/debian/packages.sh" 'CLIPHIST_VERSION="' \
        "by a version constant of its own"
}

test_matugen_checks_the_archive_before_unpacking_it() {
    local helper="$REPO_ROOT/scripts/lib/matugen.sh"

    assert_file_contains "$helper" 'archive_entries_are_safe "$archive"' \
        "the archive's entries decide where it is allowed to write"
    assert_file_contains "$helper" 'tar --no-same-owner --no-same-permissions' \
        "and nothing in it needs the owner or the mode it carries"
}

# The asset is picked by matching the names the release published, so a fixture of that
# release drives the real function. The function reads this machine's os-release, but every
# asset below is one the tag really shipped, so the answer does not depend on the host.
test_the_darkly_deb_asset_is_resolved_from_the_pinned_tag() {
    local tmp log out version
    tmp="$(new_tmpdir)"
    log="$tmp/curl.log"
    version="$(sed -n 's/^DARKLY_VERSION="\([^"]*\)"$/\1/p' "$REPO_ROOT/installer/distro/debian/packages.sh" | head -n1)"

    cat > "$tmp/release.json" << 'JSON'
{"tag_name":"v0.5.43","assets":[
{"browser_download_url":"https://github.com/Bali10050/Darkly/releases/download/v0.5.43/darkly-0.5.43_debian13_amd64.deb","digest":"sha256:7cb8e5ad23156958a3dbedcd4402b4db00381f31b43e740b0244cd7a9da87c86"},
{"browser_download_url":"https://github.com/Bali10050/Darkly/releases/download/v0.5.43/darkly-0.5.43_debian14_amd64.deb","digest":"sha256:078de84200e25597255c9dd1a7800771c481b806ba25fdb52ac0ac97df49749b"},
{"browser_download_url":"https://github.com/Bali10050/Darkly/releases/download/v0.5.43/darkly-0.5.43_kdeneon_amd64.deb","digest":"sha256:2fec38dd564940aeddf18a6f314223306318fb3cc9236ce2ec60c91f86e1b61f"},
{"browser_download_url":"https://github.com/Bali10050/Darkly/releases/download/v0.5.43/darkly-0.5.43_kubuntu-26.04_amd64.deb","digest":"sha256:8d7370a32e835592a926d72c57be53b74a95260dfb10416f90736902b1f0d7ee"}]}
JSON

    out="$(
        eval "$(extract_function "$REPO_ROOT/installer/distro/debian/packages.sh" darkly_deb_asset_url)"
        DARKLY_VERSION="$version"
        curl() {
            printf '%s\n' "$*" >> "$log"
            cat "$tmp/release.json"
        }
        darkly_deb_asset_url
    )"

    local asset="${out%%$'\t'*}" digest="${out#*$'\t'}"
    assert_contains "$asset" "/releases/download/v${version}/" "the asset should come from the pinned tag"
    [[ "$asset" == *_amd64.deb ]] || fail "the resolved asset should be a .deb, got $(printf '%q' "$asset")"
    assert_contains "$digest" "sha256:" \
        "the digest the release reports travels with the asset, so the download can be checked"
    assert_file_contains "$log" "/releases/tags/v${version}" "which is the release the API was asked about"
    assert_file_not_contains "$log" "releases/latest" "never whichever one is newest"
}

# The digest is what the download is checked against, so what it does with a match, a
# mismatch and an algorithm it cannot check has to be exact.
test_the_release_digest_decides_whether_a_download_is_used() {
    local tmp file expected status
    tmp="$(new_tmpdir)"
    file="$tmp/asset"
    printf 'darkly\n' > "$file"
    eval "$(extract_function "$REPO_ROOT/scripts/lib/download.sh" asset_matches_digest)"
    eval "$(extract_function "$REPO_ROOT/scripts/lib/download.sh" file_sha256)"
    expected="$(file_sha256 "$file")"

    asset_matches_digest "$file" "sha256:$expected"
    assert_status 0 "$?" "the bytes the release published are accepted"

    asset_matches_digest "$file" "sha256:${expected%?}0"
    assert_status 1 "$?" "and anything else is not"

    asset_matches_digest "$file" ""
    assert_status 2 "$?" "a release that reports no digest says so, rather than matching nothing"

    asset_matches_digest "$file" "md5:abc"
    assert_status 2 "$?" "and an algorithm the check cannot read is the same answer"
}

test_an_unknown_darkly_asset_is_reported_rather_than_substituted() {
    local tmp out status version
    tmp="$(new_tmpdir)"
    version="$(sed -n 's/^DARKLY_VERSION="\([^"]*\)"$/\1/p' "$REPO_ROOT/installer/distro/debian/packages.sh" | head -n1)"
    printf '%s\n' '{"tag_name":"v0.5.43","assets":[]}' > "$tmp/release.json"

    out="$(
        eval "$(extract_function "$REPO_ROOT/installer/distro/debian/packages.sh" darkly_deb_asset_url)"
        DARKLY_VERSION="$version"
        curl() { cat "$tmp/release.json"; }
        darkly_deb_asset_url
    )"
    status=$?

    assert_status 1 "$status" "a release with no package for this distro resolves to nothing"
    assert_eq "" "$out" "so the caller falls back to what it already did"
}

run_tests
