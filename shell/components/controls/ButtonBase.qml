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

    // What a screen reader announces. A leaf that renders a label fills this in;
    // the base has neither text nor icon of its own.
    property string accessibleLabel

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

    function activate(): void {
        if (disabled)
            return;
        if (isToggle)
            internalChecked = !internalChecked;
        clicked();
    }

    onCheckedChanged: internalChecked = checked

    Accessible.role: Accessible.Button
    Accessible.name: accessibleLabel
    Accessible.checkable: isToggle
    Accessible.checked: internalChecked
    Accessible.pressed: pressed
    Accessible.onPressAction: activate()

    // A button is reachable by keyboard, and Space or Return stands in for a click.
    activeFocusOnTab: enabled && !disabled
    Keys.onSpacePressed: activate()
    Keys.onReturnPressed: activate()
    Keys.onEnterPressed: activate()

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
        onClicked: root.activate()
    }

    // Hover and press are drawn by the state layer; a keyboard user needs to see where
    // focus is, so the ring sits just outside the button's own edge.
    StyledRect {
        anchors.fill: parent
        anchors.margins: -2

        radius: root.radius + 2
        border.width: 2
        border.color: Colours.palette.m3primary
        visible: root.activeFocus && root.activeFocusOnTab
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
