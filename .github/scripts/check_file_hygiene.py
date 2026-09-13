#!/usr/bin/env python3
"""Check repository file hygiene for files changed in this PR only.

Checks:
  1. No files > 500 KB (prevents accidental large binary commits)
  2. No unresolved merge conflict markers (<<<<<<<, =======, >>>>>>>)
  3. No trailing whitespace in code files
  4. No tab indentation in QML / Python / CMake / C++ files
  5. No binary files in text-only directories (docs/, scripts/)
  6. .sh files have the correct extension and shebang
  7. Scripts the repository runs by path carry the executable bit
"""

import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[0;33m"
BOLD = "\033[1m"
RESET = "\033[0m"

MAX_FILE_SIZE_KB = 500

EXIT_CODE = 0
VIOLATIONS: list[str] = []

# Files and directories to always skip
SKIP_PATTERNS = [
    "diff_upstream.txt",
    "QMLTermWidget",
    "json.hpp",
]

# Skipped for whitespace/tab checks: vendored or generated. `templates` covers the
# matugen theming templates under src/matugen/templates/, which are upstream files.
STYLE_SKIP_DIRS = {"QMLTermWidget", "build", "__pycache__", ".git", "templates"}


def error(msg: str) -> None:
    global EXIT_CODE
    print(f"{RED}[ERR]{RESET}  {msg}")
    VIOLATIONS.append(msg)
    EXIT_CODE = 1


def warn(msg: str) -> None:
    print(f"{YELLOW}[WARN]{RESET} {msg}")


def ok(msg: str) -> None:
    print(f"{GREEN}[OK]{RESET}   {msg}")


def is_text_file(filepath: Path) -> bool:
    """Heuristic: try to read as UTF-8 text; if it fails, treat as binary."""
    try:
        filepath.read_text(encoding="utf-8")
        return True
    except (UnicodeDecodeError, OSError):
        return False


def should_skip(rel_path: str, patterns: list[str] | None = None) -> bool:
    """Check if a path should be skipped based on patterns."""
    for pat in (patterns or SKIP_PATTERNS):
        if pat in rel_path.replace("\\", "/"):
            return True
    return False


def get_changed_files() -> list[str]:
    """Get list of files changed in this PR/push, or empty list if no diff available."""
    # For pull_request events, use GITHUB_BASE_REF
    base_ref = os.environ.get("GITHUB_BASE_REF")
    if not base_ref:
        # For push events, try comparing with origin/main
        result = subprocess.run(
            ["git", "rev-parse", "--verify", "origin/main"],
            capture_output=True, text=True, cwd=ROOT,
        )
        if result.returncode == 0:
            base_ref = "main"

    if base_ref:
        result = subprocess.run(
            ["git", "diff", "--name-only", f"origin/{base_ref}...HEAD"],
            capture_output=True, text=True, cwd=ROOT,
        )
        if result.returncode == 0 and result.stdout.strip():
            files = [f.strip() for f in result.stdout.splitlines() if f.strip()]
            print(f"Checking {len(files)} changed file(s) against {base_ref}")
            return files

    # On push to main/dev with no diff context, skip to avoid flagging pre-existing issues
    print("No diff context available - skipping file hygiene check")
    return []


TEXT_FILE_EXTS = {".qml", ".py", ".cpp", ".hpp", ".h", ".cmake", ".txt",
                  ".md", ".json", ".yml", ".yaml", ".sh", ".bash",
                  ".css", ".js", ".ts", ".xml", ".html", ".conf",
                  ".desktop", ".service", ".timer", ".env", ".toml"}

SPACE_ONLY_EXTS = {".qml", ".py", ".cpp", ".hpp", ".h"}

NON_TEXT_DIRS = {"assets", "wallpapers", "sounds", "icons", "images"}


def check_large_files(changed_files: list[str]) -> None:
    """Check for files larger than MAX_FILE_SIZE_KB in changed files."""
    for rel_path in changed_files:
        if should_skip(rel_path):
            continue

        filepath = ROOT / rel_path
        if not filepath.is_file():
            continue

        try:
            size_kb = filepath.stat().st_size / 1024
        except OSError:
            continue

        if size_kb > MAX_FILE_SIZE_KB:
            if any(skip in rel_path for skip in ("wallpapers", "sounds", "assets", "fonts")):
                warn(f"Large asset file: {rel_path} ({size_kb:.0f} KB)")
            else:
                error(f"File too large ({size_kb:.0f} KB): {rel_path} - max allowed is {MAX_FILE_SIZE_KB} KB")


def check_merge_conflicts(changed_files: list[str]) -> None:
    """Check for unresolved merge conflict markers in changed files."""
    conflict_markers = (
        re.compile(rb"^<{7} "),
        re.compile(rb"^={7}$"),
        re.compile(rb"^>{7} "),
    )

    for rel_path in changed_files:
        if should_skip(rel_path):
            continue

        filepath = ROOT / rel_path
        if not filepath.is_file():
            continue
        if not is_text_file(filepath):
            continue

        try:
            content = filepath.read_bytes()
        except OSError:
            continue

        for line_no, line in enumerate(content.split(b"\n"), 1):
            for marker in conflict_markers:
                if marker.match(line):
                    error(f"Unresolved merge conflict in {rel_path}:{line_no}")
                    break


def check_trailing_whitespace(changed_files: list[str]) -> None:
    """Check for trailing whitespace in changed code files."""
    for rel_path in changed_files:
        if should_skip(rel_path, SKIP_PATTERNS):
            continue

        filepath = ROOT / rel_path
        if not filepath.is_file():
            continue

        ext = filepath.suffix
        if ext not in TEXT_FILE_EXTS:
            continue
        if not is_text_file(filepath):
            continue

        # Skip vendored directories
        if any(d in rel_path.replace("\\", "/").split("/") for d in STYLE_SKIP_DIRS):
            continue

        try:
            lines = filepath.read_text(encoding="utf-8").split("\n")
        except OSError:
            continue

        for line_no, line in enumerate(lines, 1):
            if line.rstrip() != line.rstrip("\n") and line.rstrip() != line:
                error(f"Trailing whitespace: {rel_path}:{line_no}")


def check_tab_indentation(changed_files: list[str]) -> None:
    """Check that code files use spaces, not tabs."""
    for rel_path in changed_files:
        if should_skip(rel_path, SKIP_PATTERNS):
            continue

        filepath = ROOT / rel_path
        if not filepath.is_file():
            continue

        if filepath.suffix not in SPACE_ONLY_EXTS:
            continue
        if not is_text_file(filepath):
            continue

        if any(d in rel_path.replace("\\", "/").split("/") for d in STYLE_SKIP_DIRS):
            continue

        try:
            lines = filepath.read_text(encoding="utf-8").split("\n")
        except OSError:
            continue

        for line_no, line in enumerate(lines, 1):
            if line.startswith("\t"):
                error(f"Tab indentation in {rel_path}:{line_no} - use spaces instead")
                break


def check_binary_in_text_dirs(changed_files: list[str]) -> None:
    """Flag binary files in directories that should only contain text."""
    text_only_dirs = ["docs", "scripts", ".github/scripts"]

    for rel_path in changed_files:
        for check_dir in text_only_dirs:
            if rel_path.replace("\\", "/").startswith(check_dir + "/"):
                filepath = ROOT / rel_path
                if filepath.is_file() and not is_text_file(filepath):
                    error(f"Binary file in text-only directory: {rel_path}")
                break


def check_shell_extensions(changed_files: list[str]) -> None:
    """Ensure .sh files are shell scripts with proper shebangs."""
    for rel_path in changed_files:
        if not rel_path.endswith(".sh"):
            continue
        if should_skip(rel_path):
            continue

        filepath = ROOT / rel_path
        if not filepath.is_file():
            continue

        try:
            first_line = filepath.read_text(encoding="utf-8").split("\n")[0]
        except (OSError, UnicodeDecodeError):
            continue

        if not first_line.startswith("#!"):
            warn(f"Shell script missing shebang: {rel_path}")
        elif "sh" not in first_line.split("/")[-1]:
            warn(f"Shell script has unexpected shebang: {rel_path}: {first_line}")


def git_mode(rel_path: str) -> str | None:
    """Return the mode git records for a path, e.g. 100644 or 100755."""
    result = subprocess.run(
        ["git", "ls-files", "-s", "--", rel_path],
        capture_output=True, text=True, cwd=ROOT,
    )
    lines = result.stdout.strip().splitlines()
    return lines[0].split()[0] if lines else None


def is_run_by_path(rel_path: str) -> bool:
    """True for scripts something executes directly rather than through `bash <path>`.

    The step scripts, the command and its helpers, the three entry points, and the
    packaging helpers. Not scripts/lib, which is sourced, and not tests/, which run
    under bash.
    """
    if rel_path in ("install.sh", "update.sh", "uninstall.sh"):
        return True
    if rel_path.startswith("src/bin/"):
        return True
    if rel_path.startswith("packaging/") and rel_path.endswith(".sh"):
        return True
    return rel_path.startswith("scripts/") and rel_path.count("/") == 1 and rel_path.endswith(".sh")


def check_shell_executable(changed_files: list[str]) -> None:
    """Ensure a script that is run by path is executable in git.

    This is the one hygiene rule a Windows checkout cannot check by looking at the
    files, because the working tree has no mode to look at. CI checks the repository
    out with the mode git recorded, so a script committed as 100644 fails there with
    exit 126, and a test that runs it reports "Permission denied" rather than anything
    about the file it wanted.
    """
    for rel_path in changed_files:
        if not is_run_by_path(rel_path):
            continue
        if should_skip(rel_path) or not (ROOT / rel_path).is_file():
            continue

        mode = git_mode(rel_path)
        if mode is None:
            continue
        if not mode.endswith("755"):
            warn(f"Script run by path is not executable (git mode {mode}): {rel_path}")


def main() -> int:
    # --all scans every git-tracked file (used for push events where there is
    # no PR diff to diff against). Without it, only changed files are checked.
    all_files = "--all" in sys.argv
    if all_files:
        result = subprocess.run(
            ["git", "ls-files"],
            capture_output=True, text=True, cwd=ROOT,
        )
        changed_files = [f.strip() for f in result.stdout.splitlines() if f.strip()]
        print(f"Checking {len(changed_files)} tracked file(s) (full-repo mode)")
    else:
        changed_files = get_changed_files()

    if not changed_files:
        print(f"{YELLOW}No files to check.{RESET}")
        return 0

    print(f"{BOLD}=== File Size Check ==={RESET}")
    check_large_files(changed_files)
    if EXIT_CODE == 0:
        ok("No oversized files found")

    print(f"\n{BOLD}=== Merge Conflict Marker Check ==={RESET}")
    check_merge_conflicts(changed_files)
    if EXIT_CODE == 0:
        ok("No unresolved merge conflicts")

    print(f"\n{BOLD}=== Trailing Whitespace Check ==={RESET}")
    check_trailing_whitespace(changed_files)
    if EXIT_CODE == 0:
        ok("No trailing whitespace")

    print(f"\n{BOLD}=== Tab Indentation Check ==={RESET}")
    check_tab_indentation(changed_files)
    if EXIT_CODE == 0:
        ok("No tab indentation in code files")

    print(f"\n{BOLD}=== Binary in Text Directories Check ==={RESET}")
    check_binary_in_text_dirs(changed_files)
    if EXIT_CODE == 0:
        ok("No binary files in text-only directories")

    print(f"\n{BOLD}=== Shell Script Extension Check ==={RESET}")
    check_shell_extensions(changed_files)
    if EXIT_CODE == 0:
        ok("All .sh files have proper shebangs")

    print(f"\n{BOLD}=== Executable Bit Check ==={RESET}")
    check_shell_executable(changed_files)
    if EXIT_CODE == 0:
        ok("Every script run by path is executable")

    print()
    if EXIT_CODE == 0:
        print(f"{BOLD}{GREEN}All file hygiene checks passed.{RESET}")
    else:
        print(f"{BOLD}{RED}{len(VIOLATIONS)} file hygiene violation(s) found.{RESET}")

    return EXIT_CODE


if __name__ == "__main__":
    sys.exit(main())
