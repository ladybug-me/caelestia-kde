#!/usr/bin/env python3
"""Read and write the proxy KDE applications use.

Plasma stores the system proxy in `kioslaverc` under `[Proxy Settings]`, and every KIO
application reads it from there, so that file is the thing to edit: setting environment
variables would only reach programs started afterwards. The file also holds unrelated
sections, which is why this edits keys in place instead of rewriting it from a parser
that would drop comments and unknown keys.
"""
from __future__ import annotations

import argparse
import json
import os
import stat
import sys
import tempfile

SECTION = "[Proxy Settings]"
MODES = {"none": 0, "manual": 1, "pac": 2, "auto": 3, "env": 4}
MODE_NAMES = {value: key for key, value in MODES.items()}
KEYS = {
    "http": "httpProxy",
    "https": "httpsProxy",
    "ftp": "ftpProxy",
    "socks": "socksProxy",
    "noProxy": "noProxyFor",
    "pac": "Proxy Config Script",
}


def config_path() -> str:
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.join(os.path.expanduser("~"), ".config")
    return os.path.join(base, "kioslaverc")


def read_lines(path: str) -> list:
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as handle:
        return handle.read().splitlines()


def section_bounds(lines: list) -> tuple:
    """Start and end offsets of the proxy section, or where a new one belongs."""
    for index, line in enumerate(lines):
        if line.strip() == SECTION:
            end = index + 1
            while end < len(lines) and not lines[end].lstrip().startswith("["):
                end += 1
            return index, end
    return -1, -1


def section_values(lines: list) -> dict:
    start, end = section_bounds(lines)
    values = {}
    if start < 0:
        return values
    for line in lines[start + 1 : end]:
        if "=" in line:
            key, _, value = line.partition("=")
            values[key.strip()] = value.strip()
    return values


def write_key(lines: list, key: str, value: str) -> list:
    start, end = section_bounds(lines)
    if start < 0:
        if lines and lines[-1].strip() != "":
            lines.append("")
        lines.extend([SECTION, f"{key}={value}"])
        return lines

    for index in range(start + 1, end):
        if lines[index].partition("=")[0].strip() == key:
            lines[index] = f"{key}={value}"
            return lines

    # Append after the section's last real key, so the blank line that separates the
    # section from the next header stays where it was.
    insert_at = end
    while insert_at > start + 1 and lines[insert_at - 1].strip() == "":
        insert_at -= 1
    lines.insert(insert_at, f"{key}={value}")
    return lines


def current(lines: list) -> dict:
    values = section_values(lines)
    proxy_type = values.get("ProxyType", "0")
    settings = {"mode": MODE_NAMES.get(int(proxy_type) if proxy_type.lstrip("-").isdigit() else 0, "none")}
    for name, key in KEYS.items():
        settings[name] = values.get(key, "")
    return settings


def save(path: str, lines: list) -> None:
    """Replace the file in one step, so a failure cannot leave it half written.

    `kioslaverc` is the only copy of settings other applications read, and truncating it
    in place leaves a window in which a reader sees an empty file — or, after a crash, a
    permanently empty one.
    """
    directory = os.path.dirname(path) or "."
    os.makedirs(directory, exist_ok=True)
    mode = stat.S_IMODE(os.stat(path).st_mode) if os.path.exists(path) else 0o644

    handle_fd, temporary = tempfile.mkstemp(dir=directory, prefix=".kioslaverc.")
    try:
        with os.fdopen(handle_fd, "w", encoding="utf-8") as handle:
            handle.write("\n".join(lines).rstrip("\n") + "\n")
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    except BaseException:
        os.unlink(temporary)
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--get", action="store_true", help="print the current proxy settings as JSON")
    parser.add_argument("--set-mode", choices=sorted(MODES), help="how the proxy is chosen")
    parser.add_argument("--set", nargs=2, metavar=("KEY", "VALUE"), action="append", default=[], help="set one value")
    args = parser.parse_args()

    path = config_path()
    lines = read_lines(path)

    if args.set:
        for key, value in args.set:
            if key not in KEYS:
                print(f"unknown key: {key} (one of {', '.join(sorted(KEYS))})", file=sys.stderr)
                return 2
            lines = write_key(lines, KEYS[key], value)

    if args.set_mode:
        lines = write_key(lines, "ProxyType", str(MODES[args.set_mode]))

    if args.set or args.set_mode:
        save(path, lines)
        return 0

    settings = current(lines)
    settings["file"] = path
    print(json.dumps(settings))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
