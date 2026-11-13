pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Caelestia
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.controls
import qs.components.effects
import qs.components.images
import qs.services
import qs.utils
import qs.modules.launcher.services

Item {
    id: root

    required property DrawerVisibilities visibilities
    required property var panels
    required property real maxWidth
    required property real maxHeight

    readonly property int padding: Tokens.padding.large
    readonly property int rounding: Tokens.rounding.extraLarge
    readonly property bool isClipboardMode: search.text.startsWith(`${GlobalConfig.launcher.actionPrefix}clipboard `)
    readonly property int footerSpacing: Tokens.spacing.small
    // The profile picture hangs off the top edge of the card, so only its lower
    // half takes room inside the panel. The drawers window paints the circle
    // above the launcher and joins it to the card through the blob group.
    readonly property int avatarSize: Math.round(Tokens.sizes.launcher.browseTileHeight * 1.3)
    readonly property int headerHeight: root.modernStyle ? Math.round(root.avatarSize / 2 - 6) : 0
    readonly property bool isBrowsing: list.showAppsBrowser
    // Classic keeps the launcher as it shipped (session row under the search
    // field); Modern is the profile picture header with the corner actions.
    readonly property bool modernStyle: Style.launcherStyle === "modern"
    // The drawers window reads this to draw the circle behind the avatar.
    readonly property bool showAvatar: root.modernStyle

    function clearClipboardHistory(): void {
        Clipboard.clearHistory();
    }

    function searchTextForMode(mode: string): string {
        return mode ? `${GlobalConfig.launcher.actionPrefix}${mode} ` : "";
    }

    function triggerSessionCommand(command: list<string>): void {
        root.visibilities.launcher = false;
        if (!SessionManager.exec(command))
            Quickshell.execDetached(command);
    }

    implicitWidth: listWrapper.width + padding * 2
    implicitHeight: listWrapper.height + sessionFooter.height + searchWrapper.height + listWrapper.anchors.bottomMargin + sessionFooter.anchors.bottomMargin + searchWrapper.anchors.bottomMargin + root.headerHeight

    Connections {
        function onClearHistoryFinished(success: bool): void {
            if (success) {
                if (GlobalConfig.utilities.toasts.clipboardChanged)
                    Toaster.toast(qsTr("Clipboard history cleared"), "", "delete");
            } else {
                Toaster.toast(qsTr("Failed to clear clipboard history"), "", "error");
            }
        }

        target: Clipboard
    }

    Item {
        id: listWrapper

        implicitWidth: list.implicitWidth
        implicitHeight: list.implicitHeight + root.padding

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: root.modernStyle ? searchWrapper.top : sessionFooter.top
        anchors.bottomMargin: root.footerSpacing

        ContentList {
            id: list

            content: root
            visibilities: root.visibilities
            panels: root.panels
            maxWidth: root.maxWidth - root.padding * 2
            maxHeight: root.maxHeight - searchWrapper.implicitHeight - root.padding * 2 - (root.modernStyle ? root.headerHeight + root.footerSpacing : sessionFooter.implicitHeight + (sessionFooter.visible ? root.footerSpacing * 2 : root.footerSpacing))
            search: search
            padding: root.padding
            rounding: root.rounding
        }
    }

    // The profile picture sits on the top edge of the card: its centre is the
    // panel's top edge, so half the circle floats above the launcher and the
    // drawers window merges it with the card background.
    Item {
        id: avatar

        property int ring: Math.max(6, Math.round(root.avatarSize * 0.08))

        visible: root.modernStyle
        anchors.horizontalCenter: parent.horizontalCenter
        y: 4 - (root.avatarSize / 2 + 4) * (panels.launcher?.avatarOpenScale ?? (root.modernStyle ? 1 : 0))
        opacity: panels.launcher?.avatarOpenScale ?? (root.modernStyle ? 1 : 0)
        implicitWidth: root.avatarSize
        implicitHeight: root.avatarSize

        Item {
            id: avatarClip

            anchors.fill: parent
            layer.enabled: true
            layer.smooth: true
            layer.effect: Mask {
                maskSource: avatarMask
            }

            Item {
                anchors.fill: parent
                anchors.margins: avatar.ring

                Rectangle {
                    anchors.fill: parent
                    visible: face.status !== Image.Ready
                    color: Colours.layer(Colours.palette.m3surfaceContainerHighest, 2)

                    Behavior on color {
                        CAnim {}
                    }
                }

                CachingImage {
                    id: face

                    anchors.fill: parent
                    path: Style.avatarPath !== "" ? Style.avatarPath : `${Paths.home}/.face`
                }

                Loader {
                    anchors.centerIn: parent
                    active: face.status !== Image.Ready

                    sourceComponent: MaterialIcon {
                        text: "person"
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.extraLarge
                    }
                }
            }
        }

        Item {
            id: avatarMask

            anchors.fill: parent
            visible: false
            layer.enabled: true

            Rectangle {
                anchors.fill: parent
                anchors.margins: avatar.ring
                radius: Tokens.rounding.full
                color: "white"
            }
        }
    }

    StyledRect {
        id: sessionFooter

        visible: !root.modernStyle && Config.launcher.showPowerMenu

        color: Colours.layer(Colours.palette.m3surfaceContainerLow, 2)
        radius: Tokens.rounding.extraLarge

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: searchWrapper.top
        anchors.bottomMargin: visible ? root.footerSpacing : 0
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding

        implicitHeight: visible ? (footerLayout.implicitHeight + Tokens.padding.medium * 2) : 0

        ColumnLayout {
            id: footerLayout

            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            spacing: Tokens.spacing.small

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                IconTextButton {
                    Layout.fillWidth: true
                    type: TextButton.Tonal
                    icon: "logout"
                    text: qsTr("Log Out")
                    onClicked: root.triggerSessionCommand(["sh", "-c", "qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logout 2>/dev/null"])
                }

                IconTextButton {
                    Layout.fillWidth: true
                    type: TextButton.Tonal
                    icon: "bedtime"
                    text: qsTr("Sleep")
                    onClicked: root.triggerSessionCommand(["suspendThenHibernate"])
                }

                IconTextButton {
                    Layout.fillWidth: true
                    type: TextButton.Tonal
                    icon: "restart_alt"
                    text: qsTr("Restart")
                    inactiveColour: Colours.palette.m3secondaryContainer
                    inactiveOnColour: Colours.palette.m3onSecondaryContainer
                    onClicked: root.triggerSessionCommand(Config.session.commands.reboot)
                }

                IconTextButton {
                    Layout.fillWidth: true
                    type: TextButton.Tonal
                    icon: "power_settings_new"
                    text: qsTr("Shut Down")
                    inactiveColour: Colours.palette.m3errorContainer
                    inactiveOnColour: Colours.palette.m3onErrorContainer
                    onClicked: root.triggerSessionCommand(Config.session.commands.shutdown)
                }
            }
        }
    }

    Row {
        id: headerActions

        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: Tokens.padding.small
        anchors.rightMargin: root.padding
        spacing: Tokens.spacing.extraSmall

        IconButton {
            id: sortBtn

            visible: root.modernStyle && root.isBrowsing && Boolean(list.currentList?.sortMode)
            isRound: true
            type: IconButton.Tonal
            icon: list.currentList?.sortMode === "alpha" ? "sort_by_alpha" : "trending_up"

            onClicked: sortMenu.expanded = !sortMenu.expanded
        }

        IconButton {
            id: powerBtn

            visible: root.modernStyle && Config.launcher.showPowerMenu
            isRound: true
            type: IconButton.Tonal
            icon: "power_settings_new"

            onClicked: powerMenu.expanded = !powerMenu.expanded
        }
    }

    Menu {
        id: sortMenu

        attachTo: sortBtn
        attachSideX: Menu.Right
        thisSideX: Menu.Right
        attachSideY: Menu.Bottom
        thisSideY: Menu.Top
        marginY: Tokens.spacing.extraSmall

        items: [
            MenuItem {
                text: qsTr("Most used")
                icon: "trending_up"
                trailingIcon: list.currentList?.sortMode === "alpha" ? "" : "check"

                onClicked: {
                    sortMenu.expanded = false;
                    list.currentList?.setSortMode("most-used");
                }
            },
            MenuItem {
                text: qsTr("A-Z")
                icon: "sort_by_alpha"
                trailingIcon: list.currentList?.sortMode === "alpha" ? "check" : ""

                onClicked: {
                    sortMenu.expanded = false;
                    list.currentList?.setSortMode("alpha");
                }
            }
        ]
    }

    Menu {
        id: powerMenu

        attachTo: powerBtn
        attachSideX: Menu.Right
        thisSideX: Menu.Right
        attachSideY: Menu.Bottom
        thisSideY: Menu.Top
        marginY: Tokens.spacing.extraSmall

        items: [
            MenuItem {
                text: qsTr("Log Out")
                icon: "logout"

                onClicked: {
                    powerMenu.expanded = false;
                    root.triggerSessionCommand(["sh", "-c", "qdbus6 org.kde.Shutdown /Shutdown org.kde.Shutdown.logout 2>/dev/null"]);
                }
            },
            MenuItem {
                text: qsTr("Sleep")
                icon: "bedtime"

                onClicked: {
                    powerMenu.expanded = false;
                    root.triggerSessionCommand(["suspendThenHibernate"]);
                }
            },
            MenuItem {
                text: qsTr("Restart")
                icon: "restart_alt"

                onClicked: {
                    powerMenu.expanded = false;
                    root.triggerSessionCommand(Config.session.commands.reboot);
                }
            },
            MenuItem {
                text: qsTr("Shut Down")
                icon: "power_settings_new"

                onClicked: {
                    powerMenu.expanded = false;
                    root.triggerSessionCommand(Config.session.commands.shutdown);
                }
            }
        ]
    }

    StyledRect {
        id: searchWrapper

        color: Colours.layer(Colours.palette.m3surfaceContainer, 2)
        radius: Tokens.rounding.full

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: root.padding
        anchors.bottomMargin: CUtils.clamp(root.padding - Config.border.thickness, 0, root.padding)

        implicitHeight: Math.max(searchIcon.implicitHeight, search.implicitHeight, clearClipboardIcon.implicitHeight, clearIcon.implicitHeight, commandsBtn.implicitHeight)

        MaterialIcon {
            id: searchIcon

            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: root.padding

            text: "search"
            color: Colours.palette.m3onSurfaceVariant
        }

        StyledTextField {
            id: search

            anchors.left: searchIcon.right
            anchors.right: clearClipboardIcon.left
            anchors.leftMargin: Tokens.spacing.small
            anchors.rightMargin: Tokens.spacing.small

            topPadding: Tokens.padding.medium
            bottomPadding: Tokens.padding.medium

            placeholderText: qsTr("Type \"%1\" for commands").arg(GlobalConfig.launcher.actionPrefix)

            onAccepted: {
                if (list.showAppsBrowser) {
                    list.currentList?.activateCurrent();
                    return;
                }

                const currentItem = list.currentList?.currentItem;
                if (!currentItem)
                    return;

                // The wallpapers list is the one surface whose rows are not launcher
                // delegates, so it activates by path here; everything else owns its
                // activation and does not need to be re-derived from the text.
                if (list.showWallpapers) {
                    Wallpapers.setWallpaper(currentItem.modelData.path);
                    root.visibilities.launcher = false;
                } else {
                    currentItem.activate();
                }
            }

            Keys.onUpPressed: {
                if (!list.showWallpapers)
                    list.currentList?.decrementCurrentIndex();
            }
            Keys.onDownPressed: {
                if (!list.showWallpapers)
                    list.currentList?.incrementCurrentIndex();
            }
            Keys.onLeftPressed: event => {
                if (list.showWallpapers || list.showWindowSwitcher) {
                    list.currentList?.decrementCurrentIndex();
                    event.accepted = true;
                } else if (list.showAppsBrowser) {
                    list.currentList?.moveLeft();
                    event.accepted = true;
                } else {
                    event.accepted = false;
                }
            }
            Keys.onRightPressed: event => {
                if (list.showWallpapers || list.showWindowSwitcher) {
                    list.currentList?.incrementCurrentIndex();
                    event.accepted = true;
                } else if (list.showAppsBrowser) {
                    list.currentList?.moveRight();
                    event.accepted = true;
                } else {
                    event.accepted = false;
                }
            }

            Keys.onEscapePressed: {
                Windows.isSwitching = false;
                Kwin.clearHighlight();
                root.visibilities.launcher = false;
            }

            Keys.onReleased: event => {
                if (Windows.isSwitching && text.startsWith(`${GlobalConfig.launcher.actionPrefix}windows `)) {
                    const switcherKey = (typeof KeybindsModel !== "undefined" && KeybindsModel.getKey("windowSwitcher")) || "Alt+Tab";
                    if (!CUtils.isShortcutModifierPressed(switcherKey)) {
                        Windows.focusSelectedWindow();
                        root.visibilities.launcher = false;
                        event.accepted = true;
                    }
                }
            }

            Keys.onPressed: event => {
                if (Windows.isSwitching && text.startsWith(`${GlobalConfig.launcher.actionPrefix}windows `)) {
                    if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                        if (event.modifiers & Qt.ShiftModifier || event.key === Qt.Key_Backtab) {
                            Windows.triggerCyclePrev();
                        } else {
                            Windows.triggerCycleNext();
                        }
                        event.accepted = true;
                        return;
                    }
                    if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
                        Windows.triggerCyclePrev();
                        event.accepted = true;
                        return;
                    }
                    if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
                        Windows.triggerCycleNext();
                        event.accepted = true;
                        return;
                    }
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        Windows.focusSelectedWindow();
                        root.visibilities.launcher = false;
                        event.accepted = true;
                        return;
                    }
                    if (event.key === Qt.Key_Escape) {
                        Windows.isSwitching = false;
                        Kwin.clearHighlight();
                        root.visibilities.launcher = false;
                        event.accepted = true;
                        return;
                    }
                }

                if (list.showAppsBrowser && event.key === Qt.Key_Tab) {
                    list.currentList?.toggleFocus();
                    event.accepted = true;
                    return;
                }

                if (!GlobalConfig.launcher.vimKeybinds)
                    return;

                if (event.modifiers & Qt.ControlModifier) {
                    if (event.key === Qt.Key_J || event.key === Qt.Key_N) {
                        list.currentList?.incrementCurrentIndex();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_K || event.key === Qt.Key_P) {
                        list.currentList?.decrementCurrentIndex();
                        event.accepted = true;
                    }
                } else if (event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier))) {
                    list.currentList?.decrementCurrentIndex();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Tab) {
                    list.currentList?.incrementCurrentIndex();
                    event.accepted = true;
                }
            }

            onTextChanged: {
                if (root.visibilities.launcher)
                    Visibilities.launcherMode = Visibilities.modeForText(text);
                if (!text.startsWith(`${GlobalConfig.launcher.actionPrefix}windows `)) {
                    Windows.isSwitching = false;
                    Kwin.clearHighlight();
                }
            }

            Component.onCompleted: {
                // The launcher may have opened before this content was created.
                if (root.visibilities.launcher)
                    text = root.searchTextForMode(Visibilities.launcherMode);
                forceActiveFocus();
            }

            Connections {
                function onLauncherChanged(): void {
                    if (root.visibilities.launcher) {
                        search.text = root.searchTextForMode(Visibilities.launcherMode);
                        search.forceActiveFocus();
                    } else {
                        Windows.isSwitching = false;
                        Kwin.clearHighlight();
                        Wallpapers.stopPreview();
                    }
                }

                function onSessionChanged(): void {
                    if (!root.visibilities.session)
                        search.forceActiveFocus();
                }

                target: root.visibilities
            }

            Connections {
                // A different mode asked for while the panel is already open.
                function onLauncherOpened(mode: string): void {
                    if (Visibilities.launcherScreen === root.visibilities)
                        search.text = root.searchTextForMode(mode);
                }

                target: Visibilities
            }

            Connections {
                function onClosed(): void {
                    search.text = "";
                }

                target: root.panels.launcher
            }
        }

        MaterialIcon {
            id: clearClipboardIcon

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: clearIcon.left
            anchors.rightMargin: (root.isClipboardMode && Clipboard.items.length > 0) ? Tokens.spacing.small : 0

            width: (root.isClipboardMode && Clipboard.items.length > 0) ? implicitWidth : 0
            opacity: (root.isClipboardMode && Clipboard.items.length > 0) ? 1 : 0

            text: "delete"
            color: clipboardMouse.containsMouse ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant

            MouseArea {
                id: clipboardMouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: (root.isClipboardMode && Clipboard.items.length > 0) ? Qt.PointingHandCursor : undefined

                onClicked: {
                    if (!root.isClipboardMode || Clipboard.items.length === 0)
                        return;

                    if (GlobalConfig.launcher.confirmClearClipboard)
                        clearClipboardConfirmPopup.open();
                    else
                        root.clearClipboardHistory();
                }
            }

            Behavior on color {
                CAnim {}
            }

            Behavior on width {
                Anim {
                    type: Anim.StandardSmall
                }
            }

            Behavior on opacity {
                Anim {
                    type: Anim.StandardSmall
                }
            }
        }

        MaterialIcon {
            id: clearIcon

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: commandsBtn.left
            anchors.rightMargin: search.text ? Tokens.spacing.small : 0

            width: search.text ? implicitWidth : 0
            opacity: search.text ? 1 : 0

            text: "close"
            color: mouse.containsMouse ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant

            MouseArea {
                id: mouse

                anchors.fill: parent
                hoverEnabled: true
                cursorShape: search.text ? Qt.PointingHandCursor : undefined

                onClicked: search.text = ""
            }

            Behavior on color {
                CAnim {}
            }

            Behavior on width {
                Anim {
                    type: Anim.StandardSmall
                }
            }

            Behavior on opacity {
                Anim {
                    type: Anim.StandardSmall
                }
            }
        }

        IconButton {
            id: commandsBtn

            isToggle: true
            type: IconButton.Text
            implicitWidth: 32
            implicitHeight: 32
            radius: Tokens.rounding.full
            radiusMorph: false
            icon: "menu"

            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: root.padding
            checked: search.text.startsWith(GlobalConfig.launcher.actionPrefix)

            onClicked: {
                if (search.text.startsWith(GlobalConfig.launcher.actionPrefix)) {
                    search.text = "";
                } else {
                    search.text = GlobalConfig.launcher.actionPrefix;
                }
                search.forceActiveFocus();
                search.cursorPosition = search.text.length;
            }
        }
    }

    Popup {
        id: clearClipboardConfirmPopup

        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        x: Math.round((root.width - width) / 2)
        y: Math.round((root.height - height) / 2)

        padding: Tokens.padding.large

        contentItem: Column {
            spacing: Tokens.spacing.medium

            StyledText {
                text: qsTr("Clear clipboard history?")
                font: Tokens.font.body.builders.large.weight(Font.Medium).build()
            }

            StyledText {
                text: qsTr("This removes all clipboard entries.")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.small
            }

            Row {
                spacing: Tokens.spacing.small

                TextButton {
                    text: qsTr("Cancel")
                    onClicked: clearClipboardConfirmPopup.close()
                }

                TextButton {
                    text: qsTr("Clear")
                    type: TextButton.Filled
                    onClicked: {
                        clearClipboardConfirmPopup.close();
                        root.clearClipboardHistory();
                    }
                }
            }
        }

        background: StyledRect {
            radius: Tokens.rounding.large
            color: Colours.palette.m3surfaceContainer
        }
    }
}
