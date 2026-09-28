pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.Pipewire
import qs.components.controls
import qs.services
import qs.utils

SliderRow {
    id: root

    required property PwNode node

    property bool muteOnIconClick: false

    iconClickable: root.muteOnIconClick
    icon: Icons.getVolumeIcon(Audio.getAppVolume(root.node), Audio.getAppMuted(root.node))
    label: Audio.getStreamName(root.node)
    valueLabel: Audio.getAppMuted(root.node) ? qsTr("Muted") : Math.round(value * 100) + "%"
    value: Audio.getAppVolume(root.node)
    onIconClicked: Audio.setAppMuted(root.node, !Audio.getAppMuted(root.node))
    onMoved: v => Audio.setAppVolume(root.node, v)
}
