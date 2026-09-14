#!/usr/bin/env python3
"""
Caelestia upstream-sync tool.

Keeps the vendored shell (shell/) in sync with the upstream shell repo
(caelestia-dots/shell), tracked as the `upstream` git remote.

The vendored shell is a fork, not a copy: roughly half its files are
KDE-specific additions that must never be overwritten by a sync, and a
large number of shared files have drifted. This tool therefore does NOT
auto-merge the whole tree. It classifies the difference between shell/
and upstream into buckets, and lets you bring down chosen upstream paths
one at a time for adaptation.

Commands:
    fetch                 fetch upstream and refresh the mirror branch
    report                classify shell/ vs upstream/main (the sync report)
    bring PATH...         copy upstream paths into shell/ (then you adapt)
    bring --force PATH... overwrite an existing shell/ file with upstream

See docs/upstream-sync.md for the full process.
"""

import argparse
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

UPSTREAM = "upstream/main"
SHELL_TREE = "HEAD:shell"
MIRROR_BRANCH = "mirror/upstream"

SKIP_PREFIXES = (
    ".github",
    ".vscode",
    "nix",
    "flake.nix",
    "flake.lock",
    "README.md",
    "LICENSE",
)


def git(*args: str, cwd: str = ROOT) -> str:
    """Run git and return stdout, raising on failure."""
    proc = subprocess.run(
        ["git", *args], cwd=cwd, capture_output=True, text=True, encoding="utf-8"
    )
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr)
        raise SystemExit(proc.returncode)
    return proc.stdout


def git_bytes(*args: str, cwd: str = ROOT) -> bytes:
    proc = subprocess.run(["git", *args], cwd=cwd, capture_output=True)
    if proc.returncode != 0:
        sys.stderr.write(proc.stderr.decode(errors="replace"))
        raise SystemExit(proc.returncode)
    return proc.stdout


def ls_tree(tree: str) -> dict[str, str]:
    """Return {path: blob_hash} for every file under `tree` (paths are
    relative to the tree root, so they map 1:1 between shell/ and upstream)."""
    out = git("ls-tree", "-r", tree)
    result: dict[str, str] = {}
    for line in out.splitlines():
        meta, path = line.split("\t", 1)
        _mode, _type, blob = meta.split()
        result[path] = blob
    return result


def kind(path: str) -> str:
    """Rough file category used only to make the report scannable."""
    name = os.path.basename(path)
    ext = os.path.splitext(path)[1].lower()
    if path.startswith(SKIP_PREFIXES):
        return "meta"
    if ext in {".cpp", ".hpp", ".h", ".c", ".cc", ".frag", ".vert", ".cmake"}:
        return "cpp"
    if name == "CMakeLists.txt":
        return "cpp"
    if path.startswith("assets/") or ext in {
        ".ttf", ".otf", ".webp", ".png", ".svg", ".jpg", ".jpeg", ".gif", ".pam",
    }:
        return "asset"
    return "qml"


def hypr_paths(tree: str) -> set[str]:
    """Paths under `tree` whose content mentions Hypr (Hyprland coupling)."""
    out = git("grep", "-l", "-e", "Hypr", tree, "--", "*.qml")
    return {p for p in out.splitlines() if p}


def do_fetch() -> None:
    print("Fetching upstream ...")
    git("fetch", "upstream")
    git("branch", "-f", MIRROR_BRANCH, UPSTREAM)
    print(f"{MIRROR_BRANCH} -> {git('rev-parse', '--short', UPSTREAM).strip()}")


def do_report(full: bool) -> None:
    shell = ls_tree(SHELL_TREE)
    up = ls_tree(UPSTREAM)

    in_sync: list[str] = []
    missing: list[str] = []
    kde_only: list[str] = []
    diverged: list[str] = []

    for path, blob in up.items():
        if path not in shell:
            missing.append(path)
        elif shell[path] == blob:
            in_sync.append(path)
        else:
            diverged.append(path)
    for path in shell:
        if path not in up:
            kde_only.append(path)

    missing_kept = [p for p in missing if not p.startswith(SKIP_PREFIXES)]
    missing_skipped = [p for p in missing if p.startswith(SKIP_PREFIXES)]

    up_hypr = hypr_paths(UPSTREAM)
    shell_hypr = hypr_paths(SHELL_TREE)

    def flag(path: str) -> str:
        tags = kind(path)
        if path in up_hypr or path in shell_hypr:
            tags += ",hypr"
        return tags

    print(f"=== SYNC REPORT: shell/ vs {UPSTREAM} ===")
    print(f"shell files: {len(shell)}   upstream files: {len(up)}")
    print(f"  in sync : {len(in_sync)}")
    print(f"  kde-only: {len(kde_only)}  (never touched by sync)")
    print(f"  missing : {len(missing_kept)}  (bring down + adapt)")
    print(f"  diverged: {len(diverged)}  (triage each)")
    print()

    print(f"--- MISSING ({len(missing_kept)}) ---")
    for p in missing_kept:
        print(f"  [{flag(p):<9}] {p}")
    if missing_skipped and full:
        print(f"  ... plus {len(missing_skipped)} skipped repo-meta paths "
              f"(.github, nix, README, ...)")
    print()

    print(f"--- DIVERGED ({len(diverged)}) ---")
    shown = diverged if full else diverged[:60]
    for p in shown:
        print(f"  [{flag(p):<9}] {p}")
    if not full and len(diverged) > 60:
        print(f"  ... {len(diverged) - 60} more (use --full)")
    print()

    print("Bring a missing file with:  python tools/sync-shell.py bring <path>")


def do_bring(paths: list[str], force: bool) -> None:
    for path in paths:
        up_blob = git("ls-tree", UPSTREAM, "--", path).strip()
        if not up_blob:
            print(f"skip {path}: not present in {UPSTREAM}")
            continue

        exists = bool(git("ls-tree", SHELL_TREE, "--", path).strip())
        if exists and not force:
            print(f"skip {path}: already exists in shell/ (use --force to overwrite)")
            continue
        if exists and force:
            print(f"overwrite {path}")

        content = git_bytes("show", f"{UPSTREAM}:{path}")
        dest = os.path.join(ROOT, "shell", path)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "wb") as fh:
            fh.write(content)
        git("add", os.path.join("shell", path))
        print(f"brought  {path}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Caelestia upstream-sync tool")
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("fetch", help="fetch upstream and refresh the mirror branch")

    rep = sub.add_parser("report", help="classify shell/ vs upstream/main")
    rep.add_argument("--full", action="store_true", help="show every diverged file")

    br = sub.add_parser("bring", help="copy upstream paths into shell/")
    br.add_argument("--force", action="store_true", help="overwrite existing files")
    br.add_argument("paths", nargs="+", help="paths relative to shell/, e.g. "
                   "modules/nexus/pages/network/AddNetworkPage.qml")

    args = parser.parse_args()
    if args.cmd == "fetch":
        do_fetch()
    elif args.cmd == "report":
        do_report(args.full)
    elif args.cmd == "bring":
        do_bring(args.paths, args.force)


if __name__ == "__main__":
    main()
