pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

ColumnLayout {
    id: root

    property string name
    property string defaultName
    property string subtext

    signal renamed(string name)

    function commit(): void {
        const value = field.text.trim();
        if (value !== root.name)
            root.renamed(value === root.defaultName ? "" : value);
        field.text = root.name;
    }

    spacing: 0

    StyledTextField {
        id: field

        Layout.preferredWidth: Tokens.sizes.nexus.textFieldWidth
        Layout.fillWidth: false
        horizontalAlignment: TextInput.AlignLeft
        verticalPadding: Tokens.padding.small
        horizontalPadding: Tokens.padding.medium
        selectByMouse: true
        onAccepted: root.commit()
        onActiveFocusChanged: {
            if (!activeFocus)
                root.commit();
        }
        Keys.onEscapePressed: {
            field.text = root.name;
            field.focus = false;
        }

        Component.onCompleted: text = root.name
    }

    StyledText {
        Layout.fillWidth: true
        visible: !!root.subtext
        text: root.subtext
        color: Colours.palette.m3onSurfaceVariant
        font: NexusStyle.secondaryFont
        elide: Text.ElideRight
    }

    Connections {
        function onNameChanged(): void {
            if (!field.activeFocus)
                field.text = root.name;
        }

        target: root
    }
}
