pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services
import "wifi.js" as Wifi

Singleton {
    id: root

    property int reading: -1

    readonly property int strength: root.reading >= 0 ? root.reading : (Nmcli.active?.strength ?? 0)

    readonly property string interfaceName: Nmcli.wirelessDeviceDetails?.interface ?? ""
    readonly property bool watchable: Nmcli.isConnected && root.interfaceName !== ""

    onWatchableChanged: {
        if (!root.watchable)
            root.reading = -1;
    }

    Timer {
        interval: 10000
        repeat: true
        triggeredOnStart: true
        running: root.watchable
        onTriggered: probe.running = true
    }

    Process {
        id: probe

        command: ["iw", "dev", root.interfaceName, "link"]
        stdout: StdioCollector {
            onStreamFinished: root.reading = Wifi.qualityFromLink(text)
        }
    }
}
