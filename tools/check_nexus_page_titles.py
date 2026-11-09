#!/usr/bin/env python3
"""Check that every subcategory card names the page it opens.

The pane is the menu and the page title is the header the user lands on, so a
card that says one thing and a page that says another makes the whole section
list feel like two different taxonomies. Dynamic titles (a page that names the
selected object) are skipped: they cannot be compared without a live value.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NEXUS = ROOT / "shell" / "modules" / "nexus"
PAGES = NEXUS / "pages"
REGISTRY = NEXUS / "PageCompRegistry.qml"
PANE = NEXUS / "SubcategoryPane.qml"

PAGE_LINE = re.compile(r"^        Component \{$")
SUBPAGE = re.compile(r'SubPage \{ slot: (\d+); key: "([^"]+)"[^}]*Component \{ (\w+) \{\}')
CARD_OPEN = re.compile(r"^\s*SubcategoryCard \{")
LABEL = re.compile(r'label: qsTr\("([^"]*)"\)')
SLOT = re.compile(r"slot: (\d+)")
TITLE = re.compile(r'^ {4}title: qsTr\("([^"]*)"\)', re.M)


def registry_pages() -> dict[int, dict[int, tuple[str, str]]]:
    """Map a page index to the (key, component) in each of its slots."""
    pages: dict[int, dict[int, tuple[str, str]]] = {}
    page = -1
    for line in REGISTRY.read_text(encoding="utf-8").splitlines():
        if PAGE_LINE.match(line):
            page += 1
            pages[page] = {}
            continue
        match = SUBPAGE.search(line)
        if match and page >= 0:
            pages[page][int(match.group(1))] = (match.group(2), match.group(3))
    return pages


def pane_cards() -> dict[int, list[tuple[int, str]]]:
    """Map a page index to the (slot, label) of every card in the pane."""
    cards: dict[int, list[tuple[int, str]]] = {}
    page = -1
    lines = PANE.read_text(encoding="utf-8").splitlines()
    index = 0
    while index < len(lines):
        marker = re.match(r"^\s*// Page (\d+):", lines[index])
        if marker:
            page = int(marker.group(1))
            cards.setdefault(page, [])
            index += 1
            continue

        if CARD_OPEN.match(lines[index]):
            block: list[str] = []
            depth = 0
            while index < len(lines):
                line = lines[index]
                block.append(line)
                depth += line.count("{") - line.count("}")
                index += 1
                if depth == 0:
                    break
            text = "\n".join(block)
            label = LABEL.search(text)
            slot = SLOT.search(text)
            if page >= 0 and label and slot:
                cards[page].append((int(slot.group(1)), label.group(1)))
            continue

        index += 1
    return cards


def page_files() -> dict[str, Path]:
    return {path.stem: path for path in PAGES.rglob("*.qml")}


def page_title(path: Path) -> str | None:
    match = TITLE.search(path.read_text(encoding="utf-8"))
    return match.group(1) if match else None


def check() -> list[str]:
    registry = registry_pages()
    cards = pane_cards()
    files = page_files()
    errors: list[str] = []
    checked = 0

    for page, slots in registry.items():
        for slot, (key, component) in sorted(slots.items()):
            label = dict(cards.get(page, [])).get(slot)
            if label is None:
                continue

            path = files.get(component)
            if path is None:
                errors.append(f"page {page} slot {slot}: no source file for {component} ({key})")
                continue

            title = page_title(path)
            if title is None:
                continue

            checked += 1
            if label != title:
                errors.append(
                    f'page {page} slot {slot}: card says "{label}", '
                    f'page says "{title}" ({path.relative_to(ROOT)})'
                )

    for page, page_cards in cards.items():
        for slot, label in page_cards:
            if slot not in registry.get(page, {}):
                errors.append(f'page {page} slot {slot}: card "{label}" has no page in the registry')

    if not errors:
        print(f"checked {checked} subcategory cards")
    return errors


def main() -> int:
    errors = check()
    for error in errors:
        print(error, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
