#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/04a-window-rules.sh"
UNINSTALL_SCRIPT="$REPO_ROOT/uninstall.sh"
BASH_BIN="$(command -v bash || printf '/bin/bash')"

# The stubs that stand in for the two config tools are Python, so this file skips
# rather than fails where python3 is absent. Only bash is required to run the suite.
have_python() {
    if command -v python3 >/dev/null 2>&1; then
        return 0
    fi
    skip_test "python3 not installed"
    return 1
}

RULES_FILE="kwinrulesrc"
RULE_GROUPS=(caelestia-opacity caelestia-dialogs caelestia-pip)
# The index a fresh file has to end up with: our three groups, in the order the
# script writes them, and no other name.
FRESH_INDEX="caelestia-opacity,caelestia-dialogs,caelestia-pip"

SANDBOX=""
STUB_DIR=""
BARE_DIR=""
CALLS=""
FAKE=""
OUTPUT=""
STATUS=0

# The two config tools share one plain ini file: kwriteconfig6 rewrites it and
# kreadconfig6 answers from it, so the script's "is this value already in place"
# comparison is exercised for real instead of being answered from a fixture.
write_fake_config_tools() {
    cat > "$FAKE" <<'PY'
"""Minimal kwinrulesrc reader and writer, standing in for the two config tools."""

import sys
from pathlib import Path


def arguments(argv):
    values = {"file": "kwinrulesrc", "group": "", "key": ""}
    positional = []
    index = 0
    while index < len(argv):
        argument = argv[index]
        if argument in ("--file", "--group", "--key") and index + 1 < len(argv):
            values[argument[2:]] = argv[index + 1]
            index += 2
        else:
            positional.append(argument)
            index += 1
    return values, positional


def read(path):
    sections = {}
    current = None
    if not path.is_file():
        return sections
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line or line.startswith(("#", ";")):
            continue
        if line.startswith("[") and line.endswith("]"):
            current = line[1:-1]
            sections.setdefault(current, {})
        elif current is not None and "=" in line:
            key, _, value = line.partition("=")
            sections[current][key.strip()] = value.strip()
    return sections


def write(path, sections):
    lines = []
    for name, entries in sections.items():
        # KConfig does not keep a group that has no keys left in it.
        if not entries:
            continue
        lines.append("[%s]" % name)
        for key, value in entries.items():
            lines.append("%s=%s" % (key, value))
        lines.append("")
    path.write_text("\n".join(lines))


def main():
    mode = sys.argv[1]
    values, positional = arguments(sys.argv[2:])
    path = Path(values["file"])
    sections = read(path)

    if mode == "get":
        value = sections.get(values["group"], {}).get(values["key"])
        if value is None:
            return 1
        print(value)
        return 0

    if mode == "delete":
        entries = sections.get(values["group"])
        if entries is not None:
            entries.pop(values["key"], None)
            if not entries:
                del sections[values["group"]]
        write(path, sections)
        return 0

    sections.setdefault(values["group"], {})[values["key"]] = positional[0]
    write(path, sections)
    return 0


sys.exit(main())
PY
}

