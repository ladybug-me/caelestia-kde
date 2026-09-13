#!/usr/bin/env python3
"""Check bash/sh scripts embedded inside QML Process.command arrays.

Quickshell's `Process` element runs commands natively. Many components pass a
whole script through `command: ["bash", "-c", `<script>`]` (or `sh -c`). Those
strings are invisible to qmllint and to shellcheck (they aren't .sh files), so a
typo or unbalanced quote inside one only surfaces at runtime as a silent
`exit 127` / empty widget.

This checker extracts every such embedded script and runs `bash -n` on it.

Usage:
    python3 check_embedded_bash.py            # check all shell/**/*.qml files
    python3 check_embedded_bash.py <paths...> # check specific files/dirs

Exit code is 1 if any embedded script fails to parse (or is extracted but the
file can't be parsed). If `bash` is unavailable the check is skipped with a
warning (CI always has bash, so this only matters for local runs).
"""

import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

RED = "\033[0;31m"
GREEN = "\033[0;32m"
YELLOW = "\033[0;33m"
BOLD = "\033[1m"
RESET = "\033[0m"

# Process command arrays look like command: ["bash", "-c", `...`] or
# ["sh", "-c", "...", "--", arg]; bash/sh//bin/bash all count as the interpreter.
INTERP_RE = re.compile(r"^(?:/usr)?/?(?:bin/)?(?:ba|da|k)?sh$")

# ${...} in a backtick string is evaluated by JavaScript before the process runs, so it
# is not bash source. Replaced with `true` so bash -n sees valid syntax.
JS_INTERP_RE = re.compile(r"\$\{([^{}]*)\}")


def error(msg: str) -> None:
    print(f"{RED}[ERR]{RESET}  {msg}")


def ok(msg: str) -> None:
    print(f"{GREEN}[OK]{RESET}   {msg}")


def warn(msg: str) -> None:
    print(f"{YELLOW}[WARN]{RESET} {msg}")


class _Element:
    """One element parsed out of a `command: [...]` array literal."""

    __slots__ = ("is_script", "is_template", "line", "text")

    def __init__(self, text: str, line: int, is_script: bool = False, is_template: bool = False):
        self.text = text
        self.line = line
        self.is_script = is_script
        self.is_template = is_template


def _parse_string(src: str, pos: int, quote: str, start_line: int) -> tuple[_Element, int]:
    """Parse a quoted string / template literal starting at src[pos].

    Returns (element, next_pos). Handles `"..."`, `'...'` and `` `...` ``.
    """
    i = pos + 1
    line = start_line
    out: list[str] = []
    while i < len(src):
        ch = src[i]
        if ch == "\n":
            line += 1
        if ch == "\\" and i + 1 < len(src):
            nxt = src[i + 1]
            if quote == "`":
                # Keep backslash escapes verbatim except \` and \${ which are
                # JS escapes for literal backtick / literal bash parameter.
                if nxt == "`":
                    out.append("`")
                elif nxt == "$":
                    # \${ in a JS template literal means literal `${` for bash.
                    out.append("${")
                else:
                    out.append("\\" + nxt)
                i += 2
                continue
            # Regular quoted string: keep escapes verbatim (they are for the
            # shell, e.g. \" inside a bash -c double-quoted script).
            out.append("\\" + nxt)
            i += 2
            continue
        if ch == quote:
            return _Element("".join(out), start_line, is_script=True, is_template=(quote == "`")), i + 1
        out.append(ch)
        i += 1
    # Unterminated string — treat what we have as the element and continue.
    return _Element("".join(out), start_line, is_script=True, is_template=(quote == "`")), i


