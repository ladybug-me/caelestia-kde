/*
    SPDX-FileCopyrightText: 2024 ladybug-me
    SPDX-License-Identifier: GPL-3.0-or-later
*/

import QtQuick
import QtQuick.Layouts
import Caelestia.Services
import ".."

Rectangle {
    id: root

    property real centerScale: 1.0
    property color clSurfaceContainer: "#131b1a"
    property color clSurfaceFg: "#dce8e6"
    property color clSurfaceVariantFg: "#a2adac"
    property color clPrimary: "#9bd0cc"
    property real cardRadius: 26

    readonly property bool isHorizontalLayout: root.width >= 300 && root.height >= 80

    radius: cardRadius
    color: clSurfaceContainer
    clip: true

    // Height shrinks to fit unless Layout.fillHeight is set.
    implicitHeight: isHorizontalLayout
                    ? (horizontalContent.implicitHeight + Math.max(16, 24 * centerScale))
                    : (compactContent.implicitHeight + Math.max(12, 20 * centerScale))

    // Wide (high-DPI) layout
    RowLayout {
        id: horizontalContent

        anchors.centerIn: parent
        spacing: Math.max(12, Math.round(18 * root.centerScale))
        visible: root.isHorizontalLayout
        opacity: Weather.hasWeather ? 1.0 : 0.5

        Behavior on opacity {
            NumberAnimation {
                duration: 400
            }
        }

        // Left Section: Big Hero Temperature & Weather Icon
        RowLayout {
            id: heroSection

            Layout.alignment: Qt.AlignVCenter
            spacing: Math.max(6, Math.round(10 * root.centerScale))

            Text {
                id: heroTemp

                text: Weather.temp
                font {
                    pixelSize: Math.max(28, Math.round(38 * root.centerScale))
                    family: LockScreenConfig.fontMetrics
                    weight: Font.DemiBold
                }
                color: root.clPrimary
                verticalAlignment: Text.AlignVCenter
                Layout.alignment: Qt.AlignVCenter
            }

            Text {
                id: heroIcon

                text: Weather.icon
                font.family: LockScreenConfig.fontIcon
                font.pixelSize: Math.max(28, Math.round(38 * root.centerScale))
                color: root.clPrimary
                verticalAlignment: Text.AlignVCenter
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // Vertical Divider Separator
        Rectangle {
            id: divider

            Layout.preferredWidth: 1
            Layout.preferredHeight: Math.min(root.height - Math.round(16 * root.centerScale), Math.max(34, Math.round(46 * root.centerScale)))
            Layout.alignment: Qt.AlignVCenter
            color: Qt.rgba(root.clSurfaceVariantFg.r, root.clSurfaceVariantFg.g, root.clSurfaceVariantFg.b, 0.18)
        }

        // Right Section: Condition, Feels Like, High / Low Range
        ColumnLayout {
            id: detailsSection

            Layout.alignment: Qt.AlignVCenter
            Layout.maximumWidth: Math.max(80, root.width - heroSection.implicitWidth - divider.width - (horizontalContent.spacing * 2) - Math.round(32 * root.centerScale))
            spacing: Math.max(1, Math.round(2 * root.centerScale))

            Text {
                Layout.fillWidth: true
                Layout.maximumWidth: detailsSection.Layout.maximumWidth
                text: Weather.description
                font {
                    pixelSize: Math.max(12, Math.round(14 * root.centerScale))
                    family: LockScreenConfig.fontHeading
                    weight: Font.Medium
                }
                color: root.clSurfaceFg
                elide: Text.ElideRight
            }

            Text {
                Layout.fillWidth: true
                Layout.maximumWidth: detailsSection.Layout.maximumWidth
                text: Weather.hasWeather ? ("Feels like " + Weather.feelsLike) : "Feels like --°C"
                font {
                    pixelSize: Math.max(10, Math.round(12 * root.centerScale))
                    family: LockScreenConfig.fontBody
                }
                color: root.clSurfaceVariantFg
                elide: Text.ElideRight
            }

            Text {
                visible: Weather.hasWeather && Weather.maxTemp.length > 0 && Weather.minTemp.length > 0
                Layout.fillWidth: true
                Layout.maximumWidth: detailsSection.Layout.maximumWidth
                text: (Weather.hasWeather && Weather.maxTemp.length > 0 && Weather.minTemp.length > 0)
                      ? ("High " + Weather.maxTemp + " • Low " + Weather.minTemp)
                      : ""
                font {
                    pixelSize: Math.max(10, Math.round(11 * root.centerScale))
                    family: LockScreenConfig.fontMetrics
                }
                color: root.clSurfaceVariantFg
                elide: Text.ElideRight
            }
        }
    }

    // Compact (low-DPI) layout
    RowLayout {
        id: compactContent

        anchors.centerIn: parent
        spacing: Math.max(6, 10 * root.centerScale)
        visible: !root.isHorizontalLayout
        opacity: Weather.hasWeather ? 1.0 : 0.5

        Behavior on opacity {
            NumberAnimation {
                duration: 400
            }
        }

        Text {
            text: Weather.temp
            font {
                pixelSize: LockScreenConfig.sizeLarge
                family: LockScreenConfig.fontMetrics
                weight: Font.Medium
            }
            color: root.clPrimary
            verticalAlignment: Text.AlignVCenter
            Layout.alignment: Qt.AlignVCenter
        }

        Text {
            text: Weather.icon
            font.family: LockScreenConfig.fontIcon
            font.pixelSize: LockScreenConfig.sizeLarge
            color: root.clPrimary
            verticalAlignment: Text.AlignVCenter
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