setup_sandbox() {
    SANDBOX="$(new_tmpdir)"
    STUB_DIR="$SANDBOX/bin"
    BARE_DIR="$SANDBOX/bare"
    CALLS="$SANDBOX/calls.log"
    FAKE="$SANDBOX/kwinrules.py"
    mkdir -p "$STUB_DIR" "$BARE_DIR"
    : > "$CALLS"

    write_fake_config_tools

    stub_bin "$STUB_DIR" kreadconfig6 'exec python3 "$KW_RULES" get "$@"'
    # KW_SILENT_REJECT makes the writer report success and change nothing, which is
    # what the tool did on the VM when kwinrulesrc could not be replaced: the status
    # says one thing and the file says another, so the read-back is the only check
    # that can tell the two apart.
    stub_bin "$STUB_DIR" kwriteconfig6 "printf '%s %s\n' 'kwriteconfig6' \"\$*\" >> \"\$KW_CALLS\"
if [[ -n \"\${KW_SILENT_REJECT:-}\" ]]; then
    exit 0
fi
case \"\$*\" in
    *--delete*) exec python3 \"\$KW_RULES\" delete \"\$@\" ;;
esac
exec python3 \"\$KW_RULES\" set \"\$@\""
    recording_stub "$STUB_DIR" qdbus6 "$CALLS"

    # A PATH holding only what the script itself needs, so that kwriteconfig6 is
    # genuinely missing rather than shadowed.
    ln -s "$(command -v dirname)" "$BARE_DIR/dirname"
    recording_stub "$BARE_DIR" qdbus6 "$CALLS"
}

# The script reads the group list out of the config file itself, because KConfig
# has no query that lists a file's groups. XDG_CONFIG_HOME is the sandbox, so the
# file the stubs write and the file the script enumerates are the same one - and
# the developer's own kwinrulesrc is never read.
run_window_rules() {
    : > "$CALLS"
    OUTPUT="$(cd "$SANDBOX" && env PATH="$STUB_DIR:$PATH" XDG_CONFIG_HOME="$SANDBOX" KW_CALLS="$CALLS" KW_RULES="$FAKE" "$@" bash "$SCRIPT" 2>&1)"
    STATUS=$?
}

run_window_rules_without_kwriteconfig6() {
    : > "$CALLS"
    OUTPUT="$(cd "$SANDBOX" && env PATH="$BARE_DIR" XDG_CONFIG_HOME="$SANDBOX" KW_CALLS="$CALLS" KW_RULES="$FAKE" "$BASH_BIN" "$SCRIPT" 2>&1)"
    STATUS=$?
}

# The frozen interface: group, key, value, in the order the script writes them. The
# index pair comes after the three groups and before the single reload. Only the
# writer and the reload are recorded, so the two reads the script makes per changed
# key - before the write, and back after it - are not part of the sequence below.
expected_calls() {
    local opacity="$1" index="${2:-$FRESH_INDEX}"
    printf '%s\n' \
        "--file $RULES_FILE --group caelestia-opacity --key Description Caelestia: window opacity" \
        "--file $RULES_FILE --group caelestia-opacity --key types 33" \
        "--file $RULES_FILE --group caelestia-opacity --key opacityinactive $opacity" \
        "--file $RULES_FILE --group caelestia-opacity --key opacityinactiverule 2" \
        "--file $RULES_FILE --group caelestia-dialogs --key Description Caelestia: center dialogs" \
        "--file $RULES_FILE --group caelestia-dialogs --key types 32" \
        "--file $RULES_FILE --group caelestia-dialogs --key placement 5" \
        "--file $RULES_FILE --group caelestia-dialogs --key placementrule 2" \
        "--file $RULES_FILE --group caelestia-pip --key Description Caelestia: pin picture-in-picture" \
        "--file $RULES_FILE --group caelestia-pip --key title Picture(-| )in(-| )[Pp]icture" \
        "--file $RULES_FILE --group caelestia-pip --key titlematch 3" \
        "--file $RULES_FILE --group caelestia-pip --key above true" \
        "--file $RULES_FILE --group caelestia-pip --key aboverule 2" \
        "--file $RULES_FILE --group General --key rules $index" \
        "--file $RULES_FILE --group General --key count $(count_index "$index")"
}

# What the script derives from the list: entries are comma separated, so the number
# of entries is one more than the number of commas.
count_index() {
    awk -F, '{ print NF }' <<< "$1"
}

# The stubs write one plain ini file, so a value is read back straight from it
# rather than through the config tools: the assertions are about the file.
ini_value() {
    local file="$1" group="$2" key="$3"
    awk -v group="$group" -v key="$key" '
        $0 == "[" group "]" { inside = 1; next }
        /^\[/ { inside = 0 }
        inside && index($0, key "=") == 1 { print substr($0, length(key) + 2); exit }
    ' "$file"
}

# kwinrulesrc as it looks once a user has added a rule of their own: their group,
# and the index that names it. [$Version] is KWin's own metadata and stays out of
# the list.
write_user_rule_fixture() {
    cat > "$SANDBOX/$RULES_FILE" <<'EOF'
[General]
rules=user-rule
count=1
Order=user-rule

[user-rule]
Description=Keep this window put
wmclass=keepme
wmclassmatch=1
placement=2
placementrule=2

[$Version]
update_info=kwinrules.upd:fix-rule-order
EOF
}

# kwinrulesrc as the installer leaves it, with the index the installer writes. No
# Order key, which is what KWin 6.7 writes: only the list and its count.
write_installed_fixture() {
    local index="$1" count="$2"
    cat > "$SANDBOX/$RULES_FILE" <<EOF
[General]
rules=$index
count=$count

[user-rule]
Description=Keep this window put
wmclass=keepme
wmclassmatch=1
placement=2
placementrule=2

[caelestia-opacity]
Description=Caelestia: window opacity
types=33
opacityinactive=95
opacityinactiverule=2

[caelestia-dialogs]
Description=Caelestia: center dialogs
types=32
placement=5
placementrule=2

[caelestia-pip]
Description=Caelestia: pin picture-in-picture
title=Picture(-| )in(-| )[Pp]icture
titlematch=3
above=true
aboverule=2
EOF
}

# uninstall.sh runs from top to bottom and cannot be sourced, so its revert of the window
# rules is cut out by its own first and last lines - the first delete through the line that
# reports it - and run against the same stubs the installer step is tested with.
extract_uninstall_revert() {
    awk '
        /^kwriteconfig6 .*--group "caelestia-opacity"/ { inside = 1 }
        inside { print }
        inside && /^ok "Removed the Caelestia window rules/ { exit }
    ' "$UNINSTALL_SCRIPT"
}

run_uninstall_revert() {
    local revert="$SANDBOX/revert.sh"
    {
        printf 'set -uo pipefail\n'
        printf 'ok() { printf "  [OK]    %%s\\n" "$*"; }\n'
        extract_uninstall_revert
    } > "$revert"
    : > "$CALLS"
    OUTPUT="$(cd "$SANDBOX" && env PATH="$STUB_DIR:$PATH" XDG_CONFIG_HOME="$SANDBOX" KW_CALLS="$CALLS" KW_RULES="$FAKE" "$BASH_BIN" "$revert" 2>&1)"
    STATUS=$?
}

test_a_fresh_run_writes_every_key_of_the_three_groups() {
    have_python || return 0
    setup_sandbox
    run_window_rules

    assert_status 0 "$STATUS" "a fresh run should succeed"
    assert_eq "$(expected_calls 95)" "$(calls_to "$CALLS" kwriteconfig6)" \
        "every key of the frozen table should be written once, in order"
}

test_the_written_file_carries_the_groups_and_their_values() {
    have_python || return 0
    setup_sandbox
    run_window_rules

    local file="$SANDBOX/$RULES_FILE"
    assert_file_exists "$file"
    assert_eq "3" "$(grep -c '^\[caelestia-' "$file")" "the file should hold exactly the three named groups"

    local content
    content="$(cat "$file")"
    # The pairs below are a second assertion of the same contract the call log
    # asserts: scripts/04a-window-rules.sh owns the key list, and this file asserts it
    # in both forms on purpose, so a change has to be made deliberately in both.
    local pair
    for pair in \
        "opacityinactive=95" \
        "opacityinactiverule=2" \
        "types=33" \
        "types=32" \
        "placement=5" \
        "placementrule=2" \
        "title=Picture(-| )in(-| )[Pp]icture" \
        "titlematch=3" \
        "above=true" \
        "aboverule=2"; do
        assert_contains "$content" "$pair" "the file should carry $pair"
    done
}

test_a_fresh_file_names_exactly_the_three_groups() {
    have_python || return 0
    setup_sandbox
    run_window_rules

    local file="$SANDBOX/$RULES_FILE"
    assert_eq "$FRESH_INDEX" "$(ini_value "$file" General rules)" \
        "a fresh file should name our three groups, in the order they were written"
    assert_eq "3" "$(ini_value "$file" General count)" "and count them"
    assert_eq "3" "$(grep -c '^\[caelestia-' "$file")" \
        "the index should name what the file holds, and nothing else"
}

test_the_reload_is_called_once_and_last() {
    have_python || return 0
    setup_sandbox
    run_window_rules

    assert_eq "org.kde.KWin /KWin reconfigure" "$(calls_to "$CALLS" qdbus6)" \
        "the reload should happen exactly once, with the frozen arguments"
    assert_eq "qdbus6 org.kde.KWin /KWin reconfigure" "$(tail -n 1 "$CALLS")" \
        "the reload should come after every group has been written"
}

test_only_our_groups_and_the_index_are_written() {
    have_python || return 0
    setup_sandbox
    run_window_rules

    local call group
    while IFS= read -r call; do
        group="$(printf '%s\n' "$call" | awk '{ for (i = 1; i < NF; i++) if ($i == "--group") print $(i + 1) }')"
        case " ${RULE_GROUPS[*]} General " in
            *" $group "*) ;;
            *) fail "kwriteconfig6 was called outside the three caelestia-* groups and the index: $call" ;;
        esac
    done < <(calls_to "$CALLS" kwriteconfig6)

    # General is written for the index pair and nothing else. Order belongs to KWin:
    # rewriting it would reorder the user's own rules.
    assert_eq "$(printf '%s\n' \
        "--file $RULES_FILE --group General --key rules $FRESH_INDEX" \
        "--file $RULES_FILE --group General --key count 3")" \
        "$(calls_to "$CALLS" kwriteconfig6 | grep -F -- '--group General')" \
        "the index pair should be the only General keys written"
    assert_not_contains "$(cat "$CALLS")" "--key Order" "Order belongs to KWin and reordering the user's rules is not ours to do"
}

