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

# The installers name the programs they trust by absolute path, so that a directory this
# user can write cannot stand in for `sha256sum` or `jq`. The stubs in these tests live on
# PATH, so a subshell that drives an extracted function points the lookup back at it; that
# the real lookup uses /usr/bin is covered by tests/test_tools.sh.
path_tools() {
    system_tool() { printf '%s\n' "$1"; }
}

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
    assert_file_contains "$helper" 'fetch_verified_asset' \
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
        assert_file_contains "$REPO_ROOT/$file" 'fetch_darkly_package' \
            "and its checksum has to be checked before a package manager runs it"
    done

    assert_file_not_contains "$REPO_ROOT/installer/distro/debian/packages.sh" 'releases/latest' \
        "the cliphist binary is pinned the same way"
    assert_file_contains "$REPO_ROOT/installer/distro/debian/packages.sh" 'CLIPHIST_VERSION="' \
        "by a version constant of its own"
}

# One policy, one home: an artifact fetched from elsewhere is measured against what its
# release published, and a release that published nothing is the user's decision. Every
# caller used to spell that out, which is how the same rule ends up with five spellings.
test_the_verification_policy_has_one_home() {
    local helper="$REPO_ROOT/scripts/lib/download.sh"
    local file

    assert_file_contains "$helper" 'fetch_verified_asset()' \
        "download.sh owns the question of whether a download may be used"
    assert_file_contains "$helper" 'asset_matches_digest "$dest" "$digest"' \
        "the digest the release reports is what the bytes are measured against"
    assert_file_contains "$helper" 'unverified_download_allowed' \
        "with a release that published nothing left to the user"

    for file in \
        installer/distro/debian/packages.sh \
        installer/distro/fedora/packages.sh \
        scripts/lib/matugen.sh \
        scripts/lib/toolchain.sh \
        scripts/lib/darkly.sh; do
        assert_file_not_contains "$REPO_ROOT/$file" 'asset_matches_digest' \
            "$file must ask the one helper rather than measuring the download itself"
        assert_file_not_contains "$REPO_ROOT/$file" 'unverified_download_allowed' \
            "and must not restate the opt-in either"
    done
}

test_matugen_checks_the_archive_before_unpacking_it() {
    local helper="$REPO_ROOT/scripts/lib/matugen.sh"

    assert_file_contains "$helper" 'archive_entries_are_safe "$archive"' \
        "the archive's entries decide where it is allowed to write"
    assert_file_contains "$helper" 'tar --no-same-owner --no-same-permissions' \
        "and nothing in it needs the owner or the mode it carries"
}

# The release reports a digest for the asset, and the project publishes no sidecar, so the
# API is the only place the download can be tied to the release it came from.
test_matugen_is_checked_against_the_digest_the_release_reports() {
    local helper="$REPO_ROOT/scripts/lib/matugen.sh"

    assert_file_contains "$helper" 'releases/tags/v${MATUGEN_VERSION}' \
        "the asset and its digest have to come from the pinned tag"
    assert_file_contains "$helper" 'fetch_verified_asset "$dl_url" "$archive" "$digest"' \
        "and the digest is what the archive is measured against"
}

# `~/.cargo/bin` is the user's, so the binary root promotes is read without following a link.
test_the_cargo_matugen_binary_is_promoted_without_following_a_link() {
    local helper="$REPO_ROOT/scripts/lib/matugen.sh"

    assert_file_contains "$helper" 'privileged_copy_file "$HOME/.cargo/bin/matugen" /usr/local/bin/matugen' \
        "the file cargo wrote is copied by the helper that refuses a link"
    assert_file_not_contains "$helper" 'caelestia_sudo cp "$HOME/.cargo/bin/matugen"' \
        "rather than handed to cp, which would follow one"
}

