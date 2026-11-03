pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils

Item {
    id: root

    required property Brightness.Monitor monitor
    required property DrawerVisibilities visibilities

    required property real volume
    required property bool muted
    required property real sourceVolume
    required property bool sourceMuted
    required property real brightness

    function getVolumeIcon(value: real, muted: bool): string {
        return functions.getVolumeIcon(value, muted);
    }

    function getMicIcon(value: real, muted: bool): string {
        return functions.getMicIcon(value, muted);
    }

    function getBrightnessIcon(value: real): string {
        return functions.getBrightnessIcon(value);
    }

    function getIcon(type: string, value: real, muted: bool): string {
        return functions.getIcon(type, value, muted);
    }

    function getTitle(type: string): string {
        return functions.getTitle(type);
    }

    function isEnabled(type: string): bool {
        return functions.isEnabled(type);
    }

    implicitWidth: layout.implicitWidth + Tokens.padding.large * 2
    implicitHeight: layout.implicitHeight + Tokens.padding.large * 2

    Functions {
        id: functions
    }

    ColumnLayout {
        id: layout

        anchors.centerIn: parent
        spacing: Tokens.spacing.medium

        WrappedLoader {
            Layout.alignment: Qt.AlignHCenter
            shouldBeActive: Config.osd.enableVolume !== false
            targetWidth: Tokens.sizes.osd.sliderWidth
            targetHeight: Tokens.sizes.osd.sliderHeight

            sourceComponent: CustomMouseArea {
                function onWheel(event: WheelEvent) {
                    if (event.angleDelta.y > 0)
                        Audio.incrementVolume();
                    else if (event.angleDelta.y < 0)
                        Audio.decrementVolume();
                }

                implicitWidth: Tokens.sizes.osd.sliderWidth
                implicitHeight: Tokens.sizes.osd.sliderHeight

                FilledSlider {
                    anchors.fill: parent

                    icon: root.getVolumeIcon(value, root.muted)
                    value: root.volume
                    to: GlobalConfig.services.maxVolume
                    onMoved: Audio.setVolume(value)
                }
            }
        }

        WrappedLoader {
            Layout.alignment: Qt.AlignHCenter
            shouldBeActive: Config.osd.enableMicrophone && (!Config.osd.enableBrightness || !root.visibilities.session)
            targetWidth: Tokens.sizes.osd.sliderWidth
            targetHeight: Tokens.sizes.osd.sliderHeight

            sourceComponent: CustomMouseArea {
                function onWheel(event: WheelEvent) {
                    if (event.angleDelta.y > 0)
                        Audio.incrementSourceVolume();
                    else if (event.angleDelta.y < 0)
                        Audio.decrementSourceVolume();
                }

                implicitWidth: Tokens.sizes.osd.sliderWidth
                implicitHeight: Tokens.sizes.osd.sliderHeight

                FilledSlider {
                    anchors.fill: parent

                    icon: root.getMicIcon(value, root.sourceMuted)
                    value: root.sourceVolume
                    to: GlobalConfig.services.maxVolume
                    onMoved: Audio.setSourceVolume(value)
                }
            }
        }

        WrappedLoader {
            Layout.alignment: Qt.AlignHCenter
            shouldBeActive: Config.osd.enableBrightness
            targetWidth: Tokens.sizes.osd.sliderWidth
            targetHeight: Tokens.sizes.osd.sliderHeight

            sourceComponent: CustomMouseArea {
                function onWheel(event: WheelEvent) {
                    const monitor = root.monitor;
                    if (!monitor)
                        return;
                    if (event.angleDelta.y > 0)
                        monitor.stepBrightness(GlobalConfig.services.brightnessIncrement);
                    else if (event.angleDelta.y < 0)
                        monitor.stepBrightness(-GlobalConfig.services.brightnessIncrement);
                }

                implicitWidth: Tokens.sizes.osd.sliderWidth
                implicitHeight: Tokens.sizes.osd.sliderHeight

                FilledSlider {
                    anchors.fill: parent

                    icon: root.getBrightnessIcon(value)
                    value: root.brightness
                    onMoved: root.monitor?.setBrightness(value)
                }
            }
        }
    }

    component WrappedLoader: Loader {
        required property bool shouldBeActive
        property real targetWidth: 0
        property real targetHeight: 0

        asynchronous: true
        Layout.preferredWidth: shouldBeActive ? targetWidth : 0
        Layout.preferredHeight: shouldBeActive ? targetHeight : 0
        opacity: shouldBeActive ? 1 : 0
        active: opacity > 0
        visible: active

        Behavior on Layout.preferredWidth {
            Anim {
                type: Anim.Emphasized
            }
        }

        Behavior on Layout.preferredHeight {
            Anim {
                type: Anim.Emphasized
            }
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    component Functions: QtObject {
        function getVolumeIcon(value: real, muted: bool): string {
            return Icons.getVolumeIcon(value, muted);
        }

        function getMicIcon(value: real, muted: bool): string {
            return Icons.getMicVolumeIcon(value, muted);
        }

        function getBrightnessIcon(value: real): string {
            return `brightness_${(Math.round(value * 6) + 1)}`;
        }

        function getIcon(type: string, value: real, muted: bool): string {
            if (type === "volume")
                return getVolumeIcon(value, muted);
            if (type === "mic")
                return getMicIcon(value, muted);
            if (type === "brightness")
                return getBrightnessIcon(value);
            return "";
        }

        function getTitle(type: string): string {
            if (type === "volume")
                return qsTr("Volume");
            if (type === "mic")
                return qsTr("Microphone");
            if (type === "brightness")
                return qsTr("Brightness");
            return "";
        }

        function isEnabled(type: string): bool {
            if (type === "volume")
                return GlobalConfig.osd.enableVolume;
            if (type === "mic")
                return GlobalConfig.osd.enableMicrophone;
            if (type === "brightness")
                return GlobalConfig.osd.enableBrightness;
            return false;
        }
    }
}
