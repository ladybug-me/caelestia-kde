pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.services

Singleton {
    id: root

    enum Handoff {
        None,
        Pending,
        Running
    }

    property bool hasUpdate: false
    property string currentBranch: "main"
    property var commits: []
    property var availableBranches: ["main", "dev"]
    property var availableVersions: []
    property int pendingCount: 0
    property bool versionSummaryMode: false
    property string currentVersion: "unknown"
    property string previousVersion: "unknown"
    property string installedCommitHash: ""

    property string _localCommit: ""
    property bool loaded: false
    property bool checkingUpdates: false

    property double lastCheckMs: 0
    property double lastCheckSuccessMs: 0
    property string checkError: ""

    property int checkIntervalMs: 1800000

    property int devCommitLimit: 10
    property int devCommitOffset: 0
    property bool hasMoreCommits: false
    property bool loadingMoreCommits: false

    property int handoff: UpdateChecker.Handoff.None
    property string handoffVersion: ""
    property double _handoffStartedMs: 0
    property bool _reloadQueued: false

    readonly property int handoffProbeIntervalMs: 2000
    readonly property int handoffGraceMs: 10000
    readonly property bool checkingEnabled: GlobalConfig.general.checkUpdates
    readonly property bool checkFailed: root.checkError !== ""
    readonly property bool everChecked: root.lastCheckSuccessMs > 0

    function clampBranch(branch: string): string {
        return (branch === "dev" || branch === "main") ? branch : "main";
    }

    function updaterArgs(version): list<string> {
        const branch = root.clampBranch(root.currentBranch);
        const ref = version === undefined ? root.handoffVersion : version;
        return ref !== "" ? ["caelestia-update", branch, ref] : ["caelestia-update", branch];
    }

    // The updater runs in a terminal this shell only spawns, so the lock
    // caelestia-update holds is the only honest answer to "is it running".
    function markHandoff(version): void {
        root.handoffVersion = version === undefined ? "" : version;
        root.handoff = UpdateChecker.Handoff.Pending;
        root._handoffStartedMs = Date.now();
        root.probeHandoff();
    }

    function dismissHandoff(): void {
        root.handoff = UpdateChecker.Handoff.None;
        root.handoffVersion = "";
    }

    function probeHandoff(): void {
        if (handoffProbe.running)
            return;
        handoffProbe.running = true;
    }

    function checkNow(branch): void {
        root.startCheck(branch === undefined ? "" : branch, true);
    }

    function checkInBackground(): void {
        root.startCheck("", false);
    }

    function startCheck(branch, manual) {
        // Only an automatic check honours the periodic-check setting: a user who
        // presses Check must get an answer even with checking switched off,
        // otherwise the setting turns the whole page into a dead end.
        if (!manual && !root.checkingEnabled)
            return;
        // Only an explicit branch pick re-points the tracked update channel;
        // background checks must not fight the channel the updater recorded from
        // the tree it actually installed (issue #565).
        if (branch !== "")
            root.currentBranch = root.clampBranch(branch);
        else
            root.currentBranch = root.clampBranch(root.currentBranch);
        const persistBranch = branch !== "";
        checkingUpdates = true;
        checkError = "";
        devCommitOffset = 0;
        hasMoreCommits = false;
        checkClaudeCodeUpdate();

        let bashCmd = `
    CURRENT_BRANCH="$1"
    LOCAL_COMMIT="$(cat \"$HOME/.config/quickshell/caelestia/.current_commit\" 2>/dev/null || true)"

ALLOWED_BRANCHES="main dev"
LIVE_ALLOWED_BRANCHES=""
REACHABLE=0
for b in $ALLOWED_BRANCHES; do
    if git ls-remote --exit-code --heads https://github.com/ladybug-me/caelestia-kde.git "$b" >/dev/null 2>&1; then
        LIVE_ALLOWED_BRANCHES="$LIVE_ALLOWED_BRANCHES,$b"
        REACHABLE=1
    fi
done
LIVE_ALLOWED_BRANCHES="$(printf '%s' "$LIVE_ALLOWED_BRANCHES" | sed 's/^,//')"
if [ "$REACHABLE" -eq 0 ]; then
    echo "FAIL|GitHub is unreachable"
    exit 1
fi
echo "BRANCHES|$LIVE_ALLOWED_BRANCHES"

if ! echo ",$LIVE_ALLOWED_BRANCHES," | grep -q ",$CURRENT_BRANCH,"; then
    CURRENT_BRANCH="main"
fi

if ! echo ",main,dev," | grep -q ",$CURRENT_BRANCH,"; then
    CURRENT_BRANCH="main"
fi

STATE_HELPER=""
for candidate in \
    "\${CAELESTIA_LIB_DIR:-}/update-state.sh" \
    "$HOME/.local/lib/caelestia/update-state.sh" \
    "/usr/share/caelestia/scripts/lib/update-state.sh"; do
    if [ -r "$candidate" ]; then
        STATE_HELPER="$candidate"
        break
    fi
done
if [ -n "$STATE_HELPER" ]; then
    . "$STATE_HELPER"
fi
if [ "$2" = "1" ] && command -v update_state_set_branch >/dev/null 2>&1; then
    update_state_set_branch "$HOME/.config/quickshell/caelestia" "$CURRENT_BRANCH" || true
fi
REPO="$HOME/.cache/caelestia-update-repo"
if [ ! -d "$REPO" ]; then
    if ! git clone --bare --filter=blob:none https://github.com/ladybug-me/caelestia-kde.git "$REPO" >/dev/null 2>&1; then
        echo "FAIL|Couldn't clone the update repository"
        exit 1
    fi
else
    if ! git -C "$REPO" fetch --force origin "$CURRENT_BRANCH:$CURRENT_BRANCH" >/dev/null 2>&1; then
        echo "FAIL|Couldn't fetch the latest commits"
        exit 1
    fi
fi

normalize_version() {
    printf '%s' "\${1#v}"
}

resolve_version() {
    local ref="$1"
    local ver
    ver="$(git -C "$REPO" show "$ref:.github/version.env" 2>/dev/null | sed -nE 's/^VERSION[[:space:]]*=[[:space:]]*([A-Za-z0-9._-]+).*/\\1/p' | head -n 1)"
    if [ -n "$ver" ]; then
        printf '%s' "$ver"
        return
    fi
    ver="$(git -C "$REPO" describe --tags --abbrev=0 "$ref" 2>/dev/null || true)"
    if [ -z "$ver" ]; then
        ver="$(git -C "$REPO" show "$ref:shell/CMakeLists.txt" 2>/dev/null | sed -nE 's/.*VERSION +"?([0-9]+\\.[0-9]+\\.[0-9]+).*/\\1/p' | head -n 1)"
    fi
    if [ -z "$ver" ]; then
        ver="unknown"
    fi
    printf '%s' "$ver"
}

if [ "$CURRENT_BRANCH" = "main" ]; then
    git -C "$REPO" fetch --tags origin >/dev/null 2>&1 || true

    CURRENT_VERSION_FILE="$HOME/.config/quickshell/caelestia/.current_version"
    FROM_VERSION=""
    if [ -f "$CURRENT_VERSION_FILE" ]; then
        FROM_VERSION="$(sed -nE 's/^VERSION[[:space:]]*=[[:space:]]*([A-Za-z0-9._-]+).*/\\1/p' "$CURRENT_VERSION_FILE" | head -n 1)"
    fi
    if [ -z "$FROM_VERSION" ] && [ -n "$LOCAL_COMMIT" ]; then
        FROM_VERSION="$(resolve_version "$LOCAL_COMMIT")"
    fi
    if [ -z "$FROM_VERSION" ] && [ -f "$HOME/.config/quickshell/caelestia/.github/version.env" ]; then
        FROM_VERSION="$(sed -nE 's/^VERSION[[:space:]]*=[[:space:]]*([A-Za-z0-9._-]+).*/\\1/p' "$HOME/.config/quickshell/caelestia/.github/version.env" | head -n 1)"
    fi
    VER_HELPER_DIR="$CAELESTIA_LIB_DIR"
    if [ -z "$VER_HELPER_DIR" ]; then
        VER_HELPER_DIR=/usr/lib/caelestia
    fi
    if [ -z "$FROM_VERSION" ] && [ -x "$VER_HELPER_DIR/version" ]; then
        FROM_VERSION="$("$VER_HELPER_DIR/version" -s 2>/dev/null | awk '{ sub(/,/, "", $2); print $2 }')"
    fi
    [ -n "$FROM_VERSION" ] || FROM_VERSION="unknown"
    FROM_VERSION="$(normalize_version "$FROM_VERSION")"

    TAG_LINES="$(git -C "$REPO" for-each-ref --sort=-creatordate --format='%(refname:short)|%(creatordate:iso8601-strict)' 'refs/tags/v*' 2>/dev/null || true)"
    LATEST_VERSION="$(printf '%s\n' "$TAG_LINES" | sed -n '1s/|.*//p')"
    PREVIOUS_VERSION="$(printf '%s\n' "$TAG_LINES" | sed -n '2s/|.*//p')"
    [ -n "$LATEST_VERSION" ] || LATEST_VERSION="$FROM_VERSION"
    [ -n "$PREVIOUS_VERSION" ] || PREVIOUS_VERSION="$LATEST_VERSION"
    LATEST_VERSION="$(normalize_version "$LATEST_VERSION")"
    PREVIOUS_VERSION="$(normalize_version "$PREVIOUS_VERSION")"
    echo "META|$FROM_VERSION|$LATEST_VERSION|$PREVIOUS_VERSION"

    if [ "$FROM_VERSION" != "$LATEST_VERSION" ] && [ "$FROM_VERSION" != "unknown" ] && [ -n "$LATEST_VERSION" ]; then
        DISTANCE="$(printf '%s\n' "$TAG_LINES" | cut -d'|' -f1 | nl -v0 | awk -v local="$FROM_VERSION" '
            $2 == local { print $1; found=1; exit }
            END { if (!found) print -1 }
        ')"
        if ! [[ "$DISTANCE" =~ ^[0-9]+$ ]] || [ "$DISTANCE" -lt 1 ]; then
            DISTANCE=0
        fi
        if [ "$DISTANCE" -ge 1 ]; then
            echo "VERSION|$FROM_VERSION|$LATEST_VERSION|$DISTANCE"
        fi
    fi

    printf '%s\n' "$TAG_LINES" | while IFS='|' read -r tag created; do
        [ -n "$tag" ] || continue
        echo "RELEASE_TAG|$tag|$created"
    done

    PYTHON_BIN="$(command -v python3 || command -v python || true)"
    [ -n "$PYTHON_BIN" ] || exit 0

    FROM_VERSION="$FROM_VERSION" REPO="$REPO" "$PYTHON_BIN" - <<'PY'
import json
import os
import re
import subprocess
import sys
import urllib.request

def parse_whats_changed(text: str) -> str:
    txt = (text or "").replace("\\r", "")

    m = re.search(r"^#{2,3}\\s*What's Changed\\s*$", txt, flags=re.IGNORECASE | re.MULTILINE)
    if m:
        rest = txt[m.end():]
        next_header = re.search(r"^#{2,3}\\s+", rest, flags=re.MULTILINE)
        if next_header:
            txt = rest[:next_header.start()]
        else:
            txt = rest
    else:
        return ""

    txt = txt.strip()
    txt = re.sub(r"\\n{3,}", "\\n\\n", txt)
    txt = re.sub(r"[ \\t]+\\n", "\\n", txt)
    return txt[:1600]

def run_git(*args: str) -> str:
    repo = os.getenv("REPO") or ""
    cmd = ["git", "-C", repo, *args]
    return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL)

def fetch_releases() -> list:
    url = "https://api.github.com/repos/ladybug-me/caelestia-kde/releases?per_page=100"
    req = urllib.request.Request(url, headers={"User-Agent": "caelestia-update-checker"})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            return json.loads(resp.read().decode("utf-8") or "[]")
    except Exception:
        return []

try:
    raw_tags = run_git("for-each-ref", "--sort=-creatordate", "--format=%(refname:short)|%(creatordate:iso8601-strict)", "refs/tags/v*")
except Exception:
    raise SystemExit(0)

tags = []
for line in (raw_tags or "").splitlines():
    if not line.strip() or "|" not in line:
        continue
    tag, created = line.split("|", 1)
    tag = tag.strip()
    if tag:
        tags.append({"tag": tag, "created": created.strip()})

if not tags:
    raise SystemExit(0)

release_map = {}
for rel in fetch_releases():
    if rel.get("draft") or rel.get("prerelease"):
        continue
    tag = (rel.get("tag_name") or "").strip()
    if not tag:
        continue
    release_map[tag] = {
        "published": (rel.get("published_at") or "").strip(),
        "body": parse_whats_changed(rel.get("body") or "")
    }

from_version = (os.getenv("FROM_VERSION") or "unknown").strip()
latest = tags[0]["tag"]
previous = tags[1]["tag"] if len(tags) > 1 else latest

def norm(v):
    return (v or "").lstrip("vV")

from_version = norm(from_version)
latest = norm(latest)
previous = norm(previous)

print(f"META|{from_version}|{latest}|{previous}")

tag_names = [norm(t["tag"]) for t in tags]
if from_version != latest and from_version != "unknown" and from_version in tag_names:
    distance = tag_names.index(from_version)
    if distance > 0:
        print(f"VERSION|{from_version}|{latest}|{distance}")

for t in tags:
    tag = t["tag"]
    rel = release_map.get(tag, {})
    out = {
        "tag": tag,
        "published": rel.get("published") or t.get("created") or "",
        "body": rel.get("body") or ""
    }
    print("RELEASE_JSON|" + json.dumps(out, separators=(",", ":"), ensure_ascii=False))
PY
else
    DEV_LOG_LIMIT=10
    DEV_SKIP=0
    git -C "$REPO" log --format="COMMIT%x1f%H%x1f%h%x1f%s%x1f%an%x1f%cI%x1f%P" --skip="$DEV_SKIP" -n "$((DEV_LOG_LIMIT + 1))" "$CURRENT_BRANCH" 2>/dev/null | awk -v lim="$DEV_LOG_LIMIT" '
        NR <= lim { print }
        NR > lim { more = 1 }
        END { if (more) print "MORE|1"; else print "MORE|0" }
    '
    if [ -n "$LOCAL_COMMIT" ] && git -C "$REPO" merge-base --is-ancestor "$LOCAL_COMMIT" "$CURRENT_BRANCH" 2>/dev/null; then
        AHEAD_COUNT="$(git -C "$REPO" rev-list --count "$LOCAL_COMMIT..$CURRENT_BRANCH" 2>/dev/null || echo 0)"
    else
        AHEAD_COUNT=0
    fi
    [ -n "$AHEAD_COUNT" ] || AHEAD_COUNT=0
    echo "AHEAD|$AHEAD_COUNT"
    LOCAL_FULL="$(git -C "$REPO" rev-parse --verify --quiet "$LOCAL_COMMIT^{commit}" 2>/dev/null || true)"
    if [ -n "$LOCAL_FULL" ] && git -C "$REPO" merge-base --is-ancestor "$LOCAL_FULL" "$CURRENT_BRANCH" 2>/dev/null; then
        if ! git -C "$REPO" rev-list -n "$DEV_LOG_LIMIT" "$CURRENT_BRANCH" 2>/dev/null | grep -qx "$LOCAL_FULL"; then
            git -C "$REPO" log -1 --format="LOCAL_COMMIT%x1f%H%x1f%h%x1f%s%x1f%an%x1f%cI%x1f%P" "$LOCAL_FULL" 2>/dev/null || true
        fi
    fi
    echo "LOCAL|$LOCAL_COMMIT"
fi
`
    gitProcess.command = ["bash", "-c", bashCmd, "update-check", currentBranch, persistBranch ? "1" : "0"];
        gitProcess.running = true;
    }

    function reload() {
        loaded = false;
        if (localCommitProcess.running) {
            root._reloadQueued = true;
            return;
        }
        localCommitProcess.running = true;
    }

    function loadMoreCommits(): void {
        if (root.loadingMoreCommits || !root.hasMoreCommits || root.currentBranch !== "dev")
            return;
        root.loadingMoreCommits = true;
        const moreCmd = `
REPO="$HOME/.cache/caelestia-update-repo"
BRANCH="$1"
SKIP="$2"
LIMIT="$3"
[ -d "$REPO" ] || exit 0
git -C "$REPO" log --format="COMMIT%x1f%H%x1f%h%x1f%s%x1f%an%x1f%cI%x1f%P" --skip="$SKIP" -n "$((LIMIT + 1))" "$BRANCH" 2>/dev/null | awk -v lim="$LIMIT" '
    NR <= lim { print }
    NR > lim { more = 1 }
    END { if (more) print "MORE|1"; else print "MORE|0" }
'
`;
        moreCommitsProcess.command = ["bash", "-c", moreCmd, "load-more", root.currentBranch, String(root.devCommitOffset), String(root.devCommitLimit)];
        moreCommitsProcess.running = true;
    }

    Component.onCompleted: {
        localCommitProcess.running = true;
        // An update restarts this shell, so a fresh shell may already be sitting
        // behind a running updater. Ask the lock rather than assume none.
        root.probeHandoff();
    }

    Process {
        id: localCommitProcess

        command: ["bash", "-c", `
CONFIG="$HOME/.config/quickshell/caelestia"
STATE_HELPER=""
for candidate in \
    "\${CAELESTIA_LIB_DIR:-}/update-state.sh" \
    "$HOME/.local/lib/caelestia/update-state.sh" \
    "/usr/share/caelestia/scripts/lib/update-state.sh"; do
    if [ -r "$candidate" ]; then
        STATE_HELPER="$candidate"
        break
    fi
done
if [ -n "$STATE_HELPER" ]; then
    . "$STATE_HELPER"
fi
if command -v update_state_read_commit >/dev/null 2>&1; then
    printf '%s|%s\\n' "$(update_state_read_commit "$CONFIG")" "$(update_state_read_branch "$CONFIG")"
else
    printf '|main\\n'
fi
`]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split("|");
                root._localCommit = parts[0];
                if (parts.length > 1 && parts[1] !== "") {
                    root.currentBranch = parts[1];
                }
                root.loaded = true;
                root.checkInBackground();
            }
        }
        onExited: {
            if (root._reloadQueued) {
                root._reloadQueued = false;
                localCommitProcess.running = true;
            }
        }
    }

    Process {
        id: gitProcess

        command: []
        onExited: code => {
            root.checkingUpdates = false;
            root.lastCheckMs = Date.now();
            if (root.checkError === "" && code !== 0)
                root.checkError = qsTr("The update check failed");
            if (root.checkError === "")
                root.lastCheckSuccessMs = Date.now();
        }

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const lines = text.trim().split("\n");
                    const parsedCommits = [];
                    const parsedVersions = [];
                    let parsedPendingCount = 0;
                    let parsedHasUpdate = false;
                    let parsedVersionSummaryMode = root.currentBranch === "main";
                    let parsedLocalCommitFull = "";
                    let parsedCommitCount = 0;
                    let parsedHasMore = false;
                    root.availableBranches = ["main", "dev"];

                    for (let i = 0; i < lines.length; i++) {
                        const line = lines[i].trim();
                        if (line === "") continue;
                        if (line.startsWith("FAIL|")) {
                            root.checkError = line.substring(5).trim() || qsTr("The update check failed");
                            continue;
                        }
                        if (line.startsWith("BRANCHES|")) {
                            root.availableBranches = line.substring(9).split(",").filter(b => b === "main" || b === "dev");
                            if (root.availableBranches.length === 0)
                                root.availableBranches = ["main"];
                            if (!root.availableBranches.includes(root.currentBranch)) {
                                root.currentBranch = "main";
                            }
                            continue;
                        }
                        if (line.startsWith("VERSION|")) {
                            const parts = line.split("|");
                            const count = parseInt(parts[3] || "0");
                            parsedVersionSummaryMode = true;
                            parsedPendingCount = isNaN(count) ? 1 : Math.max(1, count);
                            parsedHasUpdate = parsedPendingCount > 0;
                            continue;
                        }
                        if (line.startsWith("META|")) {
                            const parts = line.split("|");
                            root.currentVersion = parts[1] || "unknown";
                            root.previousVersion = parts[3] || parts[2] || "unknown";
                            parsedVersionSummaryMode = true;
                            continue;
                        }
                        if (line.startsWith("RELEASE_JSON|")) {
                            const payload = line.slice("RELEASE_JSON|".length);
                            parsedVersionSummaryMode = true;
                            try {
                                const rel = JSON.parse(payload);
                                const tag = rel.tag || "";
                                const published = rel.published || "";
                                const body = rel.body || "";
                                if (tag === "")
                                    continue;

                                parsedCommits.push({
                                    hash: qsTr("Release"),
                                    subject: tag,
                                    author: qsTr("GitHub release"),
                                    date: published ? new Date(published).toLocaleString(Qt.locale(), Locale.ShortFormat) : "",
                                    details: body
                                });
                                parsedVersions.push(tag);
                            } catch (_ignored) {
                            }
                            continue;
                        }
                        if (line.startsWith("RELEASE_TAG|")) {
                            const parts = line.split("|");
                            const tag = parts[1] || "";
                            const created = parts[2] || "";
                            parsedVersionSummaryMode = true;
                            if (tag === "")
                                continue;

                            parsedCommits.push({
                                hash: qsTr("Release"),
                                subject: tag,
                                author: qsTr("Tag"),
                                date: created ? new Date(created).toLocaleString(Qt.locale(), Locale.ShortFormat) : "",
                                details: ""
                            });
                            parsedVersions.push(tag);
                            continue;
                        }
                        if (line.startsWith("COMMIT\u001f") || line.startsWith("LOCAL_COMMIT\u001f")) {
                            const parts = line.split("\u001f");
                            parsedVersionSummaryMode = false;
                            const parentsField = (parts[6] || "").trim();
                            const parentCount = parentsField === "" ? 0 : parentsField.split(/\s+/).length;
                            parsedCommits.push({
                                hash: parts[2] || "",
                                fullHash: parts[1] || "",
                                subject: parts[3] || "",
                                author: parts[4] || "",
                                date: new Date(parts[5]).toLocaleString(Qt.locale(), Locale.ShortFormat),
                                isMerge: parentCount > 1
                            });
                            if (line.startsWith("COMMIT\u001f"))
                                parsedCommitCount++;
                            continue;
                        }
                        if (line.startsWith("LOCAL|")) {
                            parsedLocalCommitFull = line.substring(6).trim();
                            continue;
                        }
                        if (line.startsWith("AHEAD|")) {
                            const count = parseInt(line.substring(6).trim());
                            parsedVersionSummaryMode = false;
                            parsedPendingCount = isNaN(count) ? 0 : count;
                            parsedHasUpdate = parsedPendingCount > 0;
                            continue;
                        }
                        if (line.startsWith("MORE|")) {
                            parsedHasMore = line.substring(5).trim() === "1";
                            continue;
                        }
                        const parts = line.split("|");
                        if (parts.length >= 4) {
                            parsedVersionSummaryMode = false;
                            parsedCommits.push({
                                hash: parts[0],
                                subject: parts[1],
                                author: parts[2],
                                date: new Date(parts[3]).toLocaleString(Qt.locale(), Locale.ShortFormat)
                            });
                        }
                    }

                    if (!parsedVersionSummaryMode && parsedLocalCommitFull === "") {
                        parsedPendingCount = 0;
                        parsedHasUpdate = false;
                    }
                    root.installedCommitHash = parsedVersionSummaryMode ? "" : parsedLocalCommitFull;

                    const dedupedCommits = [];
                    const seenKeys = new Set();
                    for (let i = 0; i < parsedCommits.length; i++) {
                        const key = parsedCommits[i].fullHash || `${parsedCommits[i].hash}|${parsedCommits[i].subject}`;
                        if (seenKeys.has(key))
                            continue;
                        seenKeys.add(key);
                        dedupedCommits.push(parsedCommits[i]);
                    }

                    root.commits = dedupedCommits;
                    if (parsedVersionSummaryMode) {
                        root.devCommitOffset = 0;
                        root.hasMoreCommits = false;
                    } else {
                        root.devCommitOffset = parsedCommitCount;
                        root.hasMoreCommits = parsedHasMore;
                    }
                    const uniqueVersions = [];
                    const seenVersions = new Set();
                    for (let i = 0; i < parsedVersions.length; i++) {
                        const v = parsedVersions[i];
                        if (seenVersions.has(v))
                            continue;
                        seenVersions.add(v);
                        uniqueVersions.push(v);
                    }
                    root.availableVersions = parsedVersionSummaryMode ? uniqueVersions : [];
                    if (parsedVersionSummaryMode) {
                        if (root.previousVersion === "unknown" && root.availableVersions.length > 1) {
                            root.previousVersion = root.availableVersions[1];
                        }
                    }
                    root.pendingCount = parsedPendingCount;
                    root.hasUpdate = parsedHasUpdate;
                    root.versionSummaryMode = parsedVersionSummaryMode;
                } catch(e) {
                    console.log("UpdateChecker git parse error:", e);
                }
            }
        }
    }

    Process {
        id: moreCommitsProcess

        command: []
        stdout: StdioCollector {
            onStreamFinished: {
                root.loadingMoreCommits = false;
                try {
                    const lines = text.trim().split("\n");
                    const newCommits = [];
                    let hasMore = false;
                    for (let i = 0; i < lines.length; i++) {
                        const line = lines[i].trim();
                        if (line === "") continue;
                        if (line.startsWith("COMMIT\u001f")) {
                            const parts = line.split("\u001f");
                            const parentsField = (parts[6] || "").trim();
                            const parentCount = parentsField === "" ? 0 : parentsField.split(/\s+/).length;
                            newCommits.push({
                                hash: parts[2] || "",
                                fullHash: parts[1] || "",
                                subject: parts[3] || "",
                                author: parts[4] || "",
                                date: new Date(parts[5]).toLocaleString(Qt.locale(), Locale.ShortFormat),
                                isMerge: parentCount > 1
                            });
                        } else if (line.startsWith("MORE|")) {
                            hasMore = line.substring(5).trim() === "1";
                        }
                    }

                    const seen = new Set();
                    for (let i = 0; i < root.commits.length; i++) {
                        const c = root.commits[i];
                        seen.add(c.fullHash || (c.hash + "|" + c.subject));
                    }
                    const unique = [];
                    for (let i = 0; i < newCommits.length; i++) {
                        const c = newCommits[i];
                        const key = c.fullHash || (c.hash + "|" + c.subject);
                        if (seen.has(key)) continue;
                        seen.add(key);
                        unique.push(c);
                    }
                    root.devCommitOffset += newCommits.length;
                    root.hasMoreCommits = hasMore;
                    root.commits = root.commits.concat(unique);
                } catch (e) {
                    console.log("UpdateChecker load-more parse error:", e);
                }
            }
        }
        onExited: _code => {
            root.loadingMoreCommits = false;
        }
    }

    property string claudeCodeVersion: ""

    property string claudeCodeLatestVersion: ""

    property bool claudeCodeChecking: false

    readonly property bool claudeCodeInstalled: claudeCodeVersion !== ""

    readonly property bool claudeCodeHasUpdate: claudeCodeInstalled
        && claudeCodeLatestVersion !== ""
        && claudeCodeLatestVersion !== claudeCodeVersion

    function checkClaudeCodeUpdate(): void {
        if (!GlobalConfig.ai.enableClaudeCode)
            return;
        claudeCodeChecking = true;
        claudeCodeProcess.running = false;
        claudeCodeProcess.running = true;
    }

    Process {
        id: claudeCodeProcess

        command: ["sh", "-c", `
BIN="$HOME/.local/bin/claude"
INSTALLED=""
[ -x "$BIN" ] && INSTALLED="$("$BIN" --version 2>/dev/null | grep -oE '[0-9]+\\.[0-9]+\\.[0-9]+' | head -1)"
LATEST="$(curl -fsSL --max-time 10 https://downloads.claude.ai/claude-code-releases/latest 2>/dev/null | head -1)"
case "$LATEST" in [0-9]*) ;; *) LATEST="" ;; esac
echo "$INSTALLED|$LATEST"
`]

        stdout: StdioCollector {
            onStreamFinished: {
                const parts = (text || "").trim().split("|");
                root.claudeCodeVersion = (parts[0] || "").trim();
                root.claudeCodeLatestVersion = (parts[1] || "").trim();
                root.claudeCodeChecking = false;
            }
        }
        onExited: root.claudeCodeChecking = false
    }

    Process {
        id: handoffProbe

        command: ["bash", "-c", `
LOCK="\${XDG_RUNTIME_DIR:-\${TMPDIR:-/tmp}}/caelestia-$UID/update.lock"
[ -e "$LOCK" ] || exit 0
command -v flock >/dev/null 2>&1 || exit 0
flock -n "$LOCK" true 2>/dev/null && exit 0
exit 1
`]
        onExited: code => {
            if (code === 1) {
                root.handoff = UpdateChecker.Handoff.Running;
                return;
            }
            if (root.handoff === UpdateChecker.Handoff.None)
                return;
            // The terminal needs a moment to start the updater, so a lock that is
            // not held yet only means "finished" once that grace has passed.
            if (root.handoff === UpdateChecker.Handoff.Pending && Date.now() - root._handoffStartedMs <= root.handoffGraceMs)
                return;
            root.dismissHandoff();
            root.checkInBackground();
        }
    }

    Timer {
        interval: root.handoffProbeIntervalMs
        repeat: true
        running: root.handoff !== UpdateChecker.Handoff.None
        onTriggered: root.probeHandoff()
    }

    FileView {
        path: `${Quickshell.env("HOME")}/.config/quickshell/caelestia/.current_commit`
        watchChanges: true
        printErrors: false
        onFileChanged: root.reload()
    }

    Timer {
        id: autoCheckTimer

        interval: root.checkIntervalMs
        repeat: true
        running: GlobalConfig.general.checkUpdates && root.loaded
        onTriggered: {
            if (!root.checkingUpdates)
                root.checkInBackground();
        }
    }
}
