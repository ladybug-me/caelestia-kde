#!/usr/bin/env bash
# suite: fast

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/helpers.sh"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/shell/scripts/disks.py"
SERVICE="$REPO_ROOT/shell/services/Disks.qml"
PAGE="$REPO_ROOT/shell/modules/nexus/pages/StoragePage.qml"
DICTIONARY="$REPO_ROOT/shell/modules/nexus/PageDictionary.qml"
REGISTRY="$REPO_ROOT/shell/modules/nexus/PageCompRegistry.qml"
PYTHON="$(command -v python3 || command -v python)"

TMP="$("$PYTHON" -c 'import tempfile; print(tempfile.mkdtemp())')"
trap 'rm -rf "$TMP"' EXIT

# A laptop disk with a swap partition, a USB stick, a stick formatted without a partition
# table, a stick that was never formatted, an optical drive with a disc and one without, and
# the plumbing lsblk also reports: loop devices and zram.
prepare() {
    "$PYTHON" - "$TMP/lsblk.json" <<'PY'
import json
import sys


def part(name, fstype, mountpoints, size, use, label=None):
    return {
        "name": name, "path": f"/dev/{name}", "type": "part", "fstype": fstype, "label": label,
        "mountpoints": mountpoints, "rm": False, "hotplug": False, "ro": False,
        "size": size, "fsuse%": use,
    }


data = {
    "blockdevices": [
        {
            "name": "sda", "path": "/dev/sda", "type": "disk", "fstype": None, "label": None,
            "mountpoints": [], "rm": False, "hotplug": False, "ro": False, "model": "Samsung SSD", "size": "931.5G",
            "children": [
                part("sda1", "vfat", ["/boot"], "1G", "12%", "ESP"),
                part("sda2", "ext4", ["/", "/var/tmp"], "930G", "41%", "root"),
                part("sda3", "swap", ["[SWAP]"], "8G", None, "swap"),
            ],
        },
        {"name": "loop0", "path": "/dev/loop0", "type": "loop", "fstype": "squashfs", "label": None,
         "mountpoints": ["/snap/core"], "rm": False, "hotplug": False, "ro": True, "model": None, "size": "128M"},
        {"name": "zram0", "path": "/dev/zram0", "type": "disk", "fstype": None, "label": None,
         "mountpoints": ["[SWAP]"], "rm": False, "hotplug": False, "ro": False, "model": None, "size": "4G"},
        {
            "name": "sdb", "path": "/dev/sdb", "type": "disk", "fstype": None, "label": None,
            "mountpoints": [], "rm": True, "hotplug": True, "ro": False, "model": "USB Stick", "size": "57.3G",
            "children": [part("sdb1", "exfat", [], "57.3G", None, "Backup")],
        },
        {"name": "sdc", "path": "/dev/sdc", "type": "disk", "fstype": "ext4", "label": "Whole disk",
         "mountpoints": ["/mnt/whole"], "rm": False, "hotplug": True, "ro": False, "model": "Portable",
         "size": "14.6G", "fsuse%": "3%"},
        {"name": "sdd", "path": "/dev/sdd", "type": "disk", "fstype": None, "label": None,
         "mountpoints": [], "rm": True, "hotplug": True, "ro": False, "model": "Blank stick", "size": "7.5G"},
        {"name": "sr0", "path": "/dev/sr0", "type": "rom", "fstype": "iso9660", "label": "INSTALL",
         "mountpoints": ["/run/media/camus/INSTALL"], "rm": True, "hotplug": False, "ro": True,
         "model": "DVD-RW", "size": "1.4G", "fsuse%": None},
        {"name": "sr1", "path": "/dev/sr1", "type": "rom", "fstype": None, "label": None,
         "mountpoints": [], "rm": True, "hotplug": False, "ro": False, "model": "DVD-ROM", "size": "1024M"},
    ]
}

with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(data, handle)
PY
    "$PYTHON" "$SCRIPT" --file "$TMP/lsblk.json" > "$TMP/out.json"
}

# The answer is nested - one row per disk, its filesystems under it - because ejecting acts
# on a disk and mounting acts on a filesystem. Git Bash rewrites a bare /dev/... argument
# into a Windows device path before Python sees it, so devices are named without the prefix.
disk_fields() {
    local device="$1"
    shift
    "$PYTHON" - "$TMP/out.json" "$device" "$@" <<'PY'
import json
import sys

disks = json.load(open(sys.argv[1], encoding="utf-8"))["disks"]
device, keys = f"/dev/{sys.argv[2].rsplit('/', 1)[-1]}", sys.argv[3:]
match = next((disk for disk in disks if disk["device"] == device), None)
print("missing" if match is None else " ".join(f"{key}={match[key]}" for key in keys))
PY
}

