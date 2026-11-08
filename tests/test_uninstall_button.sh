#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE="$REPO_ROOT/shell/services/Uninstaller.qml"
DIALOG="$REPO_ROOT/shell/modules/nexus/common/UninstallDialog.qml"
FRAME="$REPO_ROOT/shell/modules/nexus/common/NexusDialog.qml"
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

# A checkout as the probe expects to find one: the uninstaller plus the step scripts that
# make it this project rather than any directory someone pointed the record at. $2 is the
# origin the clone records, and "none" leaves the directory without a repository at all.
make_checkout() {
    local dir="$1" origin="${2-https://github.com/ladybug-me/caelestia-kde.git}"
    mkdir -p "$dir/scripts"
    printf '#!/usr/bin/env bash\n' > "$dir/uninstall.sh"
    printf '#!/usr/bin/env bash\n' > "$dir/scripts/setup.sh"
    [[ "$origin" == none ]] && return 0
    git -C "$dir" init -q
    git -C "$dir" remote add origin "$origin"
}

require_git() {
    if command -v git >/dev/null 2>&1; then
        return 0
    fi
    skip_test "git is not installed"
    return 1
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
    local dialog frame
    dialog="$(cat "$DIALOG")"
    frame="$(cat "$FRAME")"

    assert_contains "$dialog" "NexusDialog {" \
        "the dialog is the shared frame plus what the uninstaller found"
    assert_contains "$dialog" "property string state" \
        "it should take the uninstaller state as a property"
    assert_contains "$frame" "signal confirmed" \
        "the frame reports confirmation rather than launching itself"
    assert_contains "$dialog" "confirmText: root.canRun" \
        "the run button should follow what was found"
    assert_contains "$frame" 'visible: root.confirmText !== ""' \
        "and the frame hides it when nothing can run"
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
    require_git || return 0

    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/home" "$tmp/config"

    make_checkout "$tmp/checkout"
    body="$(sh -c "$command" -- "$tmp/home" "$tmp/checkout" "$tmp/config" pacman dnf apt-get 2>&1)"
    assert_contains "$body" "SCRIPT $tmp/checkout/uninstall.sh" \
        "an explicit checkout should be reported"
    assert_not_contains "$body" "PACKAGE" "no manager should be reported when a script was found"

    make_checkout "$tmp/home/caelestia-kde"
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
    require_git || return 0

    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/home" "$tmp/config" "$tmp/cloned/caelestia-kwin"
    make_checkout "$tmp/cloned/caelestia-kwin"
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
    require_git || return 0

    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/home/caelestia-kde" "$tmp/config"
    make_checkout "$tmp/home/caelestia-kde"
    make_checkout "$tmp/cloned"
    printf '%s\n' "$tmp/cloned" > "$tmp/config/.checkout"

    body="$(sh -c "$command" -- "$tmp/home" "" "$tmp/config" pacman dnf apt-get 2>&1)"
    assert_contains "$body" "SCRIPT $tmp/home/caelestia-kde/uninstall.sh" \
        "~/caelestia-kde should win, because the uninstaller restores from its own backups/"
}

test_the_probe_ignores_a_directory_that_is_not_this_project() {
    local command tmp body
    command="$(extract_probe_command)" || {
        fail "the probe command could not be read out of the service"
        return 0
    }

    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/home" "$tmp/config" "$tmp/stray"
    printf '#!/usr/bin/env bash\n' > "$tmp/stray/uninstall.sh"
    printf '%s\n' "$tmp/stray" > "$tmp/config/.checkout"

    body="$(sh -c "$command" -- "$tmp/home" "" "$tmp/config" pacman dnf apt-get 2>&1)"
    assert_contains "$body" "UNKNOWN" \
        "an uninstall.sh in a directory that is not this project is not something to run as root"
}

test_the_probe_ignores_a_linked_uninstaller() {
    local command tmp body
    command="$(extract_probe_command)" || {
        fail "the probe command could not be read out of the service"
        return 0
    }

    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/home" "$tmp/config" "$tmp/linked/scripts"
    printf '#!/usr/bin/env bash\n' > "$tmp/linked/scripts/setup.sh"
    ln -s /bin/true "$tmp/linked/uninstall.sh"
    printf '%s\n' "$tmp/linked" > "$tmp/config/.checkout"

    body="$(sh -c "$command" -- "$tmp/home" "" "$tmp/config" pacman dnf apt-get 2>&1)"
    assert_contains "$body" "UNKNOWN" \
        "a link there would run whatever it points at, which is the whole problem"
}

test_the_probe_refuses_a_recorded_directory_that_is_not_a_clone() {
    # Writing the record is nothing more than editing a file in the user's own config, so
    # the two script names alone must not be enough to get something run as root.
    local command tmp body
    command="$(extract_probe_command)" || {
        fail "the probe command could not be read out of the service"
        return 0
    }
    require_git || return 0

    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/home" "$tmp/config"
    make_checkout "$tmp/scratch" none
    printf '%s\n' "$tmp/scratch" > "$tmp/config/.checkout"

    body="$(sh -c "$command" -- "$tmp/home" "" "$tmp/config" pacman dnf apt-get 2>&1)"
    assert_contains "$body" "UNKNOWN" \
        "a directory with no repository behind it is not a checkout of this project"
}

