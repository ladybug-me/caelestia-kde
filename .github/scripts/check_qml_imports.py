#!/usr/bin/env python3
"""Cross-check QML `import` statements against actual type usage.

This repo has no real Qt/QML toolchain available in CI for a full semantic
check (`qmllint6` can't resolve the Quickshell-proprietary `qs.*` directory
imports at all, and is only run per-file/soft-fail today - see check_qml_deployment.py's
"Runtime QML lesson" notes). Instead, this script builds its own type registry
from ground truth that IS available statically:

- `qs.<path>` imports map directly to `shell/<path>/*.qml` (Quickshell's own
  directory-import convention) - exact, no guessing.
- `Caelestia(.Sub)*` imports map to C++ classes registered with QML_ELEMENT /
  QML_NAMED_ELEMENT under shell/plugin/src/Caelestia/<Sub>/ - exact, parsed
  straight from the headers.
- Any `.qml` file in the same directory as the file being checked is usable
  without an import (QML's implicit same-directory import) - exact.
- `import "some/relative/path"` (a quoted directory import) resolves to the
  `.qml` files in that directory, relative to the importing file - exact.
- Everything else (QtQuick, QtQuick.Layouts, Quickshell, Quickshell.Io, ...)
  is resolved from UNAMBIGUOUS evidence only: a file whose only non-qs/
  non-Caelestia import is a single module M proves, with certainty, that
  every type it uses (and doesn't get from local/qs/Caelestia/relative
  imports) is provided by M. A type needs at least 2 such single-module
  files as evidence before it's trusted enough to flag other files over -
  this avoids both a single-typo file poisoning the registry and one-off
  coincidences being treated as proof. Fundamental QtQml-module types
  (Connections, Timer, Binding, Component) are excluded from checking
  entirely since they're transitively available through *any* Qt/Quickshell
  module a file imports, per standard Qt/QML semantics.

Missing-import findings are a hard failure (this is exactly the bug class that
let a `Singleton {}` root ship without `import Quickshell` - see git history/
Nmcli.qml). Unused-import findings are informational only (printed, never
fail the build) since attached-property/enum-only usage of a module is
common and this script's usage extraction can't always see it.
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

IMPORT_RE = re.compile(r'^\s*import\s+(?:"([^"]+)"|([\w.]+))(?:\s+[\d.]+)?(?:\s+as\s+(\w+))?\s*$', re.MULTILINE)
LINE_COMMENT_RE = re.compile(r"^[ \t]*//.*$", re.MULTILINE)
BLOCK_COMMENT_RE = re.compile(r"/\*.*?\*/", re.DOTALL)

TYPE_INSTANTIATION_RE = re.compile(r"^[ \t]*([A-Z]\w*)\s*\{", re.MULTILINE)
QUALIFIED_INSTANTIATION_RE = re.compile(r"^[ \t]*(\w+)\.([A-Z]\w*)\s*\{", re.MULTILINE)
PROPERTY_TYPE_RE = re.compile(r"\bproperty\s+([A-Z]\w*)\s+\w+")
PROPERTY_LIST_RE = re.compile(r"\bproperty\s+list<([A-Z]\w*)>")
DOT_ACCESS_RE = re.compile(r"\b([A-Z]\w*)\.\w+")

ALWAYS_OK = {
    "Component", "QtObject", "Qt", "Math", "JSON", "Date", "Number", "String",
    "Array", "Object", "Boolean", "RegExp", "Symbol", "Map", "Set", "Promise",
    "Error", "TypeError", "RangeError", "Function", "Infinity", "NaN",
    "Connections", "Timer", "Binding",
}

CAELESTIA_CLASS_RE = re.compile(r"class\s+(\w+)\s*(?:final\s*)?(?::[^{;]*)?\{")
CAELESTIA_NAMED_ELEMENT_RE = re.compile(r'QML_NAMED_ELEMENT\(\s*"(\w+)"\s*\)')

VALID_BAREWORD_MODULE_RE = re.compile(r"^(qs(\.[\w.]+)?|[A-Z][\w.]*)$")


def strip_comments(text: str) -> str:
    return BLOCK_COMMENT_RE.sub("", LINE_COMMENT_RE.sub("", text))


def strip_imports(text: str) -> str:
    return IMPORT_RE.sub("", text)


def parse_imports(text: str) -> tuple[list[tuple[str, str | None]], list[str]]:
    """Returns (named_modules, relative_dir_imports). Named modules are dotted
    identifiers (QtQuick, qs.services, Caelestia.Services, ...); relative dir
    imports are quoted paths (`import "../drawers/blur"`), which QML resolves
    relative to the importing file's own directory, not a shared module name."""
    named: list[tuple[str, str | None]] = []
    relative: list[str] = []
    for m in IMPORT_RE.finditer(text):
        quoted, bareword, alias = m.group(1), m.group(2), m.group(3)
        if quoted is not None:
            relative.append(quoted)
        elif VALID_BAREWORD_MODULE_RE.match(bareword):
            named.append((bareword, alias))
    return named, relative