# A tag can be moved, so the tag a clone names is only how the tree is fetched: the commit
# beside it is what the checkout has to be, and a moved tag has to fail rather than build
# whatever it now points at.
test_every_cloned_build_tree_is_checked_against_a_pinned_commit() {
    local file
    for file in installer/distro/debian/packages.sh installer/distro/fedora/packages.sh; do
        assert_file_matches "$REPO_ROOT/$file" '^GPU_SCREEN_RECORDER_COMMIT="[0-9a-f]{40}"$' \
            "$file should pin the commit its gpu-screen-recorder tag pointed at"
        assert_file_matches "$REPO_ROOT/$file" '^APP2UNIT_COMMIT="[0-9a-f]{40}"$' \
            "and the one app2unit's tag did"
    done
    assert_file_matches "$REPO_ROOT/installer/distro/debian/packages.sh" '^WL_CLIP_PERSIST_COMMIT="[0-9a-f]{40}"$' \
        "the wl-clip-persist tag needs the same pin"
    assert_file_matches "$REPO_ROOT/scripts/lib/plasma-audio-visualizer.sh" '^PLASMA_AUDIO_VISUALIZER_COMMIT="[0-9a-f]{40}"$' \
        "as does the audio visualizer's"
    assert_file_matches "$REPO_ROOT/scripts/lib/skwd-wall.sh" '^SKWD_PAPER_PLASMA_COMMIT="[0-9a-f]{40}"$' \
        "and the wallpaper plugin's"

    for file in \
        installer/distro/debian/packages.sh \
        installer/distro/fedora/packages.sh \
        scripts/lib/plasma-audio-visualizer.sh \
        scripts/lib/skwd-wall.sh; do
        assert_file_contains "$REPO_ROOT/$file" 'rev-parse HEAD' \
            "$file has to check the checkout is the commit it pinned"
    done
}

# cliphist ships a bare binary that is installed as root, so it is checked the same way the
# packages are: the digest the release reports, or a sidecar, and nothing otherwise.
test_the_cliphist_binary_is_checked_against_the_release_digest() {
    local file="$REPO_ROOT/installer/distro/debian/packages.sh"

    assert_file_contains "$file" 'releases/tags/v${CLIPHIST_VERSION}' \
        "the asset has to come from the pinned tag"
    assert_file_contains "$file" 'fetch_verified_asset "$CLIPHIST_URL" "$tmpbin" "$_cliphist_digest"' \
        "and be measured against the digest the release reports"
    assert_file_not_contains "$file" 'curl -fsSL "$CLIPHIST_URL" -o "$tmpbin"' \
        "not downloaded and installed without looking at it"
}

