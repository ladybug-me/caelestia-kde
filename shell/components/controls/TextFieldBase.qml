import QtQuick
import QtQuick.Templates
import Caelestia.Config
import qs.components
import qs.services

TextField {
    id: root

    // A field announces its label, not whatever happens to be typed into it. The
    // placeholder is the fallback name; consumers with a separate label set this.
    property string accessibleLabel: root.placeholderText

    implicitWidth: contentWidth + leftPadding + rightPadding
    implicitHeight: contentHeight + topPadding + bottomPadding

    Accessible.name: accessibleLabel

    color: Colours.palette.m3onSurface
    placeholderTextColor: Colours.palette.m3onSurfaceVariant
    selectionColor: Qt.alpha(Colours.palette.m3primary, 0.4)
    selectedTextColor: color

    font: Tokens.font.body.small
    renderType: TextField.NativeRendering
    cursorVisible: !readOnly
    verticalAlignment: TextInput.AlignVCenter

    cursorDelegate: Item {}

    Behavior on color {
        CAnim {}
    }

    Behavior on selectionColor {
        CAnim {}
    }

    StyledRect {
        id: cursor

        property bool disableBlink

        x: root.cursorRectangle.x
        y: root.cursorRectangle.y
        implicitWidth: 1.5
        implicitHeight: root.cursorRectangle.height

        color: Colours.palette.m3primary
        radius: Tokens.rounding.large

        Connections {
            function onCursorPositionChanged(): void {
                if (root.activeFocus && root.cursorVisible) {
                    cursor.opacity = 1;
                    cursor.disableBlink = true;
                    enableBlink.restart();
                }
            }

            target: root
        }

        Timer {
            id: enableBlink

            interval: 500
            onTriggered: cursor.disableBlink = false
        }

        Timer {
            running: root.activeFocus && root.cursorVisible && !cursor.disableBlink
            repeat: true
            triggeredOnStart: true
            interval: 500
            onTriggered: parent.opacity = parent.opacity === 1 ? 0 : 1
        }

        Binding {
            when: !root.activeFocus || !root.cursorVisible
            cursor.opacity: 0
        }

        Behavior on x {
            Anim {
                easing.bezierCurve: [0.2, 1, 0.21, 1, 1, 1]
                duration: Tokens.anim.durations.expressiveFastEffects
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.StandardSmall
            }
        }
    }
}