test_the_probe_refuses_a_recorded_clone_of_another_project() {
    local command tmp body origin
    command="$(extract_probe_command)" || {
        fail "the probe command could not be read out of the service"
        return 0
    }
    require_git || return 0

    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/home" "$tmp/config"
    for origin in \
        "https://github.com/someone/not-caelestia.git" \
        "https://github.com/someone/caelestia-kde-tools.git" \
        "git@github.com:someone/caelestia-kde.git"; do
        rm -rf "$tmp/cloned"
        make_checkout "$tmp/cloned" "$origin"
        printf '%s\n' "$tmp/cloned" > "$tmp/config/.checkout"

        body="$(sh -c "$command" -- "$tmp/home" "" "$tmp/config" pacman dnf apt-get 2>&1)"
        assert_contains "$body" "UNKNOWN" \
            "'$origin' is another project, and its scripts are not the ones to run as root"
    done
}

test_the_probe_accepts_a_recorded_clone_of_this_project() {
    local command tmp body origin
    command="$(extract_probe_command)" || {
        fail "the probe command could not be read out of the service"
        return 0
    }
    require_git || return 0

    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/home" "$tmp/config"
    for origin in \
        "https://github.com/ladybug-me/caelestia-kde.git" \
        "https://github.com/ladybug-me/caelestia-kde" \
        "https://github.com/caelestia-kde/caelestia.git" \
        "https://github.com/ladybug-me/caelestia-kde.git/" \
        "git@github.com:ladybug-me/caelestia-kde.git" \
        "git@github.com:caelestia-kde/caelestia.git"; do
        rm -rf "$tmp/cloned"
        make_checkout "$tmp/cloned" "$origin"
        printf '%s\n' "$tmp/cloned" > "$tmp/config/.checkout"

        body="$(sh -c "$command" -- "$tmp/home" "" "$tmp/config" pacman dnf apt-get 2>&1)"
        assert_contains "$body" "SCRIPT $tmp/cloned/uninstall.sh" \
            "'$origin' names this project, so the checkout it records is the one to use"
    done
}

test_the_probe_accepts_a_clone_its_remote_is_rewritten_from() {
    # The updater's end-to-end fixture rewrites the GitHub address to a local mirror with
    # url.<base>.insteadOf, so `remote get-url` answers with the mirror. What was cloned is
    # still this project.
    local command tmp body
    command="$(extract_probe_command)" || {
        fail "the probe command could not be read out of the service"
        return 0
    }
    require_git || return 0

    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/home" "$tmp/config" "$tmp/mirror"
    make_checkout "$tmp/cloned"
    git -C "$tmp/cloned" config "url.$tmp/mirror.insteadOf" "https://github.com/ladybug-me/caelestia-kde.git"
    assert_eq "$tmp/mirror" "$(git -C "$tmp/cloned" remote get-url origin)" \
        "the rewrite has to be in effect, or this test proves nothing"
    printf '%s\n' "$tmp/cloned" > "$tmp/config/.checkout"

    body="$(sh -c "$command" -- "$tmp/home" "" "$tmp/config" pacman dnf apt-get 2>&1)"
    assert_contains "$body" "SCRIPT $tmp/cloned/uninstall.sh" \
        "a mirror of this project is this project"
}

test_the_probe_does_not_need_git_to_find_a_package_install() {
    # The probe runs on every About page visit, and git is not a dependency of the shell.
    local command tmp body
    command="$(extract_probe_command)" || {
        fail "the probe command could not be read out of the service"
        return 0
    }

    tmp="$(new_tmpdir)"
    mkdir -p "$tmp/home" "$tmp/config" "$tmp/scratch/scripts" "$tmp/bin"
    printf '#!/usr/bin/env bash\n' > "$tmp/scratch/uninstall.sh"
    printf '#!/usr/bin/env bash\n' > "$tmp/scratch/scripts/setup.sh"
    printf '%s\n' "$tmp/scratch" > "$tmp/config/.checkout"

    # A PATH with no git in it, but with the two tools the probe itself reads the record
    # with, so it can still reach the recorded path and answer for it.
    ln -sf "$(command -v sh)" "$tmp/bin/sh"
    ln -sf "$(command -v cat)" "$tmp/bin/cat"
    stub_bin "$tmp/bin" pacman 'exit 1'

    body="$(PATH="$tmp/bin" sh -c "$command" -- "$tmp/home" "" "$tmp/config" pacman 2>&1)"
    assert_contains "$body" "UNKNOWN" \
        "without git the recorded checkout cannot be proven, and the probe still finishes"
}

run_tests
