#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SEARCHER="$REPO_ROOT/shell/services/WallhavenSearcher.qml"
NODE="$(command -v node || true)"

require_node() {
    [[ -n "$NODE" ]] && return 0
    skip_test "node is not installed"
    return 1
}

# Runs one of the singleton's guards against an answer a hostile API could give. The
# QML is not loaded: the function is lifted out of the shipped source and given the
# `root` it reads, so what is exercised is the code that ships rather than a copy.
run_guard() {
    local function_name="$1" argument="$2"

    "$NODE" -e '
        const fs = require("fs");
        const source = fs.readFileSync(process.argv[1], "utf8");

        function block(name) {
            const start = source.indexOf("function " + name + "(");
            if (start < 0)
                throw new Error("no such function: " + name);
            let depth = 0;
            let i = source.indexOf("{", start);
            for (; i < source.length; i++) {
                if (source[i] === "{")
                    depth++;
                else if (source[i] === "}" && --depth === 0) {
                    i++;
                    break;
                }
            }
            return source.slice(start, i);
        }

        const root = {wallpaperExts: ["jpg", "png", "webp", "gif", "bmp", "avif"]};
        const asExpression = name => "(" + block(name).replace(/^function\s+\w+/, "function") + ")";
        const extension = eval(asExpression("wallpaperExtension"));
        const validId = eval(asExpression("isValidWallpaperId"));

        const chosen = {wallpaperExtension: extension, isValidWallpaperId: validId}[process.argv[2]];
        process.stdout.write(String(chosen(process.argv[3])));
    ' "$SEARCHER" "$function_name" "$argument"
}

test_a_wallpapers_id_has_to_be_a_plain_name() {
    require_node || return 0
    local id
    for id in "abc123" "AbC_09-x" "6to4"; do
        assert_eq "true" "$(run_guard isValidWallpaperId "$id")" "'$id' is a name the API legitimately sends"
    done
}

test_an_id_that_would_leave_the_wallpaper_directory_is_refused() {
    require_node || return 0
    local id
    for id in "../../.config/quickshell/caelestia/shell" "a/b" "a.b" "" "back\\slash"; do
        assert_eq "false" "$(run_guard isValidWallpaperId "$id")" "'$id' must not become part of a path"
    done
}

test_only_wallpaper_formats_survive_the_extension_check() {
    require_node || return 0
    assert_eq "jpg" "$(run_guard wallpaperExtension 'https://w.wallhaven.cc/full/ab/wallhaven-abc.jpeg')" "jpeg is the same format as jpg"
    assert_eq "png" "$(run_guard wallpaperExtension 'https://w.wallhaven.cc/full/ab/wallhaven-abc.png')" "png is a wallpaper"
    assert_eq "webp" "$(run_guard wallpaperExtension 'https://w.wallhaven.cc/full/ab/wallhaven-abc.webp')" "webp is a wallpaper"
    assert_eq "jpg" "$(run_guard wallpaperExtension 'https://w.wallhaven.cc/full/ab/wallhaven-abc.jpg?token=1')" "a query string does not hide the extension"
}

test_an_extension_that_is_not_a_wallpaper_falls_back_to_jpg() {
    require_node || return 0
    local ext
    for ext in qml json ttf sh js py; do
        assert_eq "jpg" "$(run_guard wallpaperExtension "https://w.wallhaven.cc/full/ab/wallhaven-abc.${ext}")" "'$ext' must not name the file that is written"
    done
    assert_eq "jpg" "$(run_guard wallpaperExtension 'https://w.wallhaven.cc/full/ab/wallhaven-abc')" "a path with no extension still writes a picture"
}

test_the_fetch_refuses_a_url_that_is_not_https() {
    assert_file_contains "$SEARCHER" 'if (!/^https:\/\//i.test(fullPath))' \
        "a data: or file: URL is a read of anything the script can reach"
    assert_file_contains "$SEARCHER" 'urllib.parse.urlsplit(url).scheme != "https"' \
        "and the fetch says so again where it happens"
}

test_the_destination_is_built_from_checked_parts() {
    assert_file_contains "$SEARCHER" 'const tmpPath = `${Paths.cache}/wallhaven-${id}.tmp`' \
        "the cache name comes from the checked id"
    assert_file_contains "$SEARCHER" 'const dstPath = `${Paths.wallsdir}/wallhaven-${id}.${ext}`' \
        "and so does the wallpaper name"
}

run_tests
