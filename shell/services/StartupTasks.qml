pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

Item {
    id: root

    readonly property string tasksDir: Quickshell.shellPath("services/startuptasks")
    readonly property string scriptsDir: Quickshell.shellPath("scripts")

    Component.onCompleted: {
        Quickshell.execDetached(["bash", "-c", `
            STATE_FILE="$HOME/.local/share/caelestia/state/startup_tasks.txt"
            mkdir -p "$(dirname "$STATE_FILE")"
            touch "$STATE_FILE"
            
            TASKS_DIR="$1"
            SCRIPTS_DIR="$2"
            export SCRIPTS_DIR
            MODIFIED=false
            
            TASKS=(
                "01-magic-lamp"
                "02-krohnkite-setup"
                "03-wallpaper-fill"
                "04-stale-font-families"
                "05-matugen"
                "06-kde-desktop-mode"
            )
            
            for script_name in "\${TASKS[@]}"; do
                script="$TASKS_DIR/$script_name.sh"
                if [[ -f "$script" ]]; then
                    if ! grep -q "^\${script_name}$" "$STATE_FILE"; then
                        bash "$script"
                        if [[ $? -eq 1 ]]; then
                            MODIFIED=true
                        fi
                        echo "$script_name" >> "$STATE_FILE"
                    fi
                fi
            done
            
            if [[ "$MODIFIED" == "true" ]]; then
                qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
            fi
        `, "caelestia-startuptasks", root.tasksDir, root.scriptsDir]);
    }
}
