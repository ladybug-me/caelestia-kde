pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import M3Shapes
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.filedialog
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    property string customWallpaperPath: ""

    readonly property list<MenuItem> fprintTriesItems: [
        MenuItem {
            property int value: 1

            text: qsTr("1 attempt")
        },
        MenuItem {
            property int value: 2

            text: qsTr("2 attempts")
        },
        MenuItem {
            property int value: 3

            text: qsTr("3 attempts")
        },
        MenuItem {
            property int value: 4

            text: qsTr("4 attempts")
        },
        MenuItem {
            property int value: 5

            text: qsTr("5 attempts")
        }
    ]

    readonly property list<MenuItem> lockShapeItems: [
        MenuItem {
            property int value: -1

            text: qsTr("Random")
        },
        MenuItem {
            property int value: MaterialShape.Circle

            text: qsTr("Circle")
        },
        MenuItem {
            property int value: MaterialShape.Square

            text: qsTr("Square")
        },
        MenuItem {
            property int value: MaterialShape.Pill

            text: qsTr("Pill")
        },
        MenuItem {
            property int value: MaterialShape.Diamond

            text: qsTr("Diamond")
        },
        MenuItem {
            property int value: MaterialShape.ClamShell

            text: qsTr("Clam Shell")
        },
        MenuItem {
            property int value: MaterialShape.Pentagon

            text: qsTr("Pentagon")
        },
        MenuItem {
            property int value: MaterialShape.Gem

            text: qsTr("Gem")
        },
        MenuItem {
            property int value: MaterialShape.Cookie4Sided

            text: qsTr("Cookie 4-Sided")
        },
        MenuItem {
            property int value: MaterialShape.Cookie6Sided

            text: qsTr("Cookie 6-Sided")
        },
        MenuItem {
            property int value: MaterialShape.Cookie7Sided

            text: qsTr("Cookie 7-Sided")
        },
        MenuItem {
            property int value: MaterialShape.Cookie9Sided

            text: qsTr("Cookie 9-Sided")
        },
        MenuItem {
            property int value: MaterialShape.Cookie12Sided

            text: qsTr("Cookie 12-Sided")
        }
    ]

    isSubPage: true
    title: qsTr("Lock Screen")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        Process {
            id: readWallpaperProc

            running: true
            command: ["kreadconfig6", "--file", "kscreenlockerrc", "--group", "Greeter", "--group", "Wallpaper", "--group", "org.kde.image", "--group", "General", "--key", "Image"]
            stdout: SplitParser {
                onRead: data => {
                    var p = data.trim();
                    if (p.startsWith("file://"))
                        p = p.slice(7);
                    root.customWallpaperPath = p;
                }
            }
        }

        SectionHeader {
            first: true
            text: qsTr("Wallpaper")
        }

        ToggleRow {
            first: true
            Layout.fillWidth: true
            text: qsTr("Sync with desktop wallpaper")
            subtext: qsTr("Keep the lock screen wallpaper in sync with the desktop wallpaper")
            reset: ({ node: GlobalConfig.lock, setting: "syncWallpaper" })
            checked: Config.lock.syncWallpaper
            onToggled: {
                GlobalConfig.lock.syncWallpaper = checked;
                GlobalConfig.save();
                if (checked && Wallpapers.current && !Images.isVideo(Wallpapers.current))
                    Wallpapers.syncPlasmaWallpaper(Wallpapers.current);
                else if (!checked)
                    readWallpaperProc.running = true;
            }
        }

        NavRow {
            visible: !Config.lock.syncWallpaper
            Layout.fillWidth: true
            icon: "image"
            label: qsTr("Lock screen wallpaper")
            status: root.customWallpaperPath ? root.customWallpaperPath.split("/").pop() : qsTr("Select an image...")
            onClicked: browseDialog.open()

            FileDialog {
                id: browseDialog

                title: qsTr("Select lock screen wallpaper")
                filterLabel: qsTr("Image files")
                filters: Images.validImageExtensions
                onAccepted: path => {
                    root.customWallpaperPath = path;
                    Quickshell.execDetached(["kwriteconfig6", "--file", "kscreenlockerrc", "--group", "Greeter", "--group", "Wallpaper", "--group", "org.kde.image", "--group", "General", "--key", "Image", "file://" + path]);
                }
            }
        }

        ToggleRow {
            last: true
            Layout.fillWidth: true
            text: qsTr("Blur wallpaper")
            subtext: qsTr("Blur the entire wallpaper, not just behind the widgets")
            reset: ({ node: GlobalConfig.lock, setting: "blurWallpaper" })
            checked: Config.lock.blurWallpaper
            onToggled: {
                GlobalConfig.lock.blurWallpaper = checked;
                GlobalConfig.save();
            }
        }

        SectionHeader {
            text: qsTr("Authentication")
        }

        ToggleRow {
            first: true
            Layout.fillWidth: true
            text: qsTr("Fingerprint unlock")
            subtext: qsTr("Allow fingerprint authentication on the lock screen")
            reset: ({ node: GlobalConfig.lock, setting: "enableFprint" })
            checked: Config.lock.enableFprint
            onToggled: {
                GlobalConfig.lock.enableFprint = checked;
                GlobalConfig.save();
            }
        }

        SelectRow {
            last: true
            Layout.fillWidth: true
            label: qsTr("Fingerprint attempts")
            subtext: qsTr("Tries before falling back to password")
            active: {
                for (let i = 0; i < fprintTriesItems.length; i++) {
                    if (fprintTriesItems[i].value === Config.lock.maxFprintTries)
                        return fprintTriesItems[i];
                }
                return fprintTriesItems[2];
            }
            menuItems: fprintTriesItems
            onSelected: item => {
                GlobalConfig.lock.maxFprintTries = item.value;
                GlobalConfig.save();
            }
        }

        SectionHeader {
            text: qsTr("General")
        }

        SelectRow {
            first: true
            Layout.fillWidth: true
            label: qsTr("Profile picture shape")
            subtext: qsTr("Choose the shape of the profile picture on the lock screen")
            fallbackIcon: "person"
            fallbackText: qsTr("Pentagon")
            active: {
                for (let i = 0; i < lockShapeItems.length; i++) {
                    if (lockShapeItems[i].value === GlobalConfig.lock.profilePicShape)
                        return lockShapeItems[i];
                }
                return lockShapeItems[0];
            }
            menuItems: lockShapeItems
            onSelected: item => {
                GlobalConfig.lock.profilePicShape = item.value;
                GlobalConfig.save();
            }
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Rotate profile picture shape")
            subtext: qsTr("Continuously rotate the profile picture shape")
            reset: ({ node: GlobalConfig.lock, setting: "rotateProfilePic" })
            checked: Config.lock.rotateProfilePic
            onToggled: {
                GlobalConfig.lock.rotateProfilePic = checked;
                GlobalConfig.save();
            }
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Lock on startup")
            subtext: qsTr("Lock the session shortly after logging in")
            reset: ({ node: GlobalConfig.lock, setting: "lockOnStartup" })
            checked: Config.lock.lockOnStartup
            onToggled: {
                GlobalConfig.lock.lockOnStartup = checked;
                GlobalConfig.save();
            }
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Hide notifications")
            subtext: qsTr("Hide notification previews until you unlock")
            reset: ({ node: GlobalConfig.lock, setting: "hideNotifs" })
            checked: Config.lock.hideNotifs
            onToggled: {
                GlobalConfig.lock.hideNotifs = checked;
                GlobalConfig.save();
            }
        }

        ToggleRow {
            last: true
            Layout.fillWidth: true
            text: qsTr("Recolor logo")
            subtext: qsTr("Tint the lock screen artwork to match the palette")
            reset: ({ node: GlobalConfig.lock, setting: "recolourLogo" })
            checked: Config.lock.recolourLogo
            onToggled: {
                GlobalConfig.lock.recolourLogo = checked;
                GlobalConfig.save();
            }
        }

        SectionHeader {
            text: qsTr("Session icons")
        }

        ToggleRow {
            first: true
            Layout.fillWidth: true
            text: qsTr("Sleep")
            subtext: qsTr("Show sleep action on the lock screen")
            reset: ({ node: GlobalConfig.lock, setting: "showSleep" })
            checked: Config.lock.showSleep
            onToggled: {
                GlobalConfig.lock.showSleep = checked;
                GlobalConfig.save();
            }
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Hibernate")
            subtext: qsTr("Show hibernate action on the lock screen")
            reset: ({ node: GlobalConfig.lock, setting: "showHibernate" })
            checked: Config.lock.showHibernate
            onToggled: {
                GlobalConfig.lock.showHibernate = checked;
                GlobalConfig.save();
            }
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Switch user")
            subtext: qsTr("Show switch user action on the lock screen")
            reset: ({ node: GlobalConfig.lock, setting: "showSwitchUser" })
            checked: Config.lock.showSwitchUser
            onToggled: {
                GlobalConfig.lock.showSwitchUser = checked;
                GlobalConfig.save();
            }
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Log out")
            subtext: qsTr("Show log out action on the lock screen")
            reset: ({ node: GlobalConfig.lock, setting: "showLogout" })
            checked: Config.lock.showLogout
            onToggled: {
                GlobalConfig.lock.showLogout = checked;
                GlobalConfig.save();
            }
        }

        ToggleRow {
            Layout.fillWidth: true
            text: qsTr("Restart")
            subtext: qsTr("Show restart action on the lock screen")
            reset: ({ node: GlobalConfig.lock, setting: "showReboot" })
            checked: Config.lock.showReboot
            onToggled: {
                GlobalConfig.lock.showReboot = checked;
                GlobalConfig.save();
            }
        }

        ToggleRow {
            last: true
            Layout.fillWidth: true
            text: qsTr("Shut down")
            subtext: qsTr("Show shut down action on the lock screen")
            reset: ({ node: GlobalConfig.lock, setting: "showShutdown" })
            checked: Config.lock.showShutdown
            onToggled: {
                GlobalConfig.lock.showShutdown = checked;
                GlobalConfig.save();
            }
        }
    }
}

