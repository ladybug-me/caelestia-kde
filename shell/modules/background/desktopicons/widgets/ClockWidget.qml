pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// Time and date, current weather and, when wide enough, the next hours.
Item {
    id: root

    property var frame
    property var controller

    readonly property bool wide: width > height * 1.6
    readonly property bool showHours: wide && height > 150 && Weather.hourlyForecast && Weather.hourlyForecast.length > 0

    Component.onCompleted: Weather.reload()

    GridLayout {
        anchors.fill: parent
        columns: root.wide ? 2 : 1
        columnSpacing: Tokens.spacing.large
        rowSpacing: Tokens.spacing.small

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: Time.format(Units.twelveHourClock ? "h:mm AP" : "hh:mm")
                font: Tokens.font.headline.builders.medium.scale(Math.min(2.2, Math.max(1, root.height / 110))).weight(Font.DemiBold).build()
                color: Colours.palette.m3primary
                fontSizeMode: Text.HorizontalFit
                minimumPointSize: 12
            }

            StyledText {
                Layout.fillWidth: true
                text: Time.format(root.width > 380 ? "dddd, MMMM d" : "ddd, MMM d")
                color: Colours.palette.m3onSurfaceVariant
                font: Tokens.font.body.medium
                elide: Text.ElideRight
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: Tokens.spacing.small
            visible: Weather.hasWeather

            RowLayout {
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: Weather.icon
                    color: Colours.palette.m3secondary
                    fontStyle: Tokens.font.icon.builders.extraLarge.build()
                }

                ColumnLayout {
                    spacing: 0

                    StyledText {
                        text: Weather.temp
                        font: Tokens.font.title.medium
                    }

                    StyledText {
                        Layout.maximumWidth: root.width / (root.wide ? 2.4 : 1.2)
                        text: Weather.city ? `${Weather.description} · ${Weather.city}` : Weather.description
                        color: Colours.palette.m3onSurfaceVariant
                        elide: Text.ElideRight
                    }
                }
            }

            RowLayout {
                visible: root.showHours
                spacing: Tokens.spacing.medium

                Repeater {
                    model: root.showHours ? Weather.hourlyForecast.slice(0, Math.max(1, Math.floor(root.width / 2 / 56))) : []

                    ColumnLayout {
                        required property var modelData

                        spacing: 0

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: String(modelData.hour).padStart(2, "0")
                            color: Colours.palette.m3outline
                            font: Tokens.font.label.small
                        }

                        MaterialIcon {
                            Layout.alignment: Qt.AlignHCenter
                            text: modelData.icon
                            color: Colours.palette.m3onSurfaceVariant
                        }

                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Weather.formatTemp(modelData.tempC, true)
                            font: Tokens.font.label.medium
                        }
                    }
                }
            }
        }
    }
}
