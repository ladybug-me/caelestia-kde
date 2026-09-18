pragma ComponentBehavior: Bound

import org.kde.pipewire as Pipewire
import QtQuick
import Quickshell.Widgets
import Caelestia.Config
import Caelestia.Services

// A window's live preview, with the application icon standing in until there is
// a stream to show -- or permanently, if KWin will not give one out.
//
// The four surfaces that want this had grown four copies of the same twenty
// lines: request a stream, letterbox a PipeWireSourceItem inside the available
// space, and swap in an icon when nothing arrives. They differed in small ways
// that were bugs rather than intent, so it lives here now.
Item {
    id: root

    required property string address
    /// Whether this preview currently wants pixels. Streams are finite; see
    /// WindowStream::active.
    property bool active: true
    /// Shown until the first frame arrives, and whenever there is no stream.
    property url fallbackIcon: ""
    property real fallbackScale: 0.5
    /// Width over height of the window being shown, used to letterbox the feed.
    /// PipeWireSourceItem fills whatever it is given, so without this a 16:9
    /// window in a square card comes out stretched.
    property real sourceAspect: 16 / 9

    readonly property bool hasStream: stream.available

    WindowStream {
        id: stream

        // bar.livePreviews is the user's switch for this whole feature -- it
        // exists because KWin's screencast protocol cannot always be shared, and
        // on some setups the shell holding streams breaks another application's
        // screen share or camera. ScreencastManager used to gate on it; when it
        // was replaced the gate was not carried over, leaving the setting
        // writable and read by nothing.
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
