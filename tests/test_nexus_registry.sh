#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK="$REPO_ROOT/tools/check_nexus_registry.py"
REGISTRY="$REPO_ROOT/shell/modules/nexus/PageCompRegistry.qml"
STATE="$REPO_ROOT/shell/modules/nexus/NexusState.qml"
STACK="$REPO_ROOT/shell/modules/nexus/common/StackPage.qml"
WINDOW_FACTORY="$REPO_ROOT/shell/modules/nexus/WindowFactory.qml"
SHORTCUTS="$REPO_ROOT/shell/modules/Shortcuts.qml"
SEARCH_RESULTS="$REPO_ROOT/shell/modules/nexus/navpane/SearchResults.qml"

test_registry_integrity_and_unique_keys() {
    if ! command -v python3 >/dev/null 2>&1; then
        skip_test "python3 is not installed"
        return 0
    fi

    local output
    if ! output="$(cd "$REPO_ROOT" && python3 "$CHECK" 2>&1)"; then
        fail "PageCompRegistry integrity check failed: $output"
    fi
}

test_zero_numeric_slots_in_entire_shell() {
    local slot_refs
    slot_refs="$(cd "$REPO_ROOT" && git grep -nE "slotForKey|subPageIdx|defaultSlot|parentSlotFor|activeSubPageSlot|initialSubPageIdx" shell/ 2>/dev/null || true)"
    assert_eq "" "$slot_refs" \
        "no legacy slot or subPageIdx symbols should exist in shell/ (found: $slot_refs)"

    local int_open
    int_open="$(cd "$REPO_ROOT" && git grep -nE "openSubPage\([0-9]+" shell/ 2>/dev/null || true)"
    assert_eq "" "$int_open" \
        "openSubPage must take string keys, never integer slots (found: $int_open)"

    local int_goto
    int_goto="$(cd "$REPO_ROOT" && git grep -nE "goToSubPage\([0-9]+,\s*[0-9]+\)" shell/ 2>/dev/null || true)"
    assert_eq "" "$int_goto" \
        "goToSubPage must take string subpage keys, never integers (found: $int_goto)"
}

test_warm_reuse_race_condition_guard() {
    local state_content
    state_content="$(cat "$STATE")"

    assert_contains "$state_content" 'property string pendingSubPageKey: ""' \
        "NexusState must have pendingSubPageKey to stage incoming subpages across category swaps"

    assert_contains "$state_content" 'property string activeSubPageKey: ""' \
        "NexusState must track activeSubPageKey as a string"

    assert_contains "$state_content" 'property var subPageKeyStack: []' \
        "NexusState subpage stack must track string keys"

    local body
    body="$(sed -n '/function goToSubPage/,/^    }/p' "$STATE")"
    assert_contains "$body" 'pendingSubPageKey = subPageKey;' \
        "goToSubPage must stage pendingSubPageKey"

    assert_contains "$body" $'pendingSubPageKey = subPageKey;\n                currentPageIdx = pageIdx;' \
        "pendingSubPageKey must be staged before currentPageIdx in 2-panel mode"
}

test_stack_page_key_mapping_and_stack() {
    local stack_content state_content
    stack_content="$(cat "$STACK")"
    state_content="$(cat "$STATE")"

    assert_contains "$stack_content" 'pageMap[item.key] = item.component' \
        "StackPage must register component by item.key"

    assert_contains "$stack_content" 'function openSubPage(target: string, immediate: bool): void' \
        "StackPage.openSubPage must accept target: string"

    assert_contains "$state_content" 'subPageKeyStack.push(target)' \
        "NexusState.openSubPage must push string target onto subPageKeyStack"

    assert_contains "$state_content" 'activeSubPageKey = key' \
        "NexusState.selectSubCategory must update activeSubPageKey"
}

test_window_factory_declarative_contract() {
    local wf_content
    wf_content="$(cat "$WINDOW_FACTORY")"

    assert_contains "$wf_content" 'win.nexus.nState.goToSubPage(pageIdx, String(subPage))' \
        "WindowFactory must forward subpage as a string"

    assert_contains "$wf_content" 'state.subPageKeyStack.length > 0' \
        "WindowFactory.goBack must check subPageKeyStack length"

    assert_contains "$wf_content" 'resolvedProps.initialSubPage = PageRegistry.defaultSubPageForKey(key)' \
        "WindowFactory must resolve category key to default subpage key"
}

test_search_results_use_semantic_keys() {
    local sr_content
    sr_content="$(cat "$SEARCH_RESULTS")"

    assert_contains "$sr_content" 'root.nState.goToSubPage(entry.pageIdx, entry.subPage)' \
        "SearchResults executeSelected must navigate with entry.subPage"

    assert_contains "$sr_content" 'readonly property string subPage: modelData.subPage' \
        "SearchResults delegate must expose subPage as string"
}

test_ipc_shortcuts_forward_string_keys() {
    local sc_content
    sc_content="$(cat "$SHORTCUTS")"

    assert_contains "$sc_content" 'function openPage(pageKey: string, subPageKey: string): void' \
        "Shortcuts IPC handler must accept pageKey and subPageKey"

    assert_contains "$sc_content" 'initialSubPage: hasSubPage ? subPageKey : ""' \
        "Shortcuts IPC handler must pass initialSubPage string key"
}

run_tests
