#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARCH_PACKAGES="$REPO_ROOT/installer/distro/arch/packages.sh"
FEDORA_PACKAGES="$REPO_ROOT/installer/distro/fedora/packages.sh"
DEBIAN_PACKAGES="$REPO_ROOT/installer/distro/debian/packages.sh"
SERVICES_PAGE="$REPO_ROOT/shell/modules/nexus/pages/ServicesPage.qml"

# The shell defers three desktop duties to KDE: system search, printing and the
# on-screen keyboard. Each one is dead without its package, so the installer has to
# pull them in and Nexus has to say where they are configured.
test_installer_pulls_the_peers_those_features_need() {
    local arch fedora debian
    arch="$(cat "$ARCH_PACKAGES")"
    fedora="$(cat "$FEDORA_PACKAGES")"
    debian="$(cat "$DEBIAN_PACKAGES")"

    assert_contains "$arch" 'krunner baloo' \
        "launcher search needs krunner and baloo installed"
    assert_contains "$arch" 'print-manager plasma-keyboard' \
        "printing and touch typing need their KDE peers installed"

    # KF6Runner is optional in the build, so a list that forgets it loses the
    # launcher's search mode with nothing but a missing feature to show for it.
    assert_contains "$fedora" 'kf6-krunner-devel' \
        "Fedora has to ship the runner headers the bridge compiles against"
    assert_contains "$fedora" 'kf6-baloo' \
        "and the indexer behind its file results"
    assert_contains "$fedora" 'plasma-print-manager plasma-keyboard' \
        "Fedora needs printing and touch typing peers installed"
    assert_contains "$debian" 'libkf6runner-dev' \
        "Debian has to ship the runner headers too"
    assert_contains "$debian" 'baloo6' \
        "and baloo6, which is what its indexer binary is packaged as"
    assert_contains "$debian" 'print-manager plasma-keyboard' \
        "Debian needs printing and touch typing peers installed"
}

test_nexus_points_at_the_kde_owned_subsystems() {
    local content
    content="$(cat "$SERVICES_PAGE")"

    assert_contains "$content" 'kcm_printer_manager' \
        "printing is configured in KDE's print-manager module"
    assert_contains "$content" 'kcm_virtualkeyboard' \
        "the on-screen keyboard is configured in KDE's virtual keyboard module"
    assert_contains "$content" 'kcm_access' \
        "system-wide accessibility lives in KDE's accessibility module"
}

test_the_links_admit_when_a_module_is_missing() {
    local content
    content="$(cat "$SERVICES_PAGE")"

    assert_contains "$content" 'Launch.kcmAvailable("kcm_printer_manager")' \
        "the page should check that a settings module exists before promising it"
    assert_file_contains "$REPO_ROOT/shell/utils/Launch.qml" 'function kcmAvailable(name: string): bool' \
        "and that check belongs with the launcher, not in one page"
    assert_contains "$content" 'Install print-manager to enable printing' \
        "a missing printing module must be reported, not opened as a dead page"
}

run_tests
