#!/usr/bin/env bash
# Shrinks this repository's history: every version of a large binary asset that is
# not the one a branch tip carries is removed from the rewrite, so translations,
# wallpapers, sounds, GIFs, video and fonts stop being stored once per update.
# Branch tips come out byte-identical; only history gets smaller.
#
# It runs on a fresh mirror and pushes nothing unless --push is given. Run it after
# the commit that drops a bundled asset (fonts, say) has landed, so the tip no
# longer references it: nothing that a tip carries is ever removed.
#
# Expect every commit SHA to change. Forks have to re-sync, open pull requests have
# to be rebased, tags are re-pointed and the package checksums for published
# versions stop matching. Old tags lose the large files they used to carry, so a
# rebuild from an old tag has no bundled sounds, wallpapers or translations.

set -euo pipefail

REPO="${REPO:-.}"
MIRROR=""
REMOTE=""
WORK=""
PUSH=0
SUFFIXES="ts qm gif png jpg jpeg webp mp4 wav mp3 ogg ttf otf ii zip"

usage() {
    sed -n '2,12p' "$0"
    cat <<'EOF'

Usage: tools/shrink-repo-history.sh [options]

  --repo <path>     repository to read the remote from (default: .)
  --mirror <dir>    where to build the rewritten mirror (default: a temp dir)
  --remote <url>    where --push sends the result (default: the repo's origin)
  --suffixes "..."  file types whose older versions are dropped (default: ts qm
                    gif png jpg jpeg webp mp4 wav mp3 ogg ttf otf ii zip)
  --push            push the rewritten refs and tags to the remote
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo) REPO="$2"; shift 2 ;;
        --mirror) MIRROR="$2"; shift 2 ;;
        --remote) REMOTE="$2"; shift 2 ;;
        --suffixes) SUFFIXES="$2"; shift 2 ;;
        --push) PUSH=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
done

find_python() {
    local candidate
    for candidate in "${PYTHON:-}" python3 python; do
        [[ -n "$candidate" ]] || continue
        command -v "$candidate" >/dev/null 2>&1 || continue
        if "$candidate" -c "import git_filter_repo" >/dev/null 2>&1; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done
    return 1
}

if ! PYTHON="$(find_python)"; then
    echo "git-filter-repo is missing from every python on PATH: pip install git-filter-repo" >&2
    exit 1
fi

# git-filter-repo runs under the native python on Windows, which cannot open an
# MSYS path.
to_native() {
    if command -v cygpath >/dev/null 2>&1; then
        cygpath -w "$1"
    else
        printf '%s' "$1"
    fi
}

REMOTE="${REMOTE:-$(git -C "$REPO" remote get-url origin)}"
if [[ -z "$MIRROR" ]]; then
    WORK="$(mktemp -d)"
    MIRROR="$WORK/caelestia-shrink.git"
else
    WORK="$MIRROR"
fi
mkdir -p "$WORK"

echo "==> mirroring $REMOTE into $MIRROR"
rm -rf "$MIRROR"
git clone --quiet --mirror "$REMOTE" "$MIRROR"

report() {
    local label="$1" pack blobs commits
    pack="$(git -C "$MIRROR" count-objects -vH | awk '/size-pack/ { print $2, $3 }')"
    blobs="$(git -C "$MIRROR" cat-file --batch-check --batch-all-objects 2>/dev/null | wc -l)"
    commits="$(git -C "$MIRROR" rev-list --all --count)"
    printf '%-6s pack %-10s objects %-8s commits %s\n' "$label" "$pack" "$blobs" "$commits"
}

# The blob of every file in every branch tip survives the rewrite untouched.
tip_blobs() {
    git -C "$MIRROR" for-each-ref --format='%(refname)' refs/heads | while read -r ref; do
        git -C "$MIRROR" ls-tree -r "$ref" | awk '{ print $3 }'
    done | sort -u
}

trees() {
    git -C "$MIRROR" for-each-ref --format='%(refname) %(tree)' refs/heads | sort
}

before_trees="$(trees)"
report before

echo "==> collecting the blobs the branch tips carry"
tip_blobs > "$WORK/tip-blobs.txt"
echo "    $(wc -l < "$WORK/tip-blobs.txt") blobs"

{
    printf "ifs = ('%s')\n" "${SUFFIXES// /', '}"
    printf 'if "TIP" not in globals():\n'
    printf '    globals()["TIP"] = set(["%s"])\n' "$(paste -sd, "$WORK/tip-blobs.txt" | sed "s/,/\", \"/g")"
    cat <<'PY'
name = filename.decode() if isinstance(filename, bytes) else filename
ident = blob_id.decode() if isinstance(blob_id, bytes) else blob_id
if ident not in TIP and name.rsplit(".", 1)[-1].lower() in ifs:
    return (filename, None, blob_id)
return (filename, mode, blob_id)
PY
} > "$WORK/callback.py"

echo "==> rewriting: the bundled SF Pro and SF Mono files go from every commit"
(
    cd "$MIRROR"
    "$PYTHON" -m git_filter_repo --force --invert-paths \
        --path shell/assets/fonts/SF-Pro --path shell/assets/fonts/SF-Mono
)

echo "==> rewriting: older versions of the large binaries go"
(
    cd "$MIRROR"
    "$PYTHON" -m git_filter_repo --force --file-info-callback "$(to_native "$WORK/callback.py")"
)

report after

if [[ "$before_trees" != "$(trees)" ]]; then
    echo "!! a branch tip changed; nothing was pushed" >&2
    diff <(printf '%s\n' "$before_trees") <(trees) >&2 || true
    exit 1
fi

echo "==> every branch tip is byte-identical"

if [[ "$PUSH" == "1" ]]; then
    echo "==> force-pushing branches and tags to $REMOTE"
    git -C "$MIRROR" push --force --all "$REMOTE"
    git -C "$MIRROR" push --force --tags "$REMOTE"
else
    echo "==> to publish it:"
    echo "    git -C $MIRROR push --force --all $REMOTE"
    echo "    git -C $MIRROR push --force --tags $REMOTE"
fi
