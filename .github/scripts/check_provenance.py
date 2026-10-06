#!/usr/bin/env python3
"""Validate the path-independent fields required in build provenance metadata."""

import json
import re
import sys
from pathlib import Path


REQUIRED_FIELDS = {
    "source_revision",
    "dependency_revision",
    "build_type",
    "compiler",
    "cmake_version",
    "qt_version",
    "hash_algorithm",
    "artifact_root_hash",
}


def validate(path: Path) -> list[str]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        return [f"could not parse {path}: {exc}"]

    failures = [f"missing provenance field: {field}" for field in sorted(REQUIRED_FIELDS - data.keys())]
    for field in ("source_revision", "dependency_revision"):
        value = data.get(field, "")
        if value != "unknown" and not re.fullmatch(r"[0-9a-f]{40}", value):
            failures.append(f"{field} must be a full revision or unknown")
    if data.get("hash_algorithm") != "sha256":
        failures.append("hash_algorithm must be sha256")
    if not re.fullmatch(r"[0-9a-f]{64}", data.get("artifact_root_hash", "")):
        failures.append("artifact_root_hash must be a SHA-256 digest")
    return failures


def main() -> int:
    failures = validate(Path(sys.argv[1])) if len(sys.argv) == 2 else ["usage: check_provenance.py FILE"]
    if failures:
        print("\n".join(failures), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
