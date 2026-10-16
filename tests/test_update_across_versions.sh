#!/usr/bin/env bash
# suite: isolated

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATER="$REPO_ROOT/src/bin/caelestia-update"
BUILD_SHELL="$REPO_ROOT/installer/src/steps/build_shell.rs"

FALLBACK_SOURCE="$(awk '/^const SPARSIFY/{found=1} found{print} found&&/\];/{exit}' "$BUILD_SHELL")"
PREVIOUS=""
UPSTREAM_RULES=()
CURRENT_RULES=()
FALLBACK_RULES=()

rules_written_by() {
    sed -n 's/.*echo "\([^"]*\)" >\+ \.git\/info\/sparse-checkout.*/\1/p' "$1"
}

fallback_rules() {
    printf '%s\n' "$FALLBACK_SOURCE" | grep -o '"[^"]*"' | tr -d '"'
}

# The release an install updating to this tree is coming from. The version being
# released cannot be a tag yet, so the newest tag the branch carries is the one before it.
previous_release() {
    local current
    current="$(sed -nE 's/^[[:space:]]*VERSION=//p' "$REPO_ROOT/.github/version.env" 2>/dev/null | tr -d '[:space:]')"
    git -C "$REPO_ROOT" tag --sort=-v:refname --list 'v*' --merged HEAD 2>/dev/null |
        grep -vx "$current" | head -n 1
}

# The rules this release writes that the release before it did not: what an install still
# on that release is missing from its checkout.
new_rules() {
    local rule
    for rule in "${CURRENT_RULES[@]}"; do
        printf '%s\n' "${UPSTREAM_RULES[@]}" | grep -qxF "$rule" || printf '%s\n' "$rule"
    done
}

resolve_previous() {
    local updater rule

    command -v git >/dev/null 2>&1 || {
        skip_test "git is not installed"
        return 1
    }

    PREVIOUS="$(previous_release)"
    [[ -n "$PREVIOUS" ]] || {
        skip_test "no earlier release tag is reachable here, so there is no prior version to update from"
        return 1
    }

    updater="$(new_tmpdir)/caelestia-update"
    git -C "$REPO_ROOT" show "$PREVIOUS:src/bin/caelestia-update" > "$updater" 2>/dev/null || {
        skip_test "$PREVIOUS ships no src/bin/caelestia-update to read its rules from"
        PREVIOUS=""
        return 1
    }

    while IFS= read -r rule; do
        UPSTREAM_RULES+=("$rule")
    done < <(rules_written_by "$updater")
    while IFS= read -r rule; do
        CURRENT_RULES+=("$rule")
    done < <(rules_written_by "$UPDATER")
    while IFS= read -r rule; do
        FALLBACK_RULES+=("$rule")
    done < <(fallback_rules)
    return 0
}

if [[ -z "$FALLBACK_SOURCE" ]]; then
    fail "could not find the SPARSIFY rules in installer/src/steps/build_shell.rs"
    run_tests
    exit 1
fi

if ! resolve_previous; then
    PREVIOUS=""
elif [[ "${#CURRENT_RULES[@]}" -eq 0 || "${#FALLBACK_RULES[@]}" -eq 0 ]]; then
    fail "could not read the sparse rules from src/bin/caelestia-update or the repair from installer/src/steps/build_shell.rs"
    run_tests
    exit 1
fi

test_a_rule_this_release_adds_is_one_the_repair_covers() {
    [[ -n "$PREVIOUS" ]] || return 0

    local rule missing=""
    while IFS= read -r rule; do
        printf '%s\n' "${FALLBACK_RULES[@]}" | grep -qxF "$rule" || missing="$missing $rule"
    done < <(new_rules)

    [[ -z "$missing" ]] || fail \
        "this release sparsifies$missing and $PREVIOUS's updater never writes them, so an install still on $PREVIOUS starts the update without them: name them in SPARSIFY in installer/src/steps/build_shell.rs"
}

# A checkout on the previous release lacks every rule this one adds, and SPARSIFY is what the
# repair reads, so each rule has to name a path the release actually ships. What the repair
# then does with them is covered by the crate test
# the_repair_fills_what_a_sparse_checkout_left_out, against a checkout it seeds itself.
test_the_paths_the_repair_fetches_are_the_ones_the_tree_ships() {
    local rule path absent=""
    for rule in "${FALLBACK_RULES[@]}"; do
        path="$REPO_ROOT/${rule%/}"
        [[ -e "$path" ]] || absent="$absent ${rule%/}"
    done
    [[ -z "$absent" ]] || fail "SPARSIFY names paths this tree does not ship:$absent"

    for rule in "${CURRENT_RULES[@]}"; do
        [[ -e "$REPO_ROOT/${rule%/}" ]] || absent="$absent ${rule%/}"
    done
    [[ -z "$absent" ]] || fail "the updater sparsifies paths this tree does not ship:$absent"

    assert_file_exists "$REPO_ROOT/installer/src/steps/build_shell.rs"
    assert_file_exists "$REPO_ROOT/shell/CMakeLists.txt"
}

run_tests
