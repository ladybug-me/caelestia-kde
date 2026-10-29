pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services

// Current weather on its own, with the next few days underneath when there is
// room for them. The data belongs to the shared weather service, so this only
// decides how much of it fits.
Item {
    id: root

    property var frame
    property var controller

    readonly property var cfg: frame?.config ?? ({})
    readonly property bool showForecast: cfg.showForecast !== false
    // A cell is not a page: more days than the card can hold would overflow it.
    readonly property int wantedDays: Math.max(1, Math.min(6, Math.round(cfg.forecastDays ?? 3)))
    readonly property int rowCount: {
        if (!root.showForecast || !Weather.forecast || Weather.forecast.length === 0)
            return 0;
        return Math.max(0, Math.min(root.wantedDays, Weather.forecast.length, Math.floor((root.height - 96) / 24)));
    }

    Component.onCompleted: Weather.reload()

    StyledText {
        anchors.centerIn: parent
        visible: !Weather.hasWeather
        text: Weather.loading ? qsTr("Loading weather…") : qsTr("No weather configured")
        color: Colours.palette.m3outline
        font: Tokens.font.body.medium
        horizontalAlignment: Text.AlignHCenter
        width: root.width
        wrapMode: Text.Wrap
    }

    ColumnLayout {
        anchors.fill: parent
        visible: Weather.hasWeather
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            MaterialIcon {
                text: Weather.icon
                color: Colours.palette.m3secondary
                fontStyle: Tokens.font.icon.builders.extraLarge.build()
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: Weather.temp
                    font: Tokens.font.title.medium
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Weather.description
                    color: Colours.palette.m3onSurfaceVariant
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: Weather.city !== ""
                    text: Weather.city
                    color: Colours.palette.m3outline
                    font: Tokens.font.label.small
                    elide: Text.ElideRight
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.topMargin: Tokens.spacing.extraSmall
            spacing: 0

            Repeater {
                model: root.rowCount

                RowLayout {
                    id: forecastRow

                    required property int index

                    readonly property var day: Weather.forecast[forecastRow.index] ?? null

                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    StyledText {
                        Layout.fillWidth: true
                        text: forecastRow.day ? new Date(forecastRow.day.date).toLocaleDateString(Qt.locale(), "ddd") : ""
                        color: Colours.palette.m3onSurfaceVariant
                        font: Tokens.font.label.medium
                        elide: Text.ElideRight
                    }

                    MaterialIcon {
                        text: forecastRow.day?.icon ?? ""
                        color: Colours.palette.m3onSurfaceVariant
                        fontStyle: Tokens.font.icon.small
                    }

                    StyledText {
                        text: forecastRow.day ? Weather.formatTemp(forecastRow.day.maxTempC, true) : ""
                        font: Tokens.font.label.medium
                    }

                    StyledText {
                        text: forecastRow.day ? Weather.formatTemp(forecastRow.day.minTempC, true) : ""
                        color: Colours.palette.m3outline
                        font: Tokens.font.label.medium
                    }
                }
            }
        }
    }
}
