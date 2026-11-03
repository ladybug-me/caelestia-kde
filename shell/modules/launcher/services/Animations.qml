pragma Singleton

import ".."
import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia.Config
import qs.components.controls
import qs.services
import qs.utils

Searcher {
    id: root

    property string currentPath: "default"
    property string currentName: qsTr("Default (Material-3 Expressive)")
    property var presetList: []
    property list<MenuItem> menuItems: []

    signal loaded()

    function transformSearch(search: string): string {
        return search.slice(`${GlobalConfig.launcher.actionPrefix}animations `.length);
    }

    function refresh(): void {
        getAnimationsProc.running = true;
    }

    function applyPreset(path: string, name: string): void {
        const target = `${Paths.config}/shell-tokens.json`;
        if (path === "default") {
            currentPath = "default";
            currentName = qsTr("Default (Material-3 Expressive)");
            Quickshell.execDetached(["rm", "-f", target]);
            Toaster.toast(qsTr("Reset animations"), qsTr("Default shell animations restored"), "animation");
        } else {
            const allowedPrefix = `${Paths.config}/animations/`;
            if (!path.startsWith(allowedPrefix) || path.includes("..")) {
                console.warn("Animations: rejected unsafe preset path:", path);
                return;
            }
            currentPath = path;
            currentName = name;
            Quickshell.execDetached(["cp", "--", path, target]);
            Toaster.toast(qsTr("Applied animation"), name, "animation");
        }
        refresh();
    }

    list: anims.instances
    useFuzzy: true

    Component.onCompleted: {
        refresh();
    }

    Process {
        id: getAnimationsProc

        running: false
        command: [
            "python3",
            "-c",
            "import json, glob, os\n" +
            "anim_dir = os.path.expanduser('~/.config/caelestia/animations')\n" +
            "tokens_file = os.path.expanduser('~/.config/caelestia/shell-tokens.json')\n" +
            "current = 'default'\n" +
            "current_name = 'Default (Material-3 Expressive)'\n" +
            "if os.path.exists(tokens_file):\n" +
            "    try:\n" +
            "        with open(tokens_file) as f:\n" +
            "            cur_data = json.load(f)\n" +
            "        current_name = cur_data.get('name', 'Custom')\n" +
            "    except Exception:\n" +
            "        current_name = 'Custom'\n" +
            "items = []\n" +
            "for p in sorted(glob.glob(os.path.join(anim_dir, '*.json'))):\n" +
            "    try:\n" +
            "        with open(p) as f:\n" +
            "            data = json.load(f)\n" +
            "        p_name = data.get('name', os.path.basename(p).replace('.json', '').replace('-', ' ').title())\n" +
            "        if p_name == current_name or p == current:\n" +
            "            current = p\n" +
            "        items.append({\n" +
            "            'name': p_name,\n" +
            "            'description': data.get('description', 'Custom animation preset'),\n" +
            "            'path': p\n" +
            "        })\n" +
            "    except Exception:\n" +
            "        pass\n" +
            "print(json.dumps({'current': current, 'currentName': current_name, 'items': items}))\n"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                let parsed = {};
                try {
                    parsed = JSON.parse(text.trim());
                } catch (e) {
                    parsed = { current: "default", currentName: "Default (Material-3 Expressive)", items: [] };
                }

                root.currentPath = parsed.current || "default";
                root.currentName = parsed.currentName || qsTr("Default (Material-3 Expressive)");

                const items = parsed.items || [];
                const allPresets = [
                    {
                        name: "Default (Material-3 Expressive)",
                        description: qsTr("Reset to built-in shell animation curves"),
                        path: "default"
                    }
                ];
                for (let item of items) {
                    allPresets.push(item);
                }

                root.presetList = allPresets;
                anims.model = allPresets;

                const newMenuItems = [];
                for (let p of allPresets) {
                    newMenuItems.push(menuItemComp.createObject(root, {
                        text: p.name,
                        icon: p.path === "default" ? "restart_alt" : "animation",
                        value: p.path
                    }));
                }
                root.menuItems = newMenuItems;
                root.loaded();
            }
        }
    }

    Component {
        id: menuItemComp

        MenuItem {}
    }

    Variants {
        id: anims

        QtObject {
            id: animItem

            required property var modelData

            readonly property string name: modelData.name
            readonly property string description: modelData.description || ""
            readonly property string path: modelData.path

            function onClicked(list: var): void {
                if (list && list.visibilities) {
                    list.visibilities.launcher = false;
                }
                root.applyPreset(path, name);
            }
        }
    }
}
