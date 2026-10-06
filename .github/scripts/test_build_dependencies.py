#!/usr/bin/env python3
"""Build dependency manifest tests.

`packaging/build-dependencies.json` is the one declaration of the Arch packages
the shell build and its QML runtime need, and the CI action installs exactly what
it lists. Only the distribution CI actually installs on is recorded: a column for
a distribution nothing reads is a second copy of the installer's own package
lists, and it cannot be the thing that fails when it drifts. The manifest grows a
distribution when a consumer for it exists.
"""

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

MANIFEST = ROOT / "packaging" / "build-dependencies.json"
INSTALL_DEPS_ACTION = ROOT / ".github" / "actions" / "install-build-deps" / "action.yml"

# The action has to install python before it can read the manifest, so that one
# package is the only one allowed to appear in the action itself.
BOOTSTRAP_PACKAGES = {"python"}

PACKAGE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9+._-]*$")


def load_packages() -> list[str]:
    return json.loads(MANIFEST.read_text(encoding="utf-8"))["arch"]


class BuildDependencyManifestTests(unittest.TestCase):
    def test_the_manifest_names_packages(self) -> None:
        self.assertTrue(load_packages(), "the manifest declares no packages")

    def test_every_package_is_a_plausible_name(self) -> None:
        for package in load_packages():
            with self.subTest(package=package):
                self.assertRegex(package, PACKAGE_RE)

    def test_no_package_is_declared_twice(self) -> None:
        seen: set[str] = set()
        for package in load_packages():
            with self.subTest(package=package):
                self.assertNotIn(package, seen, f"{package} is declared twice")
            seen.add(package)

    def test_the_ci_action_reads_the_manifest_instead_of_repeating_it(self) -> None:
        action = INSTALL_DEPS_ACTION.read_text(encoding="utf-8")
        self.assertIn(
            "packaging/build-dependencies.json",
            action,
            "the CI action has to read the manifest; that is what makes it the one declaration",
        )
        self.assertIn(
            "steps.manifest.outputs.packages",
            action,
            "the action should install the list it read, not a second copy of it",
        )
        for package in load_packages():
            if package in BOOTSTRAP_PACKAGES:
                continue
            with self.subTest(package=package):
                self.assertIsNone(
                    re.search(rf"(?<![\w-]){re.escape(package)}(?![\w-])", action),
                    f"the action still names {package} itself; it belongs in the manifest only",
                )


if __name__ == "__main__":
    unittest.main()
