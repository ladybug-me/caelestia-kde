import QtQuick

Item {
    property alias color: icon.color
    property alias text: icon.text
    property alias pointSize: icon.font.pointSize

    // Bundled the same way GoogleSansFlex.ttf is (see Main.qml): SDDM runs as its own
    // system user with no access to the logged-in user's ~/.local/share/fonts, so a
    // font that is only ever installed per-user renders as missing glyphs here.
    FontLoader {
        id: materialSymbolsRounded

        source: "../assets/material-symbols/MaterialSymbolsRounded.ttf"
    }

    Text {
        id: icon

        font.family: "Material Symbols Rounded"
        font.pointSize: 20
    }
}
