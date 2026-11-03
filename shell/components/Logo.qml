pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.services

Item {
    id: root

    readonly property real designWidth: 128
    readonly property real designHeight: 90.38

    property color topColour: Colours.palette.m3primary
    property color bottomColour: Colours.palette.m3onSurface
    property color starColour: root.topColour
    property color badgeColour: Colours.palette.m3primary
    property color badgeIconColour: Colours.palette.m3onPrimary
    property color badgeStrokeColour: Colours.palette.m3surface
    property bool showBadge: true

    implicitWidth: root.designWidth
    implicitHeight: root.designHeight

    Item {
        id: container

        anchors.centerIn: parent
        width: root.designWidth
        height: root.designHeight
        scale: Math.min(root.width / width, root.height / height)
        transformOrigin: Item.Center

        Shape {
            id: mainShapes

            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: root.topColour
                strokeColor: "transparent"

                PathSvg {
                    path: "m42.56,42.96c-7.76,1.6-16.36,4.22-22.44,6.22-.49.16-.88-.44-.53-.82,5.37-5.85,9.66-13.3,9.66-13.3,8.66-14.67,22.97-23.51,39.85-21.14,6.47.91,12.33,3.38,17.26,6.98.99.72,1.14,2.14.31,3.04-.4.44-.95.67-1.51.67-.34,0-.69-.09-1-.26-3.21-1.84-6.82-2.69-10.71-3.24-13.1-1.84-25.41,4.75-31.06,15.83-.94,1.84-.61,3.81.45,5.21.22.3.07.72-.29.8Z"
                }
            }

            ShapePath {
                fillColor: root.bottomColour
                strokeColor: "transparent"

                PathSvg {
                    path: "m103.02,51.8c-.65.11-1.26-.37-1.28-1.03-.06-1.96.15-3.89-.2-5.78-.28-1.48-1.66-2.5-3.16-2.34h-.05c-6.53.73-24.63,3.1-48,9.32-6.89,1.83-9.83,10-5.67,15.79,4.62,6.44,11.84,10.93,20.41,12.13,11.82,1.66,22.99-3.36,29.21-12.65.54-.81,1.54-1.17,2.47-.86.91.3,1.47,1.15,1.47,2.04,0,.33-.08.66-.24.98-7.23,14.21-22.91,22.95-39.59,20.6-7.84-1.1-14.8-4.5-20.28-9.43,0,0,0,0-.02-.01-7.28-5.14-14.7-9.99-27.24-11.98-18.82-2.98-9.53-8.75.46-13.78,7.36-3.13,25.17-7.9,36.24-10.73.16-.03.31-.06.47-.1,1.52-.4,3.2-.83,5.02-1.29,1.06-.26,1.93-.48,2.58-.64.09-.02.18-.04.26-.06.31-.08.56-.14.73-.18.03,0,.06-.01.08-.02.03,0,.05-.01.07-.02.02,0,.04,0,.06-.01.01,0,.03,0,.04-.01,0,0,.02,0,.03,0,.01,0,.02,0,.02,0,10.62-2.58,24.63-5.62,37.74-7.34,1.02-.13,2.03-.26,3.03-.37,7.49-.87,14.58-1.26,20.42-.81,25.43,1.95-4.71,16.77-15.12,18.61Z"
                }
            }

            ShapePath {
                fillColor: root.starColour
                strokeColor: "transparent"

                PathSvg {
                    path: "m98.12.06c-.29,2.08-1.72,8.42-8.36,9.19-.09,0-.09.13,0,.14,6.64.78,8.07,7.11,8.36,9.19.01.08.13.08.14,0,.29-2.08,1.72-8.42,8.36-9.19.09,0,.09-.13,0-.14-6.64-.78-8.07-7.11-8.36-9.19-.01-.08-.13-.08-.14,0Z"
                }
            }

            ShapePath {
                fillColor: root.starColour
                strokeColor: "transparent"

                PathSvg {
                    path: "m113.36,15.5c-.22,1.29-1.08,4.35-4.38,4.87-.08.01-.08.13,0,.14,3.3.52,4.17,3.58,4.38,4.87.01.08.13.08.14,0,.22-1.29,1.08-4.35,4.38-4.87.08-.01.08-.13,0-.14-3.3-.52-4.17-3.58-4.38-4.87-.01-.08-.13-.08-.14,0Z"
                }
            }

            ShapePath {
                fillColor: root.starColour
                strokeColor: "transparent"

                PathSvg {
                    path: "m112.69,65.22c-.19,1.01-.86,3.15-3.2,3.57-.08.01-.08.13,0,.14,2.34.42,3.01,2.56,3.2,3.57.01.08.13.08.14,0,.19-1.01.86-3.15,3.2-3.57.08-.01.08-.13,0-.14-2.34-.42-3.01-2.56-3.2-3.57-.01-.08-.13-.08-.14,0Z"
                }
            }
        }

        Item {
            id: badgeGroup

            visible: root.showBadge
            x: 77.08
            y: 65.23
            width: 41
            height: 41
            scale: 1.2423
            transformOrigin: Item.Center

            Shape {
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    fillColor: root.badgeColour
                    strokeColor: root.badgeStrokeColour
                    strokeWidth: 0.8
                    startX: 20.5
                    startY: 0

                    PathArc {
                        x: 20.5
                        y: 41
                        radiusX: 20.5
                        radiusY: 20.5
                    }

                    PathArc {
                        x: 20.5
                        y: 0
                        radiusX: 20.5
                        radiusY: 20.5
                    }
                }
            }

            Item {
                id: badgeGearGroup

                x: -1.3667
                y: -1.3667
                scale: 0.683333
                transformOrigin: Item.TopLeft

                Shape {
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        fillColor: root.badgeIconColour
                        strokeColor: "transparent"

                        PathSvg {
                            path: "m 36,11.00001 -8,1.210938 v 28.9375 L 36,39.00001 V 27.820322 l 8,13.179688 8,-3 -10,-12 L 52.003906,13.003916 44.242188,11.00001 36,24.117198 Z m -16.289062,7.847656 c -0.189184,0 -0.378371,0.07368 -0.523438,0.21875 l -3.144531,3.144532 c -0.290135,0.290134 -0.220288,0.704614 0,1.05078 l 3.253906,5.109376 c -0.241085,0.500442 -0.449846,1.01582 -0.625,1.542968 -0.0077,0.02268 -0.01978,0.04368 -0.02734,0.0664 l -5.902344,1.3125 C 12.341647,31.381998 12,31.624856 12,32.035166 v 1.964844 1.964844 c 0,0.41031 0.341647,0.65318 0.742188,0.742188 l 5.902343,1.3125 c 0.01292,0.0388 0.03357,0.07462 0.04687,0.11328 0.17049,0.512084 0.372704,1.013054 0.605469,1.5 l -3.253906,5.10547 c -0.220288,0.346166 -0.290135,0.760646 0,1.05078 l 3.144532,3.144532 c 0.290135,0.290134 0.756735,0.290134 1.046876,0 l 5.101562,-3.25 c 0.501518,0.243898 1.01821,0.455272 1.546874,0.632812 0.0347,0.0122 0.06678,0.03108 0.10156,0.04296 l 1.308592,5.898436 C 28.29296,52.668124 28.62484,53 29.035148,53 h 4.441406 c 0.41031,0 0.65318,-0.341648 0.742188,-0.742188 l 1.308594,-6.078124 c 0.601208,-0.226026 1.184836,-0.496298 1.746094,-0.808594 l 4.980468,3.5625 c 0.290136,0.290134 0.756742,0.290134 1.046876,0 l 3.14453,-3.144532 c 0.290136,-0.290134 0.220288,-0.704614 0,-1.05078 l -1.89453,-2.875 -0.19922,0.07422 c -0.450502,0.16922 -0.95765,-0.0064 -1.20703,-0.417968 l -1.99218,-3.281242 C 39.492472,42.208682 35.572478,45.00001 31,45.00001 c -6.075132,0 -11,-4.924868 -11,-11 0,-4.66184 2.905598,-8.6367 7,-10.238282 v -2.191406 l -0.0156,0.07032 c -0.04416,0.015 -0.0849,0.03914 -0.1289,0.05468 -0.52165,0.17324 -1.03179,0.379376 -1.527344,0.617188 l -5.09378,-3.246094 c -0.145072,-0.145067 -0.334254,-0.21875 -0.523438,-0.21875 z"
                        }
                    }
                }
            }
        }
    }
}


