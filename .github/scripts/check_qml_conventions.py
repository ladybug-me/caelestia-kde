#!/usr/bin/env python3
"""Regression gate for the project's QML convention linter.

`shell/scripts/qml-lint-conventions.py` reports thousands of pre-existing
convention violations, so running it as a plain gate in CI would block every
PR. Instead we compare the current violation set against a stored baseline and
fail only when NEW violations appear (same file + rule + message), which is
robust to line-number shifts.

Baseline location: .github/ci-baselines/qml-conventions.txt

Usage:
    python3 check_qml_conventions.py             # check against baseline
    python3 check_qml_conventions.py --update    # regenerate the baseline
"""

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LINTER = ROOT / "shell" / "scripts" / "qml-lint-conventions.py"
BASELINE = ROOT / ".github" / "ci-baselines" / "qml-conventions.txt"

RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[0;33m"
BOLD = "\033[1m"
RESET = "\033[0m"

ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
VIOLATION_RE = re.compile(r"\[([\w-]+)\]\s+([^:]+):(\d+):\s*(.+)")
DIGITS_RE = re.compile(r"\d+")


def normalize_key(rule: str, path: str, message: str) -> str:
    """Normalize a violation into a stable key (digits replaced, path slashes unified)."""
    path = path.replace("\\", "/")
    msg = DIGITS_RE.sub("N", message.strip())
    return f"{rule}\t{path}\t{msg}"


def run_linter() -> tuple[int, list[str]]:
    """Run the linter, returning (exit_code, normalized_violation_keys)."""
    result = subprocess.run(
        [sys.executable, str(LINTER)],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        cwd=ROOT,
    )
    text = ANSI_RE.sub("", result.stdout or "")
    keys: list[str] = []
    for line in text.splitlines():
        m = VIOLATION_RE.match(line.strip())
        if m:
            keys.append(normalize_key(m.group(1), m.group(2), m.group(4)))
    return result.returncode, keys


def load_baseline() -> set[str]:
    if not BASELINE.is_file():
        return set()
    return {line.strip() for line in BASELINE.read_text(encoding="utf-8").splitlines() if line.strip()}


def write_baseline(keys: list[str]) -> None:
    BASELINE.parent.mkdir(parents=True, exist_ok=True)
    BASELINE.write_text("\n".join(sorted(set(keys))) + "\n", encoding="utf-8")


def main() -> int:
    update = "--update" in sys.argv

    linter_code, keys = run_linter()
    current = set(keys)
    baseline = load_baseline()

    print(f"{BOLD}=== QML conventions regression check ==={RESET}")
    print(f"Linter reported {len(current)} violations (baseline: {len(baseline)})")

    if update:
        write_baseline(keys)
        print(f"{GREEN}Baseline updated: {BASELINE.relative_to(ROOT)}{RESET}")
        return 0

    if not baseline:
        print(f"{YELLOW}No baseline found — run with --update to create it, then commit.{RESET}")
        return 0 if linter_code == 0 else 1

    new_violations = sorted(current - baseline)
    resolved_violations = sorted(baseline - current)

    for key in new_violations:
        rule, path, msg = key.split("\t", 2)
        print(f"{RED}[ERR]{RESET}  NEW [{rule}] {path}: {msg}")

    if resolved_violations:
        print(f"{GREEN}{len(resolved_violations)} previously-flagged violation(s) are now resolved.{RESET}")

    print()
    if new_violations:
        print(f"{BOLD}{RED}{len(new_violations)} NEW QML convention violation(s) found.{RESET}")
        print(f"Fix them, or if intentional re-run: python3 {Path(__file__).name} --update")
        return 1

    print(f"{BOLD}{GREEN}No new QML convention violations.{RESET}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
