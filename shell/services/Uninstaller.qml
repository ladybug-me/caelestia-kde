pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.utils

Singleton {
    id: root

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string envCheckout: Quickshell.env("CAELESTIA_DIR") || ""

    readonly property string shellConfigDir: {
        const config = Quickshell.env("CAELESTIA_SHELL_CONFIG");
        if (config)
            return config.slice(0, config.lastIndexOf("/"));
        return root.home + "/.config/quickshell/caelestia";
    }

    readonly property var packageManagers: [
        { tool: "pacman", command: "sudo pacman -Rns caelestia-kde" },
        { tool: "dnf", command: "sudo dnf remove caelestia-kde" },
        { tool: "apt-get", command: "sudo apt-get remove caelestia-kde" }
    ]

    readonly property string state: {
        if (!root.probed)
            return "probing";
        if (root.scriptPath !== "")
            return "script";
        if (root.manualCommand !== "")
            return "package";
        return "unknown";
    }

    readonly property bool scriptFound: root.state === "script"

    property bool probed: false
    property string scriptPath: ""
    property string manualCommand: ""

    function launch(): void {
        if (!root.scriptFound)
            return;

        Launch.launchInTerminal(["bash", root.scriptPath], "");
    }

    Process {
        id: probe

        running: true
        command: ["sh", "-c", `
home="$1"
caelestia_dir="$2"
config_dir="$3"
shift 3

# Whether $1 is a clone of this project. Both the configured address and the address git
# would actually fetch from are read, because url.<base>.insteadOf rewrites the first into
# the second and that is how a local mirror is set up.
names_this_project() {
    command -v git >/dev/null 2>&1 || return 1

    for origin in "$(git -C "$1" remote get-url origin 2>/dev/null)" \
        "$(git -C "$1" config --get remote.origin.url 2>/dev/null)"; do
        [ -n "$origin" ] || continue
        # A trailing slash and a .git suffix name the same repository. Trimmed with sed
        # rather than a shell parameter expansion, which a QML template literal would read
        # as JavaScript.
        origin="$(printf '%s' "$origin" | sed -e 's:/$::' -e 's:\.git$::')"
        case "$origin" in
            https://github.com/ladybug-me/caelestia-kde | \
                https://github.com/caelestia-kde/caelestia | \
                git@github.com:ladybug-me/caelestia-kde | \
                git@github.com:caelestia-kde/caelestia | \
                ssh://git@github.com/ladybug-me/caelestia-kde | \
                ssh://git@github.com/caelestia-kde/caelestia)
                return 0
                ;;
        esac
    done

    return 1
}

report_uninstaller() {
    [ -n "$1" ] || return 0

    # The recorded checkout is a path from a file this user can edit, and what happens
    # next is the user running that script as root. A link is refused rather than
    # followed, and a directory that is not this project is not what the record meant.
    [ -f "$1/uninstall.sh" ] && [ ! -L "$1/uninstall.sh" ] || return 0
    [ -f "$1/scripts/setup.sh" ] && [ ! -L "$1/scripts/setup.sh" ] || return 0

    # Only a recorded path is asked for its remote: two files of the right names in a
    # directory anyone can create cost nothing to arrange. The paths the user named
    # themselves are taken at their word, because a checkout unpacked from a tarball or
    # forked from this project is still theirs to uninstall from.
    if [ "$2" = recorded ] && ! names_this_project "$1"; then
        return 0
    fi

    printf 'SCRIPT %s\n' "$1/uninstall.sh"
    exit 0
}

recorded="$(cat "$config_dir/.checkout" 2>/dev/null || true)"

report_uninstaller "$caelestia_dir"
report_uninstaller "$home/caelestia-kde"
report_uninstaller "$recorded" recorded
report_uninstaller "$home/.config/caelestia-update/repo"
report_uninstaller "$home/.cache/caelestia-update-repo"

for manager in "$@"; do
    case "$manager" in
        pacman)
            pacman -Q caelestia-kde >/dev/null 2>&1 && printf 'PACKAGE pacman\n' && exit 0
            ;;
        dnf)
            dnf list installed caelestia-kde >/dev/null 2>&1 && printf 'PACKAGE dnf\n' && exit 0
            ;;
        apt-get)
            dpkg-query -W -f='\${Status}' caelestia-kde 2>/dev/null | grep -qx 'install ok installed' && printf 'PACKAGE apt-get\n' && exit 0
            ;;
    esac
done
echo UNKNOWN`, "--", root.home, root.envCheckout, root.shellConfigDir, ...root.packageManagers.map(m => m.tool)]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n");
                const script = lines.find(l => l.startsWith("SCRIPT "));
                const manager = lines.find(l => l.startsWith("PACKAGE "));
                if (script)
                    root.scriptPath = script.slice("SCRIPT ".length).trim();
                if (manager) {
                    const tool = manager.slice("PACKAGE ".length).trim();
                    const entry = root.packageManagers.find(m => m.tool === tool);
                    root.manualCommand = entry ? entry.command : "";
                }
                root.probed = true;
            }
        }
    }
}