def extract_used_types(code: str) -> set[str]:
    used: set[str] = set()
    used.update(TYPE_INSTANTIATION_RE.findall(code))
    used.update(t for _alias, t in QUALIFIED_INSTANTIATION_RE.findall(code))
    used.update(PROPERTY_TYPE_RE.findall(code))
    used.update(PROPERTY_LIST_RE.findall(code))
    used.update(DOT_ACCESS_RE.findall(code))
    return used - ALWAYS_OK


def is_qs_module(module: str) -> bool:
    return module == "qs" or module.startswith("qs.")


def is_caelestia_module(module: str) -> bool:
    return module == "Caelestia" or module.startswith("Caelestia.")


def qs_module_dir(shell_root: Path, module: str) -> Path:
    parts = module.split(".")[1:]
    return shell_root.joinpath(*parts)


def build_qs_registry(shell_root: Path, used_modules: set[str]) -> dict[str, set[str]]:
    registry: dict[str, set[str]] = {}
    for module in used_modules:
        if not is_qs_module(module):
            continue
        directory = qs_module_dir(shell_root, module)
        registry[module] = {f.stem for f in directory.glob("*.qml")} if directory.is_dir() else set()
    return registry


def relative_import_types(qml_file: Path, relative_path: str) -> set[str]:
    directory = (qml_file.parent / relative_path).resolve()
    return {f.stem for f in directory.glob("*.qml")} if directory.is_dir() else set()


def build_caelestia_registry(plugin_src_root: Path) -> dict[str, set[str]]:
    registry: dict[str, set[str]] = defaultdict(set)
    if not plugin_src_root.is_dir():
        return registry
    for hpp in plugin_src_root.rglob("*.hpp"):
        rel_parts = hpp.relative_to(plugin_src_root).parts[:-1]
        module = "Caelestia" if not rel_parts else "Caelestia." + ".".join(rel_parts)
        text = strip_comments(hpp.read_text(encoding="utf-8"))
        matches = list(CAELESTIA_CLASS_RE.finditer(text))
        for i, m in enumerate(matches):
            start, end = m.end(), (matches[i + 1].start() if i + 1 < len(matches) else len(text))
            body = text[start:end]
            if "QML_ANONYMOUS" in body:
                continue
            named = CAELESTIA_NAMED_ELEMENT_RE.search(body)
            if named:
                registry[module].add(named.group(1))
            elif "QML_ELEMENT" in body:
                registry[module].add(m.group(1))
    return registry


