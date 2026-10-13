#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/log.sh"

RULES_FILE="kwinrulesrc"
# kwriteconfig6 resolves a relative file name inside the user's config directory, and
# KConfig has no query that lists the groups of a file, so the index below is built
# from the file itself, read at the same path the tools write.
RULES_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/$RULES_FILE"
RULE_GROUPS=(caelestia-opacity caelestia-dialogs caelestia-pip)
RULE_INDEX=""
RULE_INDEX_COUNT=0
WINDOW_OPACITY="${WINDOW_OPACITY:-95}"
RULE_WRITES=0
RULE_FAILURES=0

# Read every key before writing it, so a second run reports the rules that were
# already in place instead of claiming a fresh write, and read it back after, so
# only a write that reached the file counts as one. The outcome goes back to the
# caller through an out parameter - written, unchanged or failed - because the exit
# status alone is not evidence that a write landed: asked to write a key of
# caelestia-opacity into a kwinrulesrc that was a directory, kwriteconfig6 on Plasma
# 6.7.5 exited 0, wrote nothing, and the key read back empty. Both tools keep their
# error stream on 2>/dev/null, as in 04-deploy-kde.sh, and the read-back decides.
set_rule_key() {
    local group="$1" key="$2" value="$3" outcome_var="$4" current confirmed
    current="$(kreadconfig6 --file "$RULES_FILE" --group "$group" --key "$key" 2>/dev/null || true)"
    if [[ "$current" == "$value" ]]; then
        printf -v "$outcome_var" '%s' "unchanged"
    else
        kwriteconfig6 --file "$RULES_FILE" --group "$group" --key "$key" "$value" 2>/dev/null || true
        confirmed="$(kreadconfig6 --file "$RULES_FILE" --group "$group" --key "$key" 2>/dev/null || true)"
        if [[ "$confirmed" == "$value" ]]; then
            printf -v "$outcome_var" '%s' "written"
        else
            printf -v "$outcome_var" '%s' "failed"
        fi
    fi
}

# Only the keys of our own named groups and the two [General] keys that index them
# are written. kwinrulesrc is the user's file: it is never truncated, no group is
# ever deleted, and every other key is left as it is. A rejected write is warned
# about rather than fatal: the rules are cosmetic and the repo's convention for
# non-critical work is warn, not die.
apply_rule_group() {
    local group="$1" label="$2"
    shift 2
    local outcome="" written=0 failed=0
    while [[ $# -ge 2 ]]; do
        set_rule_key "$group" "$1" "$2" outcome
        case "$outcome" in
            written) written=$((written + 1)) ;;
            failed) failed=$((failed + 1)) ;;
        esac
        shift 2
    done
    RULE_WRITES=$((RULE_WRITES + written))
    RULE_FAILURES=$((RULE_FAILURES + failed))

    if (( failed > 0 )); then
        warn "$failed of $((written + failed)) key(s) for $label could not be written."
    elif (( written > 0 )); then
        ok "Applied $label."
    else
        skip "$label already in place."
    fi
}

