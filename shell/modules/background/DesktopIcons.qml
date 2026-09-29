pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.services
import qs.utils

Item {
    id: root

    required property ShellScreen screenData

    property int cellWidth: 100
    property int cellHeight: 120
    property var savedOrder: []
    property bool layoutLoaded: false
    // True while an icon's inline rename editor is open; the background window
    // raises its layer-shell keyboard focus on this so the editor can type.
    property Item renamingDelegate: null

    readonly property bool renameActive: renamingDelegate !== null

    function getIconCols(): int {
        return Math.max(1, Math.floor(gridItem.width / root.cellWidth));
    }

    function getIconRows(): int {
        return Math.max(1, Math.floor(gridItem.height / root.cellHeight));
    }

    function saveLayout(): void {
        if (!layoutLoaded)
            return;
        let arr = [];
        for (let i = 0; i < instantiator.count; i++) {
            let item = instantiator.objectAt(i);
            if (item)
                arr.push({ name: item.fileName, col: item.col, row: item.row });
        }
        saveProc.jsonContent = JSON.stringify(arr);
        saveProc.running = true;
    }

    function isCellFree(c: int, r: int, ignoreItem: Item): bool {
        for (let i = 0; i < instantiator.count; i++) {
            let item = instantiator.objectAt(i);
            if (item && item !== ignoreItem && item.col === c && item.row === r)
                return false;
        }
        return true;
    }

    function findFreeCell(): var {
        for (let r = 0; r < 1000; r++) {
            for (let c = 0; c < getIconCols(); c++) {
                if (isCellFree(c, r, null))
                    return { col: c, row: r };
            }
        }
        return { col: 0, row: 0 };
    }

    function runFileOp(args: var): void {
        fileOpProc.commandLine = args;
        fileOpProc.running = true;
    }

    function trashIcon(path: string): void {
        if (path.length === 0)
            return;
        runFileOp(["kioclient", "move", path, "trash:/"]);
    }

    function renameIcon(oldPath: string, newName: string): void {
        const idx = Math.max(oldPath.lastIndexOf("/"), 0);
        const dir = oldPath.substring(0, idx);
        const trimmed = newName.trim();
        if (trimmed.length === 0 || trimmed === oldPath.substring(idx + 1))
            return;
        // Stay inside the desktop folder: no separators, no relative walks.
        if (trimmed === "." || trimmed === ".." || trimmed.includes("/"))
            return;
        runFileOp(["kioclient", "move", oldPath, dir + "/" + trimmed]);
    }

    function iconAt(x: real, y: real): bool {
        if (!visible)
            return false;
        const c = Math.floor((x - gridItem.x) / root.cellWidth);
        const r = Math.floor((y - gridItem.y) / root.cellHeight);
        for (let i = 0; i < instantiator.count; i++) {
            const item = instantiator.objectAt(i);
            if (item && item.col === c && item.row === r)
                return true;
        }
        return false;
    }

    anchors.fill: parent
    visible: GlobalConfig.forScreen(screenData.name).background.enabled && GlobalConfig.forScreen(screenData.name).background.wallpaperEnabled && GlobalConfig.forScreen(screenData.name).background.desktopIconsEnabled

    Component.onCompleted: {
        loadLayoutProc.running = true;
    }

    Process {
        id: loadLayoutProc

        command: ["sh", "-c", "cat ~/.local/share/caelestia/desktop_layout.json 2>/dev/null || echo '[]'"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.savedOrder = JSON.parse(text);
                } catch (e) {
                    root.savedOrder = [];
                }
                root.layoutLoaded = true;
                for (var i = 0; i < instantiator.count; i++) {
                    var item = instantiator.objectAt(i);
                    if (item)
                        item.initPosition();
                }
            }
        }
    }

    Process {
        id: saveProc

        property string jsonContent: ""

        command: ["python3", "-c", "import sys, os; d = os.path.dirname(sys.argv[1]); os.makedirs(d, exist_ok=True) if d else None; open(sys.argv[1], 'w').write(sys.argv[2])", Quickshell.env("HOME") + "/.local/share/caelestia/desktop_layout.json", jsonContent]
    }

    Process {
        id: fileOpProc

        property var commandLine: []
        property string errorText: ""

        command: commandLine
        stderr: StdioCollector {
            onStreamFinished: fileOpProc.errorText = text.trim()
        }
        onExited: (exitCode) => {
            if (exitCode !== 0)
                Toaster.toast(qsTr("File operation failed"),
                    fileOpProc.errorText.length > 0 ? fileOpProc.errorText : qsTr("kioclient could not complete the request"),
                    "error");
            fileOpProc.errorText = "";
        }
    }

    Item {
        id: gridItem

        readonly property int barZone: Visibilities.bars.get(root.screenData.name)?.visualThickness ?? (Tokens.sizes.bar.innerWidth + Math.max(Tokens.padding.small, Config.border.thickness))
        readonly property int baseMargin: Tokens.padding.large * 2

        anchors.fill: parent
        anchors.margins: baseMargin
        anchors.leftMargin: Config.bar.position === "left" ? baseMargin + barZone : baseMargin
        anchors.rightMargin: Config.bar.position === "right" ? baseMargin + barZone : baseMargin
        anchors.topMargin: Config.bar.position === "top" ? baseMargin + barZone : baseMargin
        anchors.bottomMargin: Config.bar.position === "bottom" ? baseMargin + barZone : baseMargin

        Instantiator {
            id: instantiator

            model: FolderListModel {
                id: folderModel

                folder: "file://" + Quickshell.env("HOME") + "/Desktop"
                showDirsFirst: true
                nameFilters: ["*"]
            }
            onObjectAdded: (index, object) => {
                object.parent = gridItem;
            }

            delegate: Item {
                id: delegateItem

                required property string fileName
                required property string filePath
                required property bool fileIsDir
                required property string fileSuffix

                property string path: filePath.replace("file://", "")
                property string desktopName: fileName
                property string desktopIcon: ""
                property int col: -1
                property int row: -1
                property bool renaming: false

                readonly property DesktopEntry desktopEntry: {
                    if (!fileName.toLowerCase().endsWith(".desktop"))
                        return null;
                    const cleanId = fileName.endsWith(".desktop") ? fileName.slice(0, -8) : fileName;
                    return DesktopEntries.applications.values.find(e => e.id === fileName || e.id === cleanId || e.id + ".desktop" === fileName)
                        ?? DesktopEntries.heuristicLookup(cleanId)
                        ?? null;
                }

                readonly property string iconSetBase: Qt.resolvedUrl(Quickshell.shellDir + "/assets/icons/yet-another-monochrome-icon-set")
                property bool useMaterialYouIcons: GlobalConfig.forScreen(screenData.name).background.materialYouIconsEnabled
                property bool useVibrantIcons: GlobalConfig.forScreen(screenData.name).background.materialYouIconsVibrant

                function startRename(): void {
                    if (root.renamingDelegate && root.renamingDelegate !== delegateItem)
                        root.renamingDelegate.cancelRename();
                    root.renamingDelegate = delegateItem;
                    renaming = true;
                    renameField.text = fileName;
                    renameField.forceActiveFocus();
                }

                function commitRename(): void {
                    if (!renaming)
                        return;
                    renaming = false;
                    if (root.renamingDelegate === delegateItem)
                        root.renamingDelegate = null;
                    root.renameIcon(path, renameField.text);
                }

                function cancelRename(): void {
                    renaming = false;
                    if (root.renamingDelegate === delegateItem)
                        root.renamingDelegate = null;
                }

                function initPosition(): void {
                    if (col !== -1 && row !== -1)
                        return;

                    let targetCol = -1;
                    let targetRow = -1;
                    let foundSaved = false;
                    for (let i = 0; i < root.savedOrder.length; i++) {
                        if (root.savedOrder[i].name === fileName) {
                            targetCol = root.savedOrder[i].col;
                            targetRow = root.savedOrder[i].row;
                            foundSaved = true;
                            break;
                        }
                    }

                    if (foundSaved && root.isCellFree(targetCol, targetRow, delegateItem)) {
                        col = targetCol;
                        row = targetRow;
                    } else {
                        let freeCell = root.findFreeCell();
                        col = freeCell.col;
                        row = freeCell.row;
                        root.saveLayout();
                    }
                }

                function getIconName(isDir: bool, filename: string, suffix: string): string {
                    if (isDir)
                        return "folder";
                    const ext = suffix.toLowerCase();
                    const imageExts = ["png", "jpg", "jpeg", "gif", "svg", "webp", "bmp"];
                    const videoExts = ["mp4", "mkv", "webm", "avi", "mov"];
                    const archiveExts = ["zip", "tar", "gz", "rar", "7z"];
                    const audioExts = ["mp3", "wav", "flac", "ogg"];
                    const codeExts = ["qml", "js", "html", "css", "py", "sh", "cpp", "c", "h", "json"];

                    if (ext === "pdf")
                        return "application-pdf";
                    if (filename.toLowerCase().endsWith(".desktop"))
                        return desktopIcon || desktopEntry?.icon || "application-x-executable";
                    if (imageExts.includes(ext))
                        return "image-x-generic";
                    if (videoExts.includes(ext))
                        return "video-x-generic";
                    if (archiveExts.includes(ext))
                        return "package-x-generic";
                    if (audioExts.includes(ext))
                        return "audio-x-generic";
                    if (codeExts.includes(ext))
                        return "text-x-script";

                    return "text-x-generic";
                }

                function getIconSource(isDir: bool, filename: string, suffix: string): string {
                    if (filename.toLowerCase().endsWith(".desktop")) {
                        const iconVal = desktopEntry?.icon || desktopIcon;
                        if (iconVal !== "") {
                            if (iconVal.startsWith("/"))
                                return "file://" + iconVal;
                            if (useMaterialYouIcons)
                                return iconSetBase + "/apps/scalable/" + iconVal + ".svg";
                            return Quickshell.iconPath(iconVal, "application-x-executable");
                        }
                    }
                    const iconName = getIconName(isDir, filename, suffix);
                    if (useMaterialYouIcons) {
                        if (isDir)
                            return iconSetBase + "/places/scalable/folder.svg";
                        return iconSetBase + "/mimetypes/scalable/" + iconName + ".svg";
                    }
                    return "image://icon/" + iconName;
                }

                function getFallbackIconSource(isDir: bool, filename: string, suffix: string): string {
                    if (filename.toLowerCase().endsWith(".desktop")) {
                        const iconVal = desktopEntry?.icon || desktopIcon;
                        if (iconVal !== "") {
                            if (iconVal.startsWith("/"))
                                return "file://" + iconVal;
                            return Quickshell.iconPath(iconVal, "application-x-executable");
                        }
                    }
                    return "image://icon/" + getIconName(isDir, filename, suffix);
                }

                function launch(): void {
                    if (delegateItem.desktopEntry)
                        Launch.launchEntry(delegateItem.desktopEntry);
                    else
                        Launch.exec(["xdg-open", path]);
                }

                width: root.cellWidth
                height: root.cellHeight
                x: col * root.cellWidth + (dragHandler.active ? dragHandler.translation.x : 0)
                y: row * root.cellHeight + (dragHandler.active ? dragHandler.translation.y : 0)
                z: dragHandler.active ? 10 : 1

                Component.onCompleted: {
                    if (root.layoutLoaded)
                        initPosition();
                    if (fileName.toLowerCase().endsWith(".desktop"))
                        desktopInfoProc.running = true;
                }

                Component.onDestruction: {
                    if (root.renamingDelegate === delegateItem)
                        root.renamingDelegate = null;
                }

                Process {
                    id: desktopInfoProc

                    command: ["cat", path]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            var lines = text.trim().split("\n");
                            var inDesktopEntry = false;
                            var nameFound = false;
                            var iconFound = false;
                            for (var i = 0; i < lines.length; i++) {
                                var line = lines[i].trim();
                                if (line === "[Desktop Entry]") {
                                    inDesktopEntry = true;
                                    continue;
                                } else if (line.startsWith("[")) {
                                    inDesktopEntry = false;
                                }

                                if (inDesktopEntry) {
                                    if (!nameFound && line.startsWith("Name=")) {
                                        desktopName = line.substring(5);
                                        nameFound = true;
                                    } else if (!iconFound && line.startsWith("Icon=")) {
                                        desktopIcon = line.substring(5);
                                        iconFound = true;
                                    }
                                }
                                if (nameFound && iconFound)
                                    break;
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    color: Colours.palette.m3onSurface
                    opacity: mouseArea.containsMouse || dragHandler.active ? 0.12 : 0
                    radius: Tokens.rounding.medium

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 100
                        }
                    }
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Tokens.padding.small
                    spacing: Tokens.spacing.small

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Image {
                            id: iconImage

                            anchors.centerIn: parent
                            width: 64
                            height: 64
                            source: delegateItem.getIconSource(delegateItem.fileIsDir, delegateItem.fileName, delegateItem.fileSuffix)
                            fillMode: Image.PreserveAspectFit
                            layer.enabled: delegateItem.useMaterialYouIcons
                            layer.effect: Colouriser {
                                sourceColor: "black"
                                colorizationColor: {
                                    let c = Colours.palette.m3primary;
                                    if (delegateItem.useVibrantIcons)
                                        return Qt.hsla(c.hslHue, 1.0, Math.max(0.4, Math.min(0.6, c.hslLightness)), c.a);
                                    return c;
                                }
                            }
                            onStatusChanged: {
                                if (status === Image.Error && delegateItem.useMaterialYouIcons) {
                                    layer.enabled = false;
                                    source = delegateItem.getFallbackIconSource(delegateItem.fileIsDir, delegateItem.fileName, delegateItem.fileSuffix);
                                }
                            }
                        }
                    }

                    Text {
                        visible: !delegateItem.renaming
                        Layout.fillWidth: true
                        text: {
                            if (delegateItem.fileName.toLowerCase().endsWith(".desktop"))
                                return delegateItem.desktopEntry?.name || delegateItem.desktopName;
                            return delegateItem.fileName;
                        }
                        color: Colours.palette.m3onSurface
                        font: Tokens.font.body.small
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                        style: Text.Outline
                        styleColor: Colours.palette.m3surface
                    }

                    StyledTextField {
                        id: renameField

                        visible: delegateItem.renaming
                        Layout.fillWidth: true
                        onAccepted: delegateItem.commitRename()
                        onActiveFocusChanged: {
                            // Clicking anywhere outside the editor cancels the rename.
                            if (!activeFocus && delegateItem.renaming)
                                delegateItem.cancelRename();
                        }
                        Keys.onEscapePressed: delegateItem.cancelRename()
                    }
                }

                DragHandler {
                    id: dragHandler

                    property real lastTranslationX: 0
                    property real lastTranslationY: 0

                    target: null
                    enabled: !delegateItem.renaming
                    onTranslationChanged: {
                        if (active) {
                            lastTranslationX = translation.x;
                            lastTranslationY = translation.y;
                        }
                    }
                    onActiveChanged: {
                        if (!active) {
                            let dropX = col * root.cellWidth + lastTranslationX + delegateItem.width / 2;
                            let dropY = row * root.cellHeight + lastTranslationY + delegateItem.height / 2;
                            let newCol = Math.floor(dropX / root.cellWidth);
                            let newRow = Math.floor(dropY / root.cellHeight);

                            newCol = Math.max(0, Math.min(newCol, root.getIconCols() - 1));
                            newRow = Math.max(0, Math.min(newRow, root.getIconRows() - 1));

                            if (!root.isCellFree(newCol, newRow, delegateItem)) {
                                // Find nearest free cell outwards using a spiral or simple fallback
                                let found = false;
                                for (let rad = 1; rad < Math.max(root.getIconCols(), root.getIconRows()); rad++) {
                                    for (let r = Math.max(0, newRow - rad); r <= Math.min(root.getIconRows() - 1, newRow + rad); r++) {
                                        for (let c = Math.max(0, newCol - rad); c <= Math.min(root.getIconCols() - 1, newCol + rad); c++) {
                                            if (root.isCellFree(c, r, delegateItem)) {
                                                newCol = c;
                                                newRow = r;
                                                found = true;
                                                break;
                                            }
                                        }
                                        if (found)
                                            break;
                                    }
                                    if (found)
                                        break;
                                }
                            }

                            col = newCol;
                            row = newRow;
                            root.saveLayout();
                        }
                    }
                }

                MouseArea {
                    id: mouseArea

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.RightButton) {
                            // The click that dismisses the editor should not
                            // immediately open a new menu on the same icon.
                            if (!delegateItem.renaming)
                                iconMenu.openFor(delegateItem, mouse.x, mouse.y);
                            return;
                        }
                        if (delegateItem.renaming) {
                            renameField.forceActiveFocus();
                            return;
                        }
                        if (root.renameActive) {
                            // Another icon's editor is open: click outside it
                            // cancels the rename instead of opening the file.
                            root.renamingDelegate.cancelRename();
                            return;
                        }
                        delegateItem.launch();
                    }
                }
            }
        }
    }

    DesktopIconContextMenu {
        id: iconMenu

        onRenameRequested: (delegateTarget) => {
            if (delegateTarget)
                delegateTarget.startRename();
        }
        onTrashRequested: path => root.trashIcon(path)
    }
}
