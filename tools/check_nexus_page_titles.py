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

TITLE = re.compile(r'^ {4}title: qsTr\("([^"]*)"\)', re.M)
LABEL = re.compile(r'label:\s*qsTr\("([^"]+)"\)')
COMP = re.compile(r'Component\s*\{\s*(\w+)\s*\{')


def extract_blocks(text: str, block_name: str) -> list[str]:
    blocks: list[str] = []
    pattern = re.compile(rf"\b{block_name}\s*\{{")
    for m in pattern.finditer(text):
        start = m.end() - 1
        depth = 1
        i = start + 1
        while i < len(text) and depth > 0:
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
            i += 1
        blocks.append(text[start + 1 : i - 1])
    return blocks


def page_files() -> dict[str, Path]:
    return {path.stem: path for path in PAGES.rglob("*.qml")}


def page_title(path: Path) -> str | None:
    match = TITLE.search(path.read_text(encoding="utf-8"))
    return match.group(1) if match else None


def check() -> list[str]:
    content = REGISTRY.read_text(encoding="utf-8")
    files = page_files()
    errors: list[str] = []
    checked = 0

    cats = extract_blocks(content, "Category")
    for cat_idx, cat in enumerate(cats):
        pages = extract_blocks(cat, "Page")
        for page in pages:
            label_match = LABEL.search(page)
            comp_match = COMP.search(page)
            if not label_match or not comp_match:
                continue

            label = label_match.group(1)
            comp = comp_match.group(1)
            path = files.get(comp)
            if not path:
                errors.append(f"Category {cat_idx}: component {comp} not found in pages dir")
                continue

            title = page_title(path)
            if title is None:
                continue

            checked += 1
            if label != title:
                errors.append(
                    f'Category {cat_idx}: registry says "{label}", page says "{title}" ({path.relative_to(ROOT)})'
                )

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
