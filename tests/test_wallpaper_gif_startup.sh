#!/usr/bin/env bash
# suite: isolated
# Exercise the real wallpaper image component with a window that gets its size later.
set -euo pipefail
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if ! command -v quickshell >/dev/null 2>&1; then
    echo 'SKIP: quickshell is not installed'
    exit 0
fi
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/runtime" "$tmp/config" "$tmp/cache" "$tmp/state" "$tmp/data"
chmod 700 "$tmp/runtime"
cp "$repo/shell/components/images/CachingAnimatedImage.qml" "$tmp/"
python3 - "$repo/shell/modules/background/Wallpaper.qml" "$tmp/shell.qml" <<'PY'
from pathlib import Path
import sys
source = Path(sys.argv[1]).read_text()
start = source.index('            CachingAnimatedImage {')
end = source.index('            CachingVideo {', start)
block = source[start:end].replace('Config.background.wallpaperFillMode', 'Image.PreserveAspectCrop')
block = block.replace('                onStatusChanged: {',
    '                onCurrentFrameChanged: { if (currentFrame > 0) root.frameSeen = true; }\n                onStatusChanged: {')
Path(sys.argv[2]).write_text('''import QtQuick
import Quickshell
Scope {
    id: root
    property var current
    property bool frameSeen: false
    FloatingWindow {
        visible: true
        implicitWidth: 640; implicitHeight: 360
        Item {
            id: img
            width: 0; height: 0
            property string imagePath: Quickshell.env("WALL_TEST")
            property bool isVideoImage: false
            property bool tiled: false
''' + block + '''
            Timer { interval: 400; running: true; onTriggered: { img.width = 640; img.height = 360; } }
            Timer { interval: 4500; running: true; onTriggered: {
                const gif = /\\.gif$/i.test(img.imagePath);
                const ok = wallpaperImage.status === Image.Ready && (!gif || root.frameSeen);
                console.log("WALLPAPER_TEST", ok ? "PASS" : "FAIL");
                Qt.exit(ok ? 0 : 1);
            } }
        }
    }
}
''')
PY
ulimit -c 0
for image in "$repo/shell/assets/bongocat.gif" "$repo/shell/assets/kurukuru_stand.png"; do
    WALL_TEST="$image" XDG_RUNTIME_DIR="$tmp/runtime" XDG_CONFIG_HOME="$tmp/config" \
    XDG_CACHE_HOME="$tmp/cache" XDG_STATE_HOME="$tmp/state" XDG_DATA_HOME="$tmp/data" \
    QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software QS_DISABLE_CRASH_HANDLER=1 \
    DBUS_SESSION_BUS_ADDRESS="unix:path=$tmp/no-session-bus" timeout 12 quickshell -p "$tmp" >"$tmp/log" 2>&1 || {
        cat "$tmp/log"; echo "FAIL: $image"; exit 1;
    }
    if ! grep -q 'WALLPAPER_TEST PASS' "$tmp/log"; then cat "$tmp/log"; exit 1; fi
    echo "PASS: $(basename "$image")"
done
