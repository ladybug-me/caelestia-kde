pragma Singleton

import ".."
import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.services
import qs.utils

Searcher {
    id: root

    function transformSearch(search: string): string {
        return search.slice(`${GlobalConfig.launcher.actionPrefix}variant `.length);
    }

    function previewVariant(variant: string): void {
        // The scheme command derives the preview from whatever is in effect: the
        // wallpaper for a dynamic scheme, the shipped colors otherwise. It prints
        // the palette instead of applying it, which is what a preview is.
        getPreviewColoursProc.command = ["caelestia", "scheme", "set", "--preview", "-v", variant, ...Colours.smartArg];
        getPreviewColoursProc.running = true;
    }

    useFuzzy: GlobalConfig.launcher.useFuzzy.variants
    list: [
        Variant {
            variant: "vibrant"
            icon: "sentiment_very_dissatisfied"
            name: qsTr("Vibrant")
            description: qsTr("A high chroma palette. The primary palette's chroma is at maximum.")
        },
        Variant {
            variant: "tonalspot"
            icon: "android"
            name: qsTr("Tonal Spot")
            description: qsTr("Default for Material theme colors. A pastel palette with a low chroma.")
        },
        Variant {
            variant: "expressive"
            icon: "compare_arrows"
            name: qsTr("Expressive")
            description: qsTr("A medium chroma palette. The primary palette's hue is different from the seed color, for variety.")
        },
        Variant {
            variant: "fidelity"
            icon: "compare"
            name: qsTr("Fidelity")
            description: qsTr("Matches the seed color, even if the seed color is very bright (high chroma).")
        },
        Variant {
            variant: "content"
            icon: "sentiment_calm"
            name: qsTr("Content")
            description: qsTr("Almost identical to fidelity.")
        },
        Variant {
            variant: "fruitsalad"
            icon: "nutrition"
            name: qsTr("Fruit Salad")
            description: qsTr("A playful theme - the seed color's hue does not appear in the theme.")
        },
        Variant {
            variant: "rainbow"
            icon: "looks"
            name: qsTr("Rainbow")
            description: qsTr("A playful theme - the seed color's hue does not appear in the theme.")
        },
        Variant {
            variant: "neutral"
            icon: "contrast"
            name: qsTr("Neutral")
            description: qsTr("Close to grayscale, a hint of chroma.")
        },
        Variant {
            variant: "monochrome"
            icon: "filter_b_and_w"
            name: qsTr("Monochrome")
            description: qsTr("All colors are grayscale, no chroma.")
        }
    ]

    Process {
        id: getPreviewColoursProc

        stdout: StdioCollector {
            onStreamFinished: {
                Colours.load(text, true);
                Colours.showPreview = true;
            }
        }
    }

    component Variant: QtObject {
        required property string variant
        required property string icon
        required property string name
        required property string description

        function onClicked(list: var): void {
            if (list) {
                list.visibilities.launcher = false;
            }
            // The variant is the user's from here on, so the wallpaper stops picking it. The
            // command is told that rather than left to read the setting back: the write below is
            // batched and debounced, and the pipeline keeps no copy of the setting anyway.
            GlobalConfig.services.smartScheme = false;
            Quickshell.execDetached(["caelestia", "scheme", "set", "--no-smart", "-v", variant]);
        }
    }
}
