pragma ComponentBehavior: Bound
pragma Singleton

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtCore
import Qt.labs.synchronizer
import Quickshell
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.utils

Singleton {
    id: root

    // The single snip-action enum. Lives next to the command builder so the
    // switch and its values can't drift apart. UI files reference it via
    // ScreenshotAction.SnipAction.
    enum SnipAction {
        Copy,
        Edit,
        Search,
        CharRecognition,
        Record,
        RecordWithSound
    }

    property string imageSearchEngineBaseUrl: "https://lens.google.com/uploadbyurl?url="
    property string fileUploadApiEndpoint: "https://uguu.se/upload"

    // Cloud-search consent (default off): the "Search" snip uploads the crop to
    // a public file host and hands the public link to Google Lens. Nothing
    // leaves the machine until the user has opted in through the consent
    // dialog below; the choice is persisted so it only ever has to be given
    // once.
    property alias cloudSearchConsent: consentSettings.cloudSearchConsent

    // Parameters of the snip waiting for consent. Replaced if another request
    // arrives while the dialog is still open.
    property var pendingCloudSearch: null

    function escapeShellStr(str) {
        if (!str) return "''";
        return str.replace(/'/g, "'\\''");
    }

    function getScript(x, y, width, height, screenshotPath, action, saveDir = "") {
        // Build the action script for the given region.
        const rx = Math.round(x);
        const ry = Math.round(y);
        const rw = Math.round(width);
        const rh = Math.round(height);

        const cropBase = `magick '${escapeShellStr(screenshotPath)}' `
            + `-crop ${rw}x${rh}+${rx}+${ry} +repage`
        const cropToFile = (outPath) => `${cropBase} '${escapeShellStr(outPath)}'`
        const cleanup = `rm -f '${escapeShellStr(screenshotPath)}'`
        const annotationCommand = `swappy -f -`; // default to swappy
        const uploadAndGetUrl = (filePath) => {
            return `curl -sF files[]=@'${escapeShellStr(filePath)}' ${root.fileUploadApiEndpoint} | jq -r '.files[0].url'`
        }

        const rawSaveDir = saveDir;

        switch (action) {
            case ScreenshotAction.SnipAction.Copy: {
                let saveDir = rawSaveDir === "" ? "~/Pictures/Screenshots" : rawSaveDir;
                return `set -euo pipefail; ` +
                    `SAVE_DIR='${escapeShellStr(saveDir)}'; ` +
                    `SAVE_DIR="\${SAVE_DIR/#\\~/$HOME}"; ` +
                    `mkdir -p "$SAVE_DIR" && ` +
                    `saveFile="$SAVE_DIR/screenshot-$(date +%Y-%m-%d_%H.%M.%S).png" && ` +
                    `${cropBase} "$saveFile" && ` +
                    `wl-copy -t image/png < "$saveFile"; ` +
                    `ACTION=$(notify-send "Screenshot Captured" "Saved to $saveFile" -i "$saveFile" -a "Screenshot" --action="open=Open" --action="folder=Open Folder" || true); ` +
                    `if [ "$ACTION" = "open" ]; then xdg-open "$saveFile"; elif [ "$ACTION" = "folder" ]; then xdg-open "$SAVE_DIR"; fi; ` +
                    `${cleanup}`
            }

            case ScreenshotAction.SnipAction.Edit: {
                let saveDir = rawSaveDir === "" ? "~/Pictures/Screenshots" : rawSaveDir;
                return `set -euo pipefail; ` +
                    `SAVE_DIR='${escapeShellStr(saveDir)}'; ` +
                    `SAVE_DIR="\${SAVE_DIR/#\\~/$HOME}"; ` +
                    `mkdir -p "$SAVE_DIR" && ` +
                    `saveFile="$SAVE_DIR/screenshot-$(date +%Y-%m-%d_%H.%M.%S).png" && ` +
                    `TMPF=$(mktemp /tmp/qs-snip-XXXXXX.png); ` +
                    `${cropBase} "$TMPF" && ` +
                    `CONF_DIR=$(mktemp -d); ln -s ~/.config/* "$CONF_DIR/" 2>/dev/null || true; rm -rf "$CONF_DIR/swappy"; mkdir -p "$CONF_DIR/swappy"; ` +
                    `SWAPPY_OUT_DIR=$(mktemp -d /tmp/swappy-out-XXXXXX); ` +
                    `if [ -f ~/.config/swappy/config ]; then cp ~/.config/swappy/config "$CONF_DIR/swappy/config"; else echo "[Default]" > "$CONF_DIR/swappy/config"; fi; ` +
                    `sed -i '/^early_exit.*/d; /^save_dir.*/d; /^save_filename_format.*/d; /^auto_save.*/d' "$CONF_DIR/swappy/config"; ` +
                    `echo -e "early_exit=true\\nsave_dir=$SWAPPY_OUT_DIR\\nsave_filename_format=swappy-out.png\\nauto_save=true" >> "$CONF_DIR/swappy/config"; ` +
                    `XDG_CONFIG_HOME="$CONF_DIR" ${annotationCommand} -f "$TMPF" -o "$saveFile" || true; ` +
                    `rm -rf "$CONF_DIR"; ` +
                    `if [ ! -s "$saveFile" ]; then ` +
                        `OUT_FILE=$(ls "$SWAPPY_OUT_DIR"/*.png 2>/dev/null | head -n 1); ` +
                        `if [ -n "$OUT_FILE" ]; then mv "$OUT_FILE" "$saveFile"; fi; ` +
                    `fi; ` +
                    `rm -rf "$SWAPPY_OUT_DIR"; ` +
                    `if [ -s "$saveFile" ]; then ` +
                        `wl-copy -t image/png < "$saveFile"; ` +
                        `ACTION=$(notify-send "Screenshot Captured" "Saved to $saveFile" -i "$saveFile" -a "Screenshot" --action="open=Open" --action="folder=Open Folder" || true); ` +
                        `if [ "$ACTION" = "open" ]; then xdg-open "$saveFile"; elif [ "$ACTION" = "folder" ]; then xdg-open "$SAVE_DIR"; fi; ` +
                    `fi; ` +
                    `rm -f "$TMPF"; ${cleanup}`
            }

            case ScreenshotAction.SnipAction.Search: {
                if (!root.cloudSearchConsent) {
                    // This is the only snip action that sends data off the
                    // machine. Ask first; the real command runs from the
                    // consent dialog once (if) the user opts in, and the
                    // harmless no-op returned here keeps the caller's
                    // execDetached contract valid.
                    root.requestCloudSearch(x, y, width, height, screenshotPath, saveDir);
                    return "true";
                }
                const tmpFile = Paths.runtimeTemp("snip-search.png")
                return `set -euo pipefail; ` +
                    `${cropToFile(tmpFile)} && ` +
                    `URL=$(${uploadAndGetUrl(tmpFile)} | tr -d '\\r\\n'); ` +
                    `case "$URL" in https://*|http://*) xdg-open "${root.imageSearchEngineBaseUrl}$URL";; *) echo "Unexpected upload response" >&2;; esac; ` +
                    `rm -f '${tmpFile}'; ${cleanup}`
            }

            case ScreenshotAction.SnipAction.CharRecognition:
                return `set -euo pipefail; TMPF=$(mktemp /tmp/qs-snip-XXXXXX.png); ` +
                    // Crop and heavily preprocess the image for Tesseract (upscale and grayscale for better accuracy)
                    `${cropBase} -colorspace gray -type grayscale -contrast-stretch 0 -resize 300% "$TMPF" && ` +
                    `LANGS=$(tesseract --list-langs 2>/dev/null | awk 'NR>1 && $1!="osd" {print $1}' | tr '\\n' '+' | sed 's/\\+$//'); ` +
                    `if [ -n "$LANGS" ]; then ` +
                        `TEXT=$(tesseract "$TMPF" stdout -l "$LANGS" 2>/dev/null); ` +
                    `else ` +
                        `TEXT=$(tesseract "$TMPF" stdout 2>/dev/null); ` +
                    `fi; ` +
                    `printf "%s" "$TEXT" | wl-copy; ` +
                    `notify-send "Text Recognized" "$TEXT" -a "Screenshot" || true; ` +
                    `rm -f "$TMPF"; ${cleanup}`

            case ScreenshotAction.SnipAction.Record:
                return `spectacle -R r`

            case ScreenshotAction.SnipAction.RecordWithSound:
                return `spectacle -R r`

            default:
                console.warn("[Region Selector] Unknown snip action, skipping snip.");
                return;
        }
    }

    function getCommand(x, y, width, height, screenshotPath, action, saveDir = "") {
        const script = root.getScript(x, y, width, height, screenshotPath, action, saveDir);
        return script ? ["bash", "-c", script] : undefined;
    }

    // ── Cloud-search consent ──────────────────────────────────────────────

    Settings {
        id: consentSettings

        category: "Screenshot"
        property bool cloudSearchConsent: false
    }

    function requestCloudSearch(x, y, width, height, screenshotPath, saveDir) {
        pendingCloudSearch = {
            x: x,
            y: y,
            width: width,
            height: height,
            screenshotPath: screenshotPath,
            saveDir: saveDir || ""
        };
        consentDialog.active = true;
    }

    // Runs the snip that was waiting for consent. Only called after the user
    // accepted the dialog (which persists the opt-in first).
    function runPendingCloudSearch() {
        const req = pendingCloudSearch;
        pendingCloudSearch = null;
        if (!req)
            return;
        const script = getScript(req.x, req.y, req.width, req.height, req.screenshotPath, ScreenshotAction.SnipAction.Search, req.saveDir);
        if (script)
            Quickshell.execDetached(["bash", "-c", script]);
    }

    // Drops the pending snip and removes the captured screenshot so no copy of
    // it lingers after a refusal.
    function cancelPendingCloudSearch() {
        const req = pendingCloudSearch;
        pendingCloudSearch = null;
        if (req && req.screenshotPath)
            Quickshell.execDetached(["rm", "-f", req.screenshotPath]);
    }

    LazyLoader {
        id: consentDialog

        active: false

        FloatingWindow {
            id: consentWindow

            function accept(): void {
                // Remember the opt-in so the dialog is only ever shown once.
                consentSettings.cloudSearchConsent = true;
                consentDialog.active = false;
                root.runPendingCloudSearch();
            }

            function reject(): void {
                consentDialog.active = false;
                root.cancelPendingCloudSearch();
            }

            implicitWidth: 500
            implicitHeight: consentContent.implicitHeight + Tokens.padding.largeIncreased * 2
            color: Colours.tPalette.m3surface
            title: qsTr("Allow online image search?")

            onVisibleChanged: {
                // Closing the window without answering counts as a refusal.
                if (!visible && consentDialog.active)
                    reject();
            }

            ColumnLayout {
                id: consentContent

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Tokens.padding.largeIncreased
                spacing: Tokens.spacing.medium

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Searching uploads the selected screenshot to %1, a public file host. Anyone with the link can view the image.").arg("uguu.se")
                    wrapMode: Text.WordWrap
                    font: Tokens.font.body.small
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("The image link is then sent to Google Lens (lens.google.com) to run the search.")
                    wrapMode: Text.WordWrap
                    font: Tokens.font.body.small
                }

                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("Nothing is uploaded unless you allow it. Your choice is remembered.")
                    wrapMode: Text.WordWrap
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.label.small
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Tokens.spacing.small
                    spacing: Tokens.spacing.medium

                    Item { Layout.fillWidth: true }

                    TextButton {
                        text: qsTr("Cancel")
                        type: TextButton.Text
                        onClicked: consentWindow.reject()
                    }

                    TextButton {
                        text: qsTr("Upload and search")
                        type: TextButton.Filled
                        onClicked: consentWindow.accept()
                    }
                }
            }
        }
    }
}
