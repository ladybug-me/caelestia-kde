pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services

// "Widget Settings": what the card looks like and, from the catalogue's schema, the
// widget's own controls. The form is rebuilt on every opening so its fields always
// start on the values the widget really has.
Item {
    id: root

    property var controller: null
    property bool open: false
    // The card being edited, in window coordinates. The panel places itself beside it,
    // so it never sits on the widget or the gear that opened it.
    property var anchorRect: ({ x: 0, y: 0, width: 0, height: 0 })
    property string widgetId: ""

    readonly property var widget: widgetId !== "" ? (DesktopLayout.widgets[widgetId] ?? null) : null
    readonly property string type: widget?.type ?? ""
    readonly property var info: type !== "" ? (controller?.widgetCatalog?.info(type) ?? null) : null
    readonly property string title: info?.name ?? qsTr("Widget")
    // The form reports how tall it wants to be, so a two-field widget does not get a
    // screen-tall panel and a long one still fits.
    readonly property real formHeight: form.item ? form.item.implicitHeight : 0
    readonly property real maxFormHeight: Math.max(120, root.height * 0.55)

    function openAt(rect: var, id: string): void {
        anchorRect = rect;
        widgetId = id;
        open = true;
        root.refresh();
    }

    function close(): void {
        open = false;
        root.refresh();
    }

    /// Builds the form afresh, so the fields never carry the previous widget's values.
    /// Called on every change that can bring a different widget into the panel -- and
    /// on the type arriving late, which is what happens when the panel is opened
    /// before the layout file has been read.
    function refresh(): void {
        form.active = false;
        if (!root.open || root.type === "")
            return;
        Qt.callLater(() => {
            form.active = root.open && root.type !== "";
        });
    }

    anchors.fill: parent
    visible: panel.opacity > 0

    /// Beside the card when the desktop has room, otherwise under or over it, and always
    /// clamped to the screen. The card keeps its own space, so its gear stays clickable.
    readonly property point place: {
        const gap = Tokens.padding.medium;
        const w = panel.width;
        const h = panel.height;
        const a = root.anchorRect;
        const edge = Tokens.padding.large;
        const besideRight = a.x + a.width + gap;
        const besideLeft = a.x - w - gap;
        const under = a.y + a.height + gap;
        const over = a.y - h - gap;
        const x = besideRight + w <= root.width - edge ? besideRight : besideLeft >= edge ? besideLeft : a.x + a.width - w;
        const y = under + h <= root.height - edge ? under : over >= edge ? over : a.y;
        return Qt.point(Math.max(edge, Math.min(root.width - w - edge, x)), Math.max(edge, Math.min(root.height - h - edge, y)));
    }

    onWidgetChanged: {
        // The widget was removed while its settings were open; there is nothing left
        // to configure, so the panel goes with it.
        if (open && widget === null)
            close();
    }

    // Every change that can put a different widget in the panel rebuilds the form.
    // `type` matters as much as the id: it is empty until the layout file has been
    // read, so a panel opened in that window would otherwise stay blank.
    onTypeChanged: root.refresh()

    // Leaving the editor leaves the panel behind it, or it would float over the
    // desktop with nothing to edit.
    Connections {
        function onActiveChanged(): void {
            if (!WidgetEditor.active)
                root.close();
        }

        target: WidgetEditor
    }

    // No backdrop on purpose: the panel is a floating inspector, not a modal. A
    // full-surface click-catcher sat above the desktop's own menus and swallowed every
    // click meant for them, so the panel only takes what lands on itself.

    Elevation {
        id: panel

        x: root.place.x
        y: root.place.y
        width: Math.min(340, root.width - Tokens.padding.large * 2)
        // Measured from what the panel actually holds, not from a layout's implicit
        // size: the form arrives a tick after the panel, and a stale height clipped the
        // last row before the layout caught up.
        height: Math.min(Tokens.padding.large * 2 + header.implicitHeight + Tokens.spacing.medium + Math.min(root.formHeight, root.maxFormHeight), root.height - Tokens.padding.large * 2)
        radius: Tokens.rounding.large
        level: 2
        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.9
        transformOrigin: Item.TopLeft

        Behavior on opacity {
            Anim {
                type: Anim.FastEffects
            }
        }

        Behavior on scale {
            Anim {
                type: Anim.FastSpatial
            }
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
        }

        StyledRect {
            anchors.fill: parent
            radius: parent.radius
            color: GlobalConfig.appearance.pitchBlack ? "#000000" : Colours.palette.m3surfaceContainerLow

            ColumnLayout {
                id: body

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                RowLayout {
                    id: header

                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: root.title
                            font: Tokens.font.title.small
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: qsTr("Edit the widget's settings")
                            color: Colours.palette.m3onSurfaceVariant
                            font: Tokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    TextButton {
                        text: qsTr("Reset")
                        type: TextButton.Text
                        onClicked: form.item?.reset()
                    }

                    IconButton {
                        type: IconButton.Text
                        icon: "close"
                        onClicked: root.close()
                    }
                }

                Flickable {
                    id: scroll

                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(root.formHeight, root.maxFormHeight)
                    contentWidth: width
                    contentHeight: form.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ScrollBar.vertical: StyledScrollBar {
                        flickable: scroll
                    }

                    Loader {
                        id: form

                        width: scroll.width
                        active: false
                        sourceComponent: WidgetSettingsForm {
                            widgetId: root.widgetId
                            type: root.type
                            catalog: root.controller?.widgetCatalog ?? null
                        }
                    }
                }
            }
        }
    }
}
