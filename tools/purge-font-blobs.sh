#!/usr/bin/env bash
# Purges the SF Pro and SF Mono blobs from every commit and tag of this project.
#
# Run it only after the fonts are gone from the tip (the commit that drops them),
# and expect it to rewrite every commit SHA: forks have to re-sync, open pull
# requests have to be rebased, the tags are re-pointed and the package checksums
# for published versions stop matching. docs/font-history-purge.md has the full
# picture, the measured numbers and the sequence to follow.
#
# Nothing is pushed unless --push is given.

set -euo pipefail

REPO="${REPO:-.}"
MIRROR=""
REMOTE=""
PUSH=0
PATHS=(shell/assets/fonts/SF-Pro shell/assets/fonts/SF-Mono)

usage() {
    sed -n '2,10p' "$0"
    cat <<'EOF'

Usage: tools/purge-font-blobs.sh [options]

  --repo <path>    repository to read the remote and the paths from (default: .)
  --mirror <dir>   where to build the rewritten mirror (default: a temp dir)
  --remote <url>   where --push sends the result (default: the repo's origin)
  --push           push the rewritten refs and tags to the remote
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo) REPO="$2"; shift 2 ;;
        --mirror) MIRROR="$2"; shift 2 ;;
        --remote) REMOTE="$2"; shift 2 ;;
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

REMOTE="${REMOTE:-$(git -C "$REPO" remote get-url origin)}"
if [[ -z "$MIRROR" ]]; then
    MIRROR="$(mktemp -d)/caelestia-purge.git"
fi
rm -rf "$MIRROR"

echo "==> mirroring $REMOTE into $MIRROR"
git clone --quiet --mirror "$REMOTE" "$MIRROR"

report() {
    local label="$1" pack fonts commits
    pack="$(git -C "$MIRROR" count-objects -vH | awk '/size-pack/ { print $2, $3 }')"
    fonts="$(git -C "$MIRROR" rev-list --objects --all | grep -cE 'assets/fonts/SF-(Pro|Mono)' || true)"
    commits="$(git -C "$MIRROR" rev-list --all --count)"
    printf '%-6s pack %-10s font objects %-4s commits %s\n' "$label" "$pack" "$fonts" "$commits"
}

# Every branch tip tree has to come out of the rewrite unchanged, because the
# fonts are already gone from the tip by the time this runs.
trees_before="$(git -C "$MIRROR" for-each-ref --format='%(refname) %(objectname)' refs/heads | while read -r ref tip; do
    printf '%s %s\n' "$ref" "$(git -C "$MIRROR" rev-parse "$tip^{tree}")"
done)"

report before

echo "==> rewriting"
args=(--force --invert-paths)
for path in "${PATHS[@]}"; do
    args+=(--path "$path")
done
(
    cd "$MIRROR"
    "$PYTHON" -m git_filter_repo "${args[@]}"
)

report after

trees_after="$(git -C "$MIRROR" for-each-ref --format='%(refname) %(objectname)' refs/heads | while read -r ref tip; do
    printf '%s %s\n' "$ref" "$(git -C "$MIRROR" rev-parse "$tip^{tree}")"
done)"

if [[ "$trees_before" != "$trees_after" ]]; then
    echo "!! a branch tip tree changed; the fonts were still in the tip, so run this after they are gone" >&2
    diff <(printf '%s\n' "$trees_before") <(printf '%s\n' "$trees_after") >&2 || true
    exit 1
fi

if [[ "$(git -C "$MIRROR" rev-list --objects --all | grep -cE 'assets/fonts/SF-(Pro|Mono)' || true)" != "0" ]]; then
    echo "!! font objects survived the rewrite" >&2
    exit 1
fi

echo "==> clean: every branch tip is unchanged and no font object is left"

if [[ "$PUSH" == "1" ]]; then
    echo "==> force-pushing branches and tags to $REMOTE"
    git -C "$MIRROR" push --force --all "$REMOTE"
    git -C "$MIRROR" push --force --tags "$REMOTE"
else
    echo "==> to publish it:"
    echo "    git -C $MIRROR push --force --all $REMOTE"
    echo "    git -C $MIRROR push --force --tags $REMOTE"
fi
