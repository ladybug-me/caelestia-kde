import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils

// Shared weather cards factored out of the dashboard WeatherTab so the bar
// popout can reuse the exact same visuals.
QtObject {
        component HourStrip: ColumnLayout {
            id: strip

            required property var entries
            required property real scrollPos
            required property int windowSize

            readonly property real colW: chart.width / windowSize
            readonly property int firstIdx: Math.max(0, Math.floor(scrollPos) - 1)
            readonly property int slotCount: Math.max(0, Math.min(windowSize + 3, entries.length - firstIdx))

            // Temperature range of the dots currently in view.
            readonly property var visibleRange: {
                const n = entries.length;
                if (n === 0)
                    return {
                        lo: 0,
                        hi: 0
                    };
                const a = Math.max(0, Math.min(n - 1, Math.ceil(scrollPos - 0.5)));
                const b = Math.max(0, Math.min(n - 1, Math.floor(scrollPos + windowSize - 0.5)));
                let lo = Infinity;
                let hi = -Infinity;
                for (let i = a; i <= b; i++) {
                    lo = Math.min(lo, entries[i].tempC);
                    hi = Math.max(hi, entries[i].tempC);
                }
                return lo <= hi ? {
                    lo: lo,
                    hi: hi
                } : {
                    lo: 0,
                    hi: 0
                };
            }

            // The chart eases toward the visible range so the scale glides instead of jumping.
            property real viewMin: visibleRange.lo
            property real viewMax: visibleRange.hi

            function xAt(i: int): real {
                return colW * (i + 0.5);
            }

            function yAt(temp: real): real {
                const range = viewMax - viewMin;
                const t = range > 0 ? (temp - viewMin) / range : 0.5;
                return chart.padTop + chart.plotH * (1 - t);
            }

            function formatHour(h: int): string {
                if (Units.twelveHourClock) {
                    const suffix = h >= 12 ? "PM" : "AM";
                    const hr = h % 12 === 0 ? 12 : h % 12;
                    return `${hr}${suffix}`;
                }
                return `${String(h).padStart(2, "0")}:00`;
            }

            // Midnight shows the weekday instead of 00:00.
            function hourLabel(entry: var): string {
                if (entry.hour === 0) {
                    const d = new Date(entry.timestamp.replace("T", " ").replace(/-/g, "/"));
                    return d.toLocaleDateString(Qt.locale(), "ddd");
                }
                return formatHour(entry.hour);
            }

            spacing: 0

            Behavior on viewMin {
                Anim {
                    type: Anim.FastEffects
                }
            }

            Behavior on viewMax {
                Anim {
                    type: Anim.FastEffects
                }
            }

            Item {
                id: chart

                readonly property real padTop: 26
                readonly property real padBottom: 12
                readonly property real plotH: height - padTop - padBottom

                // Smooth curve: cubic segments with horizontal handles.
                readonly property string curvePath: {
                    const n = strip.slotCount;
                    if (n < 2)
                        return "";
                    const first = strip.firstIdx;
                    let d = `M ${strip.xAt(first)} ${strip.yAt(strip.entries[first].tempC)}`;
                    for (let i = first + 1; i < first + n; i++) {
                        const x0 = strip.xAt(i - 1);
                        const y0 = strip.yAt(strip.entries[i - 1].tempC);
                        const x1 = strip.xAt(i);
                        const y1 = strip.yAt(strip.entries[i].tempC);
                        const cx = (x0 + x1) / 2;
                        d += ` C ${cx} ${y0}, ${cx} ${y1}, ${x1} ${y1}`;
                    }
                    return d;
                }
                readonly property real firstX: strip.xAt(strip.firstIdx)
                readonly property real lastX: strip.xAt(strip.firstIdx + strip.slotCount - 1)

                Layout.fillWidth: true
                Layout.preferredHeight: 120

                Item {
                    id: chartContent

                    x: -strip.scrollPos * strip.colW
                    width: strip.entries.length * strip.colW
                    height: chart.height

                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeWidth: 0
                            fillGradient: LinearGradient {
                                x1: 0
                                y1: 0
                                x2: 0
                                y2: chart.height

                                GradientStop {
                                    position: 0
                                    color: Qt.alpha(Colours.palette.m3primary, 0.28)
                                }
                                GradientStop {
                                    position: 1
                                    color: Qt.alpha(Colours.palette.m3primary, 0)
                                }
                            }

                            PathSvg {
                                path: chart.curvePath ? `${chart.curvePath} L ${chart.lastX} ${chart.height} L ${chart.firstX} ${chart.height} Z` : ""
                            }
                        }
                    }

                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeWidth: 3
                            strokeColor: Colours.palette.m3primary
                            fillColor: "transparent"
                            capStyle: ShapePath.RoundCap
                            joinStyle: ShapePath.RoundJoin

                            PathSvg {
                                path: chart.curvePath
                            }
                        }
                    }

                    Repeater {
                        model: strip.slotCount

                        Item {
                            id: dot

                            required property int index

                            readonly property int dataIndex: strip.firstIdx + index
                            readonly property var entry: strip.entries[dataIndex]
                            readonly property bool isNow: dataIndex === 0
                            readonly property bool isExtreme: (entry?.tempC ?? 0) === strip.visibleRange.hi || (entry?.tempC ?? 0) === strip.visibleRange.lo

                            visible: entry !== undefined
                            x: strip.xAt(dataIndex)
                            y: strip.yAt(entry?.tempC ?? 0)

                            StyledRect {
                                anchors.centerIn: parent
                                implicitWidth: dot.isExtreme ? 12 : 8
                                implicitHeight: implicitWidth
                                radius: Tokens.rounding.full
                                color: dot.isNow ? Colours.palette.m3tertiary : Colours.palette.m3primary
                            }

                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: -height - 8
                                text: Weather.formatTemp(dot.entry?.tempC, true)
                                font: Tokens.font.body.builders.small.weight(Font.DemiBold).build()
                                color: dot.isNow ? Colours.palette.m3tertiary : Colours.palette.m3onSurface
                            }
                        }
                    }
                }
            }

            // Columns use strip.xAt so they line up with the dots.
            Item {
                id: hourRow

                Layout.fillWidth: true
                Layout.topMargin: Tokens.spacing.small
                implicitHeight: sizer.implicitHeight

                // Never shown. Gives the row the height of a real cell.
                HourCell {
                    id: sizer

                    opacity: 0
                    enabled: false
                    label: "00:00"
                    icon: "cloud"
                    precip: 100
                }

                Item {
                    x: -strip.scrollPos * strip.colW

                    Repeater {
                        model: strip.slotCount

                        HourCell {
                            id: cell

                            required property int index

                            readonly property int dataIndex: strip.firstIdx + index
                            readonly property var entry: strip.entries[dataIndex]
                            readonly property bool isNow: dataIndex === 0

                            x: strip.xAt(dataIndex) - width / 2
                            width: strip.colW

                            now: isNow
                            midnight: (entry?.hour ?? -1) === 0 && !isNow
                            label: isNow ? qsTr("Now", "hourly forecast, current hour") : (entry ? strip.hourLabel(entry) : "")
                            icon: entry?.icon ?? ""
                            precip: entry?.precipChance ?? 0
                        }
                    }
                }
            }
        }

        component HourCell: ColumnLayout {
            id: cell

            property string label
            property string icon
            property int precip
            property bool now
            property bool midnight

            spacing: Tokens.spacing.extraSmall

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: cell.label
                font: Tokens.font.body.builders.small.weight(cell.now || cell.midnight ? Font.DemiBold : Font.Normal).build()
                color: cell.now ? Colours.palette.m3tertiary : (cell.midnight ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant)
            }

            MaterialIcon {
                Layout.alignment: Qt.AlignHCenter
                text: cell.icon
                fontStyle: Tokens.font.icon.large
                color: Colours.palette.m3secondary
            }

            // Hidden under 20%, but keeps its space so columns don't shift.
            StyledRect {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: rainLabel.implicitWidth + Tokens.padding.small * 2
                implicitHeight: rainLabel.implicitHeight + Tokens.padding.extraSmall * 2
                radius: Tokens.rounding.full
                color: Qt.alpha(Colours.palette.m3secondary, 0.1 + 0.3 * (cell.precip / 100))
                opacity: cell.precip >= 20 ? 1 : 0

                StyledText {
                    id: rainLabel

                    anchors.centerIn: parent
                    text: Strings.percent(cell.precip)
                    font: Tokens.font.body.builders.small.weight(Font.DemiBold).build()
                    color: Colours.palette.m3secondary
                }
            }
        }

        component ArrowButton: StyledRect {
            id: arrow

            required property string icon
            property bool active: true

            signal clicked

            implicitWidth: 36
            implicitHeight: 36
            radius: Tokens.rounding.full
            color: Colours.tPalette.m3surfaceContainerHigh
            opacity: active ? 1 : 0.38

            Behavior on opacity {
                Anim {
                    type: Anim.FastEffects
                }
            }

            StateLayer {
                radius: Tokens.rounding.full
                disabled: !arrow.active
                color: Colours.palette.m3onSurface
                onClicked: arrow.clicked()
            }

            MaterialIcon {
                anchors.centerIn: parent
                text: arrow.icon
                color: Colours.palette.m3onSurface
                fontStyle: Tokens.font.icon.medium
            }
        }

        component DetailCard: StyledRect {
            id: detailRoot

            property string icon
            property string label
            property string value
            property color colour

            Layout.fillWidth: true
            Layout.preferredHeight: 60
            radius: Tokens.rounding.medium
            color: Colours.tPalette.m3surfaceContainer

            Row {
                anchors.centerIn: parent
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: detailRoot.icon
                    color: detailRoot.colour
                    fontStyle: Tokens.font.icon.large
                    anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    StyledText {
                        text: detailRoot.label
                        font: Tokens.font.body.small
                        opacity: 0.7
                        horizontalAlignment: Text.AlignLeft
                    }
                    StyledText {
                        text: detailRoot.value
                        font: Tokens.font.body.builders.small.weight(Font.DemiBold).build()
                        horizontalAlignment: Text.AlignLeft
                    }
                }
            }
        }
}
