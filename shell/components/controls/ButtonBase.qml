import QtQuick
import Caelestia.Config
import qs.components
import qs.services

StyledRect {
    id: root

    enum ButtonType {
        Filled,
        Tonal,
        Text
    }

    property bool checked
    property alias disabled: stateLayer.disabled
    property bool isToggle
    property bool isRound

    // Screen readers announce this; a caller overrides it with a clearer name when
    // the visible content is an icon or a glyph.
    property string accessibleName

    property bool radiusMorph: true
    property alias shapeMorph: stateLayer.shapeMorph
    property bool fillWidth

    property font font: Tokens.font.body.small
    property int type: ButtonBase.Filled

    property real padding
    property real horizontalPadding: padding
    property real verticalPadding: padding

    readonly property alias pressed: stateLayer.pressed
    readonly property alias hovered: stateLayer.containsMouse
    readonly property alias stateLayer: stateLayer
    readonly property alias radiusAnim: radiusAnim

    property color activeColour
    property color inactiveColour
    property color activeOnColour
    property color inactiveOnColour

    property bool internalChecked
    property real shapeMorphExpansion: shapeMorph && pressed ? 24 : 0
    readonly property color onColour: disabled ? Colours.disabledContent : internalChecked ? activeOnColour : inactiveOnColour

    property real pressedRadius: Tokens.rounding.small
    property real checkedRadius: Tokens.rounding.medium
    property real defaultRadius: Tokens.rounding.large

    signal clicked

    activeFocusOnTab: true
    Accessible.role: Accessible.Button
    Accessible.name: accessibleName
    Accessible.checkable: isToggle
    Accessible.checked: isToggle ? internalChecked : false

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (root.isToggle)
                root.internalChecked = !root.internalChecked;
            root.clicked();
            event.accepted = true;
        }
    }

    onCheckedChanged: internalChecked = checked

    radius: {
        if (radiusMorph && pressed)
            return pressedRadius;
        if (internalChecked)
            return checkedRadius;
        if (isRound)
            return (implicitHeight || height) / 2 * Math.min(1, Tokens.rounding.scale);
        return defaultRadius;
    }
    color: type === ButtonBase.Text ? Qt.alpha(inactiveColour, 0) : disabled ? Colours.disabledContainer : internalChecked ? activeColour : inactiveColour

    required implicitWidth
    required implicitHeight

    StateLayer {
        id: stateLayer

        color: root.internalChecked ? root.activeOnColour : root.inactiveOnColour
        disabled: root.disabled
        onClicked: {
            if (root.isToggle)
                root.internalChecked = !root.internalChecked;
            root.clicked();
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: 2
        border.color: Colours.palette.m3primary
        visible: root.activeFocus
        z: 1
    }

    Behavior on radius {
        Anim {
            id: radiusAnim

            type: Anim.DefaultEffects
        }
    }

    Behavior on shapeMorphExpansion {
        Anim {
            type: Anim.FastSpatial
        }
    }
}
