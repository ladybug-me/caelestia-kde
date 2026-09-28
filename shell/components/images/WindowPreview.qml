pragma ComponentBehavior: Bound

import org.kde.pipewire as Pipewire
import QtQuick
import Quickshell.Widgets
import Caelestia.Config
import Caelestia.Services

Item {
    id: root

    required property string address
    property bool active: true
    /// Shown until the first frame arrives, and whenever there is no stream.
    property url fallbackIcon: ""
    property real fallbackScale: 0.5
    property real sourceAspect: 16 / 9

    readonly property bool hasStream: stream.available

    WindowStream {
        id: stream

        active: root.active && GlobalConfig.bar.livePreviews
        address: root.address
    }

    IconImage {
        anchors.centerIn: parent
        asynchronous: true
        implicitSize: Math.min(root.width, root.height) * root.fallbackScale
        source: root.fallbackIcon
        visible: !root.hasStream
    }

    Pipewire.PipeWireSourceItem {
        readonly property real fitted: root.sourceAspect > (root.width / Math.max(1, root.height)) ? root.width / root.sourceAspect : root.height

        anchors.centerIn: parent
        height: fitted
        visible: root.hasStream
        width: fitted * root.sourceAspect

        // objectSerial is the binding that works for an unprivileged client;
        // nodeId is deprecated upstream and needs PipeWire registry access this
        // shell does not have. Older KPipeWire only has the latter, so pick
        // whichever the installed version actually exposes.
        Component.onCompleted: {
            if ("objectSerial" in this)
                this.objectSerial = Qt.binding(() => stream.objectSerial);
            else if ("nodeId" in this)
                this.nodeId = Qt.binding(() => stream.nodeId);
        }
    }
}
