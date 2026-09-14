
import QtQuick
import ".."
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import org.kde.kirigami as Kirigami

Rectangle {
    id: root

    property var liveNotifs: []
    property real centerScale: 1.0
    property bool isCaelestiaMode: false
    property bool hideNotifs: false

    property color clSurfaceContainer: "#131b1a"
    property color clSurfaceContainerHigh: "#192120"
    property color clSurfaceContainerHighest: "#1d2827"
    property color clSecondaryContainer: "#27403e"
    property color clSurfaceFg: "#dce8e6"
    property color clSurfaceVariantFg: "#a2adac"
    property color clOutline: "#6d7876"

    signal clearAllRequested()
    signal dndRequested(bool enabled)

    property bool isSystemDndEnabled: false

    property var groupedNotifs: []

    function resolveImageUrl(img) {
        if (!img) return "";
        var s = img.toString();
        if (s.startsWith("image://icon/")) {
            s = s.substring("image://icon/".length);
        }
        if (s.startsWith("/")) {
            return "file://" + s;
        }
        return s;
    }

    function formatNotifTime(timeStr) {
        if (!timeStr) return "now";
        try {
            var t = new Date(timeStr);
            var diff = Math.floor((new Date() - t) / 1000);
            if (isNaN(diff) || diff < 60) return "now";
            if (diff < 3600) return Math.floor(diff / 60) + "m";
            if (diff < 86400) return Math.floor(diff / 3600) + "h";
            return Math.floor(diff / 86400) + "d";
        } catch(e) {
            return "now";
        }
    }

    function updateGroups() {
        var list = root.liveNotifs || [];
        if (list.length === 0) {
            groupedNotifs = [];
            return;
        }
        var map = {};
        var order = [];
        for (var i = 0; i < list.length; i++) {
            var n = list[i];
            if (n.closed) continue;
            var app = n.appName || "Notifications";
            if (!map[app]) {
                map[app] = {
                    appName: app,
                    notifs: [],
                    image: "",
                    appIcon: "",
                    urgency: 0,
                    latestTime: n.time || ""
                };
                order.push(app);
            }
            var grp = map[app];
            grp.notifs.push(n);
            if (!grp.image && n.image && n.image.length > 0) {
                grp.image = n.image;
            }
            if (!grp.appIcon && n.appIcon && n.appIcon.length > 0) {
                grp.appIcon = n.appIcon;
            }
            if (n.urgency > grp.urgency) {
                grp.urgency = n.urgency;
            }
        }
        var result = [];
        for (var j = 0; j < order.length; j++) {
            result.push(map[order[j]]);
        }
        groupedNotifs = result;
    }

    onLiveNotifsChanged: updateGroups()
    Component.onCompleted: updateGroups()

    property real cardRadius: 26
    radius: cardRadius
    color: clSurfaceContainer
    clip: true

    RowLayout {
        id: headerRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 16 * centerScale

        opacity: (dinoLoader.isGameRunning || root.isSystemDndEnabled) ? 0 : 1
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: 250 } }

            Text {
                Layout.fillWidth: true
                text: root.hideNotifs
                      ? "Unlock for Notifications"
                      : (root.liveNotifs.length > 0
                          ? (root.liveNotifs.length + (root.liveNotifs.length === 1 ? " notification" : " notifications"))
                          : "Notifications")
                font { pixelSize: LockScreenConfig.sizeSmall; family: LockScreenConfig.fontBody; weight: Font.Medium }
                color: root.clOutline
                elide: Text.ElideRight
            }

            Rectangle {
                scale: (!root.hideNotifs && root.liveNotifs.length > 0) ? 1 : 0.5
                opacity: (!root.hideNotifs && root.liveNotifs.length > 0) ? 1 : 0
                visible: opacity > 0
                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }
                Behavior on opacity { NumberAnimation { duration: 250 } }
                implicitWidth: 32 * root.centerScale
                implicitHeight: 32 * root.centerScale
                radius: height / 2
                color: "transparent"

                Text {
                    anchors.centerIn: parent
                    text: "clear_all"
                    font.family: LockScreenConfig.fontIcon
                    font.pixelSize: LockScreenConfig.sizeLarge * root.centerScale
                    color: root.clSurfaceFg
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.clearAllRequested()
                    onEntered: parent.color = Qt.rgba(255, 255, 255, 0.1)
                    onExited: parent.color = "transparent"
                }
            }
        }

        Loader {
            id: dinoLoader
            z: 1
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: headerRow.bottom
            anchors.bottom: parent.bottom
            anchors.margins: 16 * centerScale
            anchors.topMargin: 12 * centerScale

            active: root.hideNotifs || root.liveNotifs.length === 0 || isGameRunning || root.isSystemDndEnabled
            readonly property bool isGameRunning: item !== null && item.isPlaying === true

            onIsGameRunningChanged: {
                root.dndRequested(isGameRunning)
            }

            opacity: active ? 1 : 0
            visible: active
            Behavior on opacity { NumberAnimation { duration: 250 } }

            sourceComponent: Item {
                readonly property bool isPlaying: dinoGame.isPlaying
                DinoGame {
                    id: dinoGame
                    anchors.centerIn: parent
                    width: dinoLoader.width
                    height: 200
                    activeColor: root.clSurfaceVariantFg
                    isCaelestiaMode: root.isCaelestiaMode
                }
            }
        }

        ListView {
            id: notifListView
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: headerRow.bottom
            anchors.bottom: parent.bottom
            anchors.margins: 16 * centerScale
            anchors.topMargin: 12 * centerScale
            clip: true

            opacity: (!root.hideNotifs && !dinoLoader.isGameRunning && !root.isSystemDndEnabled) ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 250 } }
            spacing: 10 * root.centerScale
            boundsBehavior: Flickable.StopAtBounds

            add: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 250 }
                    NumberAnimation { property: "scale"; from: 0.8; to: 1; duration: 250; easing.type: Easing.OutBack }
                }
            }
            addDisplaced: Transition {
                NumberAnimation { properties: "x,y"; duration: 250; easing.type: Easing.OutQuad }
            }

            remove: Transition {
                ParallelAnimation {
                    NumberAnimation { property: "opacity"; to: 0; duration: 250 }
                    NumberAnimation { property: "scale"; to: 0.8; duration: 250; easing.type: Easing.InBack }
                }
            }
            removeDisplaced: Transition {
                NumberAnimation { properties: "x,y"; duration: 250; easing.type: Easing.OutQuad }
            }

            model: root.groupedNotifs

            delegate: Rectangle {
                id: groupCard
                width: ListView.view.width
                radius: 18 * root.centerScale
                color: modelData.urgency === 2 ? root.clSecondaryContainer : root.clSurfaceContainerHigh
                clip: true

                property bool expanded: false

                implicitHeight: groupContent.implicitHeight + 24 * root.centerScale
                Behavior on implicitHeight {
                    NumberAnimation { duration: 220; easing.type: Easing.OutCubic }
                }

                RowLayout {
                    id: groupContent
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 12 * root.centerScale
                    spacing: 12 * root.centerScale

                    Item {
                        Layout.alignment: Qt.AlignTop
                        implicitWidth: 44 * root.centerScale
                        implicitHeight: 44 * root.centerScale

                        Rectangle {
                            id: iconCircle
                            anchors.fill: parent
                            radius: width / 2
                            color: root.clSurfaceContainerHighest
                            clip: true

                            Image {
                                id: groupImg
                                anchors.fill: parent
                                source: root.resolveImageUrl(modelData.image)
                                fillMode: Image.PreserveAspectCrop
                                visible: status === Image.Ready
                                layer.enabled: true
                                layer.effect: OpacityMask {
                                    maskSource: Rectangle {
                                        width: iconCircle.width
                                        height: iconCircle.height
                                        radius: iconCircle.radius
                                    }
                                }
                            }

                            Kirigami.Icon {
                                anchors.centerIn: parent
                                width: 22 * root.centerScale
                                height: 22 * root.centerScale
                                source: modelData.appIcon || "preferences-desktop-notification"
                                fallback: "preferences-desktop-notification"
                                visible: !groupImg.visible
                            }
                        }

                        Rectangle {
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.rightMargin: -2 * root.centerScale
                            anchors.bottomMargin: -2 * root.centerScale
                            width: 18 * root.centerScale
                            height: 18 * root.centerScale
                            radius: width / 2
                            color: root.clSurfaceContainerHigh
                            visible: groupImg.visible && Boolean(modelData.appIcon && modelData.appIcon.length > 0)
                            z: 2

                            Kirigami.Icon {
                                anchors.centerIn: parent
                                width: 11 * root.centerScale
                                height: 11 * root.centerScale
                                source: modelData.appIcon
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 4 * root.centerScale

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8 * root.centerScale

                            Text {
                                Layout.fillWidth: true
                                text: modelData.appName
                                font { pixelSize: LockScreenConfig.sizeMedium; family: LockScreenConfig.fontBody; weight: Font.Medium }
                                color: root.clSurfaceVariantFg
                                elide: Text.ElideRight
                            }

                            Text {
                                text: root.formatNotifTime(modelData.latestTime)
                                font { pixelSize: LockScreenConfig.sizeSmall; family: LockScreenConfig.fontBody }
                                color: root.clOutline
                            }

                            Rectangle {
                                id: expandPill
                                visible: modelData.notifs.length > 3
                                implicitWidth: expandPillLayout.implicitWidth + 16
                                implicitHeight: 24
                                radius: height / 2
                                color: root.clSurfaceContainerHighest

                                RowLayout {
                                    id: expandPillLayout
                                    anchors.centerIn: parent
                                    spacing: 4

                                    Text {
                                        text: modelData.notifs.length
                                        font { pixelSize: LockScreenConfig.sizeVerySmall; family: LockScreenConfig.fontBody; weight: Font.Medium }
                                        color: root.clSurfaceFg
                                    }

                                    Text {
                                        text: groupCard.expanded ? "expand_less" : "expand_more"
                                        font.family: LockScreenConfig.fontIcon
                                        font.pixelSize: LockScreenConfig.sizeMedium
                                        color: root.clSurfaceFg
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: groupCard.expanded = !groupCard.expanded
                                }
                            }
                        }

                        Repeater {
                            model: groupCard.expanded ? modelData.notifs : modelData.notifs.slice(0, 3)

                            delegate: Item {
                                Layout.fillWidth: true
                                implicitHeight: lineText.implicitHeight

                                Text {
                                    id: lineText
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    textFormat: Text.StyledText
                                    elide: Text.ElideRight
                                    font { pixelSize: LockScreenConfig.sizeSmall; family: LockScreenConfig.fontBody }
                                    text: {
                                        var sum = (modelData.summary || "").replace(/\n/g, " ");
                                        var body = (modelData.body || "").replace(/\n/g, " ");
                                        sum = sum.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
                                        body = body.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
                                        if (body.length > 0) {
                                            return "<font color='" + root.clSurfaceFg + "'>" + sum + "</font>  <font color='" + root.clOutline + "'>" + body + "</font>";
                                        }
                                        return "<font color='" + root.clSurfaceFg + "'>" + sum + "</font>";
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
