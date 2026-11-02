#!/usr/bin/env python3
"""The disks the Storage page can act on, and the filesystems on them, as JSON.

`lsblk` is the source, because it is what udisks and GNOME Disks read as well. The
decision about what is worth showing is made here rather than in QML so it can be
tested: loop devices, zram, swap and device-mapper internals are not something anyone
mounts by hand.

The answer is nested, one row per disk with its filesystems under it, because every
action the page offers is a disk action: `udisksctl power-off` takes a disk, and a disk
with no filesystem at all — a stick that was never formatted, the usual thing to want
ejected — still has to be listed to be ejectable.

A filesystem mounted at a path the system needs is reported as `system`, so the page can
show it without offering to unmount it: unmounting `/` is not a thing a settings page
should be one click away from.
"""
from __future__ import annotations

import argparse
import json
import subprocess

FIELDS = "NAME,PATH,TYPE,FSTYPE,LABEL,MOUNTPOINTS,RM,HOTPLUG,RO,MODEL,SIZE,FSUSE%"
# Devices that can hold a filesystem. Optical media reports `rom` rather than `part`, both
# as a drive and as the disc in it.
DISK_TYPES = {"disk", "rom"}
MOUNTABLE_TYPES = {"part", "disk", "rom", "crypt"}
IGNORED_FSTYPES = {"swap"}
SWAP = "[SWAP]"

CRITICAL_MOUNTPOINTS = {
    "/", "/boot", "/boot/efi", "/usr", "/etc", "/var", "/var/tmp", "/var/log", "/opt", "/srv", "/root",
}


def read_devices(path: str | None) -> list:
    if path:
        with open(path, encoding="utf-8") as handle:
            return json.load(handle)["blockdevices"]

    result = subprocess.run(["lsblk", "-J", "-o", FIELDS], capture_output=True, text=True, check=True)
    return json.loads(result.stdout)["blockdevices"]


def walk(node: dict):
    yield node
    for child in node.get("children") or []:
        yield from walk(child)


def is_mountable(node: dict) -> bool:
    return node.get("type") in MOUNTABLE_TYPES and bool(node.get("fstype")) and node["fstype"] not in IGNORED_FSTYPES


def mountpoints(node: dict) -> list:
    found = node.get("mountpoints")
    if found is None:
        found = [node.get("mountpoint")] if node.get("mountpoint") else []
    return [point for point in found if point and point != SWAP]


def filesystem(node: dict) -> dict:
    points = mountpoints(node)
    return {
        "device": node.get("path") or f"/dev/{node['name']}",
        "label": node.get("label") or "",
        "fstype": node["fstype"],
        "size": node.get("size") or "",
        "use": node.get("fsuse%") or "",
        "mountpoints": points,
        "system": any(point in CRITICAL_MOUNTPOINTS for point in points),
        "readOnly": bool(node.get("ro")),
    }


def disk(node: dict) -> dict:
    filesystems = [filesystem(child) for child in walk(node) if is_mountable(child)]
    return {
        "device": node.get("path") or f"/dev/{node['name']}",
        "name": node.get("model") or node["name"],
        "removable": bool(node.get("rm")) or bool(node.get("hotplug")),
        "mounted": sum(1 for entry in filesystems if entry["mountpoints"]),
        "entries": filesystems,
    }


def disks(devices: list) -> list:
    found = []
    for node in devices:
        if node.get("type") not in DISK_TYPES:
            continue
        entry = disk(node)
        # A disk is a row if it has something to mount or something to eject. An unformatted
        # stick is exactly the thing someone wants to power off before pulling it out; zram,
        # and an optical drive with no disc in it, are not storage anyone can act on.
        if node.get("type") == "rom" and not entry["entries"]:
            continue
        if not entry["entries"] and not entry["removable"]:
            continue
        found.append(entry)
    found.sort(key=lambda item: (not item["removable"], item["device"]))
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--file", help="read lsblk JSON from a file instead of running it")
    args = parser.parse_args()

    print(json.dumps({"disks": disks(read_devices(args.file))}))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
