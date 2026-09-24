// SPDX-FileCopyrightText: 2026 0x0nYx
// SPDX-License-Identifier: GPL-3.0-or-later
//
// Configuration dialog for the Caelestia visualiser applet. Plasma matches the
// cfg_* properties below against the KConfigXT entries in main.xml and binds
// them to the applet's configuration.

pragma ComponentBehavior: Bound

import QtQuick
import org.kde.plasma.components as PlasmaComponents3
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: root

    property alias cfg_barCount: barCountSpin.value
    property alias cfg_rounding: roundingSpin.realValue
    property alias cfg_spacing: spacingSpin.realValue
    property alias cfg_animationDuration: animationDurationSpin.value
    property alias cfg_pauseWhenHidden: pauseWhenHiddenCheck.checked
    property alias cfg_showUnavailableMessage: showUnavailableMessageCheck.checked

    PlasmaComponents3.SpinBox {
        id: barCountSpin

        Kirigami.FormData.label: i18n("Bar count:")
        from: 1
        to: 200
    }

    PlasmaComponents3.SpinBox {
        id: roundingSpin

        Kirigami.FormData.label: i18n("Rounding:")
        decimals: 1
        from: 0
        stepSize: 1
        to: 5
    }

    PlasmaComponents3.SpinBox {
        id: spacingSpin

        Kirigami.FormData.label: i18n("Spacing:")
        decimals: 1
        from: 0
        stepSize: 1
        to: 5
    }

    PlasmaComponents3.SpinBox {
        id: animationDurationSpin

        Kirigami.FormData.label: i18n("Settle animation:")
        from: 0
        stepSize: 50
        suffix: i18n(" ms")
        to: 2000
    }

    PlasmaComponents3.CheckBox {
        id: pauseWhenHiddenCheck

        Kirigami.FormData.label: i18n("Power saving:")
        text: i18n("Stop audio capture while the applet is not visible")
    }

    PlasmaComponents3.CheckBox {
        id: showUnavailableMessageCheck

        Kirigami.FormData.label: i18n("Fallback:")
        text: i18n("Show a message when the Caelestia plugin is unavailable")
    }
}
