#!/usr/bin/env bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_DIR="$REPO_DIR/shell"
TS_DIR="$SHELL_DIR/translations"

SOURCES=(
    "$SHELL_DIR/shell.qml"
    "$SHELL_DIR/components"
    "$SHELL_DIR/modules"
    "$SHELL_DIR/services"
    "$SHELL_DIR/utils"
    "$REPO_DIR/shell/plugin/src"
    "$REPO_DIR/src/kde/shells/caelestia.desktop/contents/lockscreen"
    "$REPO_DIR/src/sddm/themes"
)

find_tool() {
    local name="$1"
    local candidates=(
        "/usr/lib/qt6/bin/$name"
        "/usr/lib64/qt6/bin/$name"
        "/usr/lib/x86_64-linux-gnu/qt6/bin/$name"
        "${name}-qt6"
        "${name}6"
        "$name"
        "/usr/lib/qt/bin/$name"
    )
    local candidate found="" version
    for candidate in "${candidates[@]}"; do
        command -v "$candidate" >/dev/null 2>&1 || continue
        [[ -z "$found" ]] && found="$candidate"
        version="$("$candidate" -version 2>&1 | head -n1 || true)"
        if [[ "$version" == *"version 6"* ]]; then
            echo "$candidate"
            return 0
        fi
    done
    if [[ -n "$found" ]]; then
        echo "$found"
        return 0
    fi
    return 1
}

if ! LUPDATE="$(find_tool lupdate)"; then
    echo "[FAIL]  lupdate not found. Install Qt's Linguist tools (Arch: qt6-tools)." >&2
    exit 1
fi

mkdir -p "$TS_DIR"

LANGS=("$@")
if [[ ${#LANGS[@]} -eq 0 ]]; then
    shopt -s nullglob
    for ts in "$TS_DIR"/caelestia_*.ts; do
        ts="${ts##*/caelestia_}"
        LANGS+=("${ts%.ts}")
    done
    shopt -u nullglob
fi

if [[ ${#LANGS[@]} -eq 0 ]]; then
    echo "[FAIL]  No catalogs in $TS_DIR and no languages given." >&2
    echo "        Try: tools/update-translations.sh en tr" >&2
    exit 1
fi

for lang in "${LANGS[@]}"; do
    echo "[INFO]  Updating caelestia_$lang.ts..."
    "$LUPDATE" "${SOURCES[@]}" \
        -recursive \
        -locations relative \
        -no-obsolete \
        -source-language en_US \
        -target-language "$lang" \
        -ts "$TS_DIR/caelestia_$lang.ts" |
        grep -E 'Found|Warning' || true
done

if LRELEASE="$(find_tool lrelease)"; then
    for lang in "${LANGS[@]}"; do
        [[ -f "$TS_DIR/caelestia_$lang.ts" ]] || continue
        echo "[INFO]  Compiling caelestia_$lang.qm..."
        "$LRELEASE" -silent "$TS_DIR/caelestia_$lang.ts" -qm "$TS_DIR/caelestia_$lang.qm"
    done
else
    echo "[WARN]  lrelease not found; the committed .qm catalogs are now behind their sources." >&2
fi

echo "[ OK ]  Catalogs updated. Edit them with Qt Linguist, then rerun this script to recompile."
