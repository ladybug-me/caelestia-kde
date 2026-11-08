pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/// The helpers the shell asks polkit to run.
///
/// polkit runs whatever path it is given as root, so a helper this user could rewrite
/// would be a way to run their code as root behind a prompt for a feature they did ask
/// for. Only a copy root owns, and that nobody else can write, is ever elevated; where
/// there is none the settings row says so instead of falling back to one.
Singleton {
    id: root

    /// Where the installer puts the helpers: outside every tree this user can write.
    readonly property string systemDir: "/usr/lib/caelestia/scripts"

    /// Helper file name to the path it may be elevated from. A helper with no safe copy
    /// is absent, which is what a source install looks like before it has been reinstalled.
    property var paths: ({})

    // Every candidate, most trusted first: the installer's root-owned copy, then the one
    // a package ships next to the shell. The packaged path is root's on a package install
    // and this user's on a source install, which is what the ownership check settles.
    readonly property var candidates: [
        {
            "name": "quickshare_setup.sh",
            "path": root.systemDir + "/quickshare_setup.sh"
        },
        {
            "name": "quickshare_setup.sh",
            "path": Quickshell.shellPath("scripts/quickshare_setup.sh")
        },
        {
            "name": "ollama_setup.sh",
            "path": root.systemDir + "/ollama_setup.sh"
        },
        {
            "name": "ollama_setup.sh",
            "path": Quickshell.shellPath("scripts/ollama_setup.sh")
        }
    ]

    // A helper is usable when it is a regular file root owns and only root may write.
    // `stat` reports the link itself, so a symlink is refused rather than read through,
    // and a mode that is not a mode is not trusted. Written without a template literal:
    // the shell's own `${...}` would be read as JavaScript.
    //
    // The interpreter and `stat` are named by absolute path, and PATH is replaced before
    // either is reached. A source install puts this user's own bin directory first on
    // PATH, so a `stat` they could drop there would otherwise be the thing deciding
    // whether a helper is root's - which is the whole question. Nothing below needs PATH;
    // it is replaced so that anything added here later cannot quietly reach a user's copy.
    readonly property string ownershipCheck: [
        'PATH=/usr/sbin:/usr/bin:/sbin:/bin; export PATH',
        'for pair in "$@"; do',
        '    name="${pair%%|*}"',
        '    path="${pair#*|}"',
        '    [ -f "$path" ] && [ ! -L "$path" ] || continue',
        '    owner="$(/usr/bin/stat -c %u "$path" 2>/dev/null)" || continue',
        '    mode="$(/usr/bin/stat -c %a "$path" 2>/dev/null)" || continue',
        '    [[ "$owner" == 0 && "$mode" =~ ^[0-7]+$ ]] || continue',
        '    (( 8#$mode & 8#022 )) -eq 0 || continue',
        '    printf "%s=%s\\n" "$name" "$path"',
        'done'
    ].join("\n")

    function path(name: string): string {
        return root.paths[name] || "";
    }

    function has(name: string): bool {
        return root.path(name) !== "";
    }

    Component.onCompleted: resolveProc.running = true

    Process {
        id: resolveProc

        // /bin/bash by absolute path: the snippet is bash, and a `bash` this user could
        // shadow would be a `bash` deciding what is root's.
        command: ["/bin/bash", "-c", root.ownershipCheck, "_"].concat(root.candidates.map(candidate => candidate.name + "|" + candidate.path))

        stdout: SplitParser {
            onRead: line => {
                const split = line.indexOf("=");
                if (split < 1)
                    return;

                const name = line.slice(0, split);
                // The first acceptable candidate wins: the installer's copy comes first.
                if (root.paths[name])
                    return;

                const accepted = {};
                accepted[name] = line.slice(split + 1);
                root.paths = Object.assign({}, root.paths, accepted);
            }
        }
    }
}
