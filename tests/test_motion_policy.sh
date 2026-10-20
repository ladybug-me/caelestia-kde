#!/usr/bin/env bash

# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_DIR="$REPO_ROOT/shell"
COMPONENTS="$SHELL_DIR/components"

assert_no_match() {
    local pattern="$1" message="$2" paths="${3:-$SHELL_DIR}"
    local hits
    hits="$(grep -rlE -- "$pattern" "$paths" 2>/dev/null | grep -v '^$' || true)"
    if [[ -n "$hits" ]]; then
        fail "$message ($(printf '%s' "$hits" | paste -sd', ' -))"
    fi
}

# The switch has to exist, be global (one animation policy for the session, not per
# screen) and collapse every token duration rather than only hiding the setting.
test_the_animation_switch_is_a_global_key_that_collapses_durations() {
    assert_file_contains "$REPO_ROOT/shell/plugin/src/Caelestia/Config/appearanceconfig.hpp" \
        'CONFIG_GLOBAL_PROPERTY(bool, enabled, true)' \
        "appearance.anim.enabled must be a global key"
    assert_file_contains "$REPO_ROOT/shell/plugin/src/Caelestia/Config/appearanceconfig.cpp" \
        'if (m_anim && !m_anim->animationsEnabled())' \
        "the duration getters must consult the switch"
    assert_file_contains "$REPO_ROOT/shell/plugin/src/Caelestia/Config/rootnodes.cpp" \
        'bindAnim(m_appearance->anim())' \
        "the config root must bind the switch into the durations"
    assert_file_contains "$REPO_ROOT/shell/plugin/src/Caelestia/Config/anim.hpp" \
        'Q_PROPERTY(bool enabled READ enabled NOTIFY enabledChanged)' \
        "Tokens.anim.enabled has to be readable from QML"
    assert_file_contains "$REPO_ROOT/shell/plugin/src/Caelestia/Config/anim.hpp" \
        'Q_INVOKABLE int duration(int ms)' \
        "a duration the tokens do not name still has to honour the switch"
}

# Every animated state change in the shell is supposed to reach its duration through one
# of these two, which is what makes the switch in the settings page mean anything.
test_the_shared_animations_carry_token_durations() {
    assert_file_contains "$COMPONENTS/Anim.qml" 'Tokens.anim.durations' \
        "Anim must take its duration from the tokens"
    assert_file_contains "$COMPONENTS/CAnim.qml" 'Tokens.anim.durations.expressiveSlowEffects' \
        "CAnim must take its duration from the tokens"
}

test_a_scaled_duration_still_honours_the_switch() {
    local offenders
    offenders="$(grep -rn 'duration:.*Tokens\.anim\.durations\.scale' "$SHELL_DIR" --include='*.qml' \
        | grep -v 'Tokens\.anim\.duration(' || true)"
    if [[ -n "$offenders" ]]; then
        fail "a duration scaled by hand bypasses the switch: $(printf '%s' "$offenders" | head -5 | paste -sd' ' -)"
    fi
}

# The overview's durations come from its own config rather than the tokens, so the switch
# only reaches them if they are routed through Tokens.anim.duration() by hand. The
# overview and the drawer blob it morphs are the shell's biggest motion, so a duration
# that skips the switch is the one that is noticed.
test_the_overview_motion_honours_the_switch() {
    local file
    for file in \
        "$SHELL_DIR/modules/overview/Anim.qml" \
        "$SHELL_DIR/modules/overview/WindowGrid.qml"; do
        assert_file_contains "$file" 'Tokens.anim.duration(' \
            "$(basename "$file") should take its duration through the animations switch"
    done

    # Every duration on the object has to be wrapped, so a bare one cannot creep back in.
    assert_no_match 'readonly property int [a-zA-Z]*Duration: Math\.round' \
        "an overview duration still reads the overview config directly" \
        "$SHELL_DIR/modules/overview/Anim.qml"
}

