#!/usr/bin/env python3
"""Verify that a release archive exactly represents its staged release tree."""

from __future__ import annotations

import argparse
import tarfile
import tempfile
from pathlib import Path

from packaging_contract import file_hash, files_under


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive", type=Path)
    parser.add_argument("staged_root", type=Path)
    args = parser.parse_args()

    if not args.archive.is_file():
        parser.error(f"archive does not exist: {args.archive}")
    if not args.staged_root.is_dir():
        parser.error(f"staged root does not exist: {args.staged_root}")

    expected = files_under(args.staged_root)
    with tempfile.TemporaryDirectory() as temporary:
        extracted = Path(temporary)
        with tarfile.open(args.archive, "r:gz") as archive:
            for member in archive.getmembers():
                target = extracted / member.name
                if member.name.startswith("/") or ".." in Path(member.name).parts:
                    raise SystemExit(f"unsafe archive member: {member.name}")
                if not target.resolve().is_relative_to(extracted.resolve()):
                    raise SystemExit(f"archive member escapes extraction root: {member.name}")
            archive.extractall(extracted)

        actual = files_under(extracted)
        if set(expected) != set(actual):
            missing = sorted(set(expected) - set(actual))
            extra = sorted(set(actual) - set(expected))
            raise SystemExit(f"archive path mismatch: missing={missing} extra={extra}")

        for relative_path in sorted(expected):
            if file_hash(expected[relative_path]) != file_hash(actual[relative_path]):
                raise SystemExit(f"archive content mismatch: {relative_path}")

    print(f"release archive verified: {len(expected)} files")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
