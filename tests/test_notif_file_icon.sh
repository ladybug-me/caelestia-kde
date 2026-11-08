#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ICONS_QML="$REPO_ROOT/shell/utils/Icons.qml"
NOTIF_POPUP="$REPO_ROOT/shell/modules/notifications/Notification.qml"
NOTIF_GROUP="$REPO_ROOT/shell/modules/sidebar/NotifGroup.qml"

test_icons_defines_get_notif_app_icon() {
    local content
    content="$(cat "$ICONS_QML")"

    assert_contains "$content" 'function getNotifAppIcon(icon: string): string' \
        "Icons.qml must define getNotifAppIcon typed function"
    assert_contains "$content" 'if (!icon.startsWith("file://") && !icon.startsWith("/"))' \
        "a theme icon name is the only thing that reaches Quickshell.iconPath unchecked"
    assert_contains "$content" 'notificationIconExtensions.includes(extension)' \
        "a path the sender chose is only opened when it names a picture"
    assert_contains "$content" 'return Quickshell.iconPath(icon);' \
        "getNotifAppIcon must fall back to Quickshell.iconPath for theme icon names"
}

# The function is read out of the singleton rather than copied into the fixture, so this test
# cannot drift from what ships.
qml_function() {
    awk -v name="function $2(" '
        index($0, name) { capture = 1 }
        capture { print }
        capture && /^    }$/ { exit }
    ' "$1"
}

test_get_notif_app_icon_runtime_resolution() {
    if ! command -v qml6 >/dev/null 2>&1; then
        skip_test "qml6 not available for runtime execution test"
        return 0
    fi

    local tmp_qml output body extensions
    tmp_qml="$(mktemp /tmp/test_get_notif_app_icon_XXXXXX.qml)"
    body="$(qml_function "$ICONS_QML" getNotifAppIcon)"
    extensions="$(grep -F 'readonly property list<string> notificationIconExtensions:' "$ICONS_QML" | sed 's/^ *//')"

    if [[ -z "$body" || -z "$extensions" ]]; then
        fail "getNotifAppIcon and its extension list have to be readable out of Icons.qml"
        rm -f "$tmp_qml"
        return 0
    fi

    {
        printf 'import QtQml\n\nQtObject {\n    id: root\n\n'
        printf '    %s\n\n' "$extensions"
        printf '    readonly property var Quickshell: ({\n'
        printf '        iconPath: icon => "THEME_ICON:" + icon\n'
        printf '    })\n\n'
        printf '%s\n\n' "$body"
        cat <<'EOF'
    Component.onCompleted: {
        print("TEST_FILE_URI:" + getNotifAppIcon("file:///home/user/app.png"));
        print("TEST_ABSOLUTE_PATH:" + getNotifAppIcon("/opt/google/chrome/icon.png"));
        print("TEST_THEME_NAME:" + getNotifAppIcon("firefox"));
        print("TEST_NOT_A_PICTURE:" + getNotifAppIcon("/home/user/.ssh/id_rsa"));
        print("TEST_FILE_URI_NOT_A_PICTURE:" + getNotifAppIcon("file:///etc/shadow"));
        Qt.quit();
    }
}
EOF
    } > "$tmp_qml"

    output="$(QT_FORCE_STDERR_LOGGING=1 QT_LOGGING_TO_CONSOLE=1 QT_QPA_PLATFORM=offscreen qml6 -a core "$tmp_qml" 2>&1 || true)"
    rm -f "$tmp_qml"

    assert_contains "$output" "TEST_FILE_URI:file:///home/user/app.png" \
        "getNotifAppIcon must preserve file:// URIs without double-prefixing"
    assert_contains "$output" "TEST_ABSOLUTE_PATH:file:///opt/google/chrome/icon.png" \
        "getNotifAppIcon must prefix absolute paths with file://"
    assert_contains "$output" "TEST_THEME_NAME:THEME_ICON:firefox" \
        "getNotifAppIcon must delegate standard icon names to Quickshell.iconPath"
    assert_contains "$output" "TEST_NOT_A_PICTURE:THEME_ICON:application-x-executable" \
        "a path that is not a picture must not be opened on the sender's say-so"
    assert_contains "$output" "TEST_FILE_URI_NOT_A_PICTURE:THEME_ICON:application-x-executable" \
        "nor a file:// URI that is not a picture"
}

test_notification_popup_binds_get_notif_app_icon() {
    local popup
    popup="$(cat "$NOTIF_POPUP")"

    assert_file_matches "$NOTIF_POPUP" 'source: Icons\.getNotifAppIcon\(root\.modelData(\?\.appIcon \?\? "")?(\.appIcon)?\)' \
        "Notification popup ColouredIcon must bind Icons.getNotifAppIcon"
    assert_not_contains "$popup" 'source: Quickshell.iconPath(root.modelData' \
        "Notification popup ColouredIcon must not directly call Quickshell.iconPath"
    assert_file_matches "$NOTIF_POPUP" 'layer\.enabled: root\.modelData(\?\.appIcon\?\.endsWith\("symbolic"\) \?\? false|\.appIcon\.endsWith\("symbolic"\))' \
        "Notification popup must preserve symbolic icon colorization guard"
}

test_sidebar_notif_group_binds_get_notif_app_icon() {
    local sidebar
    sidebar="$(cat "$NOTIF_GROUP")"

    local matches
    matches="$(grep -c 'source: Icons.getNotifAppIcon(root.appIcon)' <<<"$sidebar" || true)"
    assert_eq "2" "$matches" "NotifGroup must bind Icons.getNotifAppIcon(root.appIcon) for both group header and badge"

    assert_not_contains "$sidebar" 'source: Quickshell.iconPath(root.appIcon)' \
        "NotifGroup must not directly call Quickshell.iconPath"
    assert_contains "$sidebar" 'layer.enabled: root.appIcon.endsWith("symbolic")' \
        "NotifGroup must preserve symbolic icon colorization guard"
}

run_tests