filesystem_fields() {
    local device="$1" filesystem="$2"
    shift 2
    "$PYTHON" - "$TMP/out.json" "$device" "$filesystem" "$@" <<'PY'
import json
import sys

disks = json.load(open(sys.argv[1], encoding="utf-8"))["disks"]
device = f"/dev/{sys.argv[2].rsplit('/', 1)[-1]}"
wanted = f"/dev/{sys.argv[3].rsplit('/', 1)[-1]}"
keys = sys.argv[4:]
disk = next((entry for entry in disks if entry["device"] == device), None)
match = None if disk is None else next((entry for entry in disk["entries"] if entry["device"] == wanted), None)
print("missing" if match is None else " ".join(f"{key}={match[key]}" for key in keys))
PY
}

listed() {
    "$PYTHON" - "$TMP/out.json" <<'PY'
import json
import sys

print(" ".join(disk["device"] for disk in json.load(open(sys.argv[1], encoding="utf-8"))["disks"]))
PY
}

test_the_plumbing_is_left_out() {
    prepare

    assert_eq "/dev/sdb /dev/sdc /dev/sdd /dev/sr0 /dev/sda" "$(listed)" \
        "removable media comes first, and loop devices, zram and an optical drive with no disc are not storage anyone acts on"
}

test_a_disk_carries_what_is_true_of_the_whole_disk() {
    prepare

    assert_eq "name=USB Stick removable=True mounted=0" "$(disk_fields sdb name removable mounted)" \
        "the disk is the row that gets ejected, so its name and its removable flag live on it, not copied onto every filesystem"
    assert_eq "name=Samsung SSD removable=False mounted=2" "$(disk_fields sda name removable mounted)" \
        "mounted counts the filesystems that are mounted right now"
    assert_eq "label=Backup fstype=exfat mountpoints=[] system=False" \
        "$(filesystem_fields sdb sdb1 label fstype mountpoints system)" \
        "and a filesystem is only about itself"
}

test_the_filesystems_the_system_needs_are_marked() {
    prepare

    assert_eq "system=True mountpoints=['/', '/var/tmp']" "$(filesystem_fields sda sda2 system mountpoints)" \
        "the page shows these without offering to unmount them"
    assert_eq "system=False" "$(filesystem_fields sdc sdc system)" "a filesystem mounted by hand is not the system"
}

test_a_whole_disk_filesystem_is_listed_too() {
    prepare

    assert_eq "use=3% mountpoints=['/mnt/whole']" "$(filesystem_fields sdc sdc use mountpoints)" \
        "a stick formatted without a partition table has no children to walk into"
}

test_an_unformatted_disk_is_still_ejectable() {
    prepare

    assert_eq "name=Blank stick removable=True mounted=0 entries=[]" "$(disk_fields sdd name removable mounted entries)" \
        "a stick that was never formatted is exactly the one someone wants to power off before pulling it out"
}

test_an_optical_drive_is_listed_only_with_a_disc() {
    prepare

    assert_eq "name=DVD-RW removable=True mounted=1" "$(disk_fields sr0 name removable mounted)" \
        "optical media reports type rom, not disk, and holds a filesystem like any other"
    assert_eq "missing" "$(disk_fields sr1 name)" "an empty drive has nothing to mount and nothing to power off"
}

test_a_source_that_cannot_be_read_fails_rather_than_reporting_no_disks() {
    local status=0
    "$PYTHON" "$SCRIPT" --file "$TMP/does-not-exist.json" > "$TMP/out.json" 2> "$TMP/err.txt" || status=$?

    assert_ne 0 "$status" "a page must be able to tell a broken script from an empty machine"
    assert_eq "" "$(cat "$TMP/out.json")" "and it must not print a list that says there is nothing to show"
}

test_mounting_goes_through_udisks() {
    assert_file_contains "$SERVICE" '["udisksctl", "mount", "-b", device]' \
        "mounting has to be the polkit-checked path, not a plain mount"
    assert_file_contains "$SERVICE" '["udisksctl", "unmount", "-b", device]' "unmounting likewise"
    assert_file_contains "$SERVICE" '["udisksctl", "power-off", "-b", device]' \
        "and a disk, not a partition, is what gets powered off"
    assert_file_contains "$SERVICE" 'script: "scripts/disks.py"' \
        "the service reads the same list this test exercises, through the one JSON-script reader"
}

test_the_page_is_reachable() {
    assert_file_exists "$PAGE"
    assert_file_contains "$DICTIONARY" '"storage":' "the page needs a dictionary entry"
    assert_file_contains "$REGISTRY" 'key: "storage"' "and a component slot"
    assert_file_contains "$PAGE" 'Disks.refresh()' "the list is re-read when the page is shown"
    assert_file_contains "$PAGE" 'Disks.eject(diskSection.disk.device)' "ejecting asks for the disk, not one of its filesystems"
    assert_file_contains "$PAGE" 'visible: Disks.lastError !== ""' "a failure is shown instead of an empty list"
}

run_tests
