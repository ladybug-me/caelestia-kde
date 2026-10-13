#!/usr/bin/env python3
"""Compare two staged install trees by relative paths and content hashes.

Every file must line up in both directions. Content is compared for the files
that carry the packaging contract; compiled artifacts are compared by presence
only, since their bytes depend on the build directory and toolchain rather than
on the packaging layout. Both roots are staging roots, not install prefixes, so
the comparison covers the whole install. See ``packaging_contract`` for the
details.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from packaging_contract import (
    PACKAGE_ONLY_PREFIXES,
    file_hash,
    files_under,
    is_compiled,
    matches_prefix,
)


def compare_trees(
    left: Path,
    right: Path,
    allowed_right_only_prefixes: set[str] | None = None,
) -> list[str]:
    """Return parity failures, allowing the packaging contract's extra paths."""
    allowed_prefixes = (
        allowed_right_only_prefixes
        if allowed_right_only_prefixes is not None
        else set(PACKAGE_ONLY_PREFIXES)
    )
    left_files = files_under(left)
    right_files = files_under(right)
    failures: list[str] = []

    for relative in sorted(left_files.keys() - right_files.keys()):
        failures.append(f"missing from right tree: {relative}")
    for relative in sorted(right_files.keys() - left_files.keys()):
        if matches_prefix(relative, allowed_prefixes):
            continue
        failures.append(f"unexpected in right tree: {relative}")
    for relative in sorted(left_files.keys() & right_files.keys()):
        if is_compiled(relative):
            continue
        left_hash = file_hash(left_files[relative])
        right_hash = file_hash(right_files[relative])
        if left_hash != right_hash:
            failures.append(f"hash mismatch: {relative} ({left_hash} != {right_hash})")
    return failures


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("left", type=Path, help="source/reference staging root")
    parser.add_argument("right", type=Path, help="package/release staging root")
    parser.add_argument(
        "--allow-right-only-prefix",
        action="append",
        default=list(PACKAGE_ONLY_PREFIXES),
        metavar="PATH",
        help="right-only relative path allowed by the packaging contract (repeatable)",
    )
    args = parser.parse_args(argv)

    for root in (args.left, args.right):
        if not root.is_dir():
            print(f"staging root is not a directory: {root}", file=sys.stderr)
            return 2

    failures = compare_trees(
        args.left,
        args.right,
        set(args.allow_right_only_prefix),
    )
    if failures:
        print("Artifact parity check failed:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1

    left_files = files_under(args.left)
    compiled = sum(1 for relative in left_files if is_compiled(relative))
    print(
        f"Artifact parity check passed: {args.left} == {args.right} "
        f"({len(left_files)} files, {compiled} compiled compared by presence)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