test_a_second_run_finds_nothing_to_do() {
    have_python || return 0
    setup_sandbox
    run_window_rules
    assert_status 0 "$STATUS" "the first run should succeed"

    run_window_rules
    assert_status 0 "$STATUS" "the second run should succeed"
    assert_eq "" "$(calls_to "$CALLS" kwriteconfig6)" \
        "a config that already holds every value should need no writes"
    assert_contains "$OUTPUT" "already in place" "the second run should report the rules as already in place"
    assert_not_contains "$OUTPUT" "Window rules applied." "the second run should not claim to have applied anything"
    assert_contains "$OUTPUT" "Rule index names 3 group(s)." \
        "the rollup should still report the index a re-run did not have to rebuild"
}

test_the_step_can_be_switched_off() {
    have_python || return 0
    setup_sandbox
    run_window_rules APPLY_WINDOW_RULES=false

    assert_status 0 "$STATUS" "switching the step off should not fail the install"
    assert_contains "$OUTPUT" "Skipping window rules" "the skip should be reported"
    assert_eq "" "$(cat "$CALLS")" "nothing should be written or reloaded"
    assert_file_missing "$SANDBOX/$RULES_FILE"
}

test_a_missing_kwriteconfig6_warns_instead_of_failing() {
    have_python || return 0
    setup_sandbox
    run_window_rules_without_kwriteconfig6

    assert_status 0 "$STATUS" "a missing kwriteconfig6 should not fail the install"
    assert_contains "$OUTPUT" "kwriteconfig6 not found" "the warning should name the missing tool"
    assert_eq "" "$(cat "$CALLS")" "nothing should be written or reloaded"
}

