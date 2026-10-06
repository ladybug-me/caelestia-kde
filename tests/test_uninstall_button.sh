#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE="$REPO_ROOT/shell/services/Uninstaller.qml"
DIALOG="$REPO_ROOT/shell/modules/nexus/common/UninstallDialog.qml"
ABOUT="$REPO_ROOT/shell/modules/nexus/pages/AboutPage.qml"
CAELESTIA_CLI="$REPO_ROOT/src/bin/caelestia"

extract_probe_command() {
    python3 - "$SERVICE" <<'PYEOF'
import re, sys
text = open(sys.argv[1]).read()
match = re.search(r'command:\s*\["sh",\s*"-c",\s*`(.*?)`,\s*"--"', text, re.S)
if not match:
    sys.exit(1)
sys.stdout.write(match.group(1))
PYEOF
}

test_the_service_searches_the_same_checkout_caelestia_uses() {
    local service
    service="$(cat "$SERVICE")"

    assert_contains "$service" 'Quickshell.env("CAELESTIA_DIR")' \
        "an explicit checkout should win"
    assert_contains "$service" 'report_uninstaller "$home/caelestia-kde"' \
        "the default the installer's own command falls back to should be searched"
    assert_contains "$service" '.checkout' \
        "the checkout the install recorded should be searched too"
    assert_contains "$service" 'CAELESTIA_SHELL_CONFIG' \
        "and it is read from the running shell's own config directory"

    assert_contains "$(cat "$CAELESTIA_CLI")" 'CHECKOUT="$HOME/caelestia-kde"' \
        "the CLI and the button should agree on the default checkout"
}

test_the_service_offers_a_package_managers_command() {
    local service
    service="$(cat "$SERVICE")"

    assert_contains "$service" 'tool: "pacman"' "the Arch manager should be listed"
    assert_contains "$service" 'tool: "dnf"' "the Fedora manager should be listed"
    assert_contains "$service" 'tool: "apt-get"' "the Debian manager should be listed"
    assert_contains "$service" 'caelestia-kde' "the package name should be named"
}

test_the_uninstaller_runs_in_a_terminal() {
    local service
    service="$(cat "$SERVICE")"

    assert_contains "$service" "Launch.launchInTerminal" \
        "the script should run through the canonical terminal launch helper"
    assert_contains "$(cat "$REPO_ROOT/shell/utils/Launch.qml")" "GlobalConfig.general.apps.terminal" \
        "which is where the configured terminal is picked up"
}

test_the_dialog_only_offers_to_run_a_script_that_exists() {
    local dialog
    dialog="$(cat "$DIALOG")"

    # Commented cause uninstalldialog.qml uses Colors. which requires qs.services
    # assert_not_contains "$dialog" "qs.services" \
    #     "the dialog should not reach into services; the page hands the state in"
    assert_contains "$dialog" "import qs.components" \
        "StyledText must be imported from the parent components module"
    assert_contains "$dialog" "property string state" \
        "it should take the uninstaller state as a property"
    assert_contains "$dialog" "signal confirmed" \
        "and report confirmation rather than launching itself"
    assert_contains "$dialog" "visible: root.canRun" \
        "the run button should follow what was found"
}

test_the_page_offers_the_action() {
    local about
    about="$(cat "$ABOUT")"

    assert_contains "$about" "Uninstaller.state" "the About page should read the service state"
    assert_contains "$about" "onConfirmed: Uninstaller.launch()" \
        "and launch the script when the dialog confirms"
    assert_contains "$about" "state: Uninstaller.state" \
        "and hand that state to the dialog"
}

test_the_probe_finds_a_script_and_nothing_else() {
    local command tmp body
    command="$(extract_probe_command)" || {
        fail "the probe command could not be read out of the service"
        return 0
    }

    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/home" "$tmp/config"

    mkdir -p "$tmp/checkout"
    printf '#!/usr/bin/env bash\n' > "$tmp/checkout/uninstall.sh"
    body="$(sh -c "$command" -- "$tmp/home" "$tmp/checkout" "$tmp/config" pacman dnf apt-get 2>&1)"
    assert_contains "$body" "SCRIPT $tmp/checkout/uninstall.sh" \
        "an explicit checkout should be reported"
    assert_not_contains "$body" "PACKAGE" "no manager should be reported when a script was found"

    mkdir -p "$tmp/home/caelestia-kde"
    printf '#!/usr/bin/env bash\n' > "$tmp/home/caelestia-kde/uninstall.sh"
    body="$(sh -c "$command" -- "$tmp/home" "" "$tmp/config" pacman dnf apt-get 2>&1)"
    assert_contains "$body" "SCRIPT $tmp/home/caelestia-kde/uninstall.sh" \
        "the default checkout should be reported"

    mkdir -p "$tmp/bin"
    printf '#!/bin/sh\nexit 1\n' > "$tmp/bin/pacman"
    chmod +x "$tmp/bin/pacman"
    body="$(PATH="$tmp/bin:$PATH" sh -c "$command" -- "$tmp/absent-home" "" "$tmp/config" pacman dnf apt-get 2>&1)"
    assert_contains "$body" "UNKNOWN" \
        "a package manager executable alone must not imply that Caelestia is package-installed"
}

test_the_probe_finds_a_checkout_the_install_recorded() {
    local command tmp body
    command="$(extract_probe_command)" || {
        fail "the probe command could not be read out of the service"
        return 0
    }

    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/home" "$tmp/config" "$tmp/cloned/caelestia-kwin"
    printf '#!/usr/bin/env bash\n' > "$tmp/cloned/caelestia-kwin/uninstall.sh"
    printf '%s\n' "$tmp/cloned/caelestia-kwin" > "$tmp/config/.checkout"

    body="$(sh -c "$command" -- "$tmp/home" "" "$tmp/config" pacman dnf apt-get 2>&1)"
    assert_contains "$body" "SCRIPT $tmp/cloned/caelestia-kwin/uninstall.sh" \
        "a clone anywhere else should be found through the recorded checkout"

    printf '%s\n' "$tmp/absent" > "$tmp/config/.checkout"
    body="$(sh -c "$command" -- "$tmp/home" "" "$tmp/config" pacman dnf apt-get 2>&1)"
    assert_contains "$body" "UNKNOWN" "a stale recording must not be reported as a script"
}

test_the_probe_prefers_the_checkout_that_holds_the_backups() {
    local command tmp body
    command="$(extract_probe_command)" || {
        fail "the probe command could not be read out of the service"
        return 0
    }

    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/home/caelestia-kde" "$tmp/config" "$tmp/cloned"
    printf '#!/usr/bin/env bash\n' > "$tmp/home/caelestia-kde/uninstall.sh"
    printf '#!/usr/bin/env bash\n' > "$tmp/cloned/uninstall.sh"
    printf '%s\n' "$tmp/cloned" > "$tmp/config/.checkout"

    body="$(sh -c "$command" -- "$tmp/home" "" "$tmp/config" pacman dnf apt-get 2>&1)"
    assert_contains "$body" "SCRIPT $tmp/home/caelestia-kde/uninstall.sh" \
        "~/caelestia-kde should win, because the uninstaller restores from its own backups/"
}

run_tests
