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

# The download script is a Python program held in the QML as one line per entry of an
# array, so a test can read the very lines that ship and run them.
extract_download_script() {
    require_node || return 1
    "$NODE" -e '
        const fs = require("fs");
        const source = fs.readFileSync(process.argv[1], "utf8");
        const match = /"-c",\s*(\[[\s\S]*?\])\.join\("\\n"\)/.exec(source);
        if (!match)
            process.exit(1);
        process.stdout.write(eval(match[1]).join("\n"));
    ' "$SEARCHER"
}

# Runs the shipped guard on one hop and prints what it did. Everything above the download
# itself is definitions, so evaluating that much exercises the rules without a network.
run_hop_guard() {
    local source="$1" hop="$2"
    python3 - "$source" "$hop" <<'PYEOF'
import sys

source, hop = sys.argv[1], sys.argv[2]
sys.argv = ["-c", "https://example.invalid/wallhaven.png", "/dev/null", "/dev/null"]
namespace = {}
exec(compile(source.split("os.makedirs(")[0], "<download guard>", "exec"), namespace)
try:
    namespace["check_hop"](hop)
except ValueError as exc:
    print("refused: " + str(exc))
else:
    print("accepted")
PYEOF
}

test_a_redirect_is_held_to_the_rule_the_first_url_was() {
    require_node || return 0
    local script hop
    script="$(extract_download_script)" || {
        fail "the download script could not be read out of the service"
        return 0
    }
    assert_contains "$script" "urllib.request.HTTPRedirectHandler" \
        "urllib follows redirects, so a handler is the only place to look at each hop"
    assert_contains "$script" "is_global" \
        "and an address that is not public is what a hop must not reach"

    for hop in \
        "http://127.0.0.1/wallhaven.png" \
        "http://169.254.169.254/latest/meta-data/" \
        "https://10.0.0.1/wallhaven.png" \
        "https://192.168.1.1/wallhaven.png" \
        "https://[::1]/wallhaven.png" \
        "https://0.0.0.0/wallhaven.png" \
        "https://224.0.0.1/wallhaven.png" \
        "file:///etc/passwd" \
        "ftp://w.wallhaven.cc/wallhaven.png"; do
        assert_contains "$(run_hop_guard "$script" "$hop")" "refused" \
            "'$hop' is a read of something only this machine can reach"
    done

    assert_contains "$(run_hop_guard "$script" "https://w.wallhaven.cc/full/ab/wallhaven-abc.png")" "accepted" \
        "a public https hop is what a download is supposed to follow"
}

test_a_name_that_resolves_to_a_private_address_is_not_connected_to() {
    require_node || return 0
    local script dir status
    script="$(extract_download_script)" || {
        fail "the download script could not be read out of the service"
        return 0
    }

    dir="$(new_tmpdir)"
    python3 -c "$script" "https://127.0.0.1:9/wallhaven.png" "$dir/download.tmp" "$dir/walls/wallhaven.png" \
        > "$dir/out" 2> "$dir/err"
    status=$?

    assert_status 1 "$status" "a loopback address is not a wallpaper host"
    assert_contains "$(cat "$dir/err")" "public address" \
        "the refusal has to say what was wrong with the address"
    assert_file_missing "$dir/download.tmp" "a download that never started leaves nothing behind"
    assert_not_contains "$(cat "$dir/out")" "PROGRESS 1" \
        "and the QML must not be told the download finished"
}

test_the_destination_is_built_from_checked_parts() {
    assert_file_contains "$SEARCHER" 'const tmpPath = `${Paths.cache}/wallhaven-${id}.tmp`' \
        "the cache name comes from the checked id"
    assert_file_contains "$SEARCHER" 'const dstPath = `${Paths.wallsdir}/wallhaven-${id}.${ext}`' \
        "and so does the wallpaper name"
}

run_tests