# The asset is picked by the names the release published, so a fixture of that release drives
# the real function.
test_the_cliphist_asset_is_resolved_from_the_pinned_tag() {
    local tmp out version asset digest
    tmp="$(new_tmpdir)"
    version="$(sed -n 's/^CLIPHIST_VERSION="\([^"]*\)"$/\1/p' "$REPO_ROOT/installer/distro/debian/packages.sh" | head -n1)"
    cat > "$tmp/release.json" << 'JSON'
{"tag_name":"v0.7.0","assets":[
{"browser_download_url":"https://github.com/sentriz/cliphist/releases/download/v0.7.0/v0.7.0-linux-386","name":"v0.7.0-linux-386","digest":"sha256:4d3e3061674e1498c72842dfd453ca6ee88b98174ffbb0bcf9aff434cad4ff23"},
{"browser_download_url":"https://github.com/sentriz/cliphist/releases/download/v0.7.0/v0.7.0-linux-amd64","name":"v0.7.0-linux-amd64","digest":"sha256:d21ca6846bd25f7bd2dabb157912e2e07226db76be32885bc53d7f27db98d08a"}]}
JSON

    out="$(
        eval "$(extract_function "$REPO_ROOT/installer/distro/debian/packages.sh" cliphist_asset_url)"
        path_tools
        CLIPHIST_VERSION="$version"
        curl() { cat "$tmp/release.json"; }
        cliphist_asset_url linux-amd64
    )"

    asset="${out%%$'\t'*}"
    digest="${out#*$'\t'}"
    assert_contains "$asset" "/releases/download/v${version}/v${version}-linux-amd64" \
        "the asset should be the one built for this architecture"
    assert_contains "$digest" "sha256:" \
        "and the digest the release reports travels with it"
}

# Both Nerd Font archives are version-pinned and the project publishes no checksum beside
# them, so the hashes are constants in the scripts that install the fonts as root. The
# helpers that check and place them are shared, so a distro only says which fonts it needs.
test_the_nerd_font_archives_are_checked_against_a_pinned_hash() {
    local file
    for file in installer/distro/debian/packages.sh installer/distro/fedora/packages.sh; do
        assert_file_matches "$REPO_ROOT/$file" '^CASCADIA_CODE_SHA256="[0-9a-f]{64}"$' \
            "$file should pin the CascadiaCode archive it unpacks"
        assert_file_matches "$REPO_ROOT/$file" '^JETBRAINS_MONO_SHA256="[0-9a-f]{64}"$' \
            "and the JetBrains Mono one"
        assert_file_contains "$REPO_ROOT/$file" 'nerd_font_archive_matches "$font_tmp/CascadiaCode.zip"' \
            "the archive is checked before it is unpacked"
        assert_file_contains "$REPO_ROOT/$file" 'nerd_font_archive_matches "$font_tmp/JetBrainsMono.zip"' \
            "both of them are"
    done

    assert_file_contains "$REPO_ROOT/installer/distro/debian/packages.sh" \
        'install_checked_font "$font_tmp/Rubik-VariableFont_wght.ttf"' \
        "the two branch downloads are checked for being a font before they are put in place"
    assert_file_contains "$REPO_ROOT/installer/distro/fedora/packages.sh" \
        'install_checked_font "$font_tmp/MaterialSymbolsRounded.ttf"' \
        "which is the only thing a mutable URL allows"
}

# The font helpers were written out in both distro scripts, byte for byte, in files that
# already source the module that owns fonts.
test_the_font_helpers_have_one_home() {
    local helper="$REPO_ROOT/scripts/lib/fonts.sh"
    local file

    assert_file_contains "$helper" 'install_checked_font()' \
        "fonts.sh is where a downloaded font is placed"
    assert_file_contains "$helper" 'nerd_font_archive_matches()' \
        "and where a pinned archive is checked"
    assert_file_contains "$helper" 'user_font_dir()' \
        "with one answer to where that directory is"

    for file in installer/distro/debian/packages.sh installer/distro/fedora/packages.sh; do
        assert_file_not_contains "$REPO_ROOT/$file" 'install_checked_font() {' \
            "$file must not carry its own copy of the helper"
        assert_file_not_contains "$REPO_ROOT/$file" 'nerd_font_archive_matches() {' \
            "of either one"
        assert_file_contains "$REPO_ROOT/$file" 'font_dir="$(user_font_dir)"' \
            "and must ask where the font directory is instead of spelling it out"
    done
}

# Upstream's installers are downloaded to a file this user named, logged and then run, so a
# transfer that stops halfway cannot leave half a script executing. None is pinned: the URL
# never changes while its content does, so a hash would break on the next upstream release.
test_upstream_installer_scripts_are_not_piped_straight_into_a_shell() {
    local file
    for file in \
        installer/distro/debian/packages.sh \
        installer/distro/fedora/packages.sh \
        scripts/lib/matugen.sh; do
        if grep -qE '\|[[:space:]]*(sudo[[:space:]]+)?(ba)?sh([[:space:]]|$)' "$REPO_ROOT/$file"; then
            fail "$file pipes an installer straight into a shell"
        fi
        assert_file_contains "$REPO_ROOT/$file" 'installer SHA-256' \
            "the hash of what ran has to reach the log"
    done
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
        path_tools
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
    path_tools
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
        path_tools
        DARKLY_VERSION="$version"
        curl() { cat "$tmp/release.json"; }
        darkly_deb_asset_url
    )"
    status=$?

    assert_status 1 "$status" "a release with no package for this distro resolves to nothing"
    assert_eq "" "$out" "so the caller falls back to what it already did"
}

run_tests
