#!/usr/bin/env bash
# suite: isolated

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATER="$REPO_ROOT/src/bin/caelestia-update"
BUILD_SHELL="$REPO_ROOT/scripts/08-build-shell.sh"

FALLBACK_SOURCE="$(extract_function "$BUILD_SHELL" sparsify_checkout_paths)"
PREVIOUS=""
UPSTREAM_RULES=()
CURRENT_RULES=()
FALLBACK_RULES=()
FIXTURE_REMOTE=""

rules_written_by() {
    sed -n 's/.*echo "\([^"]*\)" >\+ \.git\/info\/sparse-checkout.*/\1/p' "$1"
}

fallback_rules() {
    sed -n 's/^[[:space:]]*sparsify_checkout_paths \(.*\)$/\1/p' "$BUILD_SHELL" | tr ' ' '\n' |
        sed '/^$/d'
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
    fail "could not find sparsify_checkout_paths in scripts/08-build-shell.sh"
    run_tests
    exit 1
fi

if ! resolve_previous; then
    PREVIOUS=""
elif [[ "${#CURRENT_RULES[@]}" -eq 0 || "${#FALLBACK_RULES[@]}" -eq 0 ]]; then
    fail "could not read the sparse rules from src/bin/caelestia-update or the repair from scripts/08-build-shell.sh"
    run_tests
    exit 1
fi

# The tree the release ships, as the remote an update fetches from.
ensure_fixture() {
    [[ -n "$FIXTURE_REMOTE" ]] && return 0

    local remote
    remote="$(new_tmpdir)/upstream"
    mkdir -p "$remote" || return 1
    git -C "$REPO_ROOT" archive HEAD | tar -x -C "$remote" || return 1
    git -C "$remote" init -q || return 1
    git -C "$remote" add -A || return 1
    git -C "$remote" -c user.name=fixture -c user.email=fixture@example.invalid \
        commit -qm fixture || return 1
    git -C "$remote" branch -M main || return 1

    FIXTURE_REMOTE="$remote"
}

# A checkout holding exactly what the rules passed in select, which is what the updater of
# the release that wrote them leaves behind.
seed_checkout() {
    local repo="$1"
    shift

    git init -q "$repo" || return 1
    git -C "$repo" remote add origin "$FIXTURE_REMOTE" || return 1
    git -C "$repo" config core.sparseCheckout true || return 1
    printf '%s\n' "$@" > "$repo/.git/info/sparse-checkout" || return 1
    git -C "$repo" fetch -q --depth 1 origin main || return 1
    git -C "$repo" reset --hard -q FETCH_HEAD || return 1
}

run_repair() {
    BUNDLE_DIR="$1" bash -c "set -euo pipefail
${FALLBACK_SOURCE}
sparsify_checkout_paths \"\$@\"" -- "${FALLBACK_RULES[@]}" 2>&1
}

test_a_rule_this_release_adds_is_one_the_repair_covers() {
    [[ -n "$PREVIOUS" ]] || return 0

    local rule missing=""
    while IFS= read -r rule; do
        printf '%s\n' "${FALLBACK_RULES[@]}" | grep -qxF "$rule" || missing="$missing $rule"
    done < <(new_rules)

    [[ -z "$missing" ]] || fail \
        "this release sparsifies$missing and $PREVIOUS's updater never writes them, so an install still on $PREVIOUS starts the update without them: name them in sparsify_checkout_paths in scripts/08-build-shell.sh"
}

test_the_repair_fills_what_a_checkout_on_the_previous_release_lacks() {
    [[ -n "$PREVIOUS" ]] || return 0

    local repo rule path absent=""
    ensure_fixture || {
        fail "could not build the fixture repository"
        return 0
    }
    repo="$(new_tmpdir)/repo"
    seed_checkout "$repo" "${UPSTREAM_RULES[@]}" || {
        fail "could not create the fixture checkout"
        return 0
    }

    while IFS= read -r rule; do
        assert_file_missing "$repo/${rule%/}"
    done < <(new_rules)

    run_repair "$repo" >/dev/null

    while IFS= read -r rule; do
        path="$repo/${rule%/}"
        if [[ -d "$path" ]]; then
            [[ -n "$(ls -A -- "$path")" ]] || fail "the repair left $rule with nothing in it"
        else
            assert_file_exists "$path"
        fi
    done < <(new_rules)

    for rule in "${CURRENT_RULES[@]}"; do
        [[ -e "$repo/${rule%/}" ]] || absent="$absent $rule"
    done
    [[ -z "$absent" ]] || fail "a checkout that started on $PREVIOUS still lacks$absent"

    assert_file_exists "$repo/assets/org.quickshell.desktop"
}

test_the_repair_keeps_what_the_previous_release_already_had() {
    [[ -n "$PREVIOUS" ]] || return 0

    local repo rule missing=""
    ensure_fixture || {
        fail "could not build the fixture repository"
        return 0
    }
    repo="$(new_tmpdir)/repo"
    seed_checkout "$repo" "${UPSTREAM_RULES[@]}" || {
        fail "could not create the fixture checkout"
        return 0
    }

    run_repair "$repo" >/dev/null

    for rule in "${UPSTREAM_RULES[@]}"; do
        [[ -e "$repo/${rule%/}" ]] || missing="$missing $rule"
    done
    [[ -z "$missing" ]] || fail "the repair dropped what $PREVIOUS's rules already selected:$missing"

    assert_file_exists "$repo/scripts/08-build-shell.sh"
    assert_file_exists "$repo/shell/CMakeLists.txt"
}

run_tests
