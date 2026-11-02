#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EMOJI_CPP="$REPO_ROOT/shell/plugin/src/Caelestia/Services/emojidb.cpp"

test_kde_emoji_dict_loads_base_en_dict_before_regional_delta() {
    local content
    content="$(cat "$EMOJI_CPP")"
    assert_contains "$content" 'kdeDir + QStringLiteral("/en.dict")' \
        "EmojiDb must always include base en.dict in load order"
    assert_not_contains "$content" 'for (const auto& path : kdeCandidates)' \
        "EmojiDb must not pick a single candidate from kdeCandidates and break early"
}

test_kde_emoji_dict_merges_without_overwriting_or_discarding_database() {
    local content
    content="$(cat "$EMOJI_CPP")"
    assert_contains "$content" 'charMap.find(entry.ch)' \
        "EmojiDb must merge entries by character rather than overwriting the whole list"
}

test_emoji_search_ranks_by_relevance_and_frequency() {
    local content
    content="$(cat "$EMOJI_CPP")"
    assert_contains "$content" 'emojiMatchScore' \
        "EmojiDb must score candidates by relevance"
    assert_contains "$content" 'std::partial_sort(scored.begin()' \
        "EmojiDb must sort matched indices by score, favourites, and frequency"
}

run_tests
