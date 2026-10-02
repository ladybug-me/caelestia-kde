import QtQuick
import qs.components.effects
import qs.services

// The icon of a FileEntry, tinted when Material You icons are on and falling
// back to the system theme when the bundled set has no match.
Image {
    id: root

    required property var entry
    property bool materialYou: false
    property bool vibrant: false
    property bool failed: false

    readonly property bool tinted: materialYou && !failed

    source: !entry ? "" : failed ? entry.fallbackIconSource() : entry.iconSource(materialYou)
    sourceSize.width: width
    sourceSize.height: height
    fillMode: Image.PreserveAspectFit
    asynchronous: true
    layer.enabled: tinted
    layer.effect: Colouriser {
        sourceColor: "black"
        colorizationColor: {
            const c = Colours.palette.m3primary;
            if (root.vibrant)
                return Qt.hsla(c.hslHue, 1.0, Math.max(0.4, Math.min(0.6, c.hslLightness)), c.a);
            return c;
        }
    }

    onEntryChanged: failed = false
    onMaterialYouChanged: failed = false
    onStatusChanged: {
        if (status === Image.Error && materialYou && !failed)
            failed = true;
    }
}
