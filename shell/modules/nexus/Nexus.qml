pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import Caelestia.Blobs
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services
import qs.modules.nexus

Item {
    id: root

    property int initialPageIdx: 0
    property var initialSubPageIdx: -1
    readonly property bool windowActive: Window.window ? Window.window.active : false

    readonly property NexusState nState: NexusState {
        id: nState

        currentPageIdx: root.initialPageIdx
        Component.onCompleted: {
            if (root.initialSubPageIdx !== -1 && root.initialSubPageIdx !== undefined && root.initialSubPageIdx !== "")
                openSubPage(root.initialSubPageIdx);
        }

        onClose: root.requestClose()
    }
    property color blobColour: Colours.tPalette.m3surfaceContainerLow

    signal close

    function requestClose(): void {
        root.close();
    }

    function currentFlickable(): var {
        let item = pages.currentItem;
        while (item) {
            if (item.flickable !== undefined)
                return item.flickable;
            item = item.currentItem ?? null;
        }
        return null;
    }

    function scrollCurrentPage(event: var): bool {
        if (event.x <= navPane.x + navPane.width)
            return false;

        const f = root.currentFlickable();
        if (!f || !f.interactive)
            return false;

        // The page already handles the wheel when the cursor is over it.
        const pos = f.mapFromItem(root, event.x, event.y);
        if (pos.x >= 0 && pos.y >= 0 && pos.x <= f.width && pos.y <= f.height)
            return false;

        const maxY = Math.max(0, f.contentHeight - f.height);
        if (maxY <= 0)
            return false;

        f.contentY = Math.max(0, Math.min(maxY, f.contentY - event.angleDelta.y));
        return true;
    }

    implicitWidth: implicitHeight * Tokens.sizes.nexus.ratio
    implicitHeight: nState.screen.height * Tokens.sizes.nexus.heightMult

    Behavior on blobColour {
        CAnim {}
    }

    BlobGroup {
        id: blobGroup

        smoothing: root.Tokens.rounding.medium
        color: root.blobColour
    }

    BlobInvertedRect {
        anchors.fill: parent
        group: blobGroup
        opacity: root.blobColour.a
        radius: Tokens.rounding.large

        borderLeft: navPane.width + navPane.anchors.margins * 2
        borderRight: Tokens.padding.medium
        borderTop: Tokens.padding.medium
        borderBottom: Tokens.padding.medium
    }

    NavPane {
        id: navPane

        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.margins: Tokens.padding.large

        nState: nState
        width: Math.min(Tokens.sizes.nexus.maxNavWidth, Math.round(root.width / 3))
    }

    Pages {
        id: pages

        anchors.left: navPane.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: navPane.anchors.margins + anchors.margins
        anchors.margins: Tokens.padding.extraLarge

        nState: nState
    }

    // The page margins around the content are outside the page flickable, so
    // the wheel did nothing there. Forward it to the current page.
    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad

        onWheel: event => {
            if (root.scrollCurrentPage(event))
                event.accepted = true;
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton | Qt.ExtraButton1
        preventStealing: true

        onPressed: mouse => {
            WindowFactory.goBack();
            mouse.accepted = true;
        }
    }
}
