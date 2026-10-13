pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import qs.components.effects
import qs.services

// The icon of a FileEntry, tinted when Material You icons are on and falling
// back to the system theme when the bundled set has no match. Optionally
// clipped to a rounded square: full-bleed square icons get rounded corners
// while shaped icons on a transparent background are left as they are.
Item {
    id: root

    required property var entry
    property bool materialYou: false
    property bool vibrant: false
    property bool rounded: DesktopLayout.roundIcons
    property bool failed: false

    readonly property bool tinted: materialYou && !failed
    readonly property alias status: image.status

    onEntryChanged: failed = false
    onMaterialYouChanged: failed = false

    Image {
        id: image

        anchors.fill: parent
        source: !root.entry ? "" : root.failed ? root.entry.fallbackIconSource() : root.entry.iconSource(root.materialYou)
        sourceSize.width: width
        sourceSize.height: height
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        visible: !clip.active
        layer.enabled: root.tinted
        layer.effect: Colouriser {
            sourceColor: "black"
            colorizationColor: {
                const c = Colours.palette.m3primary;
                if (root.vibrant)
                    return Qt.hsla(c.hslHue, 1.0, Math.max(0.4, Math.min(0.6, c.hslLightness)), c.a);
                return c;
            }
        }

        onStatusChanged: {
            if (status === Image.Error && root.materialYou && !root.failed)
                root.failed = true;
        }
    }

    // Tinted icons are glyphs, so only full-colour icons get the corners.
    Loader {
        id: clip

        anchors.fill: parent
        active: root.rounded && !root.tinted && image.status === Image.Ready

        sourceComponent: MultiEffect {
            source: image
            maskEnabled: true
            maskSource: mask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }
    }

    Rectangle {
        id: mask

        anchors.fill: parent
        radius: width * 0.24
        visible: false
        layer.enabled: true
        layer.smooth: true
    }
}
