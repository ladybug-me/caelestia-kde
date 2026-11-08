#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$REPO_ROOT/scripts/lib/escape.sh"

# The escaper counts characters, so a locale name is not enough: this shell can
# report UTF-8 while still counting bytes. Ask it with a two-byte character.
locale_is_utf8() {
    local probe
    probe=$(printf '\303\251') # é in UTF-8
    [[ ${#probe} -eq 1 ]]
}

test_a_plain_path_is_left_alone() {
    assert_eq "file:///home/u/walls/a-b.png" "$(js_string 'file:///home/u/walls/a-b.png')" "an ordinary path should pass through unchanged"
}

test_quoting_characters_become_escapes() {
    assert_eq 'file:///home/u/a\u0027b.jpg' "$(js_string "file:///home/u/a'b.jpg")" "an apostrophe should become an escape"
    assert_eq 'x\u0022y' "$(js_string 'x"y')" "a double quote should become an escape"
    assert_eq 'x\u005cy' "$(js_string 'x\y')" "a backslash should become an escape"
    assert_eq 'a\u000ab' "$(js_string $'a\nb')" "a newline should become an escape"
}

test_nothing_the_next_two_layers_read_survives() {
    local attack escaped
    attack='a'"'"'b"c$HOME`id`$(touch /tmp/x)'$'\n'"d"
    escaped="$(js_string "$attack")"

    local ch
    for ch in "'" '"' '$' '`' $'\n'; do
        assert_not_contains "$escaped" "$ch" "the escaped output must not contain $(printf '%q' "$ch")"
    done

    assert_eq 'a\u0027b\u0022c\u0024HOME\u0060id\u0060\u0024\u0028touch\u0020/tmp/x\u0029\u000ad' "$escaped" "every character outside the safe set should be escaped"
}

test_a_quote_in_a_name_cannot_end_the_literal() {
    local escaped
    escaped="$(js_string "file:///home/u/it's here.png")"

    assert_eq "file:///home/u/it\\u0027s\\u0020here.png" "$escaped" "the space and the apostrophe should both be escaped"
    assert_not_contains "$escaped" "'" "the literal must still be able to be wrapped in single quotes"
}

test_non_ascii_keeps_its_code_point() {
    if ! locale_is_utf8; then
        skip_test "byte locale: code points below are escaped per byte instead"
        return 0
    fi

    assert_eq 'caf\u00e9.png' "$(js_string 'café.png')" "an accented character should keep its code point"
}

test_astral_characters_become_a_surrogate_pair() {
    if ! locale_is_utf8; then
        skip_test "byte locale: code points below are escaped per byte instead"
        return 0
    fi

    assert_eq 'wall\ud83c\udf0d.png' "$(js_string 'wall🌍.png')" "an astral character should become a surrogate pair"
}

test_a_sed_replacement_keeps_a_plain_path() {
    assert_eq "/home/u/walls/a-b.png" "$(sed_replacement '/home/u/walls/a-b.png')" "an ordinary path should pass through unchanged"
}

test_a_sed_replacement_escapes_what_sed_reads() {
    assert_eq 'a\&b' "$(sed_replacement 'a&b')" "an ampersand means the whole match and must be escaped"
    assert_eq 'a\|b' "$(sed_replacement 'a|b')" "the delimiter must be escaped"
    assert_eq 'a\\b' "$(sed_replacement 'a\b')" "a backslash must be doubled"
}

test_a_sed_replacement_refuses_a_line_break() {
    if sed_replacement $'a\nb' >/dev/null; then
        fail "a newline in a replacement should be refused, not escaped"
    fi
    if sed_replacement $'a\rb' >/dev/null; then
        fail "a carriage return in a replacement should be refused, not escaped"
    fi
}

run_tests
