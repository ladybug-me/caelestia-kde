#!/usr/bin/env python3
"""The packaging contract shared by the artifact checks.

``CAELESTIA_PACKAGE=ON`` installs repository assets that the source layout does
not - see the ``if(CAELESTIA_PACKAGE)`` block in ``shell/CMakeLists.txt``. The
parity check and the provenance hash both have to agree on which paths those
are, so they are declared here once instead of being repeated for every caller.

Every path is relative to the staging root - the ``DESTDIR`` tree a build
installs into, holding ``usr/`` and ``etc/`` side by side. That is the only root
that covers the whole install; a ``usr/`` root leaves the package's half of
``etc/xdg/quickshell/caelestia`` outside the checks, which is exactly where
``CAELESTIA_PACKAGE=ON`` adds the icon set.

Compiled artifacts sit outside the contract on purpose. Their bytes depend on
the build directory and the toolchain rather than on the packaging layout, so
the checks compare them by presence only. Hashing them would measure build
reproducibility, not packaging drift.
"""

from __future__ import annotations

import hashlib
from collections.abc import Iterable
from pathlib import Path

# Installed only by CAELESTIA_PACKAGE=ON, relative to the staging root.
# Keep in step with the if(CAELESTIA_PACKAGE) block in shell/CMakeLists.txt:
# the icons land under INSTALL_QSCONFDIR, which is etc/xdg, not usr/share.
PACKAGE_ONLY_PREFIXES = (
    "etc/xdg/quickshell/caelestia/assets/icons",
    "usr/share/plasma/shells/caelestia.desktop",
    "usr/share/sddm/themes/caelestia",
)

COMPILED_SUFFIXES = (".so", ".dylib", ".dll")

PROVENANCE_RELATIVE = "usr/share/caelestia/build-provenance.json"


def file_hash(path: Path) -> str:
    """Return the SHA-256 digest of a file's contents."""
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def files_under(root: Path) -> dict[str, Path]:
    """Map every file below ``root`` to its posix relative path."""
    return {
        path.relative_to(root).as_posix(): path
        for path in root.rglob("*")
        if path.is_file()
    }


def matches_prefix(relative: str, prefixes: Iterable[str]) -> bool:
    """True when ``relative`` is one of ``prefixes`` or lives underneath one."""
    return any(
        relative == prefix or relative.startswith(f"{prefix}/")
        for prefix in prefixes
    )


def is_package_only(relative: str) -> bool:
    """True for paths the package layout adds on top of the source layout."""
    return matches_prefix(relative, PACKAGE_ONLY_PREFIXES)


def is_compiled(relative: str) -> bool:
    """True for artifacts whose bytes are build-environment dependent."""
    return relative.endswith(COMPILED_SUFFIXES)