def build_local_registry(shell_root: Path) -> dict[Path, set[str]]:
    registry: dict[Path, set[str]] = defaultdict(set)
    for qml in shell_root.rglob("*.qml"):
        registry[qml.parent].add(qml.stem)
    return registry


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--shell-root", type=Path, required=True)
    parser.add_argument("--plugin-src", type=Path, default=None, help="shell/plugin/src/Caelestia")
    args = parser.parse_args()

    shell_root = args.shell_root.resolve()
    plugin_src_root = (args.plugin_src or (shell_root / "plugin" / "src" / "Caelestia")).resolve()

    qml_files = sorted(shell_root.rglob("*.qml"))
    local_registry = build_local_registry(shell_root)
    caelestia_registry = build_caelestia_registry(plugin_src_root)

    parsed: list[tuple[Path, set[str], list[str], set[str], set[str]]] = []
    all_qs_modules: set[str] = set()
    for qml_file in qml_files:
        raw = qml_file.read_text(encoding="utf-8")
        code = strip_imports(strip_comments(raw))
        named_imports, relative_imports = parse_imports(raw)
        modules = {module for module, _alias in named_imports}
        aliases = {alias: module for module, alias in named_imports if alias}
        all_qs_modules.update(m for m in modules if is_qs_module(m))
        used_types = extract_used_types(code)
        parsed.append((qml_file, modules, relative_imports, aliases.keys() & used_types, used_types))

    qs_registry = build_qs_registry(shell_root, all_qs_modules)

    per_file_unresolved: list[tuple[Path, set[str], set[str], set[str]]] = []
    type_module_evidence: dict[str, Counter[str]] = defaultdict(Counter)
    for qml_file, modules, relative_imports, alias_names, used_types in parsed:
        local_types = local_registry.get(qml_file.parent, set()) - {qml_file.stem}
        qs_types = {t for m in modules if is_qs_module(m) for t in qs_registry.get(m, set())}
        cael_types = {t for m in modules if is_caelestia_module(m) for t in caelestia_registry.get(m, set())}
        rel_types = {t for path in relative_imports for t in relative_import_types(qml_file, path)}
        resolved = local_types | qs_types | cael_types | rel_types | alias_names
        unresolved = used_types - resolved
        per_file_unresolved.append((qml_file, modules, unresolved, used_types - unresolved))

        standard_modules = {m for m in modules if not is_qs_module(m) and not is_caelestia_module(m)}
        if len(standard_modules) == 1:
            (only_module,) = standard_modules
            for t in unresolved:
                type_module_evidence[t][only_module] += 1

    type_candidates: dict[str, set[str]] = {
        t: {m for m, count in counter.items() if count >= 2}
        for t, counter in type_module_evidence.items()
    }
    type_candidates = {t: candidates for t, candidates in type_candidates.items() if candidates}

    missing_failures: list[str] = []
    unused_warnings: list[str] = []

    for qml_file, modules, unresolved, resolved_here in per_file_unresolved:
        rel = qml_file.relative_to(shell_root)
        standard_modules = {m for m in modules if not is_qs_module(m) and not is_caelestia_module(m)}
        for t in sorted(unresolved):
            candidates = type_candidates.get(t)
            if not candidates or candidates & standard_modules:
                continue
            missing_failures.append(f"{rel}: uses '{t}' but none of its known-providing modules ({', '.join(sorted(candidates))}) are imported")

    for qml_file, modules, _unresolved, used_here in per_file_unresolved:
        rel = qml_file.relative_to(shell_root)
        for module in sorted(m for m in modules if is_qs_module(m) or is_caelestia_module(m)):
            provided = qs_registry.get(module) if is_qs_module(module) else caelestia_registry.get(module)
            if not provided:
                continue
            if not (provided & used_here):
                unused_warnings.append(f"{rel}: imports '{module}' but none of its types ({', '.join(sorted(provided))}) appear to be used")

    if unused_warnings:
        print(f"::group::Possibly unused imports ({len(unused_warnings)}, informational only)", file=sys.stderr)
        for w in unused_warnings:
            print(f"- {w}", file=sys.stderr)
        print("::endgroup::", file=sys.stderr)

    if missing_failures:
        print(f"QML import validation failed ({len(missing_failures)} missing import(s)):", file=sys.stderr)
        for f in missing_failures:
            print(f"- {f}", file=sys.stderr)
        return 1

    print(f"QML import validation passed: {len(qml_files)} files checked, {len(unused_warnings)} informational unused-import warning(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
