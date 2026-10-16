#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The rule that gives a fresh install five virtual desktops lives in the crate now, and the
# crate tests its decision table (installer/src/steps/mod.rs, steps.rs). What is left here is
# the wiring: which steps apply it, and that the update path reaches one of them.

test_both_steps_that_apply_the_rule_are_native() {
    local step
    for step in services system_tweaks; do
        local file="$REPO_ROOT/installer/src/steps/$step.rs"
        assert_file_exists "$file" "$step should be a native step"
        assert_file_contains "$file" "ensure_five_desktops" \
            "$step should apply the shared desktop rule"
    done

    assert_file_contains "$REPO_ROOT/installer/src/steps/mod.rs" "fn ensure_five_desktops" \
        "the rule itself should be shared, not written twice"
}

test_the_update_path_reaches_the_rule_through_a_step() {
    assert_file_contains "$REPO_ROOT/installer/src/update.rs" '("09-system-tweaks", false)' \
        "an update re-applies the tweaks step, which applies the rule"
    assert_file_contains "$REPO_ROOT/installer/src/steps/build_shell.rs" 'run_step(context, "06-services")' \
        "building the shell re-applies the services step"
    assert_file_contains "$REPO_ROOT/src/bin/caelestia-update" "run_step 3600 08-build-shell" \
        "and a packaged update reaches both by building the shell"
}

test_the_shell_helper_is_gone_with_its_callers() {
    assert_file_missing "$REPO_ROOT/scripts/lib/virtual-desktops.sh" \
        "the shell helper has no caller left, so it should not be carried"
}

test_the_install_entries_mark_the_run_and_the_update_does_not() {
    assert_contains "$(cat "$REPO_ROOT/installer/src/app.rs")" \
        '("CAELESTIA_FRESH_INSTALL", "1"' \
        "the TUI installer should mark the run it runs the steps for"
    assert_contains "$(cat "$REPO_ROOT/src/bin/caelestia")" \
        'CAELESTIA_FRESH_INSTALL="${CAELESTIA_FRESH_INSTALL:-1}"' \
        "a packaged install should mark the run"
    assert_contains "$(cat "$REPO_ROOT/src/bin/caelestia-update")" \
        'CAELESTIA_FRESH_INSTALL=0' \
        "the updater re-applying a packaged install must not mark it"
}

run_tests