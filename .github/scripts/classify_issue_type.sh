#!/usr/bin/env bash
#
# Classify an issue into one of the three type labels this repository uses:
# "bug", "feature", or "help me".
#
# Usage: classify_issue_type.sh "<issue title>"   # issue body on stdin
#
# The label is printed on stdout, the reason for it on stderr, so the workflow
# log explains every decision. The classifier never prints nothing: an issue
# without a type label drops out of every filtered view. Anything it cannot
# classify falls back to "help me".
#
# Signals, in priority order:
#
#   1. The ticked "Issue type" box from .github/ISSUE_TEMPLATE/1-issue.yml. That
#      is the reporter's own statement of intent, so it beats every guess below.
#   2. A tag in the title: "[Bug]", "[Feature request]", "[HELP]", "fix:", "feat:".
#      Issues filed through the API never carry the form's checkboxes - the title
#      is the only signal they have.
#   3. A keyword in the title ("crash", "not working", "add support for").
#   4. Fallback: "help me".
#
# Step 3 reads the title only, on purpose. Issue bodies are full of stack traces
# and log excerpts, where a word like "error" says nothing about the issue's type.

set -euo pipefail

LABEL_BUG="bug"
LABEL_FEATURE="feature"
LABEL_HELP="help me"

# The last label an issue can get. It exists so that no issue is left untyped,
# not because "help me" is a good description of an unreadable report.
LABEL_FALLBACK="$LABEL_HELP"

# The option text in .github/ISSUE_TEMPLATE/1-issue.yml, lowercased because the
# ticked lines are lowercased before matching. tests/test_issue_type_labeling.sh
# fails if the template and this script ever drift apart.
TEMPLATE_BUG_TEXT="bug - something is broken"
TEMPLATE_HELP_TEXT="help wanted - i need assistance"

emit() {
    printf '%s\n' "$1" >&2
    printf '%s\n' "$2"
    return 0
}

# The form options the reporter actually ticked, lowercased. Unchecked boxes
# ("- [ ]") are not a statement of intent, so they are dropped here.
checked_options() {
    local body="$1" lines
    lines="$(printf '%s\n' "$body" | grep -Ei '^[[:space:]]*[-*][[:space:]]*\[[xX]\]' || true)"
    printf '%s' "${lines,,}"
}

# Leading "[tag]", or "tag:" / "tag(scope):", lowercased. Prints nothing and
# fails when the title has no tag.
#
# No regex here on purpose: bash tokenizes ")" inside [[ =~ ]] as an operator,
# so a pattern like ^([a-z]+)(\([^)]*\))?: is a syntax error, not a match.
title_tag() {
    local title="$1" head

    if [[ "$title" == \[*\]* ]]; then
        head="${title#\[}"
        printf '%s' "${head%%\]*}"
        return 0
    fi

    if [[ "$title" == *:* ]]; then
        head="${title%%:*}"
        head="${head%%(*}"
        # A conventional-commit prefix is a bare lowercase word: "fix:", "feat(ui):".
        if [[ "$head" =~ ^[a-z]+$ ]]; then
            printf '%s' "$head"
            return 0
        fi
    fi

    return 1
}

# Maps a title tag to a label. Prints nothing and fails for tags that say
# nothing about the issue type, such as "critical", "i18n", or "installer".
label_for_tag() {
    case "$1" in
        bug | bugs | bugfix | defect | fix | fixes | regression | crash)
            printf '%s\n' "$LABEL_BUG"
            ;;
        feature | features | feat | enhancement | fr | request | "feature request")
            printf '%s\n' "$LABEL_FEATURE"
            ;;
        help | "help needed" | "help wanted" | question | support | assistance | "how to" | howto)
            printf '%s\n' "$LABEL_HELP"
            ;;
        *)
            return 1
            ;;
    esac
}

# Maps a title keyword to a label. Prints nothing and fails when the title says
# nothing usable.
label_for_title_keywords() {
    case "$1" in
        *crash* | *broken* | *broke* | *"not working"* | *"doesn't work"* | *"does not work"* | *"won't work"* | \
            *freeze* | *frozen* | *hang* | *fail* | *error* | *regression* | *stuck* | *"no longer"* | \
            *silently* | *flicker* | *unresponsive* | *segfault*)
            printf '%s\n' "$LABEL_BUG"
            ;;
        *"feature request"* | *enhancement* | *"please add"* | *"add support"* | *"support for"* | \
            *"would be nice"* | *"ability to"* | *"add a "* | *"add an "*)
            printf '%s\n' "$LABEL_FEATURE"
            ;;
        *"how do i"* | *"how to"* | *question* | *help*)
            printf '%s\n' "$LABEL_HELP"
            ;;
        *)
            return 1
            ;;
    esac
}

main() {
    if [[ $# -ne 1 ]]; then
        printf 'usage: %s "<issue title>"   # issue body on stdin\n' "${0##*/}" >&2
        return 2
    fi

    local title="${1,,}" body checked tag label
    body="$(cat)"
    checked="$(checked_options "$body")"

    if [[ "$checked" == *"$TEMPLATE_BUG_TEXT"* ]]; then
        emit "issue form: bug option ticked" "$LABEL_BUG"
        return 0
    fi

    if [[ "$checked" == *"$TEMPLATE_HELP_TEXT"* ]]; then
        emit "issue form: help option ticked" "$LABEL_HELP"
        return 0
    fi

    if tag="$(title_tag "$title")" && label="$(label_for_tag "$tag")"; then
        emit "title tag [$tag]" "$label"
        return 0
    fi

    if label="$(label_for_title_keywords "$title")"; then
        emit "title keyword" "$label"
        return 0
    fi

    emit "no signal: falling back so the issue is never left untyped" "$LABEL_FALLBACK"
}

main "$@"
