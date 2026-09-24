import QtQuick
import Quickshell

// The What's New release notes.
//
// Append new entries to the end of `list` with a revision higher than every
// entry above them. Never renumber or reorder an entry that has already
// shipped: an entry's revision is how the shell records that a user has
// acknowledged it, so changing one either re-shows the entry to everybody or
// hides it from them. Pruning old entries is fine, but their revisions stay
// used up, which is why this list does not start at 1. See the authoring notes
// in ../../assets/whatsnew/README.md.
QtObject {
    // Bare media names are resolved against this directory; "root:" addresses a
    // shared shell asset, matching the convention used by GlobalConfig paths.
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
            "description": qsTr("The bar's status icons are an ordered list now instead of a wall of switches: add one, switch it off, or drag it into place under Settings -> Panels -> Taskbar -> Status icons, and the bar draws them in that order. The clock can show seconds, and the workspace indicator can hide the ones that are empty and inactive.")
        },
        {
            "id": "game_mode_quick_toggle",
            "revision": 22,
            "icon": "gamepad",
            "title": qsTr("Game Mode at a Tap"),
            "description": qsTr("The utilities panel has a game mode toggle: it stops window animations and blur, pauses a video wallpaper and stops the desktop media shapes while it is on, then puts everything back afterwards. Game mode can still switch itself on when one of your target windows opens, under Settings -> Services -> Game mode.")
        },
        {
            "id": "color_intensity",
            "revision": 23,
            "icon": "tune",
            "title": qsTr("Color Intensity"),
            "description": qsTr("Advanced color settings gained a slider that scales how saturated the palette derived from your wallpaper is: 0 percent leaves the same palette in grey, 100 percent is what the color engine produces, and 200 percent is the most the accents take. It is kept with the scheme, so it survives a wallpaper change and a reboot, and 'caelestia scheme set -i' sets it from the command line.")
        },
        {
            "id": "dock_app_badges",
            "revision": 24,
            "icon": "badge",
            "title": qsTr("Dock App Badges"),
            "description": qsTr("Dock icons can now display the count, progress, and urgency published by running applications. Configure it under Settings -> Panels -> Taskbar -> Dock.")
        },
        {
            "id": "ambient_glow",
            "revision": 25,
            "icon": "flare",
            "title": qsTr("Ambient Glow"),
            "description": qsTr("Shell surfaces and window previews can now cast a subtle, dynamic ambient glow derived from the window content. Enable it under Settings -> Appearance.")
        },
        {
            "id": "lockscreen_password_reveal",
            "revision": 26,
            "icon": "visibility",
            "title": qsTr("Lock Screen Password Reveal"),
            "description": qsTr("Click or tap the lock icon inside the greeter's password pill to reveal your typed password before unlocking.")
        },
        {
            "id": "wifi_hotspot_toggle",
            "revision": 27,
            "icon": "wifi_tethering",
            "title": qsTr("Wi-Fi Hotspot at a Tap"),
            "description": qsTr("Turn your machine into a Wi-Fi hotspot from the network quick settings or the bar's network popout. The toggle creates, starts and stops the hotspot with your saved name and password, and the Network settings page shows who is connected.")
        },
        {
            "id": "clock_calendar_popout",
            "revision": 28,
            "icon": "calendar_month",
            "title": qsTr("Calendar From the Clock"),
            "description": qsTr("Click the bar's clock for a month calendar that walks through months and highlights today. Vertical bars open it just like horizontal ones, and the popout width adapts to the calendar.")
        },
        {
            "id": "plasma_visualiser_plasmoid",
            "revision": 29,
            "icon": "equalizer",
            "title": qsTr("Visualiser as a Plasma Widget"),
            "description": qsTr("The audio visualiser is now available as a native Plasma desktop widget: add it from the desktop's widget menu. It renders with the shell's cava engine, adapts to its size, and stops audio polling whenever it is hidden.")
        },
        {
            "id": "safer_installs_and_plugins",
            "revision": 30,
            "icon": "verified_user",
            "title": qsTr("Safer Installs and Plugins"),
            "description": qsTr("Every downloaded artifact - the prebuilt shell, the installer and the CAVA SDK - is now checksum-verified and safety-checked before it is unpacked, plugins from the store are validated before any command runs, and remote installer scripts are shown for review before they execute. Lock screen passwords are also wiped from memory shortly after typing stops.")
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