# A write kwriteconfig6 rejects - a read-only or unwritable kwinrulesrc - is not a
# write that happened: it has to be warned about, and the rollup must not claim the
# rules were applied, but it must not fail the install either.
test_a_rejected_write_is_warned_about_rather_than_applied() {
    have_python || return 0
    setup_sandbox
    recording_stub "$STUB_DIR" kwriteconfig6 "$CALLS" 1
    run_window_rules

    assert_status 0 "$STATUS" "a rejected write should not fail the install"
    assert_contains "$(calls_to "$CALLS" kwriteconfig6)" "--key aboverule 2" \
        "every key should still be attempted"
    assert_contains "$(calls_to "$CALLS" kwriteconfig6)" "--key rules $FRESH_INDEX" \
        "including the index, so a file that lost its list gets one back"
    assert_contains "$OUTPUT" "[WARN]" "the rejection should be reported as a warning"
    assert_contains "$OUTPUT" "could not be written" "the warning should say what happened"
    assert_not_contains "$OUTPUT" "Applied " "a rejected write must not be reported as applied"
    assert_not_contains "$OUTPUT" "Window rules applied." "and the rollup must not claim it either"
}

# The same rejection with no error status at all: the writer exits 0 and the file
# stays as it was, which is what the VM showed with kwinrulesrc replaced by a
# directory. The value never changes on disk, so the key has to be counted as failed
# and the rollup must not claim the rules were applied.
test_a_silent_rejection_is_reported_as_failed_rather_than_applied() {
    have_python || return 0
    setup_sandbox
    run_window_rules KW_SILENT_REJECT=1

    assert_status 0 "$STATUS" "a silently rejected write should not fail the install"
    assert_contains "$(calls_to "$CALLS" kwriteconfig6)" "--key aboverule 2" \
        "every key should still be attempted"
    assert_contains "$(calls_to "$CALLS" kwriteconfig6)" "--key rules $FRESH_INDEX" \
        "including the index, so a file that lost its list gets one back"
    assert_contains "$OUTPUT" "[WARN]" "the silence should be reported as a warning"
    assert_contains "$OUTPUT" "could not be written" "the warning should say what happened"
    assert_not_contains "$OUTPUT" "Applied " "a write that did not land must not be reported as applied"
    assert_not_contains "$OUTPUT" "Window rules applied." "and the rollup must not claim it either"
    assert_file_missing "$SANDBOX/$RULES_FILE"
}

