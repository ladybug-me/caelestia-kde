#!/usr/bin/env python3
"""Validate the integrity of PageCompRegistry.qml.

Ensures:
1. Unique keys: No duplicate category keys, page keys, or subpage keys;
   no page/subpage key collisions; and no cross-category key ambiguities.
2. Complete value assignments: Every category, page, and subpage declares
   required fields (key, label, icon, description, defaultPage, keywords).
3. Valid component references: Every component named in the registry exists
   as a .qml file in shell/modules/nexus/pages/.
4. Valid defaultPage destinations: Every category's defaultPage targets a page
   or subpage defined within that category.
5. Zero legacy slot artifacts: No slot: or defaultSlot: declarations, and no
   deprecated slotForKey / subPageIdxFor functions.
"""

from __future__ import annotations

import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NEXUS = ROOT / "shell" / "modules" / "nexus"
REGISTRY = NEXUS / "PageCompRegistry.qml"
PAGES_DIR = NEXUS / "pages"


def extract_blocks(text: str, block_name: str) -> list[str]:
    """Extract top-level blocks of a given type handling nested braces."""
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
    return {path.stem: path for path in PAGES_DIR.rglob("*.qml")}


def check() -> list[str]:
    content = REGISTRY.read_text(encoding="utf-8")
    files = page_files()
    errors: list[str] = []

    # 1. Check for legacy slot artifacts in the registry
    if "slot:" in content:
        errors.append("PageCompRegistry.qml still contains 'slot:' declarations")
    if "defaultSlot:" in content:
        errors.append("PageCompRegistry.qml still contains 'defaultSlot:' declarations")
    if "slotForKey" in content:
        errors.append("PageCompRegistry.qml still contains deprecated 'slotForKey' function")
    if "subPageIdxFor" in content:
        errors.append("PageCompRegistry.qml still contains deprecated 'subPageIdxFor' function")
    if "parentSlotFor" in content:
        errors.append("PageCompRegistry.qml still contains deprecated 'parentSlotFor' function")

    cats = extract_blocks(content, "Category")
    if not cats:
        errors.append("No Category blocks found in PageCompRegistry.qml")
        return errors

    cat_keys: list[str] = []
    page_keys: list[str] = []
    subpage_keys: list[str] = []
    cat_page_map: dict[str, set[str]] = {}

    for cat_idx, cat in enumerate(cats):
        idx_match = re.search(r"categoryIdx:\s*(\d+)", cat)
        if not idx_match:
            errors.append(f"Category block {cat_idx} missing categoryIdx")
        elif int(idx_match.group(1)) != cat_idx:
            errors.append(f"Category {cat_idx} categoryIdx mismatch: got {idx_match.group(1)}, expected {cat_idx}")

        cat_key_match = re.search(r'key:\s*"([^"]+)"', cat)
        if not cat_key_match:
            errors.append(f"Category {cat_idx} missing key")
            cat_key = f"unknown_{cat_idx}"
        else:
            cat_key = cat_key_match.group(1)
            cat_keys.append(cat_key)

        cat_label_match = re.search(r'label:\s*qsTr\("([^"]+)"\)', cat)
        if not cat_label_match:
            errors.append(f"Category {cat_idx} ({cat_key}) missing or unlocalized label")

        cat_icon_match = re.search(r'icon:\s*"([^"]+)"', cat)
        if not cat_icon_match:
            errors.append(f"Category {cat_idx} ({cat_key}) missing icon")

        cat_desc_match = re.search(r'description:\s*qsTr\("([^"]+)"\)', cat)
        if not cat_desc_match:
            errors.append(f"Category {cat_idx} ({cat_key}) missing or unlocalized description")

        default_match = re.search(r'defaultPage:\s*"([^"]+)"', cat)
        if not default_match:
            errors.append(f"Category {cat_idx} ({cat_key}) missing defaultPage")
            default_page = ""
        else:
            default_page = default_match.group(1)

        pages = extract_blocks(cat, "Page")
        if not pages:
            errors.append(f"Category {cat_idx} ({cat_key}) has no Page entries")

        this_cat_keys: set[str] = set()

        for page in pages:
            pk_match = re.search(r'key:\s*"([^"]+)"', page)
            if not pk_match:
                errors.append(f"Category {cat_idx}: Page missing key")
                continue
            pk = pk_match.group(1)
            page_keys.append(pk)
            this_cat_keys.add(pk)

            plabel_match = re.search(r'label:\s*qsTr\("([^"]+)"\)', page)
            if not plabel_match:
                errors.append(f"Page '{pk}' missing or unlocalized label")

            picon_match = re.search(r'icon:\s*"([^"]+)"', page)
            if not picon_match:
                errors.append(f"Page '{pk}' missing icon")

            pdesc_match = re.search(r'description:\s*qsTr\("([^"]+)"\)', page)
            if not pdesc_match:
                errors.append(f"Page '{pk}' missing or unlocalized description")

            kw_match = re.search(r'keywords:\s*\[([^\]]*)\]', page)
            if not kw_match or not re.findall(r'"([^"]+)"', kw_match.group(1)):
                errors.append(f"Page '{pk}' missing or empty keywords array")

            comp_match = re.search(r"Component\s*\{\s*(\w+)\s*\{", page)
            if not comp_match:
                errors.append(f"Page '{pk}' missing component instantiation")
            else:
                comp_name = comp_match.group(1)
                if comp_name not in files:
                    errors.append(f"Page '{pk}' component '{comp_name}.qml' not found in pages dir")

            for sub in extract_blocks(page, "SubPage"):
                sk_match = re.search(r'key:\s*"([^"]+)"', sub)
                if not sk_match:
                    errors.append(f"Page '{pk}': SubPage missing key")
                    continue
                sk = sk_match.group(1)
                subpage_keys.append(sk)
                this_cat_keys.add(sk)

                slabel_match = re.search(r'label:\s*qsTr\("([^"]+)"\)', sub)
                if not slabel_match:
                    errors.append(f"SubPage '{sk}' missing or unlocalized label")

                skw_match = re.search(r'keywords:\s*\[([^\]]*)\]', sub)
                if not skw_match or not re.findall(r'"([^"]+)"', skw_match.group(1)):
                    errors.append(f"SubPage '{sk}' missing or empty keywords array")

                scomp_match = re.search(r"Component\s*\{\s*(\w+)\s*\{", sub)
                if not scomp_match:
                    errors.append(f"SubPage '{sk}' missing component instantiation")
                else:
                    scomp_name = scomp_match.group(1)
                    if scomp_name not in files:
                        errors.append(f"SubPage '{sk}' component '{scomp_name}.qml' not found in pages dir")

        cat_page_map[cat_key] = this_cat_keys

        if default_page and default_page not in this_cat_keys:
            errors.append(
                f"Category {cat_idx} ({cat_key}) defaultPage '{default_page}' not found in category pages or subpages"
            )

    # 2. Key uniqueness checks
    cat_counts = Counter(cat_keys)
    for k, count in cat_counts.items():
        if count > 1:
            errors.append(f"Duplicate category key: '{k}' appears {count} times")

    page_counts = Counter(page_keys)
    for k, count in page_counts.items():
        if count > 1:
            errors.append(f"Duplicate page key: '{k}' appears {count} times")

    sub_counts = Counter(subpage_keys)
    for k, count in sub_counts.items():
        if count > 1:
            errors.append(f"Duplicate subpage key: '{k}' appears {count} times")

    overlap_page_sub = set(page_keys).intersection(set(subpage_keys))
    if overlap_page_sub:
        errors.append(f"Page and subpage key collision: {sorted(overlap_page_sub)}")

    # Check for cross-category collisions (a page or subpage matching a category key must belong to that category)
    for cat_name, child_keys in cat_page_map.items():
        for other_cat, other_children in cat_page_map.items():
            if cat_name != other_cat:
                if other_cat in child_keys:
                    errors.append(
                        f"Cross-category key collision: Category '{cat_name}' contains child key '{other_cat}' which matches another category"
                    )

    # 3. Check pageComps list matches categories count
    page_comps_match = re.search(r"readonly property list<Component> pageComps:\s*\[(.*?)\]", content, re.S)
    if page_comps_match:
        comps = re.findall(r"Component\s*\{", page_comps_match.group(1))
        if len(comps) != len(cats):
            errors.append(f"pageComps count ({len(comps)}) does not match categories count ({len(cats)})")
    else:
        errors.append("pageComps list property not found in PageCompRegistry.qml")

    if not errors:
        print(f"OK: PageCompRegistry valid ({len(cats)} categories, {len(page_keys)} pages, {len(subpage_keys)} subpages)")
    return errors


def main() -> int:
    errors = check()
    for err in errors:
        print(f"ERROR: {err}", file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
