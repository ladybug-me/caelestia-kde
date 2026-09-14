#!/usr/bin/env python3
"""Cross-reference QML config accesses against the C++ config declarations.

Quickshell QML reads configuration through the `Config` attached type and the
`GlobalConfig` singleton, e.g. `Config.bar.workspaces.displayType` or
`GlobalConfig.ai.enableClaude`. Those properties are declared with the
CONFIG_PROPERTY / CONFIG_GLOBAL_PROPERTY / CONFIG_ENUM_PROPERTY /
CONFIG_GLOBAL_ENUM_PROPERTY / CONFIG_LIST / CONFIG_SUBOBJECT macros in
shell/plugin/src/Caelestia/Config/*.hpp. If a QML file references a config key
that no longer exists (renamed/removed in C++, typo, wrong nesting), the shell
logs "Cannot assign to non-existent property" and the widget silently breaks —
qmllint cannot see it because the object graph lives in C++.

This checker builds the object graph from the headers and walks every
`Config.*` / `GlobalConfig.*` chain found in QML, flagging references to
properties that don't exist.

Usage:
    python3 check_config_references.py

Exit code is 1 if any unknown config reference is found.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONFIG_DIR = ROOT / "shell" / "plugin" / "src" / "Caelestia" / "Config"

RED = "\033[0;31m"
GREEN = "\033[0;32m"
BOLD = "\033[1m"
RESET = "\033[0m"

# CONFIG_PROPERTY / CONFIG_GLOBAL_PROPERTY / CONFIG_SUBOBJECT, plus the type-first forms
# CONFIG_ENUM_PROPERTY(EnumType, name, default) and CONFIG_LIST(EntryList, name, default)
# and their GLOBAL spellings. DOTALL so multi-line invocations match.
PROP_RE = re.compile(r"CONFIG_(?:GLOBAL_)?(?:ENUM_)?(?:PROPERTY|LIST)\(\s*[^,]+,\s*(\w+)", re.DOTALL)
SUBOBJ_RE = re.compile(r"CONFIG_SUBOBJECT\(\s*(\w+),\s*(\w+)", re.DOTALL)
CLASS_RE = re.compile(r"class\s+(\w+)\s*:\s*public\s+(\w+)")
# Computed, non-config Q_PROPERTYs (e.g. BorderConfig.minThickness).
QPROP_RE = re.compile(r"Q_PROPERTY\(\s*[A-Za-z0-9_:]+\s+(\w+)\s+READ")
ATTACHED_QPROP_RE = re.compile(
    r'Q_PROPERTY\(\s*const\s+caelestia::config::(\w+)\*\s+(\w+)\s+READ'
)
LEAF = "<leaf>"
METHOD = "<method>"

# Q_INVOKABLE methods callable on the config roots.
ROOT_METHODS = {"forScreen", "defaults", "save", "reload", "resetOption", "instance"}


def parse_headers() -> tuple[dict[str, dict[str, str]], dict[str, str]]:
    """Return (class_members, root_props).

    class_members: class name -> { property name -> LEAF or sub-object type }
    root_props:    top-level Config/GlobalConfig name -> LEAF / type / METHOD
    """
    class_members: dict[str, dict[str, str]] = {}
    root_props: dict[str, str] = {}

    if not CONFIG_DIR.is_dir():
        return class_members, root_props

    for hdr in sorted(CONFIG_DIR.glob("*.hpp")):
        try:
            text = hdr.read_text(encoding="utf-8")
        except OSError:
            continue

        # Class declarations in order, so a member match can be attributed to its body.
        class_spans: list[tuple[int, str]] = []
        for m in CLASS_RE.finditer(text):
            if m.group(1) == "ConfigObject":
                continue
            class_spans.append((m.start(), m.group(1)))
            class_members.setdefault(m.group(1), {})

        def owner(pos: int) -> str | None:
            current = None
            for span_pos, name in class_spans:
                if span_pos < pos:
                    current = name
                else:
                    break
            return current

        def add_member(owner_name: str | None, name: str, kind: str) -> None:
            if owner_name is not None and name not in class_members[owner_name]:
                class_members[owner_name][name] = kind

        for m in PROP_RE.finditer(text):
            add_member(owner(m.start()), m.group(1), LEAF)
        for m in SUBOBJ_RE.finditer(text):
            add_member(owner(m.start()), m.group(2), m.group(1))
        for m in QPROP_RE.finditer(text):
            # Only computed properties on regular config classes; the attached type is separate.
            if owner(m.start()) not in (None, "Config"):
                add_member(owner(m.start()), m.group(1), LEAF)

        # Top-level roots: the Config attached type declares Q_PROPERTYs directly.
        if hdr.name == "configattached.hpp":
            for m in ATTACHED_QPROP_RE.finditer(text):
                root_props[m.group(2)] = m.group(1)
            if re.search(r"Q_PROPERTY\(QString screen", text):
                root_props["screen"] = LEAF

    # GlobalConfig sub-objects and its own properties. The singleton is ConfigSingleton
    # (QML_NAMED_ELEMENT GlobalConfig) wrapping ConfigRoot, so the root node's members
    # are the singleton's.
    globals_cls = class_members.get("ConfigRoot", {})
    root_props.update(globals_cls)
    for method in ROOT_METHODS:
        root_props.setdefault(method, METHOD)

    return class_members, root_props


def resolve(class_members: dict[str, dict[str, str]], root_props: dict[str, str], chain: list[str]) -> int | None:
    """Return the index of the first unresolvable link, or None if OK."""
    props = root_props
    for i, name in enumerate(chain):
        if name not in props:
            return i
        member = props[name]
        if member == METHOD:
            # A callable: nothing statically resolvable after it.
            return None
        if member == LEAF:
            # A concrete value (array/string/number): what follows is JS member access on it
            # (.includes, .length, .join), which cannot be verified statically.
            return None
        if i == len(chain) - 1:
            return None
        props = class_members.get(member, {})
    return None


def strip_comments_and_strings(src: str) -> str:
    """Blank out comments and '...'/"..." strings, keeping template literals.

    Template literals (backticks) are kept because JS interpolation inside them
    can reference config, e.g. `${Config.bar.scale}`.
    """
    out = list(src)
    i = 0
    n = len(src)
    while i < n:
        ch = src[i]
        if ch == "/" and i + 1 < n and src[i + 1] == "/":
            j = src.find("\n", i)
            if j == -1:
                j = n
            for k in range(i, j):
                out[k] = " "
            i = j
            continue
        if ch == "/" and i + 1 < n and src[i + 1] == "*":
            j = src.find("*/", i + 2)
            if j == -1:
                j = n
            else:
                j += 2
            for k in range(i, j):
                out[k] = " "
            i = j
            continue
        if ch in "\"'":
            quote = ch
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == quote:
                    j += 1
                    break
                j += 1
            for k in range(i, j):
                out[k] = " "
            i = j
            continue
        i += 1
    return "".join(out)


# A chain starting at a standalone Config/GlobalConfig token, optionally via an id
# like `root.Config.`. The lookbehind rejects the `Config` inside longer identifiers.
CHAIN_RE = re.compile(r"(?<![A-Za-z0-9_$])(Config|GlobalConfig)\.([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*)")


def main() -> int:
    class_members, root_props = parse_headers()

    print(f"{BOLD}=== Config reference check ==={RESET}")
    print(f"Parsed {len(class_members)} config classes, {len(root_props)} root properties")

    if not class_members or not root_props:
        print(f"{RED}Could not parse config headers under {CONFIG_DIR}{RESET}")
        return 1

    errors: list[str] = []
    checked = 0

    for qml in sorted(ROOT.rglob("*.qml")):
        if "build" in qml.parts or ".git" in qml.parts:
            continue
        try:
            src = qml.read_text(encoding="utf-8")
        except OSError:
            continue
        cleaned = strip_comments_and_strings(src)
        for m in CHAIN_RE.finditer(cleaned):
            prefix, chain_text = m.group(1), m.group(2)
            chain = chain_text.split(".")
            checked += 1
            bad = resolve(class_members, root_props, chain)
            if bad is not None:
                missing = chain[bad]
                context = qml.relative_to(ROOT).as_posix()
                # Report file-relative line number
                line = src.count("\n", 0, m.start()) + 1
                errors.append(
                    f"{context}:{line}: unknown config reference "
                    f"{prefix}.{chain_text} (no property '{missing}'"
                    f"{'' if bad == 0 else ' at this level'})"
                )

    for err in errors:
        print(f"{RED}[ERR]{RESET}  {err}")

    print()
    print(f"Checked {checked} config references across QML files.")
    if errors:
        print(f"{BOLD}{RED}{len(errors)} unknown config reference(s) found.{RESET}")
        return 1
    print(f"{BOLD}{GREEN}All config references resolve.{RESET}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
