#!/usr/bin/env python3
"""Report which outputs advertise an HDR transfer function, from their EDID.

KScreen accepts any HDR request and keeps it in its config whether or not the panel can
show the result, so the capability cannot be read back from the compositor. The panel's own
EDID can: an HDR Static Metadata block whose transfer functions include SMPTE ST 2084 (PQ,
what HDR10 uses) or HLG is a screen that can show an HDR signal, while a block that only
describes the SDR range is not.

With no arguments it reads every connector in /sys/class/drm; `--file PATH` reads a single
EDID, which is what the tests use. It is dependency-free on purpose: edid-decode is not
installed everywhere and one data block is all this needs.
"""

import glob
import json
import os
import sys

CTA_EXTENSION = 0x02
EXTENDED_TAG = 0x07
HDR_STATIC_METADATA = 0x06
# Bit 2 of the transfer-function byte is PQ, bit 3 is HLG.
HDR_TRANSFER_FUNCTIONS = 0x0C

EDID_HEADER = b"\x00\xff\xff\xff\xff\xff\xff\x00"


def output_name(path):
    """`/sys/class/drm/card0-eDP-1/edid` describes the connector KScreen calls `eDP-1`."""
    parent = os.path.basename(os.path.dirname(path))
    if parent.startswith("card"):
        return parent.split("-", 1)[-1]

    return os.path.splitext(os.path.basename(path))[0]


def read_edid(path):
    try:
        with open(path, "rb") as handle:
            data = handle.read()
    except OSError:
        return b""

    return data if data[:8] == EDID_HEADER else b""


def data_blocks(block):
    """The CTA-861 data blocks of one extension block, as (tag, payload) pairs."""
    if len(block) < 4 or block[0] != CTA_EXTENSION:
        return

    end = min(block[2], len(block))
    position = 4
    while position < end:
        header = block[position]
        length = header & 0x1F
        payload = block[position + 1:position + 1 + length]
        if len(payload) < length:
            return
        yield (header >> 5) & 0x07, payload
        position += 1 + length


def supports_hdr(data):
    if len(data) < 128:
        return False

    for index in range(1, data[126] + 1):
        for tag, payload in data_blocks(data[index * 128:(index + 1) * 128]):
            if tag == EXTENDED_TAG and len(payload) >= 2 and payload[0] == HDR_STATIC_METADATA:
                if payload[1] & HDR_TRANSFER_FUNCTIONS:
                    return True

    return False


def main(argv):
    paths = argv[1:2] if argv[:1] == ["--file"] else sorted(glob.glob("/sys/class/drm/*/edid"))

    reports = []
    for path in paths:
        data = read_edid(path)
        if data:
            reports.append({"output": output_name(path), "hdr": supports_hdr(data)})

    print(json.dumps(reports))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
