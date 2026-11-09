import QtQuick
import QtQuick.Layouts
import Quickshell
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

PageBase {
    id: root

    property int highlightedLocationIdx: -1
    property var pendingLocation
    readonly property bool compactWeatherPicker: root.cappedWidth < 620

    function selectLocationCandidate(item: var): void {
        if (!item)
            return;

        pendingLocation = item;
        highlightedLocationIdx = -1;
        Weather.locationSearchResults = [];
    }

    function applyPendingLocation(): void {
        if (!pendingLocation)
            return;

        if (Weather.applyLocationResult(pendingLocation)) {
            highlightedLocationIdx = -1;
            Weather.locationSearchResults = [];
            Weather.locationSearchError = "";
            Weather.locationSearchQuery = "";
            locationField.text = "";
        }
    }

    Component.onCompleted: Weather.reload()

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
        },
        MenuItem {
            text: qsTr("K")
            value: TemperatureUnit.Kelvin
        }
    ]

    readonly property list<MenuItem> dataItems: [
        MenuItem {
            text: qsTr("Binary (KiB, MiB)")
            value: DataUnit.Binary
        },
        MenuItem {
            text: qsTr("Decimal (KB, MB)")
            value: DataUnit.Decimal
        }
    ]

    readonly property var languageOptions: [
        {
            code: "system",
            label: qsTr("System language")
        },
        ...Translations.available.map(lang => ({
                    code: lang.code,
                    label: lang.nativeName
                }))
    ]

    readonly property list<MenuItem> clockItems: [
        MenuItem {
            text: qsTr("Auto")
            value: ClockFormat.Auto
        },
        MenuItem {
            text: qsTr("12-hour")
            value: ClockFormat.TwelveHour
        },
        MenuItem {
            text: qsTr("24-hour")
            value: ClockFormat.TwentyFourHour
        }
    ]

    title: qsTr("Language & region")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Language")
        }

        Variants {
            id: languageVariants

            model: root.languageOptions

            MenuItem {
                required property var modelData

                readonly property string code: modelData.code

                text: modelData.label
                icon: modelData.code === GlobalConfig.general.language ? "check" : ""
                activeIcon: "translate"
            }
        }

        SelectRow {
            first: true
            last: true
            label: qsTr("Shell language")
            subtext: GlobalConfig.general.language === "system" ? qsTr("Follows your system locale (%1)").arg(Qt.locale().name) : qsTr("Untranslated text falls back to English")
            menuItems: languageVariants.instances
            active: menuItems.find(i => i.code === GlobalConfig.general.language) ?? null
            fallbackIcon: "translate"
            fallbackText: qsTr("System language")
            onSelected: item => GlobalConfig.general.language = item.code
        }

        SectionHeader {
            text: qsTr("Weather")
        }

        ConnectedRect {
            Layout.fillWidth: true
            first: true
            last: true
            implicitHeight: weatherContent.implicitHeight + Tokens.padding.largeIncreased * 2

            ColumnLayout {
                id: weatherContent

                anchors.fill: parent
                anchors.margins: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: "location_on"
                        color: Colours.palette.m3primary
                        fontStyle: Tokens.font.icon.large
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: Weather.city || qsTr("Using auto-detected location")
                            font: Tokens.font.body.builders.small.weight(Font.DemiBold).build()
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: GlobalConfig.services.weatherLocation
                                ? qsTr("Saved weather coordinates: %1").arg(GlobalConfig.services.weatherLocation)
                                : qsTr("No fixed location saved")
                            color: Colours.palette.m3onSurfaceVariant
                            font: NexusStyle.secondaryFont
                            elide: Text.ElideRight
                        }
                    }

                    CircularIndicator {
                        implicitSize: 18
                        visible: Weather.locationSearchLoading
                    }
                }

                SearchBar {
                    id: locationField

                    Layout.fillWidth: true
                    placeholderText: qsTr("Search city or region")
                    font: Tokens.font.body.large
                    bg.color: Colours.tPalette.m3surfaceContainerLowest
                    bg.border.color: Colours.palette.m3outlineVariant
                    searchIcon.fontStyle: Tokens.font.icon.medium
                    searchIcon.anchors.leftMargin: Tokens.padding.largeIncreased
                    clearIcon.font: Tokens.font.icon.medium
                    clearIcon.padding: Tokens.padding.extraSmall

                    text: Weather.locationSearchQuery

                    onTextChanged: {
                        root.highlightedLocationIdx = -1;
                        Weather.queueLocationSearch(text);
                        if (text.length === 0) {
                            root.pendingLocation = null;
                            Weather.locationSearchResults = [];
                            Weather.locationSearchError = "";
                        }
                    }

                    Keys.onDownPressed: {
                        if (Weather.locationSearchResults.length === 0)
                            return;

                        root.highlightedLocationIdx = Math.min(root.highlightedLocationIdx + 1, Weather.locationSearchResults.length - 1);
                    }

                    Keys.onUpPressed: {
                        if (Weather.locationSearchResults.length === 0)
                            return;

                        if (root.highlightedLocationIdx < 0)
                            root.highlightedLocationIdx = Weather.locationSearchResults.length - 1;
                        else
                            root.highlightedLocationIdx = Math.max(root.highlightedLocationIdx - 1, 0);
                    }

                    Keys.onReturnPressed: {
                        if (Weather.locationSearchResults.length === 0)
                            return;

                        const idx = root.highlightedLocationIdx >= 0 ? root.highlightedLocationIdx : 0;
                        root.selectLocationCandidate(Weather.locationSearchResults[idx]);
                    }
                }

                StyledRect {
                    Layout.fillWidth: true
                    radius: Tokens.rounding.large
                    color: Colours.layer(Colours.palette.m3surfaceContainerHigh, 1)
                    visible: Weather.locationSearchError || (!Weather.locationSearchLoading && locationField.text.length >= 2)
                    implicitHeight: resultsColumn.implicitHeight + Tokens.padding.small * 2

                    ColumnLayout {
                        id: resultsColumn

                        anchors.fill: parent
                        anchors.margins: Tokens.padding.small
                        spacing: Tokens.spacing.extraSmall

                        StyledText {
                            Layout.fillWidth: true
                            visible: Weather.locationSearchError.length > 0
                            text: Weather.locationSearchError
                            wrapMode: Text.WordWrap
                            color: Colours.palette.m3error
                            font: NexusStyle.secondaryFont
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: !Weather.locationSearchError && locationField.text.length >= 2 && Weather.locationSearchResults.length === 0
                            text: qsTr("No matching locations")
                            color: Colours.palette.m3onSurfaceVariant
                            font: NexusStyle.secondaryFont
                        }

                        Repeater {
                            model: Weather.locationSearchResults

                            StyledRect {
                                id: resultRow

                                required property int index
                                required property var modelData

                                readonly property bool highlighted: root.highlightedLocationIdx === resultRow.index

                                Layout.fillWidth: true
                                radius: Tokens.rounding.medium
                                color: highlighted ? Colours.layer(Colours.palette.m3secondaryContainer, 2) : "transparent"
                                implicitHeight: resultText.implicitHeight + Tokens.padding.small * 2

                                StateLayer {
                                    anchors.fill: parent
                                    radius: resultRow.radius
                                    onClicked: root.selectLocationCandidate(resultRow.modelData)
                                }

                                Column {
                                    id: resultText

                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: Tokens.padding.small
                                    anchors.rightMargin: Tokens.padding.small
                                    spacing: 0

                                    StyledText {
                                        text: resultRow.modelData.label || resultRow.modelData.name
                                        font: Tokens.font.body.small
                                        elide: Text.ElideRight
                                    }

                                    StyledText {
                                        text: resultRow.modelData.timezone || ""
                                        color: Colours.palette.m3onSurfaceVariant
                                        font: NexusStyle.secondaryFont
                                        visible: text.length > 0
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: actionFlow.implicitHeight

                    Flow {
                        id: actionFlow

                        width: parent.width
                        spacing: Tokens.spacing.small

                        TextButton {
                            type: TextButton.Filled
                            text: qsTr("Apply location")
                            disabled: !root.pendingLocation
                            onClicked: root.applyPendingLocation()
                        }

                        TextButton {
                            type: TextButton.Tonal
                            text: qsTr("Use auto-detect")
                            onClicked: {
                                root.pendingLocation = null;
                                root.highlightedLocationIdx = -1;
                                Weather.locationSearchQuery = "";
                                Weather.locationSearchResults = [];
                                Weather.locationSearchError = "";
                                locationField.text = "";
                                Weather.resetToAutoLocation();
                            }
                        }

                        StyledText {
                            width: root.compactWeatherPicker ? Math.max(120, actionFlow.width - Tokens.padding.extraLarge * 2) : 260
                            text: root.pendingLocation ? (root.pendingLocation.label || root.pendingLocation.name) : qsTr("No location selected")
                            color: Colours.palette.m3onSurfaceVariant
                            font: NexusStyle.secondaryFont
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            visible: root.compactWeatherPicker
        }

        SectionHeader {
            text: qsTr("Units")
        }

        SelectRow {
            first: true
            label: qsTr("Temperature")
            subtext: qsTr("Units for weather temperatures")
            menuItems: root.tempItems
            active: root.tempItems.find(i => i.value === GlobalConfig.services.weatherUnits)
            onSelected: item => GlobalConfig.services.weatherUnits = item.value
        }

        SelectRow {
            label: qsTr("System temperatures")
            subtext: qsTr("Units for CPU and GPU temperatures")
            menuItems: root.tempItems
            active: root.tempItems.find(i => i.value === GlobalConfig.services.sensorUnits)
            onSelected: item => GlobalConfig.services.sensorUnits = item.value
        }

        SelectRow {
            last: true
            label: qsTr("Data sizes")
            subtext: qsTr("Units for data sizes and network speeds")
            menuItems: root.dataItems
            active: root.dataItems.find(i => i.value === GlobalConfig.services.dataUnits)
            onSelected: item => GlobalConfig.services.dataUnits = item.value
        }

        SectionHeader {
            text: qsTr("Time & date")
        }

        SelectRow {
            first: true
            last: true
            label: qsTr("Clock format")
            subtext: qsTr("How times are shown across the shell")
            menuOnTop: true
            menuItems: root.clockItems
            active: root.clockItems.find(i => i.value === GlobalConfig.services.clockFormat)
            onSelected: item => GlobalConfig.services.clockFormat = item.value
        }
    }
}
