#!/usr/bin/env bash

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIRROR="$REPO_ROOT/shell/scripts/mirror-idle-suspend.sh"

# The script reaches powerdevil through these two tools. The reader answers from
# PD_<PROFILE>_<KEY> variables, so a test states a profile's settings in the
# environment; the writer records every write it is asked to make.
make_stubs() {
    local dir="$1"
    mkdir -p "$dir"

    cat >"$dir/kreadconfig6" <<'EOF'
#!/bin/bash
profile=""
key=""
fallback=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --group)
            if [[ -z "$profile" ]]; then
                profile="${2:-}"
                profile="${profile^^}"
            fi
            shift 2
            ;;
        --key)
            key="${2:-}"
            key="${key^^}"
            shift 2
            ;;
        --default)
            fallback="${2:-}"
            shift 2
            ;;
        *) shift ;;
    esac
done
name="PD_${profile}_${key}"
printf '%s\n' "${!name:-$fallback}"
EOF

    cat >"$dir/kwriteconfig6" <<'EOF'
#!/bin/bash
profile=""
key=""
value=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --file) shift 2 ;;
        --group) [[ -z "$profile" ]] && profile="${2:-}"; shift 2 ;;
        --key) key="${2:-}"; shift 2 ;;
        *) value="$1"; shift ;;
    esac
done
printf '%s %s %s\n' "$profile" "$key" "$value" >>"${PD_LOG:?}"
if [[ "${PD_WRITE_FAILS:-0}" == "1" ]]; then
    exit 1
fi
exit 0
EOF

    chmod +x "$dir/kreadconfig6" "$dir/kwriteconfig6"
}

# PATH holds the stubs alone, so a developer machine's own kreadconfig6 cannot
# answer for them. env and bash are named by absolute path because their own
# lookup would otherwise go through that PATH.
ENV_BIN="$(command -v env)"

run_mirror() {
    local dir="$1" log="$2" seconds="$3"
    shift 3
    PATH="$dir" "$ENV_BIN" PD_LOG="$log" "$@" "$BASH" "$MIRROR" "$seconds" >/dev/null 2>&1
    printf '%s' "$?"
}

writes_to() {
    cat "$1" 2>/dev/null || true
}

test_a_kde_timer_is_moved_to_the_caelestia_timeout() {
    local dir log
    dir="$(new_tmpdir)/stubs"
    log="$(new_tmpdir)/writes.log"
    make_stubs "$dir"

    assert_eq "0" "$(run_mirror "$dir" "$log" 1800 \
        PD_AC_AUTOSUSPENDACTION=1 PD_AC_AUTOSUSPENDIDLETIMEOUTSEC=900 \
        PD_BATTERY_AUTOSUSPENDACTION=1 PD_BATTERY_AUTOSUSPENDIDLETIMEOUTSEC=600)" "the mirror should succeed"
    assert_contains "$(writes_to "$log")" "AC AutoSuspendIdleTimeoutSec 1800" "the AC profile should take the Caelestia timeout"
    assert_contains "$(writes_to "$log")" "Battery AutoSuspendIdleTimeoutSec 1800" "the battery profile should take the Caelestia timeout"
}

test_a_profile_that_never_suspends_is_left_alone() {
    local dir log
    dir="$(new_tmpdir)/stubs"
    log="$(new_tmpdir)/writes.log"
    make_stubs "$dir"

    run_mirror "$dir" "$log" 1800 \
        PD_AC_AUTOSUSPENDACTION=0 PD_AC_AUTOSUSPENDIDLETIMEOUTSEC=900 \
        PD_BATTERY_AUTOSUSPENDACTION=1 PD_BATTERY_AUTOSUSPENDIDLETIMEOUTSEC=600 >/dev/null
    assert_not_contains "$(writes_to "$log")" "AC " "a profile powerdevil does not suspend from has no timer to line up"
    assert_contains "$(writes_to "$log")" "Battery AutoSuspendIdleTimeoutSec 1800" "the profile that does suspend should still be lined up"
}

test_the_low_battery_profile_is_never_touched() {
    local dir log
    dir="$(new_tmpdir)/stubs"
    log="$(new_tmpdir)/writes.log"
    make_stubs "$dir"

    run_mirror "$dir" "$log" 1800 \
        PD_AC_AUTOSUSPENDACTION=1 PD_AC_AUTOSUSPENDIDLETIMEOUTSEC=900 \
        PD_BATTERY_AUTOSUSPENDACTION=1 PD_BATTERY_AUTOSUSPENDIDLETIMEOUTSEC=600 \
        PD_LOWBATTERY_AUTOSUSPENDACTION=2 PD_LOWBATTERY_AUTOSUSPENDIDLETIMEOUTSEC=420 >/dev/null
    assert_not_contains "$(writes_to "$log")" "LowBattery" "low battery sleeps early by design, not because of an idle preference"
}

test_a_timeout_that_already_matches_is_not_rewritten() {
    local dir log
    dir="$(new_tmpdir)/stubs"
    log="$(new_tmpdir)/writes.log"
    make_stubs "$dir"

    run_mirror "$dir" "$log" 1800 \
        PD_AC_AUTOSUSPENDACTION=1 PD_AC_AUTOSUSPENDIDLETIMEOUTSEC=1800 \
        PD_BATTERY_AUTOSUSPENDACTION=1 PD_BATTERY_AUTOSUSPENDIDLETIMEOUTSEC=1800 >/dev/null
    assert_eq "" "$(writes_to "$log")" "an already matching profile should not be written again"
}

test_caelestia_not_owning_suspend_touches_nothing() {
    local dir log
    dir="$(new_tmpdir)/stubs"
    log="$(new_tmpdir)/writes.log"
    make_stubs "$dir"

    run_mirror "$dir" "$log" 0 \
        PD_AC_AUTOSUSPENDACTION=1 PD_AC_AUTOSUSPENDIDLETIMEOUTSEC=900 \
        PD_BATTERY_AUTOSUSPENDACTION=1 PD_BATTERY_AUTOSUSPENDIDLETIMEOUTSEC=600 >/dev/null
    assert_eq "" "$(writes_to "$log")" "KDE's timers stay as the user left them while Caelestia has no suspend timeout"
}

test_a_failed_write_reaches_the_caller_and_spares_the_other_profile() {
    local dir log
    dir="$(new_tmpdir)/stubs"
    log="$(new_tmpdir)/writes.log"
    make_stubs "$dir"

    # The setting reads as applied either way, so the caller has to be able to
    # tell that the mirror did not land.
    assert_ne "0" "$(run_mirror "$dir" "$log" 1800 PD_WRITE_FAILS=1 \
        PD_AC_AUTOSUSPENDACTION=1 PD_AC_AUTOSUSPENDIDLETIMEOUTSEC=900 \
        PD_BATTERY_AUTOSUSPENDACTION=1 PD_BATTERY_AUTOSUSPENDIDLETIMEOUTSEC=600)" "a failed write has to reach the caller"
    assert_contains "$(writes_to "$log")" "Battery AutoSuspendIdleTimeoutSec 1800" "one failing profile must not stop the other"
}

test_missing_tools_are_not_a_reason_to_write() {
    local dir log
    dir="$(new_tmpdir)/stubs"
    log="$(new_tmpdir)/writes.log"
    mkdir -p "$dir"

    assert_eq "0" "$(run_mirror "$dir" "$log" 1800 PD_AC_AUTOSUSPENDACTION=1)" "without the tools the mirror should give up quietly"
    assert_eq "" "$(writes_to "$log")" "nothing can be written without them"
}

test_a_non_numeric_timeout_is_ignored() {
    local dir log
    dir="$(new_tmpdir)/stubs"
    log="$(new_tmpdir)/writes.log"
    make_stubs "$dir"

    assert_eq "0" "$(run_mirror "$dir" "$log" "half an hour" PD_AC_AUTOSUSPENDACTION=1 PD_AC_AUTOSUSPENDIDLETIMEOUTSEC=900)" "a nonsense timeout should be refused"
    assert_eq "" "$(writes_to "$log")" "a nonsense timeout must not reach powerdevil"
}

