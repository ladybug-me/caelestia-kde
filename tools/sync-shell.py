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
from dataclasses import dataclass
from pathlib import Path
from typing import NamedTuple

DEFAULT_ROOT = Path(__file__).resolve().parents[1]

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


class GitError(RuntimeError):
    """A git invocation that mattered returned a non-zero status."""

    def __init__(self, args: tuple[str, ...], returncode: int, stderr: str) -> None:
        super().__init__(f"git {' '.join(args)} failed with status {returncode}: {stderr.strip()}")
        self.returncode = returncode


@dataclass(frozen=True)
class Repo:
    """A checkout to operate on, passed explicitly so tests get their own."""

    root: Path

    def _raw(self, args: tuple[str, ...]) -> subprocess.CompletedProcess[bytes]:
        return subprocess.run(["git", *args], cwd=self.root, capture_output=True)

    def _checked(self, args: tuple[str, ...]) -> bytes:
        proc = self._raw(args)
        if proc.returncode != 0:
            raise GitError(args, proc.returncode, proc.stderr.decode(errors="replace"))
        return proc.stdout

    def git(self, *args: str) -> str:
        return self._checked(args).decode("utf-8")

    def git_bytes(self, *args: str) -> bytes:
        return self._checked(args)

    def ls_tree(self, tree: str) -> dict[str, str]:
        """Return {path: blob_hash} for every file under `tree` (paths are
        relative to the tree root, so they map 1:1 between shell/ and upstream)."""
        result: dict[str, str] = {}
        for line in self.git("ls-tree", "-r", tree).splitlines():
            meta, path = line.split("\t", 1)
            _mode, _type, blob = meta.split()
            result[path] = blob
        return result

    def grep_paths(self, tree: str, needle: str, glob: str) -> set[str]:
        """Paths under `tree` matching `glob` whose content mentions `needle`."""
        args = ("grep", "-l", "-e", needle, tree, "--", glob)
        proc = self._raw(args)
        if proc.returncode == 1:
            return set()  # git grep exits 1 when nothing matches
        if proc.returncode != 0:
            raise GitError(args, proc.returncode, proc.stderr.decode(errors="replace"))
        return {p for p in proc.stdout.decode("utf-8").splitlines() if p}


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


class Classified(NamedTuple):
    """Where each shell/ path stands relative to upstream."""

    in_sync: list[str]
    missing: list[str]
    kde_only: list[str]
    diverged: list[str]


def classify_paths(shell: dict[str, str], up: dict[str, str]) -> Classified:
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

    return Classified(in_sync, missing, kde_only, diverged)


def do_fetch(repo: Repo) -> None:
    print("Fetching upstream ...")
    repo.git("fetch", "upstream")
    repo.git("branch", "-f", MIRROR_BRANCH, UPSTREAM)
    print(f"{MIRROR_BRANCH} -> {repo.git('rev-parse', '--short', UPSTREAM).strip()}")


def do_report(repo: Repo, full: bool) -> None:
    shell = repo.ls_tree(SHELL_TREE)
    up = repo.ls_tree(UPSTREAM)
    classified = classify_paths(shell, up)

    missing_kept = [p for p in classified.missing if not p.startswith(SKIP_PREFIXES)]
    missing_skipped = [p for p in classified.missing if p.startswith(SKIP_PREFIXES)]

    up_hypr = repo.grep_paths(UPSTREAM, "Hypr", "*.qml")
    shell_hypr = repo.grep_paths(SHELL_TREE, "Hypr", "*.qml")

    def flag(path: str) -> str:
        tags = kind(path)
        if path in up_hypr or path in shell_hypr:
            tags += ",hypr"
        return tags

    print(f"=== SYNC REPORT: shell/ vs {UPSTREAM} ===")
    print(f"shell files: {len(shell)}   upstream files: {len(up)}")
    print(f"  in sync : {len(classified.in_sync)}")
    print(f"  kde-only: {len(classified.kde_only)}  (never touched by sync)")
    print(f"  missing : {len(missing_kept)}  (bring down + adapt)")
    print(f"  diverged: {len(classified.diverged)}  (triage each)")
    print()

    print(f"--- MISSING ({len(missing_kept)}) ---")
    for p in missing_kept:
        print(f"  [{flag(p):<9}] {p}")
    if missing_skipped and full:
        print(f"  ... plus {len(missing_skipped)} skipped repo-meta paths "
              f"(.github, nix, README, ...)")
    print()

    print(f"--- DIVERGED ({len(classified.diverged)}) ---")
    shown = classified.diverged if full else classified.diverged[:60]
    for p in shown:
        print(f"  [{flag(p):<9}] {p}")
    if not full and len(classified.diverged) > 60:
        print(f"  ... {len(classified.diverged) - 60} more (use --full)")
    print()

    print("Bring a missing file with:  python tools/sync-shell.py bring <path>")


def do_bring(repo: Repo, paths: list[str], force: bool) -> None:
    for path in paths:
        up_blob = repo.git("ls-tree", UPSTREAM, "--", path).strip()
        if not up_blob:
            print(f"skip {path}: not present in {UPSTREAM}")
            continue

        exists = bool(repo.git("ls-tree", SHELL_TREE, "--", path).strip())
        if exists and not force:
            print(f"skip {path}: already exists in shell/ (use --force to overwrite)")
            continue
        if exists and force:
            print(f"overwrite {path}")

        content = repo.git_bytes("show", f"{UPSTREAM}:{path}")
        dest = repo.root / "shell" / path
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(content)
        repo.git("add", f"shell/{path}")
        print(f"brought  {path}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Caelestia upstream-sync tool")
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT,
                        help="checkout to operate on (default: the one this tool lives in)")
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("fetch", help="fetch upstream and refresh the mirror branch")

    rep = sub.add_parser("report", help="classify shell/ vs upstream/main")
    rep.add_argument("--full", action="store_true", help="show every diverged file")

    br = sub.add_parser("bring", help="copy upstream paths into shell/")
    br.add_argument("--force", action="store_true", help="overwrite existing files")
    br.add_argument("paths", nargs="+", help="paths relative to shell/, e.g. "
                    "modules/nexus/pages/network/AddNetworkPage.qml")

    args = parser.parse_args()
    repo = Repo(args.root.resolve())
    try:
        if args.cmd == "fetch":
            do_fetch(repo)
        elif args.cmd == "report":
            do_report(repo, args.full)
        elif args.cmd == "bring":
            do_bring(repo, args.paths, args.force)
    except GitError as error:
        sys.stderr.write(f"{error}\n")
        raise SystemExit(error.returncode) from error


if __name__ == "__main__":
    main()
