#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PAGES="$REPO_ROOT/shell/modules/nexus/Pages.qml"

test_every_load_takes_the_container() {
    local pages
    pages="$(cat "$PAGES")"

    assert_contains "$pages" "++loadGeneration" \
        "a load should claim the container"
    assert_contains "$pages" "generation !== loadGeneration" \
        "a page that incubates after a newer load should be recognised as superseded"
}

test_a_superseded_page_is_destroyed_rather_than_left_in_the_container() {
    local pages
    pages="$(cat "$PAGES")"

    assert_contains "$pages" "incubator.object.destroy()" \
        "the superseded page should be taken out, not left as a second page on top"
}

test_the_replaced_page_stops_drawing_before_it_is_deleted() {
    local pages
    pages="$(cat "$PAGES")"

    assert_contains "$pages" "currentItem.visible = false" \
        "destroy() is deferred, so the page being replaced must be hidden as well"
    assert_contains "$pages" "currentItem = null" \
        "and forgotten, so the next load cannot destroy it twice"
}

test_a_page_is_only_shown_once_it_is_the_current_one() {
    local pages
    pages="$(cat "$PAGES")"

    assert_contains "$pages" "visible: false" \
        "pages should incubate invisible, so an unfinished one cannot draw"
    assert_contains "$pages" "incubator.object.visible = true" \
        "and be shown when the load that owns the container attaches them"
}

run_tests