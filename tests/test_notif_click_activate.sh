#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NOTIF_DATA="$REPO_ROOT/shell/services/NotifData.qml"
NOTIF_POPUP="$REPO_ROOT/shell/modules/notifications/Notification.qml"
SWIPE_DELEGATE="$REPO_ROOT/shell/modules/sidebar/NotifSwipeDelegate.qml"

test_notif_data_defines_activate_failsafes() {
    local content
    content="$(cat "$NOTIF_DATA")"

    assert_contains "$content" 'function activate(): bool' \
        "NotifData must define activate typed function"
    assert_contains "$content" 'if (shellRaised)' \
        "activate must guard against shellRaised notifications launching apps"
    assert_contains "$content" 'lowerApp === "notify-send"' \
        "activate must guard against CLI notify-send"
    assert_contains "$content" 'lowerApp.startsWith("caelestia")' \
        "activate must guard against internal caelestia tools"
    assert_contains "$content" 'entry.id.includes("caelestia-shell")' \
        "activate must never launch caelestia-shell desktop entry"
    assert_contains "$content" 'actions.find(a => a.identifier === "open")' \
        "activate should support open action as primary fallback"
}

test_popup_guards_link_clicks_and_swipes() {
    local popup
    popup="$(cat "$NOTIF_POPUP")"

    assert_contains "$popup" 'swiped || (root.expanded && body.hoveredLink)' \
        "popup click handler must guard against hoveredLink and swipe gestures"
    assert_contains "$popup" 'swiped = Math.abs(root.x) > drag.threshold;' \
        "popup onReleased must update swiped state"
    assert_contains "$popup" 'swiped = false;' \
        "popup onPressed must reset swiped state"
}

test_swipe_delegate_resets_swiped_on_pressed() {
    local delegate
    delegate="$(cat "$SWIPE_DELEGATE")"

    assert_contains "$delegate" 'root.swiped = false;' \
        "swipe delegate onPressed must reset swiped state"
}

test_activate_runtime_logic() {
    if ! command -v qml6 >/dev/null 2>&1; then
        skip_test "qml6 not available for runtime execution test"
        return 0
    fi

    local tmp_qml output
    tmp_qml="$(mktemp /tmp/test_activate_XXXXXX.qml)"

    cat <<'EOF' > "$tmp_qml"
import QtQml

QtObject {
    id: root

    property var lastLaunched: null
    property var mockLaunch: QtObject {
        function launchEntry(entry: var): void {
            root.lastLaunched = entry.id;
        }
    }

    property var mockDesktopEntries: QtObject {
        function heuristicLookup(name: string): var {
            if (name === "firefox" || name === "org.mozilla.firefox")
                return { id: "firefox.desktop" };
            if (name === "caelestia-shell" || name === "Caelestia")
                return { id: "caelestia-shell.desktop" };
            return null;
        }
    }

    function createNotif(props: var): var {
        return {
            actions: props.actions ?? [],
            shellRaised: props.shellRaised ?? false,
            appName: props.appName ?? "",
            hints: props.hints ?? ({}),
            activate: function(): bool {
                const Launch = root.mockLaunch;
                const DesktopEntries = root.mockDesktopEntries;

                const action = this.actions.find(a => a.identifier === "default")
                    ?? this.actions.find(a => a.identifier === "open")
                    ?? this.actions.find(a => a.identifier === "run")
                    ?? (this.actions.length === 1 ? this.actions[0] : null);
                if (action) {
                    action.invoke();
                    return true;
                }

                if (this.shellRaised)
                    return false;

                const lowerApp = (this.appName ?? "").toLowerCase();
                if (lowerApp === "notify-send"
                        || lowerApp.startsWith("caelestia")
                        || lowerApp === "screenshot"
                        || lowerApp === "color picker")
                    return false;

                const desktopHint = this.hints?.["desktop-entry"];
                if (desktopHint && desktopHint.toLowerCase().startsWith("caelestia"))
                    return false;

                const entry = DesktopEntries.heuristicLookup(desktopHint || this.appName);
                if (!entry || entry.id.includes("caelestia-shell"))
                    return false;

                Launch.launchEntry(entry);
                return true;
            }
        };
    }

    Component.onCompleted: {
        let actionInvoked = false;
        const n1 = createNotif({
            appName: "Firefox",
            actions: [{ identifier: "default", invoke: () => { actionInvoked = true; } }]
        });
        print("T1_ACTION:" + n1.activate() + ":" + actionInvoked);

        const n2 = createNotif({
            appName: "Firefox",
            hints: { "desktop-entry": "firefox" }
        });
        print("T2_LAUNCH:" + n2.activate() + ":" + root.lastLaunched);

        const n3 = createNotif({
            appName: "Caelestia",
            shellRaised: true
        });
        print("T3_SHELL_RAISED:" + n3.activate());

        const n4 = createNotif({
            appName: "notify-send"
        });
        print("T4_NOTIFY_SEND:" + n4.activate());

        const n5 = createNotif({
            appName: "Caelestia Update"
        });
        print("T5_CAELESTIA_UPDATE:" + n5.activate());

        const n6 = createNotif({
            appName: "RandomApp",
            hints: { "desktop-entry": "caelestia-shell" }
        });
        print("T6_SHELL_ENTRY_BLOCKED:" + n6.activate());

        let openInvoked = false;
        const n7 = createNotif({
            appName: "Screenshot",
            actions: [{ identifier: "open", invoke: () => { openInvoked = true; } }, { identifier: "folder", invoke: () => {} }]
        });
        print("T7_OPEN_ACTION:" + n7.activate() + ":" + openInvoked);

        Qt.quit();
    }
}
EOF

    output="$(QT_FORCE_STDERR_LOGGING=1 QT_LOGGING_TO_CONSOLE=1 QT_QPA_PLATFORM=offscreen qml6 -a core "$tmp_qml" 2>&1 || true)"
    rm -f "$tmp_qml"

    assert_contains "$output" "T1_ACTION:true:true" "default action must be invoked"
    assert_contains "$output" "T2_LAUNCH:true:firefox.desktop" "desktop app must be launched for regular apps"
    assert_contains "$output" "T3_SHELL_RAISED:false" "shellRaised notifications must never launch apps"
    assert_contains "$output" "T4_NOTIFY_SEND:false" "notify-send must not launch apps"
    assert_contains "$output" "T5_CAELESTIA_UPDATE:false" "caelestia CLI tools must not launch apps"
    assert_contains "$output" "T6_SHELL_ENTRY_BLOCKED:false" "caelestia-shell desktop entry must never be launched"
    assert_contains "$output" "T7_OPEN_ACTION:true:true" "open action fallback must be invoked for screenshots"
}

run_tests