# Locking the session twice around a suspend - once by ksmserver on resume, once by our
# lockBeforeSleep - is the double-lock that leaves the greeter without its elements
# (issue #815). These keep the deference and the greeter's re-arm from being dropped;
# they are greps the way test_lock_password_reveal.sh guards its feature, because the
# greeter and the idle monitors only run inside a session.
IDLE_MONITORS="$REPO_ROOT/shell/modules/IdleMonitors.qml"
GENERAL_CONFIG="$REPO_ROOT/shell/plugin/src/Caelestia/Config/generalconfig.hpp"
POWER_PAGE="$REPO_ROOT/shell/modules/nexus/pages/PowerPage.qml"
LOCK_SCREEN_UI="$REPO_ROOT/src/kde/shells/caelestia.desktop/contents/lockscreen/LockScreenUi.qml"
SESSION_MANAGER="$REPO_ROOT/shell/plugin/src/Caelestia/Services/sessionmanager.cpp"

test_the_suspend_lock_defers_to_kdes_own_resume_lock() {
    local qml
    qml="$(cat "$IDLE_MONITORS")"

    assert_contains "$qml" "kreadconfig6 --file kscreenlockerrc --group Daemon --key LockOnResume" \
        "KDE's own resume lock is read before ours is fired"
    assert_contains "$qml" 'if (GlobalConfig.general.idle.lockBeforeSleep && !root.kdeLocksOnResume)' \
        "our lock is skipped when KDE locks on resume itself"
}

test_the_default_idle_lock_is_exposed_where_it_fires() {
    local hpp qml
    hpp="$(cat "$GENERAL_CONFIG")"
    assert_contains "$hpp" '{ u"timeout"_s, 180 },' "the 180 second idle lock default is still shipped"

    qml="$(cat "$POWER_PAGE")"
    assert_contains "$qml" 'qsTr("Idle lock")' "the idle lock has a row on the Power page"
    assert_contains "$qml" "lockTimeout" "the row edits the idle timeouts' lock entry"
}

test_the_greeter_re_arms_after_a_resume() {
    local qml
    qml="$(cat "$LOCK_SCREEN_UI")"

    assert_contains "$qml" "rearmAfterResume" "a resume re-runs the one-shot loaders"
    assert_contains "$qml" 'schemeLoader.connectSource' "the scheme is re-read"
    assert_contains "$qml" 'configLoader.connectSource' "the config is re-read"
    assert_contains "$qml" 'fetchLoader.connectSource' "the system info is re-read"
    assert_contains "$qml" 'now - mprisTimer.lastTick > 10000' \
        "a poll that lands far late is taken as the resume the host does not signal"
}

test_the_wallpaper_blur_survives_a_missing_wallpaper_item() {
    local qml
    qml="$(cat "$LOCK_SCREEN_UI")"

    assert_contains "$qml" 'typeof wallpaper !== "undefined" && wallpaper' \
        "the blur resolves the host's wallpaper to null rather than erroring"
    assert_contains "$qml" "wallpaperResolveNonce" "the lookup is repeated after a resume"
}

test_the_power_page_reports_and_documents_hibernation() {
    local qml
    qml="$(cat "$POWER_PAGE")"

    assert_contains "$qml" "CanHibernate" "logind is asked whether hibernation is available"
    assert_contains "$qml" "HibernateDelaySecUSec" "the hibernate delay is surfaced"
    assert_contains "$qml" "resume=" "the swap and resume= requirement is stated where the toggle lives"
}

test_the_suspend_fallback_to_plain_suspend_is_announced() {
    local cpp
    cpp="$(cat "$SESSION_MANAGER")"

    assert_contains "$cpp" 'tr("Hibernation is not available")' \
        "the fallback from suspend-then-hibernate to suspend says so"
}

run_tests
