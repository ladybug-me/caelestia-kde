#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2024 ladybug-me
# SPDX-License-Identifier: GPL-3.0-or-later

import json
import os
import pwd


def find_logo(logo_id: str) -> str:
    """Search standard icon directories for the distro SVG logo."""
    candidates = [
        f"/usr/share/icons/{logo_id}.svg",
        f"/usr/share/pixmaps/{logo_id}.svg",
        f"/usr/share/icons/hicolor/scalable/apps/{logo_id}.svg",
        "/usr/share/icons/hicolor/scalable/apps/distributor-logo.svg",
        "/usr/share/pixmaps/distributor-logo.svg",
    ]
    for path in candidates:
        if os.path.isfile(path):
            return "file://" + path
    return ""


def read_os_release() -> dict:
    """Parse /etc/os-release into a dict, stripping surrounding quotes."""
    result = {}
    try:
        with open("/etc/os-release") as f:
            for line in f:
                line = line.strip()
                if "=" in line:
                    k, v = line.split("=", 1)
                    result[k] = v.strip('"')
    except OSError:
        pass
    return result


def format_uptime(seconds: float) -> str:
    s = int(seconds)
    h = s // 3600
    m = (s % 3600) // 60
    if h > 0:
        return f"{h} hours, {m} mins"
    return f"{m} mins"


def current_user() -> str:
    user = os.environ.get("USER") or os.environ.get("LOGNAME") or ""
    if not user:
        try:
            user = pwd.getpwuid(os.getuid()).pw_name
        except KeyError:
            user = "user"
    return user


def main() -> None:
    d = read_os_release()
    os_name = d.get("PRETTY_NAME") or d.get("NAME") or "Linux"
    logo_id = d.get("LOGO") or d.get("ID") or "linux"

    logo_path = find_logo(logo_id)

    try:
        with open("/proc/uptime") as f:
            uptime_secs = float(f.read().split()[0])
        uptime = format_uptime(uptime_secs)
    except OSError:
        uptime = "unknown"

    print(json.dumps({
        "os":       os_name,
        "wm":       "KDE",
        "user":     current_user(),
        "uptime":   uptime,
        "id":       logo_id,
        "logoPath": logo_path,
    }))


if __name__ == "__main__":
    main()
