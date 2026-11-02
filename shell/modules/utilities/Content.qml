import "cards"
import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import Caelestia.Services.QuickShare
import qs.components
import qs.modules.bar.popouts as BarPopouts

Item {
    id: root

    required property var props
    required property DrawerVisibilities visibilities
    required property BarPopouts.Wrapper popouts
    required property matrix4x4 deformMatrix

    // The cards that are showing, in the order the layout stacks them: their own
    // non-animated heights, plus the spacing between them. Read from the layout rather
    // than from a list of names, so a new card cannot be added to one and forgotten in
    // the other.
    readonly property real nonAnimHeight: {
        const visible = [...layout.children].filter(card => card.visible && card.nonAnimHeight !== undefined);
        return visible.reduce((total, card) => total + card.nonAnimHeight, 0) + layout.spacing * Math.max(0, visible.length - 1);
    }

    implicitWidth: layout.implicitWidth
    implicitHeight: layout.implicitHeight

    ColumnLayout {
        id: layout

        anchors.fill: parent
        spacing: Tokens.spacing.medium

        TimersCard {
            id: timers

            visible: Config.utilities.showTimers
            visibilities: root.visibilities
        }

        CaptureCard {
            id: capture

            visible: Config.utilities.showScreenRecorder

            props: root.props
            visibilities: root.visibilities
            z: 1
        }

        QuickShareList {
            id: quickShare

            visible: Config.utilities.showQuickShare && QuickShareService.isEnabled

            props: root.props
            visibilities: root.visibilities
        }

        Toggles {
            id: toggles

            visible: Config.utilities.showQuickToggles

            visibilities: root.visibilities
            popouts: root.popouts
        }
    }

    RecordingDeleteModal {
        props: root.props
        deformMatrix: root.deformMatrix
    }

    QuickShareDeviceSelector {
        props: root.props
        deformMatrix: root.deformMatrix
    }

    QuickShareDeleteModal {
        props: root.props
        deformMatrix: root.deformMatrix
    }
}
