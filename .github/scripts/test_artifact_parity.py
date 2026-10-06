#!/usr/bin/env python3

import tempfile
import unittest
from pathlib import Path

from check_artifact_parity import compare_trees, main
from packaging_contract import PACKAGE_ONLY_PREFIXES


class ArtifactParityTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tempdir = tempfile.TemporaryDirectory()
        root = Path(self.tempdir.name)
        self.left = root / "left"
        self.right = root / "right"
        self.left.mkdir()
        self.right.mkdir()

    def tearDown(self) -> None:
        self.tempdir.cleanup()

    def write_both(self, relative: str, content: str) -> None:
        for root in (self.left, self.right):
            path = root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8")

    def write_right_only(self, relative: str, content: str) -> None:
        path = self.right / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")

    def test_identical_trees_pass(self) -> None:
        self.write_both("usr/bin/caelestia", "#!/bin/sh\n")
        self.assertEqual([], compare_trees(self.left, self.right))

    def test_missing_file_fails(self) -> None:
        self.write_both("usr/lib/caelestia/module", "module")
        (self.right / "usr/lib/caelestia/module").unlink()
        self.assertEqual(
            ["missing from right tree: usr/lib/caelestia/module"],
            compare_trees(self.left, self.right),
        )

    def test_hash_drift_fails(self) -> None:
        self.write_both("etc/xdg/quickshell/caelestia/shell.qml", "old")
        (self.right / "etc/xdg/quickshell/caelestia/shell.qml").write_text(
            "new", encoding="utf-8"
        )
        failures = compare_trees(self.left, self.right)
        self.assertEqual(1, len(failures))
        self.assertIn("hash mismatch: etc/xdg/quickshell/caelestia/shell.qml", failures[0])

    def test_compiled_artifacts_are_compared_by_presence_only(self) -> None:
        """Two build trees differ in every .so; that is not packaging drift."""
        library = "usr/lib/qt6/qml/Caelestia/lib/libcaelestia-core.so"
        self.write_both(library, "build-source")
        (self.right / library).write_text("build-package", encoding="utf-8")
        self.assertEqual([], compare_trees(self.left, self.right))

    def test_missing_compiled_artifact_still_fails(self) -> None:
        library = "usr/lib/qt6/qml/Caelestia/lib/libcaelestia-core.so"
        self.write_both(library, "binary")
        (self.right / library).unlink()
        self.assertEqual(
            [f"missing from right tree: {library}"],
            compare_trees(self.left, self.right),
        )

    def test_cli_allows_the_package_only_paths_the_contract_declares(self) -> None:
        """Every declared prefix has to cover real package content, and passing
        the contract explicitly has to mean the same thing as defaulting to it."""
        self.write_both("usr/share/caelestia/shell.qml", "qml")
        for prefix in PACKAGE_ONLY_PREFIXES:
            self.write_right_only(f"{prefix}/content", "package only")

        self.assertEqual(0, main([str(self.left), str(self.right)]))
        self.assertEqual([], compare_trees(self.left, self.right, set(PACKAGE_ONLY_PREFIXES)))
        self.assertEqual(
            sorted(f"unexpected in right tree: {prefix}/content" for prefix in PACKAGE_ONLY_PREFIXES),
            sorted(compare_trees(self.left, self.right, set())),
        )

    def test_cli_rejects_undocumented_extra(self) -> None:
        self.write_both("usr/bin/caelestia", "binary")
        self.write_right_only("etc/sddm.conf.d/zz-caelestia.conf", "[Theme]\nCurrent=caelestia\n")
        self.assertEqual(1, main([str(self.left), str(self.right)]))


if __name__ == "__main__":
    unittest.main()
