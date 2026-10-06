#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/lib/selection.sh"

indices_of() {
    local count="$1" input="$2"
    select_indices "$count" "$input" | sort -n
}

test_a_single_number_picks_that_one_entry() {
    assert_eq "0" "$(indices_of 4 '1')" "1 should pick the first entry"
    assert_eq "2" "$(indices_of 4 '3')" "3 should pick the third entry"
    assert_eq "3" "$(indices_of 4 '4')" "the last entry should be reachable"
}

test_several_numbers_pick_several_entries() {
    assert_eq "$(printf '0\n2\n')" "$(indices_of 4 '1 3')" "a space-separated list should pick each one"
    assert_eq "$(printf '0\n1\n')" "$(indices_of 4 '1,2')" "a comma-separated list should pick each one"
}

test_a_range_expands_inclusively() {
    assert_eq "$(printf '0\n1\n2\n')" "$(indices_of 4 '1-3')" "1-3 should pick the first three"
    assert_eq "1" "$(indices_of 4 '2-2')" "a one-wide range should pick that entry"
    assert_eq "3" "$(indices_of 4 '4-9')" "a range past the end should stop at the last entry"
}

test_out_of_range_and_junk_are_dropped_without_picking_anything() {
    assert_eq "" "$(indices_of 4 '999')" "a number past the end should not pick anything"
    assert_eq "" "$(indices_of 4 '0')" "0 is not an entry"
    assert_eq "" "$(indices_of 4 'abc')" "a word should not pick anything"
    assert_eq "" "$(indices_of 4 '-1')" "a negative number should not pick anything"
    assert_eq "" "$(indices_of 4 '1-')" "a half-written range should not pick anything"
    assert_eq "" "$(indices_of 4 '')" "an empty answer should not pick anything"
    assert_eq "" "$(indices_of 4 '   ')" "whitespace alone should not pick anything"
}

test_a_bad_token_does_not_discard_the_good_ones() {
    assert_eq "$(printf '0\n2\n')" "$(indices_of 4 '1 nope 3')" "the valid tokens should still be picked"
}

test_the_output_has_no_duplicates() {
    assert_eq "0" "$(indices_of 4 '1 1')" "the same number twice should pick one entry"
    assert_eq "$(printf '0\n1\n2\n')" "$(indices_of 4 '1-3 2')" "a number inside a range should not repeat"
    assert_eq "$(printf '0\n1\n2\n')" "$(indices_of 4 '1 1-3 2-2 3')" "overlapping spellings should still collapse"
}

test_whitespace_and_case_do_not_matter() {
    assert_eq "$(printf '0\n2\n')" "$(indices_of 4 '  1   3  ')" "surrounding spaces should be ignored"
    assert_eq "$(printf '0\n1\n')" "$(indices_of 4 $'1\t2')" "a tab should separate tokens like a space"
}

test_a_zero_count_has_nothing_to_pick() {
    assert_eq "" "$(indices_of 0 '1')" "there is no entry to pick when the list is empty"
    assert_eq "" "$(indices_of 0 '1-3')" "nor for a range"
}

run_tests
