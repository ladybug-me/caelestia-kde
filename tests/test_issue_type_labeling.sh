#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLASSIFY="$REPO_ROOT/.github/scripts/classify_issue_type.sh"
ISSUE_FORM="$REPO_ROOT/.github/ISSUE_TEMPLATE/1-issue.yml"
WORKFLOW="$REPO_ROOT/.github/workflows/label-issue-type.yml"

# Mirrors how the workflow calls it: title as an argument, body on stdin.
classify() {
    local title="$1" body="${2:-}"
    printf '%s\n' "$body" | bash "$CLASSIFY" "$title" 2>/dev/null
}

TYPED_LABELS=("bug" "feature" "help me")

assert_typed() {
    local label="$1" title="$2"
    local known
    for known in "${TYPED_LABELS[@]}"; do
        [[ "$label" == "$known" ]] && return 0
    done
    fail "issue was left without a type label (title: $(printf '%q' "$title"))"
}

test_form_bug_option_labels_bug() {
    local body label

    body='### Issue type

- [X] Bug - something is broken or not working correctly
- [ ] Help wanted - I need assistance with configuration, setup, or usage'

    label="$(classify "Something went wrong" "$body")"
    assert_eq "bug" "$label" "a ticked bug option should be labelled bug"
}

test_form_help_option_labels_help_me() {
    local body label

    body='### Issue type

- [ ] Bug - something is broken or not working correctly
- [X] Help wanted - I need assistance with configuration, setup, or usage'

    label="$(classify "How do I set a wallpaper" "$body")"
    assert_eq "help me" "$label" "a ticked help option should be labelled help me"
}

test_form_option_match_ignores_case_and_spacing() {
    local label

    label="$(classify "Something went wrong" "-  [x]  bug - something is broken or not working correctly")"
    assert_eq "bug" "$label" "the box form should not have to match the template byte for byte"
}

test_unticked_form_options_are_not_a_signal() {
    local body label

    body='- [ ] Bug - something is broken or not working correctly
- [ ] Help wanted - I need assistance with configuration, setup, or usage'

    label="$(classify "Ambient color mode" "$body")"
    assert_typed "$label" "Ambient color mode"
    assert_ne "bug" "$label" "an unticked bug box is not a bug report"
}

# #740: filed through the API, so it carries no form checkboxes at all. The
# title is the only signal and it has to be enough.
test_free_form_bug_report_with_a_title_prefix_is_labelled_bug() {
    local body label

    body='## Symptom

The Show Desktop button in the bar intermittently does nothing.

## Root cause

`ShowDesktop.qml` triggers it through a subprocess.'

    label="$(classify "[Bug] Show Desktop bar button unreliable" "$body")"
    assert_eq "bug" "$label" "a [Bug] title should be enough without the form"
}

test_title_prefix_is_case_insensitive() {
    assert_eq "bug" "$(classify "[BUG] Lock screen stays black" "")" "[BUG] should match"
    assert_eq "feature" "$(classify "[Feature] Add Russian language support" "")" "[Feature] should match"
    assert_eq "help me" "$(classify "[HELP] KDE native shortcuts editing" "")" "[HELP] should match"
}

test_feature_request_title_prefix_labels_feature() {
    assert_eq "feature" "$(classify "[Feature request] lock.enableWeather config toggle" "")" \
        "[Feature request] should match"
    assert_eq "feature" "$(classify "[Enhancement] Per monitor task bar position" "")" \
        "[Enhancement] should match"
}

test_conventional_commit_prefixes_are_recognized() {
    assert_eq "bug" "$(classify "fix: dock icon leaves the window hidden" "")" "fix: should match"
    assert_eq "feature" "$(classify "feat: add a YAML config exporter" "")" "feat: should match"
    assert_eq "feature" "$(classify "feat(bar): per monitor positioning" "")" "feat(scope): should match"
}

# A tag that says nothing about the type (severity, subsystem) must not swallow
# the title: the keyword pass still gets a chance.
test_unmappable_title_tag_falls_through_to_keywords() {
    assert_eq "bug" "$(classify "[CRITICAL] Shell crashes on login" "")" \
        "an unmapped tag should fall through to the keyword pass"
}

test_bug_keywords_in_the_title_label_bug() {
    local title
    while IFS= read -r title; do
        assert_eq "bug" "$(classify "$title" "")" "expected bug for: $title"
    done <<'TITLES'
The launcher freezes when I type "terminal"
Update fails halfway through the download
Wallpaper is broken after the update
Speech dispatcher is no longer started on login
The dock is stuck behind a fullscreen window
TITLES
}

# Bodies are full of stack traces, so the keyword pass reads titles only. This
# keeps a calm feature request from being read as a bug report.
test_words_in_the_body_do_not_decide_the_type() {
    local label

    label="$(classify "Ambient color mode" 'Stack trace:
error: the module crashed while loading
this is broken and it fails')"

    assert_typed "$label" "Ambient color mode"
    assert_ne "bug" "$label" "a body full of error text should not decide the type"
}

test_every_issue_gets_a_type_label() {
    local title label

    while IFS= read -r title; do
        label="$(classify "$title" "")"
        assert_typed "$label" "$title"
    done <<'TITLES'
Help
Ambient color mode
Lock Screen Issue
i18n: shortcut names are not localized
Sidebar disappearing on second monitor when playing videos
[Refactor] Move the bar into its own service
[CRITICAL] libcava not compiled in pre-built shell asset
Community discord at 1k!
Create a website for the kde port
TITLES
}

# The classifier matches the form's option text by hand. If someone rewords the
# template, the form path silently stops working, so fail loudly here instead.
test_issue_form_still_contains_the_option_text_the_classifier_matches() {
    local form
    form="$(cat "$ISSUE_FORM")"

    assert_contains "$form" "Bug - something is broken" \
        "the form's bug option text changed; update TEMPLATE_BUG_TEXT"
    assert_contains "$form" "Help wanted - I need assistance" \
        "the form's help option text changed; update TEMPLATE_HELP_TEXT"
}

test_workflow_uses_the_classifier() {
    local workflow
    workflow="$(cat "$WORKFLOW")"

    assert_contains "$workflow" "classify_issue_type.sh" \
        "the workflow should classify through .github/scripts/classify_issue_type.sh"
    assert_contains "$workflow" "--add-label" "the workflow should still apply the label"
    assert_contains "$workflow" "types: [opened, edited]" \
        "issues filed through the API are edited into shape after the fact"
}

run_tests
