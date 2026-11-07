pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.components.filedialog
import qs.components.images
import qs.services
import qs.utils

// An image on the desktop: a sticker, a logo, an animated GIF. Double click to pick
// another file; the card is moved and resized from the widget editor like the rest.
Item {
    id: root

    property var frame
    property var controller

    readonly property var cfg: frame?.config ?? ({})
    readonly property string path: cfg.path ?? ""
    readonly property real imageOpacity: typeof cfg.opacity === "number" ? Math.max(0, Math.min(1, cfg.opacity)) : 1
    readonly property bool animated: /\.gif$/i.test(root.path)

    function chooseImage(): void {
        dialog.open();
    }

    StyledText {
        anchors.centerIn: parent
        visible: root.path === ""
        width: root.width
        text: qsTr("Double click to choose an image")
        color: Colours.palette.m3outline
        font: Tokens.font.body.medium
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
    }

    CachingImage {
        anchors.fill: parent
        visible: root.path !== "" && !root.animated
        path: root.path
        fillMode: Image.PreserveAspectFit
        opacity: root.imageOpacity
    }

    CachingAnimatedImage {
        anchors.fill: parent
        visible: root.path !== "" && root.animated
        path: root.path
        fillMode: Image.PreserveAspectFit
        opacity: root.imageOpacity
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onDoubleClicked: root.chooseImage()
    }

    FileDialog {
        id: dialog

        title: qsTr("Choose an image")
        filters: ["*.png", "*.jpg", "*.jpeg", "*.webp", "*.svg", "*.gif"]
        filterLabel: qsTr("Images")
        cwd: root.path.startsWith(Paths.home) ? ["Home", ...root.path.substring(Paths.home.length).split("/").filter(s => s.length > 0)] : ["Home"]
        onAccepted: path => root.frame?.setConfig({ path: path.replace(/^file:\/\//, "") })
    }
}
