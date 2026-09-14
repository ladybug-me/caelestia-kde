pragma ComponentBehavior: Bound
import "../singletons"
import Qt5Compat.GraphicalEffects
import QtQuick
import "shapes"
import "shapes/material-shapes.js" as MaterialShapes

Item {
    id: root

    property int currentUserIndex: 0
    property var userModel: null
    property var onSwitchUser: null
    // Actual visual size, from the shape bounds.
    readonly property var bounds: bgShape.bounds

    onCurrentUserIndexChanged: {
        if (avatarImage.status !== Image.Null)
            avatarImage.rebuildAvatarCandidates();
    }
    implicitWidth: Theme.avatarFrameSize
    implicitHeight: Theme.avatarShape === "clamshell" ? 220 : Theme.avatarFrameSize
    clip: true

    property real hoverBoost: avatarHover.containsMouse ? 0.05 : 0
    scale: 1.0 + root.hoverBoost + avatarBounce.bounce

    Behavior on hoverBoost {
        NumberAnimation {
            duration: Theme.animDurationFast
            easing.type: Easing.OutCubic
        }
    }

    TapBounce {
        id: avatarBounce
    }

    Item {
        id: shapeContainer

        width: Theme.avatarFrameSize
        height: Theme.avatarFrameSize
        x: root.bounds ? (root.implicitWidth / 2 - (root.bounds[0] + root.bounds[2]) / 2 * Theme.avatarFrameSize) : 0
        y: root.bounds ? (root.implicitHeight / 2 - (root.bounds[1] + root.bounds[3]) / 2 * Theme.avatarFrameSize) : 0

        ShapeCanvas {
            id: bgShape

            anchors.fill: parent
            roundedPolygon: {
                if (Theme.avatarShape === "circle")
                    return MaterialShapes.getCircle();

                if (Theme.avatarShape === "cookie" || Theme.avatarShape === "cookie4sided" || Theme.avatarShape === "cookie4")
                    return MaterialShapes.getCookie4Sided();

                return MaterialShapes.getClamShell();
            }
            color: "#000000"
        }

        Image {
            id: avatarImage

            property var avatarCandidates: ["../assets/logo.png"]
            property int avatarCandidateIndex: 0
            property int roleHomeDir: Qt.UserRole + 3
            property int roleIcon: Qt.UserRole + 4

            function toSourceUrl(pathOrUrl) {
                if (!pathOrUrl || pathOrUrl === "")
                    return "";

                var value = String(pathOrUrl);
                if (value.startsWith("file://") || value.startsWith("qrc:/") || value.startsWith(":/") || value.startsWith("http://") || value.startsWith("https://"))
                    return value;

                if (value.startsWith("/"))
                    return "file://" + value;

                return value;
            }

            function appendCandidate(list, value) {
                var normalized = toSourceUrl(value);
                if (normalized !== "" && list.indexOf(normalized) === -1)
                    list.push(normalized);
            }

            function rebuildAvatarCandidates() {
                var list = [];
                appendCandidate(list, "../assets/avatar.face.icon");
                appendCandidate(list, "../assets/avatar.face");
                if (root.userModel) {
                    if (root.currentUserIndex >= 0 && root.currentUserIndex < root.userModel.count) {
                        const modelIndex = root.userModel.index(root.currentUserIndex, 0);
                        const icon = root.userModel.data(modelIndex, roleIcon);
                        const homeDir = root.userModel.data(modelIndex, roleHomeDir);
                        appendCandidate(list, icon);
                        if (homeDir && homeDir !== "") {
                            appendCandidate(list, homeDir + "/.face.icon");
                            appendCandidate(list, homeDir + "/.face");
                        }
                    }
                }
                appendCandidate(list, "../assets/logo.png");
                avatarCandidates = list;
                avatarCandidateIndex = 0;
            }

            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            smooth: true
            mipmap: true
            layer.enabled: true
            source: avatarCandidates.length > 0 ? avatarCandidates[avatarCandidateIndex] : "../assets/logo.png"
            onStatusChanged: {
                if (status === Image.Error && avatarCandidateIndex < avatarCandidates.length - 1)
                    avatarCandidateIndex += 1;
            }
            Component.onCompleted: rebuildAvatarCandidates()

            layer.effect: OpacityMask {
                maskSource: bgShape
            }
        }
    }

    MouseArea {
        id: avatarHover

        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            avatarBounce.trigger();
            if (root.onSwitchUser)
                root.onSwitchUser();
        }
    }
}
