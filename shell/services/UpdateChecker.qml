pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config
import qs.services
import qs.utils

Singleton {
    id: root

    property bool hasUpdate: false
    property string currentBranch: "main"
    property var commits: []
    property var availableBranches: ["main", "dev"]
    property var availableVersions: []
    property int pendingCount: 0
    property bool versionSummaryMode: false
    property string currentVersion: "unknown"
    property string previousVersion: "unknown"
    property string targetVersion: ""
    property string installedCommitHash: ""

    // Owner of the repositories this checker consults. Forks set the
    // CAELESTIA_REPO_OWNER environment variable to their own GitHub user so
    // the shell's update badge tracks the fork instead of upstream.
    // The owner ends up interpolated into shell scripts below, so a hostile
    // or malformed CAELESTIA_REPO_OWNER falls back to the default instead of
    // riding into a command string. Owner names are [A-Za-z0-9-].
    readonly property string repoOwner: {
        const owner = Qt.getenv("CAELESTIA_REPO_OWNER") || "ladybug-me";
        return /^[A-Za-z0-9-]{1,64}$/.test(owner) ? owner : "ladybug-me";
    }

    property string _localCommit: ""
    property bool loaded: false
    property bool checkingUpdates: false

    // Periodic auto-check heartbeat (drives the tray indicator popout's
    // "last check X ago / next check in Y" readout, CachyOS-updater style).
    // A single-shot timer is restarted every time a check completes so the
    // next auto-check always lands one interval after the most recent one,
    // manual or otherwise.
    property double lastCheckMs: 0

    property int checkIntervalMs: 1800000 // 30 minutes

    // Dev-branch commit pagination: the update checker only fetches the
    // first page (devCommitLimit commits) and exposes a "load more" affordance
    // for the rest, so we never pull the whole dev history up front.
    property int devCommitLimit: 10
    property int devCommitOffset: 0
    property bool hasMoreCommits: false
    property bool loadingMoreCommits: false

    // ── Update process state ────────────────────────────────────────────
    // Lives on the singleton (rather than UpdatesPage) so it survives the
    // page being destroyed/recreated when the user navigates to a different
    // top-level Nexus page and back (see Pages.qml `loadPage`).
    property string updateLogs: ""
    property bool updateRunning: false
    property bool updateCancelled: false
    property real updateProgress: 0.0
    property string updateStatus: ""
    property bool logsExpanded: false
    property double lastUpdateOutputMs: 0
    property bool stallNoticeShown: false
    property string processLineBuffer: ""

    function clampBranch(branch: string): string {
        return (branch === "dev" || branch === "main") ? branch : "main";
    }

    function checkUpdates(branch) {
        if (branch === undefined) branch = "";
        if (!GlobalConfig.general.checkUpdates) return;
        if (branch !== "") currentBranch = clampBranch(branch);
        else currentBranch = clampBranch(currentBranch);
        checkingUpdates = true;
        devCommitOffset = 0;
        hasMoreCommits = false;
        checkClaudeCodeUpdate();
        
        let bashCmd = `
    CURRENT_BRANCH="$1"
    LOCAL_COMMIT="$(cat \"$HOME/.config/quickshell/caelestia/.current_commit\" 2>/dev/null || true)"
    REPO_OWNER="${root.repoOwner}"

ALLOWED_BRANCHES="main dev"
LIVE_ALLOWED_BRANCHES=""
for b in $ALLOWED_BRANCHES; do
    if git ls-remote --exit-code --heads https://github.com/$REPO_OWNER/caelestia-kde.git "$b" >/dev/null 2>&1; then
        LIVE_ALLOWED_BRANCHES="$LIVE_ALLOWED_BRANCHES,$b"
    fi
done
LIVE_ALLOWED_BRANCHES="$(printf '%s' "$LIVE_ALLOWED_BRANCHES" | sed 's/^,//')"
if [ -z "$LIVE_ALLOWED_BRANCHES" ]; then
    LIVE_ALLOWED_BRANCHES="main"
fi
echo "BRANCHES|$LIVE_ALLOWED_BRANCHES"

if ! echo ",$LIVE_ALLOWED_BRANCHES," | grep -q ",$CURRENT_BRANCH,"; then
    CURRENT_BRANCH="main"
fi

if ! echo ",main,dev," | grep -q ",$CURRENT_BRANCH,"; then
    CURRENT_BRANCH="main"
fi

mkdir -p "$HOME/.config/quickshell/caelestia"
echo "$CURRENT_BRANCH" > "$HOME/.config/quickshell/caelestia/.update_branch"
REPO="$HOME/.cache/caelestia-update-repo"
if [ ! -d "$REPO" ]; then
    git clone --bare --filter=blob:none https://github.com/$REPO_OWNER/caelestia-kde.git "$REPO" >/dev/null 2>&1
else
    git -C "$REPO" fetch --force origin "$CURRENT_BRANCH:$CURRENT_BRANCH" >/dev/null 2>&1
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
    # Fall through instead of elif-chaining: an existing but empty/unparseable
    # .current_version file (e.g. truncated by a failed git show) must not
    # block the commit- and version.env-based fallbacks below.
    if [ -z "$FROM_VERSION" ] && [ -n "$LOCAL_COMMIT" ]; then
        FROM_VERSION="$(resolve_version "$LOCAL_COMMIT")"
    fi
    if [ -z "$FROM_VERSION" ] && [ -f "$HOME/.config/quickshell/caelestia/.github/version.env" ]; then
        FROM_VERSION="$(sed -nE 's/^VERSION[[:space:]]*=[[:space:]]*([A-Za-z0-9._-]+).*/\\1/p' "$HOME/.config/quickshell/caelestia/.github/version.env" | head -n 1)"
    fi
    # The compiled version helper, which is what the caelestia command reports from as
    # well. On a packaged install it is the only one of these that answers: there is no
    # checkout for git to describe and no version.env beside the config, and without it the
    # update row stays empty because an unknown version is never offered as updatable.
    #
    # This comment and the script below avoid naming template-literal syntax directly.
    # Both of its forms are syntax to the QML template literal they live in:
    # dollar-brace interpolation is evaluated as QML before bash is handed the script, and
    # an unescaped backtick ends the literal, which stops the file parsing and takes every
    # singleton that imports this service down with it. Each has broken this file once,
    # the backtick in a comment that named a command in backticks, the interpolation in
    # the comment that replaced it.
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
        # Announce an update only when the installed version is a known
        # release strictly behind the newest tag. Unresolvable local commits
        # resolve to "unknown", and version.env can be bumped ahead of the
        # newest tag — neither may count as "update available", otherwise a
        # user already at (or ahead of) the latest main is offered a downgrade.
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

    FROM_VERSION="$FROM_VERSION" REPO="$REPO" REPO_OWNER="$REPO_OWNER" "$PYTHON_BIN" - <<'PY'
import json
import os
import re
import subprocess
import sys
import urllib.request

def parse_whats_changed(text: str) -> str:
    txt = (text or "").replace("\\r", "")

    # Keep only the "What's Changed" section when present.
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

    # Normalize spacing and keep it compact for list rows.
    txt = txt.strip()
    txt = re.sub(r"\\n{3,}", "\\n\\n", txt)
    txt = re.sub(r"[ \\t]+\\n", "\\n", txt)
    return txt[:1600]

def run_git(*args: str) -> str:
    repo = os.getenv("REPO") or ""
    cmd = ["git", "-C", repo, *args]
    return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL)

def fetch_releases() -> list:
    owner = os.getenv("REPO_OWNER") or "ladybug-me"
    url = "https://api.github.com/repos/" + owner + "/caelestia-kde/releases?per_page=100"
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

# Strip a leading "v" so "v2.3.1" and "2.3.1" compare equal.
def norm(v):
    return (v or "").lstrip("vV")

from_version = norm(from_version)
latest = norm(latest)
previous = norm(previous)

print(f"META|{from_version}|{latest}|{previous}")

# Mirror the bash logic above: only a known release strictly behind the
# newest tag is an available update. "unknown" or a version bumped ahead
# of the newest tag must not trigger the shell's update offer.
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
    # Dev branch: paginated commit history — emit only the first page (10
    # commits by default) plus a MORE flag so the UI can offer to load the
    # next page instead of pulling the whole dev history up front.
    DEV_LOG_LIMIT=10
    DEV_SKIP=0
    git -C "$REPO" log --format="COMMIT%x1f%H%x1f%h%x1f%s%x1f%an%x1f%cI%x1f%P" --skip="$DEV_SKIP" -n "$((DEV_LOG_LIMIT + 1))" "$CURRENT_BRANCH" 2>/dev/null | awk -v lim="$DEV_LOG_LIMIT" '
        NR <= lim { print }
        NR > lim { more = 1 }
        END { if (more) print "MORE|1"; else print "MORE|0" }
    '
    # Count commits only when the installed commit is a true ancestor of the
    # branch — a diverged or unknown commit must not make every branch commit
    # look "new", otherwise a build from a local branch is told it is behind.
    if [ -n "$LOCAL_COMMIT" ] && git -C "$REPO" merge-base --is-ancestor "$LOCAL_COMMIT" "$CURRENT_BRANCH" 2>/dev/null; then
        AHEAD_COUNT="$(git -C "$REPO" rev-list --count "$LOCAL_COMMIT..$CURRENT_BRANCH" 2>/dev/null || echo 0)"
    else
        AHEAD_COUNT=0
    fi
    [ -n "$AHEAD_COUNT" ] || AHEAD_COUNT=0
    echo "AHEAD|$AHEAD_COUNT"
    echo "LOCAL|$LOCAL_COMMIT"
fi
`
    gitProcess.command = ["bash", "-c", bashCmd, "update-check", currentBranch];
        gitProcess.running = true;
    }

    function reload() {
        loaded = false;
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

    function handleProgressLine(rawLine: string): void {
        const line = rawLine.trim();
        if (line === "")
            return;

        const progressMatch = line.match(/PROGRESS:\s*(done.*|\d+\/\d+:\s*.+)$/);
        if (progressMatch) {
            const pText = progressMatch[1].trim();
            if (pText.startsWith("done")) {
                root.updateProgress = 1.0;
                root.updateStatus = qsTr("Done!");
                return;
            }

            const stageMatch = pText.match(/^(\d+)\/(\d+):\s*(.+)$/);
            if (stageMatch) {
                const current = parseInt(stageMatch[1]);
                const total = parseInt(stageMatch[2]);
                if (total > 0) {
                    root.updateProgress = current / total;
                    root.updateStatus = stageMatch[3];
                }
            }
            return;
        }

        // Fallback: mark deploy stage as finished when deploy script confirms completion.
        if (line.indexOf("Config deployment complete") !== -1 && root.updateProgress < 0.8) {
            root.updateProgress = 0.7;
            root.updateStatus = qsTr("Preparing shell build...");
        }
    }

    function ingestProcessText(rawText: string): void {
        root.lastUpdateOutputMs = Date.now();
        root.stallNoticeShown = false;

        const cleaned = rawText
            .replace(/\u001b\[[0-9;?]*[A-Za-z]/g, "")
            .replace(/\r/g, "\n");

        const chunk = cleaned.endsWith("\n") ? cleaned : (cleaned + "\n");
        root.updateLogs += chunk;

        const combined = root.processLineBuffer + chunk;
        const lines = combined.split("\n");
        root.processLineBuffer = lines.pop();

        for (let i = 0; i < lines.length; i++) {
            root.handleProgressLine(lines[i]);
        }
    }

    function startUpdate(targetVersion: string): void {
        if (root.updateRunning)
            return;
        root.targetVersion = targetVersion;
        root.updateCancelled = false;
        root.updateLogs = "";
        root.updateProgress = 0.0;
        root.updateStatus = qsTr("Starting…");
        root.updateRunning = true;
        root.lastUpdateOutputMs = Date.now();
        root.stallNoticeShown = false;
        root.processLineBuffer = "";
        root.logsExpanded = true;
        updateProcess.running = true;
    }

    function stopUpdate(): void {
        if (!root.updateRunning)
            return;
        root.updateCancelled = true;
        updateProcess.running = false;
        root.updateRunning = false;
        root.updateStatus = qsTr("Canceled");
        root.updateLogs += "\n[Canceled by user]";
    }

    // Process to read local commit and saved branch
    Process {
        id: localCommitProcess

        running: GlobalConfig.general.checkUpdates
        command: ["bash", "-c", "echo \"$(cat ~/.config/quickshell/caelestia/.current_commit 2>/dev/null)|$(cat ~/.config/quickshell/caelestia/.update_branch 2>/dev/null)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split("|");
                root._localCommit = parts[0];
                if (parts.length > 1 && parts[1] !== "") {
                    root.currentBranch = parts[1];
                }
                root.loaded = true;
                root.checkUpdates();
            }
        }
    }

    Process {
        id: gitProcess

        command: []
        onExited: _code => { // qmllint disable signal-handler-parameters
            root.checkingUpdates = false;
            root.lastCheckMs = Date.now();
            if (autoCheckTimer.running)
                autoCheckTimer.restart();
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
                            // Show only version entries in main mode; no commit-level rows.
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
                                // Ignore malformed release lines and keep parsing.
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

                            // Fallback path when release JSON parsing is unavailable.
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
                        if (line.startsWith("COMMIT\u001f")) {
                            // COMMIT<US>fullHash<US>shortHash<US>subject<US>author<US>date<US>parents
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
                        // No installed commit on record yet: can't say what's pending.
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
                        if (!root.availableVersions.includes(root.targetVersion)) {
                            root.targetVersion = root.availableVersions.length > 0 ? root.availableVersions[0] : "";
                        }
                        // Leave currentVersion as "unknown" when the installed
                        // version could not be resolved — pretending the newest
                        // release is installed hides the real state and invites
                        // wrong upgrade/downgrade offers.
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

    // Fetch the next page of dev-branch commits. Unlike checkUpdates() this
    // does not re-clone/re-fetch or re-resolve branches — the bare repo
    // already exists, so it's just a git log with a --skip offset.
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
        onExited: _code => { // qmllint disable signal-handler-parameters
            root.loadingMoreCommits = false;
        }
    }

    Settings {
        id: updaterSettings

        category: "Updater"

        property bool deployConfigs: true

        property bool buildShell: true
    }

    property alias deployConfigs: updaterSettings.deployConfigs

    property alias buildShell: updaterSettings.buildShell

    // ---- Claude Code (the `claude` CLI backing the AI assistant) ----
    // Checked alongside the shell's own updates so the AI settings page can offer
    // "Update" or "Check for updates" without having to poll on its own.
    property string claudeCodeVersion: ""       // installed, "" when not installed

    property string claudeCodeLatestVersion: "" // newest published, "" when unknown

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

        // Prints "<installed>|<latest>". The published version comes from the same
        // endpoint claude.ai/install.sh reads, which is what the settings page's
        // install/update button runs, so the two can't disagree about what "latest" is.
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

    Timer {
        interval: 30000
        repeat: true
        running: root.updateRunning
        onTriggered: {
            if (!root.updateRunning) return;
            if (root.lastUpdateOutputMs <= 0) return;
            const idleMs = Date.now() - root.lastUpdateOutputMs;
            if (idleMs >= 120000 && !root.stallNoticeShown) {
                root.stallNoticeShown = true;
                root.updateLogs += "[WARN] No updater output for 120s. If this persists, stop and retry.\n";
            }
        }
    }

    Timer {
        id: autoCheckTimer

        interval: root.checkIntervalMs
        repeat: false
        running: GlobalConfig.general.checkUpdates && root.loaded
        onTriggered: {
            if (!root.checkingUpdates && !root.updateRunning)
                root.checkUpdates();
        }
    }

    Process {
        id: updateProcess

        command: [Paths.bin("caelestia-update"), root.currentBranch]
            .concat(root.targetVersion !== "" ? [root.targetVersion] : [])
        environment: ({
            CAELESTIA_SKIP_DEPLOY: updaterSettings.deployConfigs ? "0" : "1",
            CAELESTIA_SKIP_BUILD: updaterSettings.buildShell ? "0" : "1"
        })
        stdout: SplitParser {
            onRead: function(text) {
                root.ingestProcessText(text);
            }
        }
        stderr: SplitParser {
            onRead: function(text) {
                root.ingestProcessText(text);
            }
        }
        onExited: function(code) {
            if (root.processLineBuffer !== "") {
                root.handleProgressLine(root.processLineBuffer);
                root.processLineBuffer = "";
            }
            root.updateRunning = false;
            root.lastUpdateOutputMs = 0;
            if (root.updateCancelled) {
                root.updateCancelled = false;
                root.updateStatus = qsTr("Canceled");
                return;
            }
            if (code === 0) {
                Toaster.toast(qsTr("Update Successful"), qsTr("The update is complete. Please log out to apply changes."), "done");
                root.reload();
            } else {
                root.updateStatus = qsTr("Update failed (exit code %1)").arg(code);
                Toaster.toast(qsTr("Update Failed"), qsTr("The update script returned error code %1").arg(code), "error");
            }
        }
    }
}
