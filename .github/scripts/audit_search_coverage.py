#!/usr/bin/env python3
"""Audit how much of the Nexus settings tree the search index can actually reach.

The search index is built from `shell/modules/nexus/PageDictionary.qml`
(see `PageRegistry.buildIndex()`), which is hand written. A page, a section or a
setting that is missing from that table is invisible to search, and nothing else
in CI notices: the QML still parses, the pages still render, and the setting is
still reachable by clicking through. That is how searching "font" ended up
returning only the Appearance page while the font pickers sat unreachable.

Hard gate (exits non-zero):
  every settings sub-page listed in PageCompRegistry must have a search entry.
  Sub-pages that only render a device, network or app the user picked before are
  exempt - a search hit for those would open an empty page.

Reported, not gated:
  section headers and individual setting rows. Only a minority of them are named
  by an entry, and giving every one of them an entry is a data change large
  enough to need its own decision (and a result cap, or a common query returns
  hundreds of rows). Until then the counts below are printed on every run so the
  gap stays visible instead of silent.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
NEXUS = ROOT / "shell" / "modules" / "nexus"

LABEL = re.compile(r'label: qsTr\("([^"]+)"\)')
KEYWORDS = re.compile(r'keywords: \[([^\]]*)\]')
DESCRIPTION = re.compile(r'description: qsTr\("([^"]+)"\)')
CATEGORY = re.compile(r'category: "([^"]+)"')
PAIR = re.compile(r"subPageIdx: (\d+)")
PAGE_COMPONENT = re.compile(r"^\s{16}Component \{$")
PAGE = re.compile(r"^\s{8}Component \{$")
COMPONENT_NAME = re.compile(r"^\s{20}([A-Za-z0-9_]+) \{\}$")

SETTING_BLOCKS = (
    "ToggleRow",
    "StepperRow",
    "DoubleStepperRow",
    "SelectRow",
    "TextFieldRow",
    "NavRow",
)

CONTEXT_DEPENDENT = {
    (0, 2): "wallpaper category, needs the chosen category",
    (3, 1): "ethernet details, needs the chosen interface",
    (3, 2): "add network, needs the SSID being joined",
    (3, 3): "network details, needs the chosen network",
    (3, 4): "add VPN, opened as an action from the network list",
    (4, 1): "device info, needs the chosen device",
    (11, 2): "app info, needs the chosen app",
}

REPORT_LIMIT = 25


def normalise(text: str) -> str:
    """Lowercase and strip punctuation, keeping word boundaries."""
    spaced = "".join(char if char.isalnum() else " " for char in text.lower())
    return re.sub(r"\s+", " ", spaced).strip()


def dictionary_lines() -> list[str]:
    return (NEXUS / "PageDictionary.qml").read_text(encoding="utf-8").splitlines()


def search_index() -> list[str]:
    """Mirror PageRegistry.buildIndex(): the strings a query is matched against."""
    entries: list[str] = []
    page: tuple[str, ...] = ()
    in_settings = False

    for line in dictionary_lines():
        stripped = line.strip()
        indent = len(line) - len(line.lstrip())
        if stripped.startswith("settings: ["):
            in_settings = True
            continue
        if in_settings and stripped in ("]", "],"):
            in_settings = False
            continue

        if in_settings:
            match = LABEL.search(line)
            if not match:
                continue
            words = [match.group(1)]
            keywords = KEYWORDS.search(line)
            if keywords:
                words += re.findall(r'"([^"]*)"', keywords.group(1))
            entries.append(" ".join(words + list(page)))
            continue

        if indent != 12:
            continue
        match = LABEL.search(line)
        if match:
            page = (match.group(1),)
            continue
        extra = DESCRIPTION.search(line) or CATEGORY.search(line)
        if extra:
            page = page + (extra.group(1),)
            entries.append(" ".join(page))

    return [normalise(entry) for entry in entries]


def navigation_targets() -> set[tuple[int, int]]:
    """(pageIdx, subPageIdx) pairs the dictionary can open."""
    targets: set[tuple[int, int]] = set()
    page = -1
    in_settings = False

    for line in dictionary_lines():
        stripped = line.strip()
        indent = len(line) - len(line.lstrip())
        if stripped.startswith("settings: ["):
            in_settings = True
            continue
        if in_settings and stripped in ("]", "],"):
            in_settings = False
            continue
        if indent == 12 and LABEL.search(line):
            page += 1
            continue
        if in_settings:
            match = PAIR.search(line)
            targets.add((page, int(match.group(1)) if match else -1))

    return targets


def registry_subpages() -> list[tuple[int, int, str]]:
    """Every sub-page, as (pageIdx, subPageIdx, component name)."""
    pages: list[list[str]] = []
    for line in (NEXUS / "PageCompRegistry.qml").read_text(encoding="utf-8").splitlines():
        if PAGE.match(line):
            pages.append([])
            continue
        if not pages:
            continue
        if PAGE_COMPONENT.match(line):
            pages[-1].append("")
            continue
        match = COMPONENT_NAME.match(line)
        if match and pages[-1] and pages[-1][-1] == "":
            pages[-1][-1] = match.group(1)
    return [(page, sub, name) for page, names in enumerate(pages) for sub, name in enumerate(names)]


def block_labels(block_type: str) -> list[tuple[str, str]]:
    """Labels rendered by a given component type, as (label, relative path)."""
    found: list[tuple[str, str]] = []
    for path in sorted((NEXUS / "pages").rglob("*.qml")):
        lines = path.read_text(encoding="utf-8").splitlines()
        for number, line in enumerate(lines, 1):
            if f"{block_type} {{" not in line:
                continue
            for offset in range(1, 8):
                index = number - 1 + offset
                if index >= len(lines):
                    break
                match = re.search(r'(?:text|label): qsTr\("([^"]+)"\)', lines[index])
                if match:
                    found.append((match.group(1), path.relative_to(NEXUS).as_posix()))
                    break
    return found


def setting_labels() -> list[tuple[str, str]]:
    found: list[tuple[str, str]] = []
    for block_type in SETTING_BLOCKS:
        found += block_labels(block_type)
    return found


def is_subsequence(needle: str, haystack: str) -> bool:
    position = 0
    for char in needle:
        position = haystack.find(char, position) + 1
        if position == 0:
            return False
    return True


def reached(label: str, index: list[str]) -> bool:
    """fzf matches a query as a subsequence of a candidate string."""
    needle = normalise(label)
    return any(is_subsequence(needle, candidate) for candidate in index)


def named(label: str, index: list[str]) -> bool:
    """An entry actually names this label, rather than matching it by accident."""
    needle = normalise(label)
    return any(needle in candidate for candidate in index)


def report(title: str, rows: list[tuple[str, str]], index: list[str], qualify) -> None:
    print(f"\n== {title}: {len(rows)} of {qualify['total']}")
    for label, location in rows[:REPORT_LIMIT]:
        print(f"   {location:<44} {label}")
    if len(rows) > REPORT_LIMIT:
        print(f"   ... and {len(rows) - REPORT_LIMIT} more")


def main() -> int:
    index = search_index()
    targets = navigation_targets()

    subpages = registry_subpages()
    unreachable = [
        (page, sub, name)
        for page, sub, name in subpages
        if sub > 0 and (page, sub) not in targets and (page, sub) not in CONTEXT_DEPENDENT
    ]

    settings = setting_labels()
    headers = block_labels("SectionHeader")
    unnamed_settings = [row for row in settings if not named(row[0], index)]
    unnamed_headers = [row for row in headers if not named(row[0], index)]
    unreached_settings = [row for row in settings if not reached(row[0], index)]

    print("== Nexus search coverage ==")
    print(f"   index entries          {len(index)}")
    print(f"   settings sub-pages     {len([s for s in subpages if s[1] > 0])} ({len(CONTEXT_DEPENDENT)} context-dependent)")
    print(f"   section headers        {len(headers)}")
    print(f"   setting rows           {len(settings)}")

    report("Section headers no entry names", unnamed_headers, index, {"total": len(headers)})
    report("Setting rows no entry names", unnamed_settings, index, {"total": len(settings)})
    report("Setting rows no query can match", unreached_settings, index, {"total": len(settings)})

    if unreachable:
        print(f"\n[ERR] {len(unreachable)} settings sub-page(s) cannot be reached from search:")
        for page, sub, name in unreachable:
            print(f"   page {page} sub {sub}  {name}")
        print("   Add an entry for each to PageDictionary.qml, or list it in CONTEXT_DEPENDENT "
              "with the reason it cannot stand on its own.")
        return 1

    print("\n[OK] every settings sub-page is reachable from search")
    return 0


if __name__ == "__main__":
    sys.exit(main())
