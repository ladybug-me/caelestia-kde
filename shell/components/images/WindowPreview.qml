pragma ComponentBehavior: Bound

import org.kde.pipewire as Pipewire
import QtQuick
import Quickshell.Widgets
import Caelestia
import Caelestia.Config
import Caelestia.Images
import Caelestia.Services
import qs.components
import qs.components.images
import qs.utils

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
    property bool _thumbExists: root.thumbPath ? IUtils.fileExists(root.thumbPath) : false

    readonly property bool hasStream: stream.available
    readonly property string thumbPath: root.address ? `${Paths.runtimeDir}/caelestia/window-thumbs/${root.address.startsWith("0x") ? root.address.slice(2) : root.address}.png` : ""
    readonly property real fitted: root.sourceAspect > (root.width / Math.max(1, root.height)) ? root.width / root.sourceAspect : root.height

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
        implicitSize: Math.min(root.width, root.height) * root.fallbackScale
        source: root.fallbackIcon
        visible: root.fallbackIcon != "" && (!root.active || (!cachedThumb.visible && !root.hasStream))
    }

    CachingImage {
        id: cachedThumb

        anchors.centerIn: parent
        width: root.fitted * root.sourceAspect
        height: root.fitted
        path: (root.active && root._thumbExists) ? root.thumbPath : ""
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        visible: root.active && GlobalConfig.bar.livePreviews && root._thumbExists && status === Image.Ready && opacity > 0
        opacity: root.hasStream ? 0 : 1

        Behavior on opacity {
            Anim { type: Anim.FastEffects }
        }
    }

    Pipewire.PipeWireSourceItem {
        id: sourceItem

        anchors.centerIn: parent
        width: root.fitted * root.sourceAspect
        height: root.fitted
        opacity: root.hasStream ? 1 : 0
        visible: root.active && opacity > 0

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

        Behavior on opacity {
            Anim { type: Anim.FastEffects }
        }
    }

    Timer {
        id: grabTimer

        interval: 400
        repeat: false
        onTriggered: {
            if (root.hasStream && root.address && sourceItem.width > 0 && sourceItem.height > 0 && root.thumbPath) {
                CUtils.saveItem(sourceItem, Qt.resolvedUrl("file://" + root.thumbPath), () => {
                    root._thumbExists = true;
                });
            }
        }
    }

    Connections {
        function onStreamChanged(): void {
            if (stream.available) {
                grabTimer.restart();
            }
        }

        target: stream
    }
}