# KConfig has no query that lists the groups of a file, so they are read straight
# out of it. [General] holds the index itself, and a group whose name starts with $
# is KWin's own metadata: its isMetaDataGroup() skips those as well.
list_rule_groups() {
    local path="$1"
    [[ -f "$path" ]] || return 0
    awk '
        /^[[:space:]]*\[/ {
            name = $0
            sub(/^[[:space:]]*\[/, "", name)
            sub(/\].*$/, "", name)
            if (name != "" && name != "General" && substr(name, 1, 1) != "$") {
                print name
            }
        }
    ' "$path"
}

# An entry may carry the spaces KConfig leaves around a list item; the name is
# compared exactly otherwise, so the user's own spelling of a rule survives.
trim_rule_name() {
    local name="$1"
    name="${name#"${name%%[![:space:]]*}"}"
    name="${name%"${name##*[![:space:]]}"}"
    printf '%s' "$name"
}

# The index is a union, so a name is added once, in the order it was first seen: the
# user's order is kept and a re-run adds nothing.
add_to_rule_index() {
    local name="$1"
    [[ -n "$name" ]] || return 0
    case ",$RULE_INDEX," in
        *",$name,"*) return 0 ;;
    esac
    RULE_INDEX="${RULE_INDEX:+$RULE_INDEX,}$name"
    RULE_INDEX_COUNT=$((RULE_INDEX_COUNT + 1))
}

# The index is what makes the groups take effect. KWin builds its rule book from the
# names in [General] rules= alone, so a group that is present in the file but left
# out of that list is never loaded, and the next time KWin saves the rule book it
# deletes every group the list does not name. Both KWin 6.7 and master read this
# key, master as the ordered group list, so the list is rebuilt as the union of the
# current value, every group the file holds and our three groups. Naming only our
# own would hand KWin a list that drops the user's rules.
build_rule_index() {
    local current="$1" groups="$2" name
    RULE_INDEX=""
    RULE_INDEX_COUNT=0
    while IFS= read -r name; do
        add_to_rule_index "$(trim_rule_name "$name")"
    done <<< "$(printf '%s' "$current" | tr ',' '\n')"
    while IFS= read -r name; do
        add_to_rule_index "$name"
    done <<< "$groups"
    for name in "${RULE_GROUPS[@]}"; do
        add_to_rule_index "$name"
    done
}

echo
echo ""
info "Applying KWin window rules"
echo ""

if [[ "${APPLY_WINDOW_RULES:-true}" == "true" ]]; then
    if ! command -v kwriteconfig6 >/dev/null 2>&1; then
        warn "kwriteconfig6 not found - skipping window rules."
        exit 0
    fi

    # KWin has no floating action and no keepabove key: a rule cannot make a window
    # float, and the keep-above action below is spelled above.

    # types=33 is Normal|Dialog, so panels, tooltips and the OSD keep full opacity.
    apply_rule_group "caelestia-opacity" "window opacity" \
        Description "Caelestia: window opacity" \
        types 33 \
        opacityinactive "$WINDOW_OPACITY" \
        opacityinactiverule 2

    # The rule placement is a bare integer, 5 being PlacementCentered; the global
    # [Windows] Placement key in kwinrc is a string, this one is not.
    apply_rule_group "caelestia-dialogs" "dialog centering" \
        Description "Caelestia: center dialogs" \
        types 32 \
        placement 5 \
        placementrule 2

    # No types key here: picture-in-picture windows are Normal or Dialog depending
    # on the app, and the title regex is specific enough on its own.
    apply_rule_group "caelestia-pip" "picture-in-picture pin" \
        Description "Caelestia: pin picture-in-picture" \
        title "Picture(-| )in(-| )[Pp]icture" \
        titlematch 3 \
        above true \
        aboverule 2

    # Our groups first, then the index that names them, then the reload. The index
    # is rebuilt from the file as it is now, so the groups just written are in it.
    build_rule_index \
        "$(kreadconfig6 --file "$RULES_FILE" --group General --key rules 2>/dev/null || true)" \
        "$(list_rule_groups "$RULES_PATH")"
    apply_rule_group "General" "the rule index" \
        rules "$RULE_INDEX" \
        count "$RULE_INDEX_COUNT"

    # One reload, after every group and the index are written: KWin drops groups it
    # has not read yet when it saves the file, so reloading between writes loses
    # rules.
    if command -v qdbus6 >/dev/null 2>&1; then
        qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
    else
        warn "qdbus6 not found - KWin picks the rules up on its next restart."
    fi

    if (( RULE_FAILURES > 0 )); then
        warn "Window rules not fully applied: $RULE_FAILURES key(s) rejected, $RULE_WRITES written."
    elif (( RULE_WRITES > 0 )); then
        ok "Window rules applied."
    else
        skip "Window rules already in place."
    fi
    info "Rule index names $RULE_INDEX_COUNT group(s)."
else
    skip "Skipping window rules"
fi
