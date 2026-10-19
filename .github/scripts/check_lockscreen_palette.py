#!/usr/bin/env python3
"""Check the lock screen's fallback palette against the shell's default palette.

The lock screen reads `$XDG_STATE_HOME/caelestia/scheme.json` and wears a palette of its
own until one lands. That palette has to be the shell's default one, held in
`shell/services/Colours.qml` as `M3Palette`, otherwise a machine with no scheme yet - a
fresh install before the colour step runs, or a scheme that was removed - shows one set of
colours under the shell and another on the lock screen.

This checker reads both declarations and compares the pairs that carry the same meaning.
A lock screen property with no shell counterpart, or a counterpart with a different value,
fails.

Usage:
    python3 check_lockscreen_palette.py

Exit code is 1 if the two disagree.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SHELL_COLOURS = ROOT / "shell" / "services" / "Colours.qml"
LOCK_SCREEN = (
    ROOT
    / "src"
    / "kde"
    / "shells"
    / "caelestia.desktop"
    / "contents"
    / "lockscreen"
    / "LockScreenUi.qml"
)

PAIRS = {
    "clSurface": "m3surface",
    "clSurfaceFg": "m3onSurface",
    "clSurfaceContainer": "m3surfaceContainer",
    "clSurfaceContainerHigh": "m3surfaceContainerHigh",
    "clSurfaceContainerHighest": "m3surfaceContainerHighest",
    "clPrimary": "m3primary",
    "clSecondary": "m3secondary",
    "clPrimaryFg": "m3onPrimary",
    "clError": "m3error",
    "clSurfaceVariantFg": "m3onSurfaceVariant",
    "clPrimaryContainer": "m3primaryContainer",
    "clSecondaryContainer": "m3secondaryContainer",
    "clTertiary": "m3tertiary",
    "clOnTertiary": "m3onTertiary",
    "clOutline": "m3outline",
}

PALETTE_RE = re.compile(r"component\s+M3Palette\s*:\s*QtObject\s*\{(.*?)\n\s*\}", re.DOTALL)
COLOUR_RE = re.compile(r'property\s+color\s+(\w+)\s*:\s*"(#[0-9a-fA-F]{6})"')
TERMS_RE = re.compile(r"property\s+var\s+clTerms\s*:\s*\[([^\]]*)\]")
TERM_RE = re.compile(r'"(#[0-9a-fA-F]{6})"')

RED = "\033[0;31m"
GREEN = "\033[0;32m"
BOLD = "\033[1m"
RESET = "\033[0m"


def shell_palette() -> dict[str, str]:
    text = SHELL_COLOURS.read_text(encoding="utf-8")
    block = PALETTE_RE.search(text)
    if not block:
        sys.exit(f"{RED}could not find M3Palette in {SHELL_COLOURS}{RESET}")
    return {name: value.lower() for name, value in COLOUR_RE.findall(block.group(1))}


def lock_palette() -> dict[str, str]:
    text = LOCK_SCREEN.read_text(encoding="utf-8")
    colours = {name: value.lower() for name, value in COLOUR_RE.findall(text)}
    terms = TERMS_RE.search(text)
    if terms:
        for index, value in enumerate(TERM_RE.findall(terms.group(1))):
            colours[f"clTerm{index}"] = value.lower()
    return colours


def main() -> int:
    shell = shell_palette()
    lock = lock_palette()

    problems = []
    for here, there in PAIRS.items():
        mine = lock.get(here)
        theirs = shell.get(there)
        if mine is None:
            problems.append(f"{here} is not declared, so it keeps whatever Qt gives it")
        elif theirs is None:
            problems.append(f"{there} is not declared in M3Palette")
        elif mine != theirs:
            problems.append(f"{here} is {mine} but {there} is {theirs}")

    for index in range(8):
        mine = lock.get(f"clTerm{index}")
        theirs = shell.get(f"term{index}")
        if mine is not None and theirs is not None and mine != theirs:
            problems.append(f"clTerm{index} is {mine} but term{index} is {theirs}")

    if problems:
        print(f"{BOLD}{RED}the lock screen's fallback palette differs from the shell's{RESET}")
        for problem in problems:
            print(f"  {RED}{problem}{RESET}")
        print(f"\n{BOLD}fix{RESET}: copy the values from M3Palette in {SHELL_COLOURS.relative_to(ROOT)}")
        return 1

    print(f"{GREEN}the lock screen falls back to the shell's own palette{RESET}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
