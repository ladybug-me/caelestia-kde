#!/usr/bin/env python3
"""Read and edit the XDG autostart entries, which is where log-in programs live.

Both halves matter: the list has to merge the system entries with the user's own copies and
report what a copy actually does (a `Hidden=true` stub in ~/.config/autostart is how a
system entry gets switched off), and an edit has to touch one key without rewriting
anything else in a file the user or a package owns.

  autostart.py --list
  autostart.py --set NAME on|off
  autostart.py --remove NAME
  autostart.py --add DESKTOP_ID

`--list` writes JSON; the other commands print nothing and exit non-zero on a name it does
not know. `NAME` is the desktop file's stem, which is what an entry is called here.
"""

import json
import os
import shutil
import sys
from pathlib import Path


def user_dir():
    return Path(os.environ.get("XDG_CONFIG_HOME", os.path.expanduser("~/.config"))) / "autostart"


def system_dirs():
    return [Path(directory) / "autostart" for directory in os.environ.get("XDG_CONFIG_DIRS", "/etc/xdg").split(":")]


def parse(path):
    """The keys of one desktop file, first occurrence winning, as XDG says."""
    entry = {}
    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return entry

    in_entry = False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith("["):
            in_entry = stripped == "[Desktop Entry]"
            continue
        if not in_entry or "=" not in stripped or stripped.startswith("#"):
            continue
        key, _, value = stripped.partition("=")
        entry.setdefault(key.strip(), value.strip())
    return entry


def enabled(entry):
    if entry.get("Hidden", "").lower() == "true":
        return False
    if entry.get("X-GNOME-Autostart-enabled", "").lower() == "false":
        return False
    return True


def entries():
    """Every entry, the user's copies taking precedence over the system ones."""
    system = {}
    for directory in reversed(system_dirs()):
        if not directory.is_dir():
            continue
        for path in sorted(directory.glob("*.desktop")):
            entry = parse(path)
            if entry.get("Type", "Application") == "Application":
                system[path.stem] = entry

    user = {}
    if user_dir().is_dir():
        for path in sorted(user_dir().glob("*.desktop")):
            entry = parse(path)
            if entry.get("Type", "Application") == "Application":
                user[path.stem] = entry

    listed = []
    for name in sorted(set(system) | set(user)):
        # A user copy of a system entry is an override, not a second entry: that is how a
        # system program gets switched off, so what it says wins while what it *is* stays.
        entry = user.get(name, system.get(name, {}))
        listed.append({
            "id": name,
            "name": entry.get("Name", name),
            "command": entry.get("Exec", ""),
            "icon": entry.get("Icon", ""),
            "enabled": enabled(entry),
            "system": name in system,
            "own": name in user,
        })

    # Read by name, not by file name: that is the column the page shows.
    listed.sort(key=lambda item: item["name"].casefold())
    return listed


def find_user_file(name):
    path = user_dir() / f"{name}.desktop"
    return path if path.is_file() else None


def find_any_file(name):
    """Where the entry comes from, so a system one can be copied into the user's directory."""
    for directory in system_dirs():
        path = directory / f"{name}.desktop"
        if path.is_file():
            return path
    return find_user_file(name)


def write_hidden(path, hidden):
    """Set `Hidden` in a desktop file, leaving every other line as it was."""
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError:
        return False

    lines = [line for line in lines if not line.strip().startswith("Hidden=")]
    if hidden:
        group = next((index for index, line in enumerate(lines) if line.strip() == "[Desktop Entry]"), -1)
        lines.insert(group + 1, "Hidden=true")

    path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return True


def set_enabled(name, want_enabled):
    source = find_any_file(name)
    if source is None:
        return False

    target = find_user_file(name)
    if target is None:
        # A system entry is switched off (or back on) through a copy of its own, which is
        # exactly what KDE's own settings do.
        if want_enabled:
            return True
        target = user_dir() / f"{name}.desktop"
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)

    return write_hidden(target, not want_enabled)


def remove(name):
    path = find_user_file(name)
    if path is None:
        return False

    path.unlink()
    return True


def add(desktop_id):
    """Copy an installed application's desktop file in, so it runs at log-in."""
    source = find_application(desktop_id)
    if source is None:
        return False

    target = user_dir() / f"{desktop_id}.desktop"
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, target)
    return write_hidden(target, False)


def find_application(desktop_id):
    data_home = Path(os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share")))
    data_dirs = [data_home] + [Path(directory) for directory in os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":")]
    for directory in data_dirs:
        path = directory / "applications" / f"{desktop_id}.desktop"
        if path.is_file():
            return path
    return None


def main(argv):
    if argv[:1] == ["--list"]:
        print(json.dumps(entries()))
        return 0

    if argv[:1] == ["--set"] and len(argv) == 3:
        return 0 if set_enabled(argv[1], argv[2] == "on") else 1

    if argv[:1] == ["--remove"] and len(argv) == 2:
        return 0 if remove(argv[1]) else 1

    if argv[:1] == ["--add"] and len(argv) == 2:
        return 0 if add(argv[1]) else 1

    print("usage: autostart.py --list | --set NAME on|off | --remove NAME | --add DESKTOP_ID", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
