import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

StyledText {
    id: root

    property bool first
    readonly property bool isSectionHeader: true

    Layout.fillWidth: true
    Layout.topMargin: first ? 0 : Math.max(0, Tokens.spacing.large - (parent && parent.spacing !== undefined ? parent.spacing : 0))
    Layout.bottomMargin: -(parent && parent.spacing !== undefined ? Math.max(0, parent.spacing - 4) : 0)
    Layout.leftMargin: Tokens.padding.small

    color: Colours.palette.m3onSurfaceVariant
    font: Tokens.font.label.medium
    elide: Text.ElideRight
}
