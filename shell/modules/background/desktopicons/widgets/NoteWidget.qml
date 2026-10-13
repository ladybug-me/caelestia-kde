pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// A sticky note typed straight on the desktop. The text is kept in the
// widget's config, saved shortly after typing stops.
Item {
    id: root

    property var frame
    property var controller

    readonly property string savedText: frame?.config.text ?? ""

    onSavedTextChanged: {
        if (!area.activeFocus && area.text !== savedText)
            area.text = savedText;
    }

    Timer {
        id: saveTimer

        interval: 600
        onTriggered: root.frame.setConfig({ text: area.text })
    }

    Flickable {
        id: flick

        anchors.fill: parent
        contentWidth: width
        contentHeight: area.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: StyledScrollBar {
            flickable: flick
        }

        TextArea.flickable: TextArea {
            id: area

            text: root.savedText
            placeholderText: qsTr("Write something…")
            placeholderTextColor: Colours.palette.m3outline
            color: Colours.palette.m3onSurface
            selectionColor: Qt.alpha(Colours.palette.m3primary, 0.35)
            selectedTextColor: Colours.palette.m3onSurface
            font: Tokens.font.body.medium
            wrapMode: TextEdit.Wrap
            padding: 0
            background: null
            onTextChanged: {
                if (text !== root.savedText)
                    saveTimer.restart();
            }
            onActiveFocusChanged: {
                if (!activeFocus && text !== root.savedText) {
                    saveTimer.stop();
                    root.frame.setConfig({ text });
                }
            }
            Keys.onEscapePressed: root.controller.grabKeyboard()
        }
    }
}
