/*
    SPDX-FileCopyrightText: 2024 ladybug-me
    SPDX-License-Identifier: GPL-3.0-or-later
*/

pragma Singleton

import QtQuick

QtObject {
    readonly property string fontHeading: "Outfit"
    readonly property string fontBody: "Rubik"
    readonly property string fontMono: "JetBrainsMono Nerd Font, monospace"
    readonly property string fontIcon: "Material Symbols Rounded"
    readonly property string fontMetrics: "Google Sans Flex"

    readonly property int sizeVerySmall: 12
    readonly property int sizeSmall: 14
    readonly property int sizeNormal: 14
    readonly property int sizeMedium: 16
    readonly property int sizeLarge: 20
    readonly property int sizeVeryLarge: 28

    readonly property int animFast: 150
    readonly property int animStandard: 250
    readonly property int animSlow: 500
}
