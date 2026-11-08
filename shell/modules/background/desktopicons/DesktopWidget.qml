pragma ComponentBehavior: Bound

import QtQuick

// What the desktop hands every widget: the card that holds it, the screen it lives on,
// and its own settings with the type's defaults already applied. Declaring them once is
// what makes them a contract instead of three lines every widget repeats.
Item {
    id: root

    property var frame
    property var controller
    readonly property var cfg: root.frame?.config ?? ({})

    // Set by a widget that has nothing to show (no track playing, say) so the card can
    // step aside. It is only a wish: the widget editor always shows the card, or the
    // widget could never be brought back.
    property bool wantsHidden: false
}
