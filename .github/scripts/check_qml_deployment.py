#!/usr/bin/env python3
"""Validate the installed QML module tree produced by the shell build."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

EXPECTED_MODULES = (
    "Caelestia",
    "Caelestia/Components",
    "Caelestia/Config",
    "Caelestia/Settings",
    "Caelestia/Models",
    "Caelestia/Services",
    "Caelestia/Blobs",
    "Caelestia/Images",
    "Caelestia/Layouts",
    "M3Shapes",
)
PLUGIN_PATTERN = re.compile(r"^(?:optional\s+)?plugin\s+(\S+)", re.MULTILINE)
PLUGIN_SUFFIXES = (".so", ".dylib", ".dll")

CONTAINER_CHILD_TYPES = (
    "FileView",
    "Timer",
    "Connections",
    "Settings",
    "PersistentProperties",
    "Process",
    "Socket",
)


def plugin_exists(module_dir: Path, plugin_name: str) -> bool:
    candidates = {plugin_name, f"lib{plugin_name}"}
    return any(
        (module_dir / f"{candidate}{suffix}").is_file()
        for candidate in candidates
        for suffix in PLUGIN_SUFFIXES
    )


def check_singleton_roots(source_root: Path) -> list[str]:
    failures: list[str] = []
    for qml_file in source_root.rglob("*.qml"):
        text = qml_file.read_text(encoding="utf-8")
        if "pragma Singleton" not in text:
            continue

        rel = qml_file.relative_to(source_root)
        root_match = re.search(r"^(Item|QtObject|Singleton|Searcher)\s*\{", text, re.MULTILINE)
        if not root_match:
            failures.append(f"{rel}: no supported singleton root found (expected Item, QtObject, Singleton or Searcher)")
            continue

        root_type = root_match.group(1)

        if re.search(r"^\s*default property\b", text, re.MULTILINE):
            failures.append(f"{rel}: singleton root must not redeclare a default property")
            continue

        if root_type == "QtObject":
            child_match = re.search(rf"^    ({'|'.join(CONTAINER_CHILD_TYPES)})\s*\{{", text, re.MULTILINE)
            if child_match:
                failures.append(
                    f"{rel}: QtObject root cannot hold a {child_match.group(1)} child implicitly "
                    "(QtObject has no default property) -- use Singleton or Item as the root instead"
                )

        if root_type == "Singleton" and not re.search(r"^import\s+Quickshell\s*$", text, re.MULTILINE):
            failures.append(f"{rel}: root is 'Singleton' but file has no 'import Quickshell'")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--qml-root", type=Path)
    parser.add_argument("--source-root", type=Path)
    args = parser.parse_args()

    if not args.qml_root and not args.source_root:
        parser.error("at least one of --qml-root or --source-root is required")

    failures = check_singleton_roots(args.source_root.resolve()) if args.source_root else []
    if args.qml_root:
        qml_root = args.qml_root.resolve()
        for module in EXPECTED_MODULES:
            module_dir = qml_root / module
            qmldir = module_dir / "qmldir"
            if not qmldir.is_file():
                failures.append(f"{module}: missing {qmldir}")
                continue

            plugins = PLUGIN_PATTERN.findall(qmldir.read_text(encoding="utf-8"))
            if not plugins:
                failures.append(f"{module}: qmldir declares no plugin")
                continue
            for plugin in plugins:
                if not plugin_exists(module_dir, plugin):
                    failures.append(f"{module}: missing plugin library for '{plugin}'")

    if failures:
        print("QML deployment validation failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    checks = []
    if args.source_root:
        checks.append(f"singleton roots under {args.source_root.resolve()}")
    if args.qml_root:
        checks.append(f"{len(EXPECTED_MODULES)} modules under {args.qml_root.resolve()}")
    print("QML compatibility validated: " + ", ".join(checks))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
