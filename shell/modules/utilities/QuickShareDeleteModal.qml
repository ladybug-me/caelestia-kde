pragma ComponentBehavior: Bound

import QtQuick
import Caelestia
import Caelestia.Services.QuickShare
import qs.components
import qs.components.effects

Loader {
    id: root

    required property var props
    required property matrix4x4 deformMatrix

    asynchronous: true
    anchors.fill: parent

    opacity: root.props.quickShareConfirmDeletePath ? 1 : 0
    active: opacity > 0

    sourceComponent: DrawerConfirmModal {
        // The props are cleared as soon as the modal is dismissed, but the card keeps
        // naming the file while it fades out. The entry is named by its path and time
        // rather than by a position the transfer list can shift.
        property string path
        property real timestamp

        function clearConfirmation(): void {
            root.props.quickShareConfirmDeletePath = "";
            root.props.quickShareConfirmDeleteTimestamp = 0;
        }

        deformMatrix: root.deformMatrix
        open: root.props.quickShareConfirmDeletePath !== ""
        title: qsTr("Delete file?")
        message: qsTr("'%1' will be permanently deleted.").arg(path)
        confirmText: qsTr("Delete")
        onDismissed: clearConfirmation()
        onConfirmed: {
            CUtils.deleteFile(Qt.resolvedUrl(path));
            QuickShareService.removeHistoryEntry(path, timestamp);
        }

        Component.onCompleted: {
            path = root.props.quickShareConfirmDeletePath;
            timestamp = root.props.quickShareConfirmDeleteTimestamp;
        }
    }

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }
}
