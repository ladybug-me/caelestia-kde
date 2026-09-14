pragma ComponentBehavior: Bound
import Qt5Compat.GraphicalEffects
import QtQuick
import "shapes"
import "shapes/material-shapes.js" as MaterialShapes

Item {
    id: root

    z: 2

    property string avatarShape: "hexagon"

    property bool hovered: false
    property int hexIndex: 0
    property var shapeGetters: [MaterialShapes.getClamShell, MaterialShapes.getCookie6Sided]

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: root.hovered = true
        onExited: root.hovered = false
    }

    onHoveredChanged: {
        if (root.avatarShape !== "hexagon")
            return;
        if (hovered) {
            root.hexIndex = 1;
        } else {
            root.hexIndex = 0;
        }
    }

    ShapeCanvas {
        id: hexMask
        anchors.fill: parent
        visible: root.avatarShape === "hexagon"
        roundedPolygon: root.shapeGetters[root.hexIndex]()
        color: "#000000"
        clip: true
    }

    Rectangle {
        id: circleMask
        anchors.fill: parent
        visible: root.avatarShape === "circle"
        radius: Math.min(width, height) / 2
        color: "#000000"
    }

    property int currentUserIndex: 0
    property var userModel: null

    Image {
        id: avatarImage

        property var avatarCandidates: ["../assets/avatar.png"]
        property int avatarCandidateIndex: 0
        property int roleHomeDir: Qt.UserRole + 3
        property int roleIcon: Qt.UserRole + 4

        function toSourceUrl(pathOrUrl) {
            if (!pathOrUrl || pathOrUrl === "")
                return "";
            var value = String(pathOrUrl);
            if (value.startsWith("file://") || value.startsWith("qrc:/") || value.startsWith(":/"))
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
            if (root.userModel && root.currentUserIndex >= 0 && root.currentUserIndex < root.userModel.count) {
                var modelIndex = root.userModel.index(root.currentUserIndex, 0);
                var icon = root.userModel.data(modelIndex, roleIcon);
                var homeDir = root.userModel.data(modelIndex, roleHomeDir);
                appendCandidate(list, icon);
                if (homeDir && homeDir !== "") {
                    appendCandidate(list, homeDir + "/.face.icon");
                    appendCandidate(list, homeDir + "/.face");
                }
            }
            appendCandidate(list, "../assets/avatar.face.icon");
            appendCandidate(list, "../assets/avatar.face");
            appendCandidate(list, "../assets/avatar.png");
            avatarCandidates = list;
            avatarCandidateIndex = 0;
        }

        mipmap: true
        smooth: true
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        layer.enabled: true
        onStatusChanged: {
            if (status === Image.Error && avatarCandidateIndex < avatarCandidates.length - 1)
                avatarCandidateIndex += 1;
        }
        Component.onCompleted: rebuildAvatarCandidates()

        layer.effect: OpacityMask {
            maskSource: root.avatarShape === "circle" ? circleMask : hexMask
        }
    }
}
