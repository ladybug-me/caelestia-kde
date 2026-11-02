import QtQuick
import Quickshell

FontLoader {
    readonly property bool systemProvidesFamily: Qt.fontFamilies().includes("Google Sans Flex")

    source: systemProvidesFamily ? "" : Quickshell.shellPath("assets/google-sans-flex/GoogleSansFlex-VariableFont_GRAD,ROND,opsz,slnt,wdth,wght.ttf")
}
