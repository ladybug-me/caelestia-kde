#!/usr/bin/env python3
r"""Check for unescaped bash parameter expansion inside QML template literals.

QML (like JavaScript) treats `` `...${...}...` `` as a template literal where
``${...}`` is evaluated as JavaScript before the string is used. Embedded bash
scripts therefore must escape a literal ``${`` as ``\${`` — e.g. ``${1#v}``
must be written ``\${1#v}``.

Leaving it unescaped makes the QML engine parse bash syntax as JavaScript and
fail with an error like ``Expected token ','``. Because every singleton that
transitively imports the broken file then reports "Type X unavailable", the
failure cascades across the whole shell (see shell/services/UpdateChecker.qml,
which shipped ``${1#v}`` unescaped and broke every singleton on load).

A backtick does the same in one step, and it is easier to do by accident: it is
the literal's own delimiter, so a stray one in a comment ends the script there.
That file has since been broken that way too, by a comment naming a command in
backticks - hence the second check below.

The fix for that broke it a third time, in a comment that explained the rule by
writing ``${...}``. Its body was ``...``, which is neither valid JavaScript nor
recognised bash, so the body check below let it through; the engine interpolated
it anyway and failed the file with ``Expected token 'numeric literal'``. That is
the reason for the comment rule: a comment is prose, so no interpolation in one
can be intended, and every unescaped ``${`` on a comment line inside a literal is
now flagged whatever its body looks like.

This checker scans every backtick template literal in QML files and flags
unescaped ``${...}`` in comments, unescaped backticks in comments, and unescaped
``${...}`` in code whose body is clearly bash parameter expansion rather than
valid JavaScript. Legitimate interpolation (identifiers, member access, calls,
ternaries) is left alone.

Usage:
    python3 check_qml_template_interp.py            # all *.qml under repo root
    python3 check_qml_template_interp.py <paths...> # specific files/dirs

Exit code is 1 if any offending interpolation is found.
"""

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

RED = "\033[0;31m"
GREEN = "\033[0;32m"
BOLD = "\033[1m"
RESET = "\033[0m"

# Bash parameter-expansion bodies, never valid JavaScript (a legitimate JS
# interpolation here is an identifier/member/call expression).
BASH_INTERP_RE = re.compile(
    r"#"            # ${#var} length, ${var#pat} / ${var##pat} removal, ${1#v}
    r"|%"           # ${var%pat} / ${var%%pat} removal
    r"|:-|:=|:\?|:\+"  # ${var:-def} ${var:=def} ${var:?err} ${var:+alt}
    r"|:[0-9]"      # ${var:0} / ${var:0:5} substring
    r"|\^"          # ${var^} / ${var^^} case conversion
    r"|,$"          # ${var,} / ${var,,} lowercase
    r"|\[[@*]\]"    # ${arr[@]} / ${arr[*]} array expansion
)


def _unescaped_interpolations(src: str) -> list[tuple[int, str, bool]]:
    """Return (offset, body, in_comment) for unescaped ${...} in backtick literals."""
    found: list[tuple[int, str, bool]] = []
    in_template = False
    line_start = 0
    i = 0
    n = len(src)
    while i < n:
        ch = src[i]
        if ch == "\\" and i + 1 < n:
            # Escaped char (\` or \${): skip both, so an escaped interpolation is not flagged.
            i += 2
            continue
        if ch == "\n":
            line_start = i + 1
            i += 1
            continue
        if ch == "`":
            in_template = not in_template
            i += 1
            continue
        if in_template and ch == "$" and i + 1 < n and src[i + 1] == "{":
            body_start = i + 2
            j = body_start
            depth = 1
            while j < n and depth > 0:
                if src[j] == "{":
                    depth += 1
                elif src[j] == "}":
                    depth -= 1
                j += 1
            body = src[body_start:j - 1]
            # On a comment line everything is prose: the engine interpolates it before bash sees
            # the script. Only body shape has to be judged in code.
            in_comment = src[line_start:i].lstrip().startswith("#")
            if in_comment or BASH_INTERP_RE.search(body):
                found.append((i, body, in_comment))
            i = j
            continue
        i += 1
    return found


def _line_col(src: str, offset: int) -> tuple[int, int]:
    """Return the 1-based line and column of an offset."""
    return src.count("\n", 0, offset) + 1, offset - src.rfind("\n", 0, offset)


def _backticks_in_template_comments(src: str) -> list[int]:
    """Return offsets of unescaped backticks sitting in a comment inside a literal.

    A backtick ends the literal it is in, so one written in a bash comment in the middle
    of an embedded script cuts the script short and the rest of the file stops being a
    string at all. The engine then reports the damage far from the cause - "Expected
    token ';'" - and every singleton importing the file reports its type unavailable.
    Prose is where this turns up: a comment naming a command in backticks.

    Only comments are checked. A backtick in the script's own code is command
    substitution and the author's business; the closing delimiter is on its own line.
    """
    found: list[int] = []
    in_template = False
    line_start = 0
    i = 0
    n = len(src)
    while i < n:
        ch = src[i]
        if ch == "\\" and i + 1 < n:
            i += 2
            continue
        if ch == "\n":
            line_start = i + 1
            i += 1
            continue
        if ch == "`":
            if in_template and src[line_start:i].lstrip().startswith("#"):
                found.append(i)
            in_template = not in_template
            i += 1
            continue
        i += 1
    return found


def check_file(path: Path) -> list[str]:
    """Return list of error strings for one QML file."""
    try:
        src = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        return [f"{path}: cannot read file: {exc}"]

    errors: list[str] = []
    for offset, body, in_comment in _unescaped_interpolations(src):
        line, col = _line_col(src, offset)
        if in_comment:
            errors.append(
                f"{path}:{line}:{col}: unescaped ${{{body}}} inside a comment within a "
                "template literal - QML interpolates it before bash sees the script, "
                "and a body like this is not valid QML, so the file stops parsing; "
                f"write \\${{{body}}} or reword the comment"
            )
        else:
            errors.append(
                f"{path}:{line}:{col}: unescaped bash parameter expansion "
                f"${{{body}}} inside a template literal - escape it as \\${{{body}}}"
            )
    for offset in _backticks_in_template_comments(src):
        line, col = _line_col(src, offset)
        errors.append(
            f"{path}:{line}:{col}: backtick inside a comment within a template literal - "
            "it ends the literal and the file stops parsing; drop it or write it as \\`"
        )
    return errors


def main(argv: list[str]) -> int:
    if argv:
        targets: list[Path] = []
        for arg in argv:
            p = Path(arg)
            if not p.is_absolute():
                p = ROOT / p
            targets.append(p)
    else:
        targets = [ROOT]

    files: list[Path] = []
    for t in targets:
        if t.is_dir():
            files.extend(sorted(t.rglob("*.qml")))
        elif t.suffix == ".qml":
            files.append(t)

    print(f"{BOLD}=== QML template interpolation check ({len(files)} files) ==={RESET}")
    all_errors: list[str] = []
    for f in files:
        all_errors.extend(check_file(f))

    for err in all_errors:
        print(f"{RED}[ERR]{RESET}  {err}")

    print()
    if all_errors:
        print(f"{BOLD}{RED}{len(all_errors)} unescaped bash interpolation(s) found.{RESET}")
        return 1
    print(f"{BOLD}{GREEN}No unescaped bash interpolation in QML template literals.{RESET}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
