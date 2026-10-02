pragma ComponentBehavior: Bound

import "desktopicons"
import "desktopicons/LayoutEngine.js" as Engine
import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.components
import qs.services
import qs.utils
import qs.modules.launcher.services

Item {
    id: root

    required property ShellScreen screenData
    // Wallpaper layer, sampled for the frosted cards of large items.
    property Item wallpaper: null
    readonly property point gridOrigin: Qt.point(gridItem.x, gridItem.y)

    readonly property var screenConfig: GlobalConfig.forScreen(screenData.name).background
    readonly property bool materialYou: screenConfig.materialYouIconsEnabled
    readonly property bool vibrant: screenConfig.materialYouIconsVibrant
    readonly property string desktopDir: Paths.home + "/Desktop"

    readonly property int iconSize: DesktopLayout.iconSize
    readonly property int cellWidth: iconSize + 36
    readonly property int cellHeight: iconSize + 56
    readonly property int cols: Math.max(1, Math.floor(gridItem.areaWidth / cellWidth))
    readonly property int rows: Math.max(1, Math.floor(gridItem.areaHeight / cellHeight))
    readonly property bool gridReady: gridItem.areaWidth > 0 && gridItem.areaHeight > 0
    readonly property bool folderReady: folderModel.status === FolderListModel.Ready

    // File name -> FileEntry for everything in ~/Desktop.
    property var files: ({})

    // Selected item keys. While a group is open these are its members.
    property var selection: ({})
    property string anchorKey: ""
    property string focusKey: ""
    property bool keyboardActive: false
    property var cutUris: []

    // Drag session. dragGroup is set when the items come out of an open group.
    property var dragKeys: []
    property string dragGroup: ""
    property string dragAnchor: ""
    // Where the anchor was grabbed, relative to its top-left corner.
    property point dragHotSpot
    property var previewPositions: null
    property var dropCells: []
    property string mergeKey: ""
    property bool dragImageReady: false
    property string dragImageKey: ""

    property string openGroupId: ""
    property var tiles: ({})

    // Renames that are in flight: old file name -> new file name, so the new
    // file keeps the old one's cell or group slot.
    property var pendingRenames: ({})
    // New file name -> cell, for files dropped or pasted at a spot.
    property var pendingPlacements: ({})
    property point lastPointer: Qt.point(0, 0)

    // Set while an inline rename editor is open; the background window raises
    // its layer-shell keyboard focus on this so the editor can type.
    property Item renamingDelegate: null
    readonly property bool renameActive: renamingDelegate !== null
    readonly property var displayPositions: previewPositions ?? DesktopLayout.positions
    // Key -> { w, h } for everything bigger than one cell: large folders and widgets.
    readonly property var spans: {
        const out = {};
        for (const id in DesktopLayout.groups) {
            const s = DesktopLayout.groups[id].size;
            if (s && (s.w > 1 || s.h > 1))
                out[DesktopLayout.groupKey(id)] = s;
        }
        for (const id in DesktopLayout.widgets)
            out[DesktopLayout.widgetKey(id)] = DesktopLayout.widgets[id].size;
        return out;
    }
    // Sizes shown while a resize is being dragged.
    property var previewSpans: null
    readonly property var displaySpans: previewSpans ?? spans
    readonly property WidgetCatalog widgetCatalog: WidgetCatalog {}

    property string ctrlAdded: ""
    property point pressPoint
    property var fileOpQueue: []
    property string typeAhead: ""

    // Rewrites one key in the [Desktop Entry] group, leaving the rest of the file as is.
    readonly property string setDesktopKeyScript: `import os, sys
path, key, value = sys.argv[1:4]
value = value.replace('\\\\', '\\\\\\\\').replace('\\n', '\\\\n').replace('\\t', '\\\\t').replace('\\r', '\\\\r')
with open(path, encoding='utf-8') as f:
    lines = f.read().split('\\n')
group = None
header = None
found = False
for i, line in enumerate(lines):
    stripped = line.strip()
    if stripped.startswith('['):
        group = stripped
        if group == '[Desktop Entry]' and header is None:
            header = i
        continue
    if group == '[Desktop Entry]' and stripped.split('=', 1)[0].strip() == key:
        lines[i] = key + '=' + value
        found = True
        break
if not found:
    if header is None:
        sys.exit('no [Desktop Entry] group in ' + path)
    lines.insert(header + 1, key + '=' + value)
mode = os.stat(path).st_mode & 0o7777
tmp = os.path.join(os.path.dirname(path), '.' + os.path.basename(path) + '.tmp')
with open(tmp, 'w', encoding='utf-8') as f:
    f.write('\\n'.join(lines))
os.chmod(tmp, mode)
os.replace(tmp, path)
`

    // ---- Lookups ----------------------------------------------------------

    function isGroupKey(key: string): bool {
        return key.startsWith("g/");
    }

    function isWidgetKey(key: string): bool {
        return key.startsWith("w/");
    }

    function isBigKey(key: string): bool {
        return isWidgetKey(key) || (isGroupKey(key) && key in spans);
    }

    function spanOf(key: string): var {
        return spans[key] ?? { w: 1, h: 1 };
    }

    function widgetOf(key: string): var {
        return isWidgetKey(key) ? (DesktopLayout.widgets[nameOf(key)] ?? null) : null;
    }

    function nameOf(key: string): string {
        return key.substring(2);
    }

    function entryOf(key: string): var {
        return key.startsWith("f/") ? (files[nameOf(key)] ?? null) : null;
    }

    function groupOf(key: string): var {
        return isGroupKey(key) ? (DesktopLayout.groups[nameOf(key)] ?? null) : null;
    }

    function groupEntries(id: string): var {
        const g = DesktopLayout.groups[id];
        return g ? g.members.map(m => files[m]).filter(e => !!e) : [];
    }

    function groupContaining(name: string): string {
        for (const id in DesktopLayout.groups)
            if (DesktopLayout.groups[id].members.indexOf(name) !== -1)
                return id;
        return "";
    }

    function labelOf(key: string): string {
        if (isWidgetKey(key))
            return widgetCatalog.info(widgetOf(key)?.type ?? "").name;
        if (isGroupKey(key))
            return groupOf(key)?.name ?? "";
        return entryOf(key)?.displayName ?? nameOf(key);
    }

    // Entries a key stands for: the file itself, or every member of a group.
    function entriesFor(keys: var): var {
        const out = [];
        for (const key of keys) {
            if (isGroupKey(key))
                out.push(...groupEntries(nameOf(key)));
            else if (!isWidgetKey(key) && entryOf(key))
                out.push(entryOf(key));
        }
        return out;
    }

    function topLevelKeys(): var {
        const out = [];
        for (let i = 0; i < entriesModel.count; i++)
            out.push(entriesModel.get(i).key);
        for (let i = 0; i < bigModel.count; i++)
            out.push(bigModel.get(i).key);
        return out;
    }

    // Positions of whatever the keyboard and selection act on right now.
    function contextPositions(): var {
        if (openGroupId !== "")
            return groupPopup.memberPositions();
        const out = {};
        for (const key of topLevelKeys())
            if (DesktopLayout.positions[key])
                out[key] = DesktopLayout.positions[key];
        return out;
    }

    function iconAt(x: real, y: real): bool {
        if (!visible)
            return false;
        if (openGroupId !== "")
            return true;
        const c = Math.floor((x - gridItem.x) / cellWidth);
        const r = Math.floor((y - gridItem.y) / cellHeight);
        return cellOccupant(c, r, []) !== "";
    }

    function cellOccupant(col: int, row: int, exclude: var): string {
        return Engine.occupantAt(contextPositionsTopLevel(), col, row, exclude, spans);
    }

    // ---- Syncing files, groups and positions ------------------------------

    function registerFile(entry: var): void {
        const next = Object.assign({}, files);
        next[entry.fileName] = entry;
        files = next;
        Qt.callLater(syncEntries);
    }

    function unregisterFile(entry: var): void {
        if (files[entry.fileName] !== entry)
            return;
        const next = Object.assign({}, files);
        delete next[entry.fileName];
        files = next;
        Qt.callLater(syncEntries);
    }

    function describe(key: string): var {
        if (isWidgetKey(key))
            return { key, name: labelOf(key), kind: "widget", type: widgetOf(key)?.type ?? "", modified: 0, size: 0 };
        if (isGroupKey(key))
            return { key, name: labelOf(key), kind: "group", type: "", modified: 0, size: 0 };
        const e = entryOf(key);
        return {
            key,
            name: labelOf(key),
            kind: e?.kind ?? "file",
            type: e?.typeName ?? "",
            modified: e?.fileModified ? new Date(e.fileModified).getTime() : 0,
            size: e?.fileSize ?? 0
        };
    }

    function arranged(positions: var, newKeys: var): var {
        if (DesktopLayout.sortKey !== "")
            return Engine.compact(Engine.sortItems(Object.keys(positions).concat(newKeys).map(describe), DesktopLayout.sortKey).map(i => i.key), rows, spans);
        return Engine.compact(Engine.orderedKeys(positions, rows).concat(newKeys), rows, spans);
    }

    function samePositions(a: var, b: var): bool {
        const ka = Object.keys(a);
        if (ka.length !== Object.keys(b).length)
            return false;
        for (const k of ka)
            if (!b[k] || b[k].col !== a[k].col || b[k].row !== a[k].row)
                return false;
        return true;
    }

    function syncEntries(): void {
        if (!DesktopLayout.loaded || !gridReady)
            return;

        // Follow renames and drop members whose files are gone.
        const renames = pendingRenames;
        let renamesChanged = false;
        const groups = {};
        let groupsChanged = false;
        const inherited = {};
        for (const id in DesktopLayout.groups) {
            const g = DesktopLayout.groups[id];
            const members = [];
            for (const m of g.members) {
                if (renames[m] && files[renames[m]] && !files[m]) {
                    members.push(renames[m]);
                    groupsChanged = true;
                } else if (files[m] || !folderReady || renames[m]) {
                    members.push(m);
                } else {
                    groupsChanged = true;
                }
            }
            if (members.length >= 2 || !folderReady) {
                groups[id] = Object.assign({}, g, { members });
            } else {
                groupsChanged = true;
                if (members.length === 1)
                    inherited[DesktopLayout.fileKey(members[0])] = DesktopLayout.groupKey(id);
            }
        }

        const grouped = {};
        for (const id in groups)
            for (const m of groups[id].members)
                grouped[m] = true;
        const desired = [];
        for (const name in files)
            if (!grouped[name])
                desired.push(DesktopLayout.fileKey(name));
        for (const id in groups)
            desired.push(DesktopLayout.groupKey(id));
        for (const id in DesktopLayout.widgets)
            desired.push(DesktopLayout.widgetKey(id));

        const old = DesktopLayout.positions;
        const positions = {};
        for (const key of desired) {
            if (old[key]) {
                positions[key] = old[key];
            } else if (inherited[key] && old[inherited[key]]) {
                positions[key] = old[inherited[key]];
            } else if (key.startsWith("f/")) {
                for (const from in renames) {
                    if (renames[from] === nameOf(key) && old[DesktopLayout.fileKey(from)]) {
                        positions[key] = old[DesktopLayout.fileKey(from)];
                        break;
                    }
                }
            }
        }
        // Keep cells of files that are still loading, so they come back where they were.
        if (!folderReady)
            for (const key in old)
                if (!(key in positions))
                    positions[key] = old[key];

        for (const from in renames) {
            if (files[renames[from]] || (folderReady && !files[from])) {
                delete renames[from];
                renamesChanged = true;
            }
        }
        if (renamesChanged)
            pendingRenames = Object.assign({}, renames);

        const occ = Engine.occupancy(positions, null, spans);
        const newKeys = [];
        for (const key of desired) {
            if (key in positions)
                continue;
            const name = nameOf(key);
            const wanted = pendingPlacements[name];
            let cell;
            const span = spanOf(key);
            if (wanted) {
                cell = Engine.nearestFree(occ, wanted.col, wanted.row, cols, rows, span);
                delete pendingPlacements[name];
            } else {
                cell = Engine.firstFree(occ, cols, rows, span);
            }
            if (DesktopLayout.autoArrange && !wanted) {
                newKeys.push(key);
                continue;
            }
            positions[key] = cell;
            Engine.markRect(occ, cell, span, key);
        }

        const next = DesktopLayout.autoArrange ? arranged(positions, newKeys) : positions;

        if (groupsChanged)
            DesktopLayout.setGroups(groups);
        if (!samePositions(next, old))
            DesktopLayout.setPositions(next);

        // Mirror the top-level keys in the models, keeping existing delegates.
        // Large folders and widgets get their own delegate type.
        mirror(entriesModel, desired.filter(k => !isBigKey(k)));
        mirror(bigModel, desired.filter(k => isBigKey(k)));

        if (openGroupId !== "" && !groups[openGroupId] && folderReady)
            closeGroup();
        pruneSelection();
    }

    function mirror(model: ListModel, keys: var): void {
        const want = {};
        for (const key of keys)
            want[key] = true;
        for (let i = model.count - 1; i >= 0; i--)
            if (!want[model.get(i).key])
                model.remove(i);
        const have = {};
        for (let i = 0; i < model.count; i++)
            have[model.get(i).key] = true;
        for (const key of keys)
            if (!have[key])
                model.append({ key });
    }

    function refit(): void {
        if (!DesktopLayout.loaded || !gridReady)
            return;
        const current = contextPositionsTopLevel();
        const next = DesktopLayout.autoArrange ? arranged(current, []) : Engine.fitIntoGrid(current, cols, rows, spans);
        if (!samePositions(next, current))
            DesktopLayout.setPositions(Object.assign({}, DesktopLayout.positions, next));
    }

    function contextPositionsTopLevel(): var {
        const out = {};
        for (const key of topLevelKeys())
            if (DesktopLayout.positions[key])
                out[key] = DesktopLayout.positions[key];
        return out;
    }

    function sortBy(key: string): void {
        DesktopLayout.setSortKey(key);
        const current = contextPositionsTopLevel();
        const order = Engine.sortItems(Object.keys(current).map(describe), key).map(i => i.key);
        DesktopLayout.setPositions(Engine.compact(order, rows, spans));
        if (!DesktopLayout.autoArrange)
            DesktopLayout.setSortKey("");
    }

    function setAutoArrange(on: bool): void {
        DesktopLayout.setAutoArrange(on);
    }

    // ---- Selection --------------------------------------------------------

    function isSelected(key: string): bool {
        return selection[key] === true;
    }

    function selectedKeys(): var {
        return Object.keys(selection);
    }

    function setSelection(keys: var): void {
        const next = {};
        for (const k of keys)
            next[k] = true;
        selection = next;
    }

    function toggleSelected(key: string): void {
        const next = Object.assign({}, selection);
        if (next[key])
            delete next[key];
        else
            next[key] = true;
        selection = next;
    }

    function clearSelection(): void {
        if (Object.keys(selection).length > 0)
            selection = {};
    }

    function pruneSelection(): void {
        const valid = contextPositions();
        const keys = selectedKeys();
        const kept = keys.filter(k => k in valid);
        if (kept.length !== keys.length)
            setSelection(kept);
        if (focusKey !== "" && !(focusKey in valid))
            focusKey = "";
    }

    function rangeTo(key: string): var {
        if (openGroupId !== "")
            return groupPopup.range(anchorKey || key, key);
        return Engine.rangeBetween(contextPositions(), anchorKey || key, key, rows);
    }

    // ---- Pointer handling for tiles ---------------------------------------

    function grabKeyboard(): void {
        root.forceActiveFocus();
        Kwin.setActiveOutputName(screenData.name);
    }

    function tilePressed(key: string, mouse: var): void {
        if (renameActive && renamingDelegate !== tiles[key])
            renamingDelegate.commitRename();
        grabKeyboard();
        keyboardActive = false;
        lastPointer = mapFromItem(tiles[key], mouse.x, mouse.y);
        pressPoint = Qt.point(mouse.x, mouse.y);
        const ctrl = mouse.modifiers & Qt.ControlModifier;
        const shift = mouse.modifiers & Qt.ShiftModifier;
        if (mouse.button === Qt.RightButton) {
            if (!isSelected(key)) {
                setSelection([key]);
                anchorKey = key;
            }
            focusKey = key;
            return;
        }
        if (shift) {
            const range = rangeTo(key);
            setSelection(ctrl ? selectedKeys().concat(range) : range);
        } else if (!ctrl && !isSelected(key)) {
            setSelection([key]);
            anchorKey = key;
        } else if (ctrl && !isSelected(key)) {
            // Ctrl+press adds right away so a Ctrl+drag carries the item;
            // Ctrl+click on a selected item removes it on release instead.
            toggleSelected(key);
            anchorKey = key;
            ctrlAdded = key;
        }
        focusKey = key;
        prepareDragImage(key);
    }

    function tileClicked(key: string, mouse: var): void {
        const ctrl = mouse.modifiers & Qt.ControlModifier;
        const shift = mouse.modifiers & Qt.ShiftModifier;
        if (ctrl) {
            if (ctrlAdded !== key)
                toggleSelected(key);
            ctrlAdded = "";
            anchorKey = key;
            return;
        }
        ctrlAdded = "";
        if (shift)
            return;
        setSelection([key]);
        anchorKey = key;
        if (DesktopLayout.singleClick)
            openKeys([key]);
    }

    function tileDoubleClicked(key: string, mouse: var): void {
        if (DesktopLayout.singleClick || (mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier)))
            return;
        openKeys([key]);
    }

    function tileContextMenu(key: string, x: real, y: real): void {
        const p = mapFromItem(tiles[key], x, y);
        iconMenu.openAt(p.x, p.y, selectedKeys(), openGroupId);
    }

    function memberContextMenu(groupId: string, name: string, x: real, y: real): void {
        iconMenu.openAt(x, y, [DesktopLayout.fileKey(name)], groupId);
    }

    function openKeys(keys: var): void {
        let launched = false;
        for (const key of keys) {
            if (isWidgetKey(key))
                continue;
            if (isGroupKey(key)) {
                if (keys.length === 1)
                    openGroup(nameOf(key));
                continue;
            }
            const e = entryOf(key);
            if (e) {
                e.launch();
                launched = true;
            }
        }
        if (launched && openGroupId !== "")
            closeGroup();
    }

    // ---- Groups -----------------------------------------------------------

    function openGroup(id: string): void {
        if (!DesktopLayout.groups[id])
            return;
        const tile = tiles[DesktopLayout.groupKey(id)];
        groupPopup.anchorRect = tile ? tile.mapToItem(root, 0, 0, tile.width, tile.height) : Qt.rect(width / 2, height / 2, 0, 0);
        openGroupId = id;
        selection = {};
        focusKey = "";
        anchorKey = "";
    }

    function closeGroup(): void {
        if (openGroupId === "")
            return;
        if (renameActive)
            renamingDelegate.commitRename();
        const key = DesktopLayout.groupKey(openGroupId);
        openGroupId = "";
        setSelection(DesktopLayout.groups[nameOf(key)] ? [key] : []);
        focusKey = isSelected(key) ? key : "";
        anchorKey = focusKey;
    }

    function defaultGroupName(entries: var): string {
        let common = "";
        for (const e of entries) {
            const cat = e.isDesktopFile ? Categories.categoryForApp({ categories: e.categories }) : "other";
            if (cat === "other" || (common !== "" && cat !== common))
                return qsTr("Group");
            common = cat;
        }
        return Categories.definitions.find(d => d.id === common)?.name ?? qsTr("Group");
    }

    function groupable(keys: var): bool {
        if (keys.length < 2)
            return false;
        for (const key of keys)
            if (!isGroupKey(key) && entryOf(key)?.fileIsDir !== false)
                return false;
        return true;
    }

    // Merges the given top-level keys into one group placed at `cell`.
    // An existing group among them (or `intoGroup`) absorbs the rest.
    function makeGroup(keys: var, cell: var, intoGroup: string): void {
        const groups = Object.assign({}, DesktopLayout.groups);
        let id = intoGroup;
        if (id === "") {
            const existing = keys.find(k => isGroupKey(k));
            id = existing ? nameOf(existing) : "";
        }
        const names = [];
        for (const key of keys) {
            if (isGroupKey(key)) {
                if (nameOf(key) === id)
                    continue;
                names.push(...(groups[nameOf(key)]?.members ?? []));
                delete groups[nameOf(key)];
            } else {
                names.push(nameOf(key));
            }
        }
        // Items might come straight out of another group.
        for (const gid in groups) {
            if (gid === id)
                continue;
            const left = groups[gid].members.filter(m => names.indexOf(m) === -1);
            if (left.length !== groups[gid].members.length)
                groups[gid] = Object.assign({}, groups[gid], { members: left });
        }
        if (id === "") {
            id = DesktopLayout.newGroupId();
            groups[id] = { name: defaultGroupName(names.map(n => files[n]).filter(e => !!e)), members: names };
        } else {
            const members = groups[id].members.filter(m => names.indexOf(m) === -1).concat(names);
            groups[id] = Object.assign({}, groups[id], { members });
        }

        const positions = Object.assign({}, DesktopLayout.positions);
        for (const key of keys)
            delete positions[key];
        for (const n of names)
            delete positions[DesktopLayout.fileKey(n)];
        const gkey = DesktopLayout.groupKey(id);
        if (cell)
            positions[gkey] = { col: cell.col, row: cell.row };
        DesktopLayout.setGroups(groups);
        DesktopLayout.setPositions(positions);
        setSelection([gkey]);
        focusKey = gkey;
        anchorKey = gkey;
        Qt.callLater(syncEntries);
    }

    function groupSelection(): void {
        const keys = selectedKeys();
        if (openGroupId !== "" || !groupable(keys))
            return;
        const first = Engine.orderedKeys(contextPositions(), rows).find(k => keys.indexOf(k) !== -1);
        makeGroup(keys, DesktopLayout.positions[first], "");
    }

    function ungroup(id: string): void {
        const g = DesktopLayout.groups[id];
        if (!g)
            return;
        const gkey = DesktopLayout.groupKey(id);
        const groups = Object.assign({}, DesktopLayout.groups);
        delete groups[id];
        const positions = Object.assign({}, DesktopLayout.positions);
        const at = positions[gkey];
        delete positions[gkey];
        const occ = Engine.occupancy(positions, null, spans);
        const keys = [];
        for (const m of g.members) {
            const key = DesktopLayout.fileKey(m);
            const cell = at ? Engine.nearestFree(occ, at.col, at.row, cols, rows) : Engine.firstFree(occ, cols, rows);
            positions[key] = cell;
            Engine.markRect(occ, cell, { w: 1, h: 1 }, key);
            keys.push(key);
        }
        if (openGroupId === id)
            openGroupId = "";
        DesktopLayout.setGroups(groups);
        DesktopLayout.setPositions(DesktopLayout.autoArrange ? arranged(positions, []) : positions);
        Qt.callLater(() => {
            syncEntries();
            setSelection(keys);
        });
    }

    // Takes members out of their group, placing them from `cell` onwards.
    function removeFromGroup(id: string, names: var, cell: var): void {
        const g = DesktopLayout.groups[id];
        if (!g)
            return;
        const groups = Object.assign({}, DesktopLayout.groups);
        const left = g.members.filter(m => names.indexOf(m) === -1);
        const positions = Object.assign({}, DesktopLayout.positions);
        const gkey = DesktopLayout.groupKey(id);
        const groupCell = positions[gkey];
        if (left.length >= 2) {
            groups[id] = Object.assign({}, g, { members: left });
        } else {
            delete groups[id];
            delete positions[gkey];
            if (left.length === 1 && groupCell)
                positions[DesktopLayout.fileKey(left[0])] = groupCell;
            if (openGroupId === id)
                openGroupId = "";
        }
        const occ = Engine.occupancy(positions, null, spans);
        const from = cell ?? groupCell ?? { col: 0, row: 0 };
        for (const n of names) {
            const key = DesktopLayout.fileKey(n);
            const c = Engine.nearestFree(occ, from.col, from.row, cols, rows);
            positions[key] = c;
            Engine.markRect(occ, c, { w: 1, h: 1 }, key);
        }
        DesktopLayout.setGroups(groups);
        DesktopLayout.setPositions(DesktopLayout.autoArrange ? arranged(positions, []) : positions);
        Qt.callLater(syncEntries);
    }

    function renameGroup(id: string, name: string): void {
        const trimmed = name.trim();
        const g = DesktopLayout.groups[id];
        if (!g || trimmed.length === 0 || trimmed === g.name)
            return;
        const groups = Object.assign({}, DesktopLayout.groups);
        groups[id] = Object.assign({}, g, { name: trimmed });
        DesktopLayout.setGroups(groups);
    }

    function reorderGroup(id: string, names: var, index: int): void {
        const g = DesktopLayout.groups[id];
        if (!g)
            return;
        const rest = g.members.filter(m => names.indexOf(m) === -1);
        const at = Math.max(0, Math.min(index, rest.length));
        rest.splice(at, 0, ...g.members.filter(m => names.indexOf(m) !== -1));
        const groups = Object.assign({}, DesktopLayout.groups);
        groups[id] = Object.assign({}, g, { members: rest });
        DesktopLayout.setGroups(groups);
    }

    // ---- Large folders and widgets ----------------------------------------

    // Spans with one key changed, for resize previews and commits.
    function spansWith(key: string, w: int, h: int): var {
        const out = Object.assign({}, spans);
        if (w === 1 && h === 1 && isGroupKey(key))
            delete out[key];
        else
            out[key] = { w, h };
        return out;
    }

    function resizePlan(key: string, w: int, h: int): var {
        const current = contextPositionsTopLevel();
        const s = spansWith(key, w, h);
        if (DesktopLayout.autoArrange)
            return Engine.compact(Engine.orderedKeys(current, rows), rows, s);
        return Engine.planMove(current, [key], key, current[key], cols, rows, s);
    }

    function previewResize(key: string, w: int, h: int): void {
        if (!DesktopLayout.positions[key])
            return;
        const next = resizePlan(key, w, h);
        previewSpans = spansWith(key, w, h);
        previewPositions = Object.assign({}, DesktopLayout.positions, next);
    }

    function endResizePreview(): void {
        previewSpans = null;
        previewPositions = null;
    }

    function resizeItem(key: string, w: int, h: int): void {
        endResizePreview();
        const pos = DesktopLayout.positions[key];
        if (!pos)
            return;
        const next = Object.assign({}, DesktopLayout.positions, resizePlan(key, w, h));
        if (isGroupKey(key)) {
            const id = nameOf(key);
            const groups = Object.assign({}, DesktopLayout.groups);
            if (!groups[id])
                return;
            groups[id] = Object.assign({}, groups[id], { size: { w, h } });
            DesktopLayout.setGroups(groups);
        } else if (isWidgetKey(key)) {
            const id = nameOf(key);
            const widgets = Object.assign({}, DesktopLayout.widgets);
            if (!widgets[id])
                return;
            widgets[id] = Object.assign({}, widgets[id], { size: { w, h } });
            DesktopLayout.setWidgets(widgets);
        }
        DesktopLayout.setPositions(next);
        Qt.callLater(syncEntries);
    }

    function addWidget(type: string, cell: var): void {
        const info = widgetCatalog.info(type);
        if (!info.type)
            return;
        const id = DesktopLayout.newGroupId();
        const key = DesktopLayout.widgetKey(id);
        const widgets = Object.assign({}, DesktopLayout.widgets);
        widgets[id] = { type, size: { w: info.size.w, h: info.size.h }, config: Object.assign({}, info.config ?? {}) };
        const occ = Engine.occupancy(contextPositionsTopLevel(), null, spans);
        const at = cell ? Engine.nearestFree(occ, cell.col, cell.row, cols, rows, info.size) : Engine.firstFree(occ, cols, rows, info.size);
        const positions = Object.assign({}, DesktopLayout.positions);
        positions[key] = at;
        DesktopLayout.setWidgets(widgets);
        DesktopLayout.setPositions(DesktopLayout.autoArrange ? Object.assign(positions, arranged(Object.assign(contextPositionsTopLevel(), { [key]: at }), [])) : positions);
        Qt.callLater(() => {
            syncEntries();
            setSelection([key]);
        });
    }

    function removeWidgets(keys: var): void {
        const widgets = Object.assign({}, DesktopLayout.widgets);
        const positions = Object.assign({}, DesktopLayout.positions);
        let changed = false;
        for (const key of keys) {
            if (!isWidgetKey(key) || !widgets[nameOf(key)])
                continue;
            delete widgets[nameOf(key)];
            delete positions[key];
            changed = true;
        }
        if (!changed)
            return;
        DesktopLayout.setWidgets(widgets);
        DesktopLayout.setPositions(positions);
        Qt.callLater(syncEntries);
    }

    // ---- Renaming ---------------------------------------------------------

    function startRename(key: string): void {
        const tile = tiles[key];
        if (!tile)
            return;
        if (renameActive && renamingDelegate !== tile)
            renamingDelegate.commitRename();
        if (isWidgetKey(key))
            return;
        renamingDelegate = tile;
        if (isGroupKey(key)) {
            tile.startRename(labelOf(key), 0);
            return;
        }
        const e = entryOf(key);
        if (!e)
            return;
        // Launchers are renamed by their shown name, not the file name.
        // Otherwise preselect the base name so typing keeps the extension.
        const dot = e.fileName.lastIndexOf(".");
        tile.startRename(e.isDesktopFile ? e.displayName : e.fileName, !e.isDesktopFile && !e.fileIsDir && dot > 0 ? dot : 0);
    }

    function finishRename(tile: Item): void {
        if (renamingDelegate === tile)
            renamingDelegate = null;
    }

    function applyRename(key: string, text: string): void {
        if (isGroupKey(key)) {
            renameGroup(nameOf(key), text);
            return;
        }
        const e = entryOf(key);
        const trimmed = text.trim();
        if (!e || trimmed.length === 0)
            return;
        if (e.isDesktopFile) {
            if (trimmed !== e.displayName)
                runFileOp(["python3", "-c", setDesktopKeyScript, e.path, e.desktopNameKey, trimmed], qsTr("Rename failed"), () => e.reloadDesktopFile());
            return;
        }
        // Stay inside the desktop folder: no separators, no relative walks.
        if (trimmed === e.fileName || trimmed === "." || trimmed === ".." || trimmed.includes("/"))
            return;
        const renames = Object.assign({}, pendingRenames);
        renames[e.fileName] = trimmed;
        pendingRenames = renames;
        runFileOp(["kioclient", "move", e.url, "file://" + desktopDir + "/" + encodeURIComponent(trimmed)], qsTr("Rename failed"), null);
    }

    // ---- File operations --------------------------------------------------

    function runFileOp(command: var, failTitle: string, done: var): void {
        fileOpQueue = fileOpQueue.concat([{ command, failTitle, done }]);
        if (!fileOpProc.running)
            nextFileOp();
    }

    function nextFileOp(): void {
        if (fileOpQueue.length === 0)
            return;
        const op = fileOpQueue[0];
        fileOpQueue = fileOpQueue.slice(1);
        fileOpProc.current = op;
        fileOpProc.command = op.command;
        fileOpProc.running = true;
    }

    function trashKeys(keys: var): void {
        const urls = entriesFor(keys).map(e => e.url);
        if (urls.length > 0)
            runFileOp(["kioclient", "move", ...urls, "trash:/"], qsTr("File operation failed"), null);
    }

    // action is "move", "copy" or "link"; dest is a local directory.
    function transfer(urls: var, dest: string, action: string, cell: var): void {
        const sources = urls.filter(u => {
            if (action !== "move")
                return true;
            // Moving something into the folder it is already in does nothing.
            const local = decodeURIComponent(u.replace(/^file:\/\//, ""));
            return local.substring(0, local.lastIndexOf("/")) !== dest;
        });
        if (sources.length === 0)
            return;
        if (cell && dest === desktopDir) {
            const placements = Object.assign({}, pendingPlacements);
            for (let i = 0; i < sources.length; i++) {
                const name = decodeURIComponent(sources[i].replace(/\/+$/, "").split("/").pop());
                placements[name] = cell;
            }
            pendingPlacements = placements;
        }
        if (action === "link") {
            // kioclient has no link command; only local files can be linked.
            const local = sources.filter(u => u.startsWith("file://")).map(u => decodeURIComponent(u.substring(7)));
            if (local.length > 0)
                runFileOp(["ln", "-s", "--", ...local, dest + "/"], qsTr("File operation failed"), null);
            return;
        }
        // Interactive so that name clashes bring up KIO's usual rename dialog.
        runFileOp(["kioclient", "--interactive", action === "copy" ? "copy" : "move", ...sources, "file://" + dest + "/"], qsTr("File operation failed"), null);
    }

    function copyKeys(keys: var, cut: bool): void {
        copyUrls(entriesFor(keys).map(e => e.url), cut);
    }

    function copyUrls(urls: var, cut: bool): void {
        if (urls.length === 0)
            return;
        cutUris = cut ? urls : [];
        Quickshell.execDetached(["wl-copy", "--type", "text/uri-list", urls.join("\r\n") + "\r\n"]);
    }

    function paste(cell: var): void {
        pasteProc.cell = cell;
        pasteProc.running = true;
    }

    // ---- Drag and drop ----------------------------------------------------

    function prepareDragImage(key: string): void {
        dragImageReady = false;
        dragImageKey = key;
        // Large items are grabbed as they look; icons go through dragPreview
        // so several files get a count badge.
        let source = tiles[key];
        if (!isBigKey(key)) {
            dragPreview.key = key;
            dragPreview.count = Math.max(1, entriesFor(selectedKeys()).length);
            source = dragPreview;
        }
        if (!source)
            return;
        source.grabToImage(result => {
            if (dragImageKey !== key)
                return;
            dragSource.Drag.imageSource = result.url;
            dragImageReady = true;
        });
    }

    function beginDrag(key: string): void {
        if (renameActive)
            return;
        const keys = isSelected(key) ? selectedKeys() : [key];
        startDrag(keys, key, openGroupId, isBigKey(key) ? pressPoint : Qt.point(dragPreview.width / 2, Tokens.padding.small + iconSize / 2));
    }

    // Drags one app straight out of a large folder, without opening it.
    function beginMemberDrag(groupId: string, name: string, item: Item, x: real, y: real): void {
        if (renameActive)
            return;
        const key = DesktopLayout.fileKey(name);
        setSelection([]);
        dragImageReady = false;
        dragImageKey = key;
        item.grabToImage(result => {
            if (dragImageKey !== key)
                return;
            dragSource.Drag.imageSource = result.url;
            dragImageReady = true;
            startDrag([key], key, groupId, Qt.point(x, y));
        });
    }

    // Drags files that are not desktop items, such as those in a folder view.
    // Desktop drops treat them like files coming from another app.
    function beginFileDrag(urls: var, item: Item, x: real, y: real): void {
        if (renameActive || urls.length === 0)
            return;
        dragImageKey = "";
        item.grabToImage(result => {
            dragKeys = [];
            dragGroup = "";
            dragAnchor = "";
            dragSource.Drag.mimeData = { "text/uri-list": urls.join("\r\n") + "\r\n" };
            dragSource.Drag.imageSource = result.url;
            dragSource.Drag.hotSpot = Qt.point(x, y);
            dragSource.Drag.active = true;
        });
    }

    function startDrag(keys: var, anchor: string, fromGroup: string, hotSpot: point): void {
        const urls = entriesFor(keys).map(e => e.url);
        if (urls.length === 0 && !keys.some(isWidgetKey))
            return;
        dragKeys = keys;
        dragGroup = fromGroup;
        dragAnchor = anchor;
        dragHotSpot = hotSpot;
        // Widgets have nothing to hand to other apps; the private type keeps
        // the drag alive for moving them around the desktop.
        const mime = { "application/x-caelestia-desktop-items": keys.join("\n") };
        if (urls.length > 0)
            mime["text/uri-list"] = urls.join("\r\n") + "\r\n";
        dragSource.Drag.mimeData = mime;
        dragSource.Drag.hotSpot = hotSpot;
        if (!dragImageReady || dragImageKey !== anchor)
            dragSource.Drag.imageSource = "";
        dragSource.Drag.active = true;
    }

    function endDrag(): void {
        dragSource.Drag.active = false;
        dragKeys = [];
        dragGroup = "";
        dragAnchor = "";
        clearDropPreview();
    }

    function clearDropPreview(): void {
        previewPositions = null;
        dropCells = [];
        mergeKey = "";
    }

    function cellAt(x: real, y: real): var {
        return {
            col: Math.max(0, Math.min(cols - 1, Math.floor((x - gridItem.x) / cellWidth))),
            row: Math.max(0, Math.min(rows - 1, Math.floor((y - gridItem.y) / cellHeight)))
        };
    }

    function isInternal(drag: var): bool {
        return drag.source === dragSource && dragKeys.length > 0;
    }

    // Works out what dropping at (x, y) in root coordinates would do.
    function dropPlan(x: real, y: real, internal: bool): var {
        const gx = x - gridItem.x;
        const gy = y - gridItem.y;
        const cell = {
            col: Math.max(0, Math.min(cols - 1, Math.floor(gx / cellWidth))),
            row: Math.max(0, Math.min(rows - 1, Math.floor(gy / cellHeight)))
        };
        const moving = internal && dragGroup === "" ? dragKeys : [];
        const target = cellOccupant(cell.col, cell.row, moving);
        // Large items land where their top-left corner is closest to, not
        // where the pointer is, so they stay under the dragged image.
        const place = moving.length > 0 && isBigKey(dragAnchor) ? {
            col: Math.max(0, Math.min(cols - 1, Math.round((gx - dragHotSpot.x) / cellWidth))),
            row: Math.max(0, Math.min(rows - 1, Math.round((gy - dragHotSpot.y) / cellHeight)))
        } : cell;
        const plan = { cell, place, target, mode: "place", dest: "" };
        if (target === "")
            return plan;
        const draggingFiles = !internal || dragKeys.every(k => isGroupKey(k) ? dragGroup === "" : entryOf(k)?.fileIsDir === false);

        // Large items take drops anywhere on them.
        if (isBigKey(target)) {
            if (isGroupKey(target)) {
                if (internal && dragGroup === nameOf(target))
                    plan.mode = "none";
                else if (internal && draggingFiles)
                    plan.mode = "join";
            } else if (widgetOf(target)?.type === "folder" && (!internal || dragKeys.every(k => !isWidgetKey(k)))) {
                plan.mode = "folder";
                plan.dest = widgetOf(target).config.path ?? "";
            }
            return plan;
        }

        const tile = tiles[target];
        if (!tile || !tile.overIcon(gx - cell.col * cellWidth, gy - cell.row * cellHeight))
            return plan;
        const targetEntry = entryOf(target);
        if (targetEntry?.fileIsDir) {
            plan.mode = "folder";
            plan.dest = targetEntry.path;
        } else if (internal) {
            const targetIsDraggedGroup = isGroupKey(target) && dragGroup === nameOf(target);
            if (draggingFiles && !targetIsDraggedGroup && (isGroupKey(target) || targetEntry))
                plan.mode = isGroupKey(target) ? "join" : "merge";
        } else if (targetEntry?.isDesktopFile) {
            plan.mode = "openWith";
        }
        return plan;
    }

    function updateDropPreview(x: real, y: real, internal: bool): void {
        const plan = dropPlan(x, y, internal);
        mergeKey = plan.mode === "place" || plan.mode === "none" ? "" : plan.target;
        if (plan.mode !== "place") {
            previewPositions = null;
            dropCells = [];
            return;
        }
        if (!internal) {
            dropCells = [{ col: plan.cell.col, row: plan.cell.row, w: 1, h: 1 }];
            previewPositions = null;
            return;
        }
        const base = contextPositionsTopLevel();
        let moving = dragKeys;
        let anchor = dragAnchor;
        if (dragGroup !== "") {
            // Members coming out of a group start off where the pointer is.
            moving = dragKeys.filter(k => !isGroupKey(k));
            anchor = moving.indexOf(dragAnchor) !== -1 ? dragAnchor : moving[0];
            moving.forEach((k, i) => base[k] = { col: plan.cell.col, row: plan.cell.row + i });
        }
        const next = DesktopLayout.autoArrange ? Engine.planInsert(base, moving, plan.place, rows, spans) : Engine.planMove(base, moving, anchor, plan.place, cols, rows, spans);
        dropCells = moving.map(k => Object.assign({}, next[k], spanOf(k)));
        // The dragged items stay faded where they were; only the others move aside.
        const shown = Object.assign({}, DesktopLayout.positions, next);
        for (const k of moving)
            if (DesktopLayout.positions[k])
                shown[k] = DesktopLayout.positions[k];
        previewPositions = shown;
    }

    function commitDrop(drop: var): void {
        const internal = isInternal(drop);
        const plan = dropPlan(drop.x, drop.y, internal);
        clearDropPreview();

        if (!internal) {
            const urls = drop.urls.map(u => u.toString());
            drop.accept(Qt.CopyAction);
            if (urls.length === 0)
                return;
            if (plan.mode === "openWith") {
                entryOf(plan.target).launchWith(urls.map(u => u.startsWith("file://") ? decodeURIComponent(u.substring(7)) : u));
            } else if (plan.mode === "folder") {
                if (plan.dest !== "")
                    dropMenu.openAt(drop.x, drop.y, urls, plan.dest, null);
            } else {
                dropMenu.openAt(drop.x, drop.y, urls, desktopDir, plan.cell);
            }
            return;
        }

        drop.accept(Qt.MoveAction);
        const keys = dragKeys;
        const fromGroup = dragGroup;
        if (plan.mode === "none")
            return;
        if (plan.mode === "folder") {
            const copy = drop.proposedAction === Qt.CopyAction;
            if (plan.dest !== "")
                transfer(entriesFor(keys).map(e => e.url), plan.dest, copy ? "copy" : "move", null);
            return;
        }
        if (plan.mode === "merge" || plan.mode === "join") {
            const into = plan.mode === "join" ? nameOf(plan.target) : "";
            const merging = plan.mode === "merge" ? [plan.target].concat(keys) : keys;
            makeGroup(merging, DesktopLayout.positions[plan.target], into);
            return;
        }
        if (fromGroup !== "") {
            removeFromGroup(fromGroup, keys.filter(k => !isGroupKey(k)).map(nameOf), plan.cell);
            return;
        }
        const landed = DesktopLayout.autoArrange ? Engine.planInsert(contextPositionsTopLevel(), keys, plan.place, rows, spans) : Engine.planMove(contextPositionsTopLevel(), keys, dragAnchor || keys[0], plan.place, cols, rows, spans);
        DesktopLayout.setPositions(Object.assign({}, DesktopLayout.positions, landed));
        if (DesktopLayout.sortKey !== "")
            DesktopLayout.setSortKey("");
    }

    // ---- Keyboard ---------------------------------------------------------

    function focusOn(key: string, extend: bool): void {
        if (key === "")
            return;
        keyboardActive = true;
        focusKey = key;
        if (extend) {
            setSelection(rangeTo(key));
        } else {
            setSelection([key]);
            anchorKey = key;
        }
    }

    function handleKey(event: var): void {
        const ctrl = event.modifiers & Qt.ControlModifier;
        const shift = event.modifiers & Qt.ShiftModifier;
        const positions = contextPositions();
        const order = openGroupId !== "" ? groupPopup.order() : Engine.orderedKeys(positions, rows);
        const current = focusKey !== "" && focusKey in positions ? focusKey : "";
        const dirs = {
            [Qt.Key_Left]: "left",
            [Qt.Key_Right]: "right",
            [Qt.Key_Up]: "up",
            [Qt.Key_Down]: "down"
        };
        event.accepted = true;

        if (event.key in dirs) {
            if (current === "")
                focusOn(order[0] ?? "", false);
            else
                focusOn(Engine.navigate(positions, current, dirs[event.key], openGroupId !== "" ? null : spans) ?? current, shift);
        } else if (event.key === Qt.Key_Home) {
            focusOn(order[0] ?? "", shift);
        } else if (event.key === Qt.Key_End) {
            focusOn(order[order.length - 1] ?? "", shift);
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            openKeys(selectedKeys());
        } else if (event.key === Qt.Key_F2) {
            const keys = selectedKeys();
            if (keys.length === 1)
                startRename(keys[0]);
        } else if (event.key === Qt.Key_Delete) {
            // Widgets go too, except notes that hold text.
            const keys = selectedKeys();
            trashKeys(keys);
            removeWidgets(keys.filter(k => isWidgetKey(k) && !(widgetOf(k)?.type === "note" && (widgetOf(k)?.config.text ?? "").length > 0)));
        } else if (event.key === Qt.Key_Escape) {
            if (openGroupId !== "")
                closeGroup();
            else
                clearSelection();
        } else if (ctrl && event.key === Qt.Key_A) {
            setSelection(order);
        } else if (ctrl && event.key === Qt.Key_C) {
            copyKeys(selectedKeys(), false);
        } else if (ctrl && event.key === Qt.Key_X) {
            copyKeys(selectedKeys(), true);
        } else if (ctrl && event.key === Qt.Key_V) {
            paste(null);
        } else if (ctrl && event.key === Qt.Key_G) {
            if (shift)
                selectedKeys().filter(isGroupKey).forEach(k => ungroup(nameOf(k)));
            else
                groupSelection();
        } else if (ctrl && (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal)) {
            DesktopLayout.stepIconSize(1);
        } else if (ctrl && event.key === Qt.Key_Minus) {
            DesktopLayout.stepIconSize(-1);
        } else if (event.key === Qt.Key_Menu || (shift && event.key === Qt.Key_F10)) {
            const key = current || selectedKeys()[0];
            if (key && tiles[key]) {
                if (!isSelected(key))
                    focusOn(key, false);
                tileContextMenu(key, tiles[key].width / 2, tiles[key].height / 2);
            }
        } else if (!ctrl && event.text.length === 1 && event.text.trim().length === 1) {
            // Type to jump to the next icon starting with what was typed.
            typeAhead += event.text.toLowerCase();
            typeAheadTimer.restart();
            const start = Math.max(0, order.indexOf(current));
            const rotated = order.slice(start + (typeAhead.length === 1 ? 1 : 0)).concat(order.slice(0, start + (typeAhead.length === 1 ? 1 : 0)));
            const hit = rotated.find(k => labelOf(k).toLowerCase().startsWith(typeAhead));
            if (hit)
                focusOn(hit, false);
        } else {
            event.accepted = false;
        }
    }

    anchors.fill: parent
    visible: GlobalConfig.forScreen(screenData.name).background.enabled && GlobalConfig.forScreen(screenData.name).background.wallpaperEnabled && GlobalConfig.forScreen(screenData.name).background.desktopIconsEnabled
    focus: true
    Keys.onPressed: event => handleKey(event)

    onColsChanged: refitTimer.restart()
    onRowsChanged: refitTimer.restart()
    onFolderReadyChanged: Qt.callLater(syncEntries)
    onGridReadyChanged: Qt.callLater(syncEntries)

    Connections {
        function onLoadedChanged(): void {
            Qt.callLater(root.syncEntries);
        }

        function onGroupsChanged(): void {
            Qt.callLater(root.syncEntries);
        }

        function onWidgetsChanged(): void {
            Qt.callLater(root.syncEntries);
        }

        function onAddWidgetRequested(screenName: string, x: real, y: real): void {
            if (screenName === root.screenData.name)
                widgetGallery.openAt(x, y, root.cellAt(x, y));
        }

        function onAutoArrangeChanged(): void {
            if (DesktopLayout.autoArrange)
                root.refit();
        }

        function onPasteRequested(screenName: string, x: real, y: real): void {
            if (screenName !== root.screenData.name)
                return;
            root.paste(root.cellAt(x, y));
        }

        function onViewOptionsRequested(screenName: string, x: real, y: real): void {
            if (screenName === root.screenData.name)
                viewOptions.openAt(x, y);
        }

        target: DesktopLayout
    }

    Timer {
        id: refitTimer

        interval: 300
        onTriggered: root.refit()
    }

    Timer {
        id: typeAheadTimer

        interval: 900
        onTriggered: root.typeAhead = ""
    }

    Instantiator {
        model: FolderListModel {
            id: folderModel

            folder: "file://" + root.desktopDir
            showDirsFirst: true
            nameFilters: ["*"]
        }
        delegate: FileEntry {}
        onObjectAdded: (index, object) => root.registerFile(object)
        onObjectRemoved: (index, object) => root.unregisterFile(object)
    }

    ListModel {
        id: entriesModel
    }

    ListModel {
        id: bigModel
    }

    Process {
        id: fileOpProc

        property var current: null

        stderr: StdioCollector {
            id: fileOpErr
        }
        onExited: exitCode => {
            const op = current;
            if (exitCode !== 0 && op)
                Toaster.toast(op.failTitle, fileOpErr.text.trim().length > 0 ? fileOpErr.text.trim() : qsTr("%1 could not complete the request").arg(op.command[0]), "error");
            if (op?.done)
                op.done();
            current = null;
            root.nextFileOp();
        }
    }

    Process {
        id: pasteProc

        property var cell: null

        command: ["sh", "-c", `types=$(wl-paste --list-types 2>/dev/null) || exit 3
printf '%s\\n' "$types" | grep -qx 'text/uri-list' || exit 3
cut=0
if printf '%s\\n' "$types" | grep -qx 'application/x-kde-cutselection' && [ "$(wl-paste --type application/x-kde-cutselection)" = 1 ]; then cut=1; fi
echo "CUT=$cut"
wl-paste --no-newline --type text/uri-list`]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split(/\r?\n/).map(l => l.trim()).filter(l => l.length > 0 && !l.startsWith("#"));
                if (lines.length === 0 || !lines[0].startsWith("CUT="))
                    return;
                const urls = lines.slice(1);
                const cut = lines[0] === "CUT=1" || (root.cutUris.length > 0 && urls.length === root.cutUris.length && urls.every(u => root.cutUris.indexOf(u) !== -1));
                root.transfer(urls, root.desktopDir, cut ? "move" : "copy", pasteProc.cell);
                if (cut)
                    root.cutUris = [];
            }
        }
    }

    // Empty desktop: click to clear the selection, drag to select a range.
    Item {
        id: bandArea

        property point origin
        property var base: ({})

        anchors.fill: parent

        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: {
                root.grabKeyboard();
                root.keyboardActive = false;
                if (!(point.modifiers & Qt.ControlModifier))
                    root.clearSelection();
            }
        }

        DragHandler {
            id: bandDrag

            target: null
            acceptedButtons: Qt.LeftButton
            enabled: root.openGroupId === ""
            onActiveChanged: {
                if (active) {
                    root.grabKeyboard();
                    if (root.renameActive)
                        root.renamingDelegate.commitRename();
                    bandArea.origin = centroid.pressPosition;
                    bandArea.base = (centroid.modifiers & Qt.ControlModifier) ? Object.assign({}, root.selection) : {};
                    root.selection = Object.assign({}, bandArea.base);
                }
            }
            onCentroidChanged: {
                if (!active)
                    return;
                const r = band.rect();
                const hit = Engine.keysInRect(root.contextPositionsTopLevel(), Qt.rect(r.x - gridItem.x, r.y - gridItem.y, r.width, r.height), root.cellWidth, root.cellHeight, Tokens.padding.small, root.spans);
                const next = Object.assign({}, bandArea.base);
                for (const k of hit)
                    next[k] = true;
                root.selection = next;
            }
        }

        WheelHandler {
            property real accumulated: 0

            acceptedModifiers: Qt.ControlModifier
            onWheel: event => {
                accumulated += event.angleDelta.y;
                if (Math.abs(accumulated) >= 120) {
                    DesktopLayout.stepIconSize(accumulated > 0 ? 1 : -1);
                    accumulated = 0;
                }
            }
        }

        StyledRect {
            id: band

            readonly property rect current: bandDrag.active ? rect() : Qt.rect(0, 0, 0, 0)

            function rect(): rect {
                const p = bandDrag.centroid.position;
                return Qt.rect(Math.min(p.x, bandArea.origin.x), Math.min(p.y, bandArea.origin.y), Math.abs(p.x - bandArea.origin.x), Math.abs(p.y - bandArea.origin.y));
            }

            visible: bandDrag.active
            x: current.x
            y: current.y
            width: current.width
            height: current.height
            radius: Tokens.rounding.small
            color: Qt.alpha(Colours.palette.m3primary, 0.18)
            border.width: 1
            border.color: Qt.alpha(Colours.palette.m3primary, 0.7)
            z: 50
        }
    }

    DropArea {
        anchors.fill: parent
        onEntered: drag => {
            if (!drag.hasUrls && !root.isInternal(drag)) {
                drag.accepted = false;
                return;
            }
            drag.accept(root.isInternal(drag) ? Qt.MoveAction : Qt.CopyAction);
            root.updateDropPreview(drag.x, drag.y, root.isInternal(drag));
        }
        onPositionChanged: drag => root.updateDropPreview(drag.x, drag.y, root.isInternal(drag))
        onExited: root.clearDropPreview()
        onDropped: drop => root.commitDrop(drop)
    }

    Item {
        id: gridItem

        readonly property int barZone: Visibilities.bars.get(root.screenData.name)?.visualThickness ?? (Tokens.sizes.bar.innerWidth + Math.max(Tokens.padding.small, Config.border.thickness))
        readonly property int baseMargin: Tokens.padding.large * 2
        readonly property int marginLeft: Config.bar.position === "left" ? baseMargin + barZone : baseMargin
        readonly property int marginRight: Config.bar.position === "right" ? baseMargin + barZone : baseMargin
        readonly property int marginTop: Config.bar.position === "top" ? baseMargin + barZone : baseMargin
        readonly property int marginBottom: Config.bar.position === "bottom" ? baseMargin + barZone : baseMargin
        // Space the cells may use. Only whole cells fit, so the grid is centred in it
        // and the leftover is split between both sides instead of all going right and down.
        readonly property real areaWidth: root.width - marginLeft - marginRight
        readonly property real areaHeight: root.height - marginTop - marginBottom

        x: marginLeft + Math.floor((areaWidth - width) / 2)
        y: marginTop + Math.floor((areaHeight - height) / 2)
        width: root.cols * root.cellWidth
        height: root.rows * root.cellHeight

        // Where the dragged items would land.
        Repeater {
            model: root.dropCells

            StyledRect {
                required property var modelData

                x: modelData.col * root.cellWidth + Tokens.padding.small / 2
                y: modelData.row * root.cellHeight + Tokens.padding.small / 2
                width: (modelData.w ?? 1) * root.cellWidth - Tokens.padding.small
                height: (modelData.h ?? 1) * root.cellHeight - Tokens.padding.small
                radius: Tokens.rounding.medium
                color: Qt.alpha(Colours.palette.m3primary, 0.12)
                border.width: 2
                border.color: Qt.alpha(Colours.palette.m3primary, 0.6)
            }
        }

        Repeater {
            model: bigModel

            BigItem {
                id: big

                readonly property var pos: root.displayPositions[key] ?? DesktopLayout.positions[key] ?? null

                controller: root
                visible: pos !== null
                width: span.w * root.cellWidth
                height: span.h * root.cellHeight
                x: (pos?.col ?? 0) * root.cellWidth
                y: (pos?.row ?? 0) * root.cellHeight
                z: resizing ? 3 : 0
                selected: root.selection[key] === true && root.openGroupId === ""
                focusVisible: root.keyboardActive && root.focusKey === key && root.openGroupId === ""
                dimmed: root.dragGroup === "" && root.dragKeys.indexOf(key) !== -1
                mergeTarget: root.mergeKey === key

                Component.onCompleted: {
                    const next = Object.assign({}, root.tiles);
                    next[key] = big;
                    root.tiles = next;
                }
                Component.onDestruction: {
                    if (root.tiles[key] === big) {
                        const next = Object.assign({}, root.tiles);
                        delete next[key];
                        root.tiles = next;
                    }
                    root.finishRename(big);
                }

                onPressed: mouse => root.tilePressed(key, mouse)
                onClicked: mouse => root.tileClicked(key, mouse)
                onDoubleClicked: mouse => root.tileDoubleClicked(key, mouse)
                onContextMenuRequested: (x, y) => root.tileContextMenu(key, x, y)
                onDragRequested: root.beginDrag(key)

                Behavior on x {
                    Anim {}
                }

                Behavior on y {
                    Anim {}
                }

                Behavior on width {
                    Anim {}
                }

                Behavior on height {
                    Anim {}
                }
            }
        }

        Repeater {
            model: entriesModel

            IconTile {
                id: tile

                required property string key
                readonly property var pos: root.displayPositions[key] ?? DesktopLayout.positions[key] ?? null
                readonly property bool cut: !isGroup && root.cutUris.indexOf(entry?.url) !== -1

                isGroup: root.isGroupKey(key)
                entry: root.entryOf(key)
                groupName: root.groupOf(key)?.name ?? ""
                groupMembers: isGroup ? root.groupEntries(root.nameOf(key)) : []
                visible: pos !== null
                width: root.cellWidth
                height: root.cellHeight
                x: (pos?.col ?? 0) * root.cellWidth
                y: (pos?.row ?? 0) * root.cellHeight
                z: selected ? 2 : 1
                iconSize: root.iconSize
                materialYou: root.materialYou
                vibrant: root.vibrant
                pointingCursor: DesktopLayout.singleClick
                selected: root.selection[key] === true && root.openGroupId === ""
                focusVisible: root.keyboardActive && root.focusKey === key && root.openGroupId === ""
                dimmed: cut || (root.dragGroup === "" && root.dragKeys.indexOf(key) !== -1)
                mergeTarget: root.mergeKey === key

                Component.onCompleted: {
                    const next = Object.assign({}, root.tiles);
                    next[key] = tile;
                    root.tiles = next;
                }
                Component.onDestruction: {
                    if (root.tiles[key] === tile) {
                        const next = Object.assign({}, root.tiles);
                        delete next[key];
                        root.tiles = next;
                    }
                    root.finishRename(tile);
                }

                onPressed: mouse => root.tilePressed(key, mouse)
                onClicked: mouse => root.tileClicked(key, mouse)
                onDoubleClicked: mouse => root.tileDoubleClicked(key, mouse)
                onContextMenuRequested: (x, y) => root.tileContextMenu(key, x, y)
                onDragRequested: root.beginDrag(key)
                onRenameCommitted: text => {
                    root.finishRename(tile);
                    root.applyRename(key, text);
                }
                onRenameCancelled: root.finishRename(tile)

                Behavior on x {
                    Anim {}
                }

                Behavior on y {
                    Anim {}
                }
            }
        }
    }

    WidgetGallery {
        id: widgetGallery

        controller: root
        z: 200
    }

    GroupPopup {
        id: groupPopup

        controller: root
        z: 100
    }

    // Carries the system drag; the image is grabbed from dragPreview.
    Item {
        id: dragSource

        width: 1
        height: 1
        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.MoveAction | Qt.CopyAction | Qt.LinkAction
        Drag.proposedAction: Qt.MoveAction
        Drag.onDragFinished: root.endDrag()
    }

    DragPreview {
        id: dragPreview

        controller: root
        x: -width * 4
    }

    DesktopIconContextMenu {
        id: iconMenu

        controller: root
    }

    DropMenu {
        id: dropMenu

        controller: root
    }

    ViewOptions {
        id: viewOptions

        controller: root
        z: 200
    }
}