def _extract_command_arrays(src: str) -> list[tuple[int, list[_Element]]]:
    """Find `command: [ ... ]` literals and return (array_start_line, elements)."""
    results: list[tuple[int, list[_Element]]] = []
    for m in re.finditer(r"\bcommand\s*:\s*\[", src):
        start_line = src.count("\n", 0, m.start()) + 1
        i = m.end()  # position just after '['
        elements: list[_Element] = []
        line = start_line
        while i < len(src):
            ch = src[i]
            if ch == "\n":
                line += 1
            if ch.isspace() or ch in ",]":
                if ch == "]":
                    break
                i += 1
                continue
            if ch in "\"'`":
                el, i = _parse_string(src, i, ch, line)
                elements.append(el)
                continue
            # Bare word (bash, -c, sh, etc.)
            j = i
            while j < len(src) and not (src[j].isspace() or src[j] in ",]\""):
                j += 1
            elements.append(_Element(src[i:j], line))
            i = j
        results.append((start_line, elements))
    return results


def _extract_scripts(elements: list[_Element]) -> list[_Element]:
    """Return string elements that follow an `interp -c` sequence."""
    scripts: list[_Element] = []
    for idx, el in enumerate(elements):
        # Interpreter name ("bash", 'sh', /bin/sh, ...) — quoted or bare.
        if INTERP_RE.match(el.text):
            for k in range(idx + 1, len(elements)):
                nxt = elements[k]
                if nxt.text == "-c":
                    if k + 1 < len(elements) and elements[k + 1].is_script:
                        scripts.append(elements[k + 1])
                    break
                if elements[k].is_script:
                    # A string argument appeared before `-c` — not a script form
                    break
    return scripts


def _sanitize_script(text: str, is_template: bool) -> str:
    """Remove JS-only constructs so the remainder is pure bash."""
    if is_template:
        # Unescaped ${...} here is JS interpolation, not bash source; in "..." / '...'
        # strings it is literal and must be kept.
        text = JS_INTERP_RE.sub("true", text)
    return text


def check_file(path: Path, bash_bin: str) -> list[str]:
    """Return list of error strings for one QML file."""
    errors: list[str] = []
    try:
        src = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        return [f"{path}: cannot read file: {exc}"]

    scripts_checked = 0
    for array_line, elements in _extract_command_arrays(src):
        for script_el in _extract_scripts(elements):
            body = _sanitize_script(script_el.text, script_el.is_template)
            if not body.strip():
                continue
            scripts_checked += 1
            result = subprocess.run(
                [bash_bin, "-n"],
                input=body.encode("utf-8"),
                capture_output=True,
                check=False,
            )
            if result.returncode != 0:
                detail = (result.stderr or result.stdout).decode("utf-8", "replace").strip()
                if not detail:
                    detail = "syntax error"
                errors.append(
                    f"{path}:{script_el.line} (command[] at line {array_line}): {detail}"
                )

    if errors:
        return errors
    if scripts_checked:
        ok(f"{path}: {scripts_checked} embedded script(s) OK")
    return []


def main(argv: list[str]) -> int:
    bash_bin = shutil.which("bash")
    if not bash_bin:
        warn("bash not found — skipping embedded bash syntax check")
        return 0

    if argv:
        targets = []
        for a in argv:
            p = Path(a)
            if not p.is_absolute():
                p = ROOT / p
            targets.append(p)
    else:
        targets = sorted(ROOT.rglob("*.qml"))

    files = []
    for t in targets:
        if t.is_dir():
            files.extend(sorted(t.rglob("*.qml")))
        elif t.suffix == ".qml":
            files.append(t)

    print(f"{BOLD}=== Embedded bash syntax check ({len(files)} QML files) ==={RESET}")
    all_errors: list[str] = []
    for f in files:
        all_errors.extend(check_file(f, bash_bin))

    for err in all_errors:
        error(err)

    print()
    if all_errors:
        print(f"{BOLD}{RED}{len(all_errors)} embedded bash error(s) found.{RESET}")
        return 1
    print(f"{BOLD}{GREEN}All embedded bash scripts parse cleanly.{RESET}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
