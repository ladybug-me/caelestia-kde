#!/usr/bin/env python3
"""Add a deterministic SHA-256 hash for a staged install tree.

The hash mirrors the scope of ``check_artifact_parity.py``: package-only paths
and compiled artifacts are left out, so it describes the packaging contract
rather than the build environment it happened to be produced in. The tree it is
given is the staging root, the same one the parity check compares.
"""

import hashlib
import json
import sys
from pathlib import Path

from packaging_contract import (
    PROVENANCE_RELATIVE,
    file_hash,
    is_compiled,
    is_package_only,
)


def root_hash(root: Path) -> str:
    """Hash every contract-carrying file below ``root``, path first."""
    digest = hashlib.sha256()
    for path in sorted(p for p in root.rglob("*") if p.is_file()):
        relative = path.relative_to(root).as_posix()
        if relative == PROVENANCE_RELATIVE or is_compiled(relative):
            continue
        if is_package_only(relative):
            continue
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(bytes.fromhex(file_hash(path)))
    return digest.hexdigest()


def update(metadata: Path, root: Path) -> None:
    data = json.loads(metadata.read_text(encoding="utf-8"))
    data["artifact_root_hash"] = root_hash(root)
    metadata.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("usage: write_provenance_hash.py METADATA ARTIFACT_ROOT")
    update(Path(sys.argv[1]), Path(sys.argv[2]))
