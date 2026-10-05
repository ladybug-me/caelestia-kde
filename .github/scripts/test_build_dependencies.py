#!/usr/bin/env python3
"""Build dependency manifest tests.

`packaging/build-dependencies.json` declares every package the shell build needs
for each supported distribution. The Arch column is authoritative: the CI action
installs exactly what it lists. The Fedora and Debian columns may only name
packages the installer's own per-distro list already installs, so the manifest
can never introduce a package name that nothing else in the repository knows
about. An empty list is how a distribution with no name yet is recorded.
"""

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

MANIFEST = ROOT / "packaging" / "build-dependencies.json"
INSTALL_DEPS_ACTION = ROOT / ".github" / "actions" / "install-build-deps" / "action.yml"

AUTHORITATIVE_DISTRO = "arch"
SUPPORTED_DISTROS = ("arch", "fedora", "debian")

BOOTSTRAP_PACKAGES = {"python"}

PACKAGE_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9+._-]*$")

ARRAY_RE = re.compile(r"^\w+=\(\s*(.*?)^\)", re.S | re.M)
COMMENT_RE = re.compile(r"#.*$", re.M)


def load_manifest() -> dict:
    return json.loads(MANIFEST.read_text(encoding="utf-8"))


def installer_packages(distro: str) -> set[str]:
    """Every package name the installer's own script for `distro` installs."""
    text = (ROOT / "installer" / "distro" / distro / "packages.sh").read_text(encoding="utf-8")
    packages: set[str] = set()
    for match in ARRAY_RE.finditer(text):
        body = COMMENT_RE.sub("", match.group(1))
        for token in body.split():
            token = token.strip("\"'")
            if PACKAGE_RE.match(token):
                packages.add(token)
    return packages


class BuildDependencyManifestTests(unittest.TestCase):
    def test_the_manifest_declares_every_supported_distro_for_every_dependency(self) -> None:
        """A missing key would be indistinguishable from a typo, so a gap has to
        be an empty list: a decision somebody made, not an omission."""
        manifest = load_manifest()
        self.assertEqual(
            manifest["distros"],
            list(SUPPORTED_DISTROS),
            "the distro vocabulary changed; update the installer anchoring too",
        )
        self.assertTrue(manifest["dependencies"], "the manifest declares no dependencies")
        for name, dependency in manifest["dependencies"].items():
            with self.subTest(dependency=name):
                self.assertEqual(
                    sorted(dependency),
                    sorted(SUPPORTED_DISTROS),
                    f"{name} has to name every distro, using [] where no package is known",
                )

    def test_every_dependency_has_a_package_on_the_authoritative_distro(self) -> None:
        for name, dependency in load_manifest()["dependencies"].items():
            with self.subTest(dependency=name):
                self.assertTrue(
                    dependency[AUTHORITATIVE_DISTRO],
                    f"{name} is a build dependency with no {AUTHORITATIVE_DISTRO} package",
                )

    def test_every_named_package_is_a_plausible_name(self) -> None:
        for name, dependency in load_manifest()["dependencies"].items():
            for distro, packages in dependency.items():
                for package in packages:
                    with self.subTest(dependency=name, distro=distro, package=package):
                        self.assertRegex(package, PACKAGE_RE)

    def test_no_package_is_declared_twice_for_one_distro(self) -> None:
        seen: dict[tuple[str, str], str] = {}
        for name, dependency in load_manifest()["dependencies"].items():
            for distro, packages in dependency.items():
                for package in packages:
                    key = (distro, package)
                    with self.subTest(dependency=name, distro=distro, package=package):
                        self.assertNotIn(
                            key,
                            seen,
                            f"{package} is declared for {distro} by both {seen.get(key)} and {name}",
                        )
                    seen[key] = name

    def test_the_fedora_and_debian_columns_only_use_names_the_installer_knows(self) -> None:
        """The installer is the repository's per-distro package knowledge. A name
        that is not there is a name nobody has installed from, so it cannot be
        asserted here."""
        known = {distro: installer_packages(distro) for distro in SUPPORTED_DISTROS if distro != AUTHORITATIVE_DISTRO}
        for name, dependency in load_manifest()["dependencies"].items():
            for distro, packages in dependency.items():
                if distro == AUTHORITATIVE_DISTRO:
                    continue
                for package in packages:
                    with self.subTest(dependency=name, distro=distro, package=package):
                        self.assertIn(
                            package,
                            known[distro],
                            f"{name} names {package} for {distro}, but "
                            f"installer/distro/{distro}/packages.sh never installs it",
                        )

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
        for dependency in load_manifest()["dependencies"].values():
            for package in dependency[AUTHORITATIVE_DISTRO]:
                if package in BOOTSTRAP_PACKAGES:
                    continue
                with self.subTest(package=package):
                    self.assertIsNone(
                        re.search(rf"(?<![\w-]){re.escape(package)}(?![\w-])", action),
                        f"the action still names {package} itself; it belongs in the manifest only",
                    )


if __name__ == "__main__":
    unittest.main()