test_the_inactive_opacity_comes_from_the_environment() {
    have_python || return 0
    setup_sandbox
    run_window_rules WINDOW_OPACITY=80

    assert_status 0 "$STATUS" "a custom opacity should not fail"
    assert_eq "$(expected_calls 80)" "$(calls_to "$CALLS" kwriteconfig6)" \
        "only the opacity value should differ from a default run"
    assert_contains "$(cat "$SANDBOX/$RULES_FILE")" "opacityinactive=80" "the file should carry it too"
}

# A group that is present in the file but left out of the list is never loaded, so
# the index adopts it before it can matter. Adopting is also what keeps a re-run
# from narrowing the list to our own names.
test_a_group_the_file_holds_is_added_to_the_index() {
    have_python || return 0
    setup_sandbox
    printf '[steam]\nwmclass=steamwebhelper\nwmclassmatch=1\n' > "$SANDBOX/$RULES_FILE"

    run_window_rules

    local file="$SANDBOX/$RULES_FILE"
    assert_status 0 "$STATUS" "a file with a group of its own should still succeed"
    assert_eq "steam,$FRESH_INDEX" "$(ini_value "$file" General rules)" \
        "the group the file holds should be named, before our three"
    assert_eq "4" "$(ini_value "$file" General count)" "and counted with them"
    assert_eq "steamwebhelper" "$(ini_value "$file" steam wmclass)" \
        "the user's group should be left as it was"
}

test_a_user_rule_keeps_its_place_in_the_index() {
    have_python || return 0
    setup_sandbox
    write_user_rule_fixture

    run_window_rules

    local file="$SANDBOX/$RULES_FILE"
    assert_status 0 "$STATUS" "a file with a user rule should still succeed"
    assert_eq "user-rule,$FRESH_INDEX" "$(ini_value "$file" General rules)" \
        "the user's name should keep its place and ours should be appended"
    assert_eq "4" "$(ini_value "$file" General count)" "count should cover both"
    assert_eq "user-rule" "$(ini_value "$file" General Order)" \
        "Order is KWin's own key and should not be rewritten"
    assert_eq "keepme" "$(ini_value "$file" user-rule wmclass)" "the user's rule should not be touched"
    assert_not_contains "$(ini_value "$file" General rules)" '$Version' \
        "a group whose name starts with a dollar is KWin's metadata and is not named"
}

# uninstall.sh strips our names out of the index and leaves the user's rules alone:
# the list is theirs, and deleting a name that is not ours would silently disable a
# rule they wrote.
test_the_revert_keeps_the_users_names_and_strips_ours() {
    have_python || return 0
    setup_sandbox
    write_installed_fixture "user-rule,$FRESH_INDEX" 4

    run_uninstall_revert

    local file="$SANDBOX/$RULES_FILE"
    assert_status 0 "$STATUS" "the revert should succeed"
    assert_contains "$OUTPUT" "Removed the Caelestia window rules from kwinrulesrc" \
        "the revert should report what it removed"
    assert_eq "user-rule" "$(ini_value "$file" General rules)" "only our names should leave the list"
    assert_eq "1" "$(ini_value "$file" General count)" "and count should follow the names that are left"
    assert_eq "keepme" "$(ini_value "$file" user-rule wmclass)" "the user's own rule should survive"
    assert_not_contains "$(cat "$file")" "caelestia-" "every group of ours should be gone"
}

# With no name left the file has to look like it did before the install: an index
# that names nothing, and a count of nothing, are both absent rather than empty.
test_the_revert_removes_the_index_when_no_names_are_left() {
    have_python || return 0
    setup_sandbox
    write_installed_fixture "$FRESH_INDEX" 3

    run_uninstall_revert

    local file="$SANDBOX/$RULES_FILE"
    assert_status 0 "$STATUS" "the revert should succeed"
    assert_eq "" "$(ini_value "$file" General rules)" "the index should be deleted"
    assert_eq "" "$(ini_value "$file" General count)" "and the count with it"
    assert_not_contains "$(cat "$file")" "[General]" "the General group should be gone once it is empty"
    assert_not_contains "$(cat "$file")" "caelestia-" "with none of our groups left"
}

run_tests
