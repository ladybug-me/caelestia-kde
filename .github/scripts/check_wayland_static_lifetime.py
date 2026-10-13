#!/usr/bin/env python3
"""Flag value-typed static/global instances of Wayland proxy-wrapping classes.

A class that inherits QWaylandClientExtensionTemplate<T> or a QtWayland::*
generated wrapper owns a live wl_proxy. If one of those classes is held as a
function-local static (or other static/global storage duration) by value —
e.g. `static PlasmaWindows instance;` — its destructor runs from an exit
handler, long after Qt has torn down the Wayland display connection.
Releasing a Wayland proxy is itself a protocol request, so marshalling one
there writes into an already-closed connection and SIGSEGVs the shell on its
way out.

The established fix in this codebase is to leak the singleton instead:
`static auto* s_instance = new PlasmaWindows(); return s_instance;` (see
windowscreencast.cpp, plasmawindows.cpp) with early, explicit teardown of the
Wayland handles from QCoreApplication::aboutToQuit while the connection is
still live, if cleanup is needed at all.

This checker: (1) scans shell/plugin/src/**/*.hpp for classes that directly
inherit one of those sensitive base types, then (2) scans shell/plugin/src
for `static <Type> <name>` declarations of those classes that are not
pointers, and flags each as a violation.

Usage:
    python3 check_wayland_static_lifetime.py

Exit code is 1 if any violation is found.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLUGIN_SRC = ROOT / "shell" / "plugin" / "src"

RED = "\033[0;31m"
GREEN = "\033[0;32m"
BOLD = "\033[1m"
RESET = "\033[0m"

SENSITIVE_BASE_RE = re.compile(r"QWaylandClientExtensionTemplate\s*<|QtWayland::")
CLASS_DECL_RE = re.compile(r"\bclass\s+(\w+)\s*(?:final\s*)?:\s*(.*?)\{", re.DOTALL)
STATIC_DECL_RE = re.compile(r"^\s*static\s+(?:const\s+)?([A-Za-z_]\w*)\s*(\*)?\s*(\w+)\s*[=;({]", re.MULTILINE)


def error(msg: str) -> None:
    print(f"{RED}[ERR]{RESET}  {msg}")


def ok(msg: str) -> None:
    print(f"{GREEN}[OK]{RESET}   {msg}")


def find_sensitive_classes(headers: list[Path]) -> dict[str, Path]:
    """Return {class_name: declaring_header} for classes that directly inherit
    a Wayland proxy-wrapping base type."""
    sensitive: dict[str, Path] = {}
    for path in headers:
        try:
            src = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        for m in CLASS_DECL_RE.finditer(src):
            name, bases = m.group(1), m.group(2)
            if SENSITIVE_BASE_RE.search(bases):
                sensitive[name] = path
    return sensitive


def find_violations(files: list[Path], sensitive: dict[str, Path]) -> list[str]:
    violations: list[str] = []
    for path in files:
        try:
            src = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        for m in STATIC_DECL_RE.finditer(src):
            type_name, is_pointer, var_name = m.group(1), m.group(2), m.group(3)
            if is_pointer or type_name not in sensitive:
                continue
            line = src.count("\n", 0, m.start()) + 1
            violations.append(
                f"{path.relative_to(ROOT)}:{line}: `static {type_name} {var_name}` holds a "
                f"Wayland proxy by value (see {sensitive[type_name].relative_to(ROOT)}); "
                f"leak it instead (`static auto* {var_name} = new {type_name}(...);`)"
            )
    return violations


def main(argv: list[str]) -> int:
    if not PLUGIN_SRC.is_dir():
        ok(f"{PLUGIN_SRC.relative_to(ROOT)} not found — nothing to check")
        return 0

    headers = sorted(PLUGIN_SRC.rglob("*.hpp"))
    sources = headers + sorted(PLUGIN_SRC.rglob("*.cpp"))

    sensitive = find_sensitive_classes(headers)
    print(f"{BOLD}=== Wayland static-lifetime check ({len(sources)} files) ==={RESET}")
    if sensitive:
        for name, path in sensitive.items():
            print(f"  sensitive type: {name} ({path.relative_to(ROOT)})")

    violations = find_violations(sources, sensitive)

    for v in violations:
        error(v)

    print()
    if violations:
        print(f"{BOLD}{RED}{len(violations)} Wayland static-lifetime violation(s) found.{RESET}")
        return 1
    ok("No value-typed statics of Wayland proxy-wrapping types found.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
