pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
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
    property int initialSubPageIdx: -1

    readonly property NexusState nState: NexusState {
        id: nState

        currentPageIdx: root.initialPageIdx
        Component.onCompleted: {
            if (root.initialSubPageIdx !== -1)
                openSubPage(root.initialSubPageIdx);
        }

        onClose: root.requestClose()
    }
    property color blobColour: Colours.tPalette.m3surfaceContainerLow

    signal close

    function requestClose(): void {
        root.close();
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
        anchors.left: navPane.right
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: navPane.anchors.margins + anchors.margins
        anchors.margins: Tokens.padding.extraLarge

        nState: nState
    }
}
