"""Check that C++ sources match the repository's .clang-format.

Only the files a pull request touches are checked. The vendored plugin has a large
backlog of files that predate the formatter, and rewriting them wholesale would bury
real differences for tools/sync-shell.py, so the rule is: touch a file, format it.

Usage:
    python3 .github/scripts/check_cpp_format.py            # changed files vs the base branch
    python3 .github/scripts/check_cpp_format.py FILE...    # explicit files
    python3 .github/scripts/check_cpp_format.py --all      # every C++ source in the tree
"""

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CPP_TREES = ("shell/plugin", "shell/extras")
CPP_SUFFIXES = (".cpp", ".hpp", ".h", ".cc")
# WrapNamespaceBodyWithEmptyLines (shell/.clang-format) needs clang-format 20 or newer.
MIN_MAJOR = 20
PINNED = "22.1.8"


def clang_format() -> str | None:
    return shutil.which("clang-format")


def version_of(exe: str) -> tuple[int, int, int] | None:
    result = subprocess.run([exe, "--version"], capture_output=True, text=True)
    match = re.search(r"version (\d+)\.(\d+)\.(\d+)", result.stdout)
    if not match:
        return None
    return tuple(int(part) for part in match.groups())  # type: ignore[return-value]


def changed_files() -> list[str]:
    """Files this change touches.

    Pull requests diff against the base branch; a push diffs against the previous
    commit. Both are two-dot diffs, so a shallow checkout is enough.
    """
    base_ref = os.environ.get("GITHUB_BASE_REF")
    if base_ref:
        target = f"origin/{base_ref}"
    elif os.environ.get("GITHUB_EVENT_NAME") == "push":
        target = "HEAD^"
    else:
        print("Not a pull request or push - pass files or --all")
        return []
    result = subprocess.run(["git", "diff", "--name-only", target, "HEAD"],
                            capture_output=True, text=True, cwd=ROOT)
    if result.returncode != 0:
        print(f"Could not diff against {target}: {result.stderr.strip()}")
        return []
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def tracked_cpp() -> list[str]:
    result = subprocess.run(["git", "ls-files"], capture_output=True, text=True, cwd=ROOT)
    files = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    return [f for f in files if is_cpp(f)]


def is_cpp(rel: str) -> bool:
    return rel.endswith(CPP_SUFFIXES) and rel.startswith(CPP_TREES)


def main() -> int:
    args = sys.argv[1:]
    exe = clang_format()
    if not exe:
        print("clang-format is not installed")
        print(f"Install the pinned version: pip install clang-format=={PINNED}")
        return 1

    version = version_of(exe)
    if version is None:
        print(f"Could not read the clang-format version from {exe}")
        return 1
    if version[0] < MIN_MAJOR:
        print(f"clang-format {'.'.join(str(p) for p in version)} is too old")
        print("shell/.clang-format uses WrapNamespaceBodyWithEmptyLines, which needs 20 or newer")
        print(f"Install the pinned version: pip install clang-format=={PINNED}")
        return 1

    if "--all" in args:
        files = tracked_cpp()
    elif args:
        files = [f for f in args if Path(f).exists()]
    else:
        files = [f for f in changed_files() if is_cpp(f)]

    # A deleted file has nothing to format.
    files = [f for f in files if (ROOT / f).exists()]

    if not files:
        print("No C++ files to check")
        return 0

    print(f"Checking {len(files)} file(s) with clang-format {'.'.join(str(p) for p in version)}")
    dirty = []
    for rel in files:
        result = subprocess.run([exe, "--dry-run", "--Werror", rel],
                                capture_output=True, text=True, cwd=ROOT)
        if result.returncode != 0:
            dirty.append(rel)

    if dirty:
        print("\nNot formatted with shell/.clang-format:")
        for rel in dirty:
            print(f"  {rel}")
        print(f"\n{len(dirty)} of {len(files)} file(s) need formatting")
        print("Run: clang-format -i <file>")
        return 1

    print("All checked files are formatted")
    return 0


if __name__ == "__main__":
    sys.exit(main())
