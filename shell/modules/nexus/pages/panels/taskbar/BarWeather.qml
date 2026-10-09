pragma ComponentBehavior: Bound

import QtQuick.Layouts
import Caelestia
import Caelestia.Config
import qs.components.controls
import qs.modules.nexus
import qs.modules.nexus.common

PageBase {
    id: root

    readonly property list<MenuItem> tempItems: [
        MenuItem {
            text: qsTr("Auto")
            value: TemperatureUnit.Auto
        },
        MenuItem {
            text: qsTr("°C")
            value: TemperatureUnit.Celsius
        },
        MenuItem {
            text: qsTr("°F")
            value: TemperatureUnit.Fahrenheit
        }
    ]

    title: qsTr("Weather")
    isSubPage: true

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Units")
        }

        SelectRow {
            first: true
            label: qsTr("Temperature")
            subtext: qsTr("Units for weather temperatures")
            menuItems: root.tempItems
            active: root.tempItems.find(i => i.value === GlobalConfig.services.weatherUnits) ?? null
            onSelected: item => GlobalConfig.services.weatherUnits = item.value
        }

        NavRow {
            last: true
            icon: "location_on"
            label: qsTr("Location")
            status: qsTr("Set the weather location")
            onClicked: {
                const index = PageRegistry.indexForKey("language");
                if (index >= 0)
                    root.nState.currentPageIdx = index;
            }
        }
    }
}
