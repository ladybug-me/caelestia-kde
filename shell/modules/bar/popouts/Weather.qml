pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.widgets as WeatherWidgets
import qs.services
import qs.utils
import qs.modules.dashboard.dash

// Weather popout: dashboard SmallWeather plus stats and an hourly strip,
// all reusing the shared WeatherCards visuals.
ColumnLayout {
    id: root

    required property var popouts

    property real scaleOffset: 1.0
    property real fontScale: 1.0
    property bool _isSidebarOpen: false

    readonly property var allHourly: Weather.hourlyForecast ?? []
    readonly property int windowSize: 6
    readonly property int step: 3
    readonly property int maxOffset: Math.max(0, allHourly.length - windowSize)

    property int hourOffset: 0
    property real scrollPos: hourOffset
    property bool hourlyExpanded: true

    onHourOffsetChanged: {
        if (hourOffset > maxOffset)
            hourOffset = maxOffset;
    }

    width: 380
    spacing: Tokens.spacing.small

    Behavior on scrollPos {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: smallWeather.implicitHeight

        SmallWeather {
            id: smallWeather
        }
    }

    StyledText {
        Layout.alignment: Qt.AlignHCenter
        text: qsTr("H:%1 L:%2").arg(Weather.maxTemp).arg(Weather.minTemp)
        font: Tokens.font.body.small
        color: Colours.palette.m3onSurfaceVariant
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.medium

        WeatherWidgets.WeatherCards.DetailCard {
            icon: "water_drop"
            label: qsTr("Humidity")
            value: Strings.percent(Weather.humidity)
            colour: Colours.palette.m3secondary
        }
        WeatherWidgets.WeatherCards.DetailCard {
            icon: "thermostat"
            label: qsTr("Feels like", "apparent temperature")
            value: Weather.feelsLike
            colour: Colours.palette.m3primary
        }
        WeatherWidgets.WeatherCards.DetailCard {
            icon: "air"
            label: qsTr("Wind")
            value: Weather.windSpeed ? qsTr("%1 km/h").arg(Weather.windSpeed) : "--"
            colour: Colours.palette.m3tertiary
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small
        visible: root.allHourly.length > 0

        StyledText {
            text: qsTr("Hourly forecast")
            font: Tokens.font.body.builders.medium.weight(Font.DemiBold).build()
            color: Colours.palette.m3onSurface

            CustomMouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.hourlyExpanded = !root.hourlyExpanded
            }
        }

        WeatherWidgets.WeatherCards.ArrowButton {
            icon: root.hourlyExpanded ? "keyboard_arrow_up" : "keyboard_arrow_down"
            active: true
            onClicked: root.hourlyExpanded = !root.hourlyExpanded
        }

        Item {
            Layout.fillWidth: true
        }

        WeatherWidgets.WeatherCards.ArrowButton {
            icon: "chevron_left"
            visible: root.hourlyExpanded
            active: root.hourOffset > 0
            onClicked: root.hourOffset = Math.max(0, root.hourOffset - root.step)
        }

        WeatherWidgets.WeatherCards.ArrowButton {
            icon: "chevron_right"
            visible: root.hourlyExpanded
            active: root.hourOffset < root.maxOffset
            onClicked: root.hourOffset = Math.min(root.maxOffset, root.hourOffset + root.step)
        }
    }

    StyledClippingRect {
        Layout.fillWidth: true
        visible: root.hourlyExpanded && root.allHourly.length > 0
        implicitHeight: hourStrip.implicitHeight + Tokens.padding.medium * 2

        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainer

        WeatherWidgets.WeatherCards.HourStrip {
            id: hourStrip

            anchors.fill: parent
            anchors.margins: Tokens.padding.medium
            entries: root.allHourly
            scrollPos: root.scrollPos
            windowSize: root.windowSize
        }
    }
}