# `type` names a duration and an easing together. Overriding only one of them beside a
# `type` leaves the other coming from the type, so the pair ends up half from the token and
# half from the caller - a spatial duration on an effects curve, or the reverse. Set the
# pair yourself and drop the type, or name the type alone.
test_an_anim_type_is_not_half_overridden() {
    local file offenders
    while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        offenders="$(awk '
            function indent_of(s,   m) {
                if (match(s, /^[ \t]*/))
                    return RLENGTH;
                return 0;
            }
            function scan(fname,   k, e, j, t) {
                for (k = 1; k <= n; k++) {
                    if (line[k] !~ /^[ \t]*(Anim|AnchorAnim) \{/)
                        continue;
                    e = n;
                    for (j = k + 1; j <= n; j++) {
                        if (line[j] ~ /^[ \t]*$/)
                            continue;
                        if (indent_of(line[j]) <= indent_of(line[k])) {
                            e = j - 1;
                            break;
                        }
                    }
                    t = "";
                    for (j = k; j <= e; j++)
                        t = t line[j] "\n";
                    gsub(/[{;]/, "\n", t);
                    if (t ~ /(^|\n)[ \t]*type:[ ]/ && (t ~ /(^|\n)[ \t]*duration:[ ]/ || t ~ /(^|\n)[ \t]*easing[.:][ ]/))
                        printf "%s:%d: %s\n", fname, k, line[k];
                }
            }
            FNR == 1 {
                if (n > 0)
                    scan(cur);
                n = 0;
                cur = FILENAME;
            }
            { n++; line[n] = $0 }
            END { scan(cur) }
        ' "$file" || true)"
        if [[ -n "$offenders" ]]; then
            fail "an Anim type is half overridden: $(printf '%s' "$offenders" | head -5 | paste -sd', ' -)"
        fi
    done < <(grep -rlE '^[ \t]*(Anim|AnchorAnim) \{' "$SHELL_DIR" --include='*.qml' || true)
}

test_every_unbounded_animation_can_be_stopped() {
    local file offenders
    while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        offenders="$(awk '
            function indent_of(s,   m) {
                if (match(s, /^[ \t]*/))
                    return RLENGTH;
                return 0;
            }
            function block_end(h,   j, ind) {
                ind = indent_of(line[h]);
                for (j = h + 1; j <= n; j++) {
                    if (line[j] ~ /^[ \t]*$/)
                        continue;
                    if (indent_of(line[j]) <= ind)
                        return j - 1;
                }
                return n;
            }
            function has_switch(s,   name) {
                if (s ~ /Tokens\.anim\.enabled/)
                    return 1;
                for (name in derived)
                    if (s ~ ("(^|[^A-Za-z0-9_])" name "([^A-Za-z0-9_]|$)"))
                        return 1;
                return 0;
            }
            function gate_state(h,   j, ind, found, ok) {
                ind = -1;
                for (j = h + 1; j <= n; j++) {
                    if (line[j] ~ /^[ \t]*$/)
                        continue;
                    ind = indent_of(line[j]);
                    break;
                }
                if (ind < 0)
                    return 0;
                found = 0;
                ok = 0;
                for (j = h + 1; j <= n; j++) {
                    if (line[j] ~ /^[ \t]*$/)
                        continue;
                    if (indent_of(line[j]) < ind)
                        break;
                    if (indent_of(line[j]) > ind)
                        continue;
                    if (line[j] ~ /^[ \t]*(running|paused):/) {
                        found = 1;
                        if (has_switch(line[j]))
                            ok = 1;
                    }
                }
                if (ok)
                    return 1;
                return found ? -1 : 0;
            }
            { line[NR] = $0 }
            END {
                n = NR;
                for (k = 1; k <= n; k++) {
                    if (line[k] !~ /(readonly[ \t]+)?property/ || line[k] !~ /Tokens\.anim\.enabled/)
                        continue;
                    if (match(line[k], /[A-Za-z_][A-Za-z0-9_]*[ \t]*:/)) {
                        name = substr(line[k], RSTART, RLENGTH);
                        sub(/[ \t]*:$/, "", name);
                        derived[name] = 1;
                    }
                }
                for (k = 1; k <= n; k++) {
                    if (line[k] !~ /loops:[ \t]*Animation\.Infinite/ && line[k] !~ /^[ \t]*FrameAnimation[ \t]*\{/)
                        continue;
                    # A property line belongs to the object that opens above it.
                    cur = k;
                    if (line[cur] !~ /\{[ \t]*$/) {
                        cur = 0;
                        for (j = k - 1; j >= 1; j--) {
                            if (line[j] ~ /^[ \t]*$/)
                                continue;
                            if (indent_of(line[j]) < indent_of(line[k]) && line[j] ~ /\{[ \t]*$/) {
                                cur = j;
                                break;
                            }
                        }
                    }
                    ok = 0;
                    while (cur > 0) {
                        state = gate_state(cur);
                        if (state == 1) {
                            ok = 1;
                            break;
                        }
                        if (state == -1)
                            break;
                        parent = 0;
                        for (j = cur - 1; j >= 1; j--) {
                            if (line[j] ~ /^[ \t]*$/)
                                continue;
                            if (indent_of(line[j]) < indent_of(line[cur]) && line[j] ~ /\{[ \t]*$/) {
                                parent = j;
                                break;
                            }
                        }
                        cur = parent;
                    }
                    if (!ok)
                        printf "%s:%d: %s\n", FILENAME, k, line[k];
                }
            }
        ' "$file" || true)"
        if [[ -n "$offenders" ]]; then
            fail "an unbounded animation ignores the animations switch: $(printf '%s' "$offenders" | head -5 | paste -sd' ' -)"
        fi
    done < <(grep -rlE 'loops:[[:space:]]*Animation\.Infinite|^[[:space:]]*FrameAnimation[[:space:]]*\{' "$SHELL_DIR" --include='*.qml' || true)
}

test_the_settings_page_offers_the_switch() {
    assert_file_contains "$REPO_ROOT/shell/modules/nexus/pages/wallandstyle/AppearancePage.qml" \
        'GlobalConfig.appearance.anim.enabled' \
        "the animations switch belongs on the appearance page"
}

# A theme switch replaces the whole palette at once; without suppression a few hundred
# colour transitions start in the same frame and the switch smears.
test_a_theme_switch_suppresses_colour_transitions() {
    assert_file_contains "$SHELL_DIR/services/Colours.qml" 'function holdColourTransitions(): void' \
        "Colours has to be able to suspend colour transitions"
    assert_file_contains "$SHELL_DIR/services/Colours.qml" 'holdColourTransitions();' \
        "applying a palette is what suspends them"
    assert_file_contains "$SHELL_DIR/services/Colours.qml" 'Qt.callLater(() => (root.switchingTheme = false))' \
        "the hold is released once the writes have landed, not after a guessed wait"
    assert_file_not_contains "$SHELL_DIR/services/Colours.qml" 'themeSwitchTimer' \
        "the hold is not a timer"
    assert_file_contains "$COMPONENTS/CAnim.qml" 'Colours.switchingTheme ? 0 :' \
        "CAnim is where the suspension lands"
    assert_file_contains "$COMPONENTS/CAnim.qml" 'import qs.services' \
        "CAnim reads the flag off Colours"

    # Which only covers the shell while every colour animation routes through CAnim.
    local raw
    raw="$(grep -rl 'ColorAnimation' "$SHELL_DIR" --include='*.qml' | grep -v '/CAnim.qml$' || true)"
    if [[ -n "$raw" ]]; then
        fail "a raw ColorAnimation escapes the theme-switch suppression: $(printf '%s' "$raw" | paste -sd', ' -)"
    fi
}

# Bounce is always zero: the M3 Expressive curves overshoot on their own, and OutBack,
# OutElastic and friends are not part of that vocabulary.
test_no_off_token_bounce_remains() {
    assert_no_match 'Easing\.(Out|In|InOut)?(Back|Elastic|Bounce)' \
        "an easing outside the token curves is still in place"
    assert_no_match 'easing\.overshoot' \
        "overshoot belongs to the curve, not to a literal"
}

# A press or a drag settles at a scale the design names: 0.96 for a press, and one named
# value for the lift a dragged row or tile gets.
test_press_and_lift_scales_are_named() {
    assert_no_match 'PropertyChanges.*scale:\s*0\.' \
        "a state should not hardcode a press scale"
    assert_file_contains "$SHELL_DIR/modules/nexus/common/NexusStyle.qml" \
        'readonly property real dragScale: 1.05' \
        "the drag lift should be named once"
    assert_file_contains "$SHELL_DIR/modules/nexus/pages/wallandstyle/ContextMenuPage.qml" \
        'scale: NexusStyle.dragScale' \
        "the reorder drag should use the named lift"
    assert_file_contains "$SHELL_DIR/modules/nexus/pages/panels/taskbar/BarComponents.qml" \
        'scale: NexusStyle.dragScale' \
        "so should the bar widget drag"
}

# Tracking smoothing is the one interaction deliberately left out of the tokens: it
# follows a finger or a level, and a transition-length duration would read as lag.
test_no_behavior_carries_a_literal_duration() {
    local offenders
    offenders="$(grep -rA3 'Behavior on ' "$SHELL_DIR" --include='*.qml' \
        | awk '/Behavior on / { block = $0 } /duration:[ ]*[0-9]/ { print block " ||| " $0 }' \
        | grep -v 'SmoothedAnimation' || true)"
    if [[ -n "$offenders" ]]; then
        fail "a Behavior still hardcodes its duration: $(printf '%s' "$offenders" | head -5 | paste -sd' ' -)"
    fi
}

# A pill is round because it is a pill, not because its height happens to be halved: a
# bare halving ignores the corner radius scale the appearance page offers.
test_circles_go_through_the_rounding_tokens() {
    local offenders
    offenders="$(grep -rE 'radius:\s*(height|width|implicitHeight|implicitWidth|parent\.height|parent\.width)\s*/\s*2' \
        "$SHELL_DIR" --include='*.qml' | grep -v 'Tokens.rounding.scale' || true)"
    if [[ -n "$offenders" ]]; then
        fail "a radius still halves a dimension instead of naming a token: $(printf '%s' "$offenders" | head -5 | paste -sd' ' -)"
    fi
}

# Month navigation is a scroll-driven state change, so it has to retarget mid-flight
# rather than replay a fixed sequence.
test_the_calendars_animate_months_reversibly() {
    local shared="$COMPONENTS/CalendarMonthSlide.qml"
    local file

    assert_file_contains "$shared" 'property bool _repositioning' \
        "the shared month motion needs the parked-frame reposition"
    assert_file_contains "$shared" 'Behavior on animTranslate' \
        "the shared month motion should slide with a Behavior"
    assert_file_not_contains "$shared" 'trOutAnim' \
        "the fixed out-then-in sequence has to be gone"
    # The parked frame sits opposite the direction of travel, or the month appears to come
    # from the side the wheel was not turned towards.
    assert_file_matches "$shared" 'const parked = offset .* \? 1 : -1' \
        "the shared month motion must park the incoming month opposite the scroll direction"

    for file in "$SHELL_DIR/modules/bar/popouts/CalendarPopout.qml" "$SHELL_DIR/modules/dashboard/dash/Calendar.qml"; do
        assert_file_contains "$file" 'CalendarMonthSlide {' \
            "$(basename "$file") should share the month motion"
        assert_file_not_contains "$file" 'animRepositioning' \
            "$(basename "$file") should not keep its own copy of the parking protocol"
        assert_file_not_contains "$file" '_prevDate' \
            "$(basename "$file") should leave tracking the previous month to the shared motion"
    done
}

# A state carried by motion alone leaves nothing to read once the motion stops.
test_a_pulsing_state_also_has_a_static_cue() {    local file
    for file in "$SHELL_DIR/modules/bar/components/status/BluetoothStatus.qml" "$SHELL_DIR/modules/bar/components/StatusIcons.qml"; do
        assert_file_contains "$file" 'readonly property bool pending' \
            "$(basename "$file") should name the connecting state"
        assert_file_contains "$file" 'device.pending ? Qt.alpha(root.colour, 0.5) : root.colour' \
            "$(basename "$file") should carry that state in the icon colour"
        assert_file_contains "$file" 'running: device.pending && Tokens.anim.enabled' \
            "$(basename "$file") should stop the pulse with the animations switch"
    done
}

test_the_dialogs_share_one_transition_with_a_shorter_exit() {
    local dialog
    for dialog in \
        "$SHELL_DIR/modules/nexus/common/KeyCaptureDialog.qml" \
        "$SHELL_DIR/modules/nexus/common/UninstallDialog.qml" \
        "$SHELL_DIR/modules/nexus/pages/wallandstyle/AddShortcutDialog.qml"; do
        assert_file_contains "$dialog" 'enter: DialogTransition { }' \
            "$(basename "$dialog") should use the shared entrance"
        assert_file_contains "$dialog" 'exit: DialogTransition {' \
            "$(basename "$dialog") should use the shared exit"
    done
    assert_file_contains "$SHELL_DIR/modules/nexus/common/DialogTransition.qml" \
        'type: exiting ? Anim.FastEffects : Anim.DefaultEffects' \
        "an exit has to be shorter than its entrance"
    assert_file_contains "$SHELL_DIR/modules/nexus/common/DialogTransition.qml" \
        'from: exiting ? 1 : 0.9' \
        "an exit has to be smaller than its entrance"
}

test_icons_cross_fade_through_the_shared_recipe() {
    assert_file_contains "$COMPONENTS/StyledText.qml" 'property real swapFromScale: 1' \
        "the swap recipe has to be shared rather than copied"
    assert_file_contains "$COMPONENTS/MaterialIcon.qml" 'swapFromScale: 0.25' \
        "a glyph swap grows in; a run of text does not"
    assert_file_contains "$COMPONENTS/controls/IconButton.qml" 'property alias animateIcon: label.animate' \
        "a contextual glyph swap has to be able to opt in"
    assert_file_contains "$SHELL_DIR/modules/dashboard/media/Details.qml" 'animateIcon: true' \
        "play to pause is the swap this is for"
}

test_popouts_contain_their_overscroll() {
    assert_file_contains "$SHELL_DIR/modules/bar/popouts/Content.qml" 'boundsBehavior: Flickable.StopAtBounds' \
        "the popout viewport should stop at its bounds"
    assert_file_contains "$SHELL_DIR/modules/bar/popouts/kblayout/KbLayout.qml" 'boundsBehavior: Flickable.StopAtBounds' \
        "so should the keyboard layout list"
    assert_file_contains "$COMPONENTS/controls/Menu.qml" 'boundsBehavior: Flickable.StopAtBounds' \
        "so should the menu's item list"
}

test_no_dead_icon_asset_needs_a_colour_baked_in() {
    local hits
    hits="$(grep -rlE 'fill="#|stroke="#' "$SHELL_DIR/assets" --include='*.svg' 2>/dev/null || true)"
    if [[ -n "$hits" ]]; then
        fail "an icon SVG bakes in a colour instead of currentColor: $(printf '%s' "$hits" | paste -sd', ' -)"
    fi
}

run_tests
