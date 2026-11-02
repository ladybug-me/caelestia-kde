import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

Popup {
    id: root

    property string pluginId: ""

    property var settingsSchema: PluginLoader.settingsSchemaFor(root.pluginId)

    property string pluginName: ""

    // The settings file is read once when the popup opens: `Settings.value()` is a plain
    // function, so binding a control straight to it never updates after a write. Keeping
    // the values here lets the controls follow what the user just changed.
    property var values: ({})

    property bool dirty: false

    function openIn(win) {
        if (win && win.contentItem)
            parent = win.contentItem;

        open();
    }

    function defaultFor(field) {
        if (field.default !== undefined)
            return field.default;
        if (field.type === "toggle")
            return false;
        if (field.type === "text")
            return "";
        return 0;
    }

    function loadValues() {
        const next = {};
        for (const field of root.settingsSchema ?? [])
            next[field.id] = pSettings.value(field.id, root.defaultFor(field));
        root.values = next;
        root.dirty = false;
    }

    function valueOf(id, fallback) {
        return root.values[id] !== undefined ? root.values[id] : fallback;
    }

    function setValue(id, value) {
        pSettings.setValue(id, value);
        const next = Object.assign({}, root.values);
        next[id] = value;
        root.values = next;
        root.dirty = true;
    }

    // Restores the widgets the plugin contributes with the values just written, so the
    // change is visible without restarting the shell.
    function apply() {
        if (!root.dirty)
            return;

        pSettings.sync();
        PluginLoader.applySettings(root.pluginId);
        root.dirty = false;
    }

    x: parent ? Math.round((parent.width - width) / 2) : 0
    y: parent ? Math.round((parent.height - height) / 2) : 0
    width: 450
    modal: true
    dim: true
    onOpened: root.loadValues()

    background: Rectangle {
        color: Colours.palette.m3surface
        radius: Tokens.rounding.large
        border.width: 1
        border.color: Colours.palette.m3outlineVariant
    }

    contentItem: ColumnLayout {
        spacing: Tokens.spacing.large

        Settings {
            id: pSettings

            category: "Plugin_" + root.pluginId
        }

        StyledText {
            text: root.pluginName + " " + qsTr("Settings")
            font: Tokens.font.title.large
            Layout.fillWidth: true
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            Repeater {
                model: root.settingsSchema
                delegate: RowLayout {
                    id: delegateRow
                    Layout.fillWidth: true

                    required property var modelData

                    StyledText {
                        text: delegateRow.modelData.label
                        Layout.fillWidth: true
                        font: Tokens.font.body.medium
                    }

                    RowLayout {
                        visible: delegateRow.modelData.type === "enum"
                        spacing: Tokens.spacing.extraSmall

                        Repeater {
                            model: delegateRow.modelData.options
                            delegate: TextButton {
                                required property string modelData
                                property string currentVal: root.valueOf(delegateRow.modelData.id, delegateRow.modelData.default)

                                text: modelData
                                enabled: currentVal !== modelData
                                onClicked: root.setValue(delegateRow.modelData.id, modelData)
                            }
                        }
                    }

                    StyledSwitch {
                        visible: delegateRow.modelData.type === "toggle"
                        checked: root.valueOf(delegateRow.modelData.id, root.defaultFor(delegateRow.modelData))
                        onToggled: root.setValue(delegateRow.modelData.id, checked)
                    }

                    StyledTextField {
                        visible: delegateRow.modelData.type === "text"
                        Layout.preferredWidth: 180
                        text: root.valueOf(delegateRow.modelData.id, root.defaultFor(delegateRow.modelData))
                        placeholderText: delegateRow.modelData.placeholder ?? ""
                        onEditingFinished: root.setValue(delegateRow.modelData.id, text)
                    }

                    CustomSpinBox {
                        visible: delegateRow.modelData.type === "number"
                        Layout.preferredWidth: 140
                        min: delegateRow.modelData.min ?? 0
                        max: delegateRow.modelData.max ?? 100
                        step: delegateRow.modelData.step ?? 1
                        value: Number(root.valueOf(delegateRow.modelData.id, root.defaultFor(delegateRow.modelData)))
                        onValueModified: v => root.setValue(delegateRow.modelData.id, v)
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            TextButton {
                text: qsTr("Done")
                onClicked: {
                    root.apply();
                    root.close();
                }
            }
        }
    }
}
