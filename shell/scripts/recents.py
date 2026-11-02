#!/usr/bin/env python3
"""Recent documents, optionally only the ones a given application opened.

`recently-used.xbel` is the freedesktop list every toolkit writes to and Plasma's own
recent-documents runner reads, so the dock's jump list can show the same files. Each
bookmark records which applications opened it and when, which is what makes a
per-application list possible at all.

Parsing and choosing are kept apart: `parse` reports what the file says, and `select`
answers the question a caller actually asked. The order matters, because a file opened by
one application and then by another has one bookmark per visit — filtering on the app has
to happen before two visits are collapsed into one row, or the app that opened it first
loses its entry to the app that opened it last.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import xml.etree.ElementTree as ElementTree
from urllib.parse import unquote, urlparse
from urllib.request import url2pathname

BOOKMARK = "{http://www.freedesktop.org/standards/desktop-bookmarks}"
MIME = "{http://www.freedesktop.org/standards/shared-mime-info}"


def recent_file() -> str:
    base = os.environ.get("XDG_DATA_HOME") or os.path.join(os.path.expanduser("~"), ".local", "share")
    return os.path.join(base, "recently-used.xbel")


def normalise(name: str) -> str:
    """`org.kde.spectacle.desktop` and `org.kde.spectacle` name the same application."""
    name = name.strip()
    if name.endswith(".desktop"):
        name = name[: -len(".desktop")]
    return name.lower()


def short_name(name: str) -> str:
    return normalise(name).rsplit(".", 1)[-1]


def matches(app: str, targets: set) -> bool:
    return normalise(app) in targets or short_name(app) in targets


def local_path(href: str) -> str:
    """The file a `file://` bookmark points at, or "" for one on another host.

    The path is collapsed to one leading slash first: a writer that hands out
    `file:////home/…` is common enough, and POSIX `url2pathname` refuses a path that
    starts with two.
    """
    parsed = urlparse(href)
    if parsed.netloc not in ("", "localhost"):
        return ""
    return url2pathname(re.sub(r"^/+", "/", unquote(parsed.path)))


def parse(path: str) -> list:
    """Every bookmark that still points at a file, with the applications that opened it."""
    if not os.path.exists(path):
        return []

    try:
        root = ElementTree.parse(path).getroot()
    except ElementTree.ParseError:
        return []

    entries = []
    for bookmark in root.iter("bookmark"):
        href = bookmark.get("href", "")
        if not href.startswith("file://"):
            continue

        file_path = local_path(href)
        if not file_path or not os.path.isfile(file_path):
            continue

        applications = {}
        for element in bookmark.iter(f"{BOOKMARK}application"):
            name = element.get("name", "")
            if name:
                applications[name] = max(applications.get(name, ""), element.get("modified", ""))

        mime = bookmark.find(f".//{MIME}mime-type")
        entries.append(
            {
                "name": os.path.basename(file_path),
                "path": file_path,
                "uri": href,
                "mime": mime.get("type", "") if mime is not None else "",
                "modified": bookmark.get("modified", ""),
                "apps": applications,
            }
        )

    return entries


def visit(entry: dict, targets: set | None) -> str | None:
    """When this application opened the file, or None if it never did."""
    if targets is None:
        return entry["modified"]

    stamps = [stamp or entry["modified"] for app, stamp in entry["apps"].items() if matches(app, targets)]
    return max(stamps) if stamps else None


def select(entries: list, targets: set | None, limit: int) -> list:
    """One row per file, newest visit first, as this application saw it."""
    chosen = {}
    for entry in entries:
        stamp = visit(entry, targets)
        if stamp is None:
            continue
        known = chosen.get(entry["path"])
        if known is None or stamp > known[0]:
            chosen[entry["path"]] = (stamp, entry)

    ordered = sorted(chosen.values(), key=lambda pair: pair[0], reverse=True)
    return [{**entry, "modified": stamp, "apps": sorted(entry["apps"])} for stamp, entry in ordered[: max(0, limit)]]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--limit", type=int, default=10, help="how many entries to print")
    parser.add_argument("--app", action="append", default=[], help="only files this application opened")
    parser.add_argument("--file", help="read this xbel file instead of the user's")
    args = parser.parse_args()

    targets = None
    if args.app:
        targets = {normalise(name) for name in args.app} | {short_name(name) for name in args.app}

    print(json.dumps(select(parse(args.file or recent_file()), targets, args.limit)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
