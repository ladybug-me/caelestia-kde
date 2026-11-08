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
    assert_contains "$content" 'if (icon.startsWith("file://") || icon.startsWith("/"))' \
        "getNotifAppIcon must check for file:// URI or absolute path"
    assert_contains "$content" 'return icon.startsWith("/") ? `file://${icon}` : icon;' \
        "getNotifAppIcon must format absolute paths as file:// URIs and preserve file:// as-is"
    assert_contains "$content" 'return Quickshell.iconPath(icon);' \
        "getNotifAppIcon must fall back to Quickshell.iconPath for theme icon names"
}

test_get_notif_app_icon_runtime_resolution() {
    if ! command -v qml6 >/dev/null 2>&1; then
        skip_test "qml6 not available for runtime execution test"
        return 0
    fi

    local tmp_qml output
    tmp_qml="$(mktemp /tmp/test_get_notif_app_icon_XXXXXX.qml)"

    cat <<'EOF' > "$tmp_qml"
import QtQml

QtObject {
    id: root

    property var quickshellMock: QtObject {
        function iconPath(icon: string): string {
            return "THEME_ICON:" + icon;
        }
    }

    function getNotifAppIcon(icon: string): string {
        if (icon.startsWith("file://") || icon.startsWith("/"))
            return icon.startsWith("/") ? `file://${icon}` : icon;
        return quickshellMock.iconPath(icon);
    }

    Component.onCompleted: {
        print("TEST_FILE_URI:" + getNotifAppIcon("file:///home/user/app.png"));
        print("TEST_ABSOLUTE_PATH:" + getNotifAppIcon("/opt/google/chrome/icon.png"));
        print("TEST_THEME_NAME:" + getNotifAppIcon("firefox"));
        Qt.quit();
    }
}
EOF

    output="$(QT_FORCE_STDERR_LOGGING=1 QT_LOGGING_TO_CONSOLE=1 QT_QPA_PLATFORM=offscreen qml6 -a core "$tmp_qml" 2>&1 || true)"
    rm -f "$tmp_qml"

    assert_contains "$output" "TEST_FILE_URI:file:///home/user/app.png" \
        "getNotifAppIcon must preserve file:// URIs without double-prefixing"
    assert_contains "$output" "TEST_ABSOLUTE_PATH:file:///opt/google/chrome/icon.png" \
        "getNotifAppIcon must prefix absolute paths with file://"
    assert_contains "$output" "TEST_THEME_NAME:THEME_ICON:firefox" \
        "getNotifAppIcon must delegate standard icon names to Quickshell.iconPath"
}

test_notification_popup_binds_get_notif_app_icon() {
    local popup
    popup="$(cat "$NOTIF_POPUP")"

    assert_contains "$popup" 'source: Icons.getNotifAppIcon(root.modelData.appIcon)' \
        "Notification popup ColouredIcon must bind Icons.getNotifAppIcon(root.modelData.appIcon)"
    assert_not_contains "$popup" 'source: Quickshell.iconPath(root.modelData.appIcon)' \
        "Notification popup ColouredIcon must not directly call Quickshell.iconPath"
    assert_contains "$popup" 'layer.enabled: root.modelData.appIcon.endsWith("symbolic")' \
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
