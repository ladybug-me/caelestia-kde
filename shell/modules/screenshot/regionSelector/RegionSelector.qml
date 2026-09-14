import ".."
import QtQuick
import QtCore
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.components.misc
import qs.services

Scope {
    id: root

    property bool screenshotActive: false

    function dismiss() {
        root.screenshotActive = false
    }

    property var action: ScreenshotAction.SnipAction.Copy

    property var selectionMode: RegionSelection.SelectionMode.RectCorners

    // Persisted across screenshot sessions — written to disk via Settings below
    property bool showWindowOutlines: false

    Settings {
        property alias showWindowOutlines: root.showWindowOutlines

        category: "Screenshot"
    }

    Variants {
        model: Quickshell.screens
        delegate: Loader {
            id: regionSelectorLoader

            required property var modelData

            active: root.screenshotActive && modelData.name === Kwin.cursorOutputName()

            sourceComponent: RegionSelection {
                screen: regionSelectorLoader.modelData
                onDismiss: root.dismiss()
                action: root.action
                selectionMode: root.selectionMode
                showWindowOutlines: root.showWindowOutlines
                onShowWindowOutlinesChanged: root.showWindowOutlines = showWindowOutlines
            }
        }
    }

    function screenshot() {
        root.action = ScreenshotAction.SnipAction.Copy
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        root.screenshotActive = true
    }

    function search() {
        root.action = ScreenshotAction.SnipAction.Search
        // Circle selection stays dormant: no UI path selects it yet, so
        // rect-corners is the only entry point.
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        root.screenshotActive = true
    }

    function ocr() {
        root.action = ScreenshotAction.SnipAction.CharRecognition
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        root.screenshotActive = true
    }

    function record() {
        root.action = ScreenshotAction.SnipAction.Record
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        // If already open then re-trigger to stop recording
        if (root.screenshotActive) root.screenshotActive = false
        root.screenshotActive = true
    }

    function recordWithSound() {
        root.action = ScreenshotAction.SnipAction.RecordWithSound
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        // If already open then re-trigger to stop recording
        if (root.screenshotActive) root.screenshotActive = false
        root.screenshotActive = true
    }

    CustomShortcut {
        name: "regionScreenshot"
        description: qsTr("Takes a screenshot of the selected region")
        onPressed: root.screenshot()
    }
    CustomShortcut {
        name: "regionSearch"
        description: qsTr("Searches the selected region")
        onPressed: root.search()
    }
    CustomShortcut {
        name: "regionOcr"
        description: qsTr("Recognizes text in the selected region")
        onPressed: root.ocr()
    }
    CustomShortcut {
        name: "regionRecord"
        description: qsTr("Records the selected region")
        onPressed: root.record()
    }
    CustomShortcut {
        name: "regionRecordWithSound"
        description: qsTr("Records the selected region with sound")
        onPressed: root.recordWithSound()
    }
}
