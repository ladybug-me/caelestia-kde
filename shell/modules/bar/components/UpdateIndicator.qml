pragma ComponentBehavior: Bound

import QtQuick
import Caelestia.Config
import qs.components
import qs.services
import qs.utils
import qs.modules.nexus

Item {
    id: root

    readonly property bool isHorizontal: Config.bar.position === "top" || Config.bar.position === "bottom"

    readonly property int barThickness: Math.round(Tokens.sizes.bar.innerWidth * Math.max(0.6, !isNaN(Config.bar.scale) ? Config.bar.scale : 1.0))

    readonly property bool hasUpdate: UpdateChecker.hasUpdate

    readonly property bool checking: UpdateChecker.checkingUpdates

    // Index of the Nexus "Updates" page, resolved by page key so this
    // indicator can't drift out of sync if the page registry is reordered.
    readonly property int updatesPageIdx: {
        const idx = PageRegistry.indexForKey("updates");
        return idx >= 0 ? idx : 0;
    }

    implicitWidth: isHorizontal ? (icon.implicitWidth + Tokens.padding.small * 2) : barThickness
    implicitHeight: isHorizontal ? barThickness : (icon.implicitHeight + Tokens.padding.small * 2)

    MaterialIcon {
        id: icon

        anchors.centerIn: parent
        anchors.horizontalCenterOffset: Centering.pixelAlign(parent.width, width)
        text: root.checking ? "sync" : root.hasUpdate ? "update" : "check_circle"
        color: root.hasUpdate ? Colours.palette.m3primary : Colours.palette.m3secondary
    }

    StateLayer {
        anchors.fill: undefined
        anchors.centerIn: parent
        implicitWidth: root.implicitWidth
        implicitHeight: root.implicitHeight
        radius: Tokens.rounding.full
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        Accessible.name: qsTr("Caelestia updates")
        Accessible.role: Accessible.Button
        Accessible.description: qsTr("Left-click to open the Updates page. Right-click to check for updates")

        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                UpdateChecker.checkUpdates();
            } else {
                WindowFactory.create(null, { initialPageIdx: root.updatesPageIdx });
            }
        }
    }
}
