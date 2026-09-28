import QtQuick
import Quickshell

QtObject {
    readonly property string assetDir: "../../assets/whatsnew/"

    readonly property var list: [
        {
            "id": "installer_window_rules",
            "revision": 19,
            "icon": "rule",
            "title": qsTr("Window Rules Out of the Box"),
            "description": qsTr("The installer now writes three KWin rules: unfocused windows and dialogs dim to 95 percent, dialogs open centered, and picture-in-picture windows stay above others. Only Caelestia's own groups are written, so your rules keep their names and their order. Edit or remove them under System Settings -> Window Rules, or let uninstall.sh take them out again.")
        },
        {
            "id": "app_context_menu",
            "revision": 20,
            "icon": "ads_click",
            "title": qsTr("Right-Click Any App"),
            "description": qsTr("An app in the launcher or its app browser now opens a context menu on right click: pin it to the dock, add it to the desktop, hide it from the launcher, or open it in the menu editor. The dock's pinned list is its own setting now (bar.dock.pinnedApps) instead of borrowing the launcher's favorites, and an existing list is carried over.")
        },
        {
            "id": "status_icons_and_bar_options",
            "revision": 21,
            "icon": "space_dashboard",
            "title": qsTr("Status Icons You Can Arrange"),
            "settingsPage": "panels",
            "settingsSubPage": 10,
            "description": qsTr("The bar's status icons are an ordered list now instead of a wall of switches: add one, switch it off, or drag it into place under Settings -> Panels -> Taskbar -> Status icons, and the bar draws them in that order. The clock can show seconds, and the workspace indicator can hide the ones that are empty and inactive.")
        },
        {
            "id": "game_mode_quick_toggle",
            "revision": 22,
            "icon": "gamepad",
            "title": qsTr("Game Mode at a Tap"),
            "settingsPage": "utilities",
            "settingsSubPage": 1,
            "description": qsTr("The utilities panel has a game mode toggle: it stops window animations and blur, pauses a video wallpaper and stops the desktop media shapes while it is on, then puts everything back afterwards. Game mode can still switch itself on when one of your target windows opens, under Settings -> Utilities -> Game mode.")
        },
        {
            "id": "color_intensity",
            "revision": 23,
            "icon": "tune",
            "title": qsTr("Color Intensity"),
            "settingsPage": "appearance",
            "settingsSubPage": 10,
            "description": qsTr("Advanced color settings gained a slider that scales how saturated the palette derived from your wallpaper is: 0 percent leaves the same palette in grey, 100 percent is what the color engine produces, and 200 percent is the most the accents take. It is kept with the scheme, so it survives a wallpaper change and a reboot, and 'caelestia scheme set -i' sets it from the command line.")
        },
        {
            "id": "dock_app_badges",
            "revision": 24,
            "icon": "badge",
            "title": qsTr("Dock App Badges"),
            "settingsPage": "panels",
            "settingsSubPage": 12,
            "description": qsTr("Dock icons can now display the count, progress, and urgency published by running applications. Configure it under Settings -> Panels -> Taskbar -> Dock.")
        },
        {
            "id": "ambient_glow",
            "revision": 25,
            "icon": "flare",
            "title": qsTr("Ambient Glow"),
            "settingsPage": "appearance",
            "settingsSubPage": 8,
            "description": qsTr("Shell surfaces and window previews can now cast a subtle, dynamic ambient glow derived from the window content. Enable it under Settings -> Appearance.")
        },
        {
            "id": "lockscreen_password_reveal",
            "revision": 26,
            "icon": "visibility",
            "title": qsTr("Lock Screen Password Reveal"),
            "description": qsTr("Click or tap the lock icon inside the greeter's password pill to reveal your typed password before unlocking.")
        }
    ]

    function mediaSource(entry: var): url {
        if (!entry || !entry.mediaUrl)
            return "";
        if (entry.mediaUrl.startsWith("root:"))
            return Qt.resolvedUrl(`${Quickshell.shellDir}${entry.mediaUrl.slice("root:".length)}`);
        return Qt.resolvedUrl(`${assetDir}${entry.mediaUrl}`);
    }
}
