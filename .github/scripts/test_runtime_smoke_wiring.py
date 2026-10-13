#!/usr/bin/env python3
"""Runtime smoke wiring tests.

The smoke action builds the shell and runs it in a job container, so these
invariants are about the container view rather than about shell/ itself: the
directories the caller passes, and the QML modules the image has to provide.
They read the same handful of CI files and change for their own reasons, which
is why they are not in test_repo_integrity.py.
"""

import re
import unittest
from pathlib import Path

import yaml

from check_qml_imports import IMPORT_RE, VALID_BAREWORD_MODULE_RE

ROOT = Path(__file__).resolve().parents[2]

SMOKE_ACTION = "./.github/actions/runtime-smoke"

# check_qml_imports tracks upper-case rooted bareword modules. Qt also resolves
# reverse-DNS modules such as org.kde.pipewire, so this test accepts that shape
# too; the quoted form (`import "components"`) is a directory import, not a
# module, and IMPORT_RE tells the two apart.
REVERSE_DNS_MODULE_RE = re.compile(r"^(?:org|com|io|net)\.[\w.]+$")


def imported_modules(text: str) -> set[str]:
    """The modules a QML file imports, ignoring relative directory imports."""
    modules = set()
    for match in IMPORT_RE.finditer(text):
        module = match.group(2)
        if module and (
            VALID_BAREWORD_MODULE_RE.match(module) or REVERSE_DNS_MODULE_RE.match(module)
        ):
            modules.add(module)
    return modules


class RuntimeSmokeWiringTests(unittest.TestCase):
    """The runtime smoke runs inside a job container, so its directories and its
    QML modules have to exist the way the container sees them.

    A path interpolated from `github.workspace` is the runner's host path, which
    inside a container is not the workspace mount: the install tree and the logs
    land somewhere the artifact upload cannot reach, so a failing run uploads
    nothing and a passing one uploads nothing either.
    """

    DIRECTORY_INPUTS = ("deps-dir", "install-root", "log-dir")

    # QML modules the shell imports from outside this repository, and the Arch
    # package that provides each one. The smoke container is built from
    # install-build-deps, so a module the shell imports and that action never
    # installs shows up as "Failed to load configuration" halfway through a run.
    EXTERNAL_QML_MODULES = {"org.kde.pipewire": "kpipewire"}

    # Module roots the environment supplies itself: Quickshell, this repository's
    # own qs.*/Caelestia.*/M3Shapes imports, and Qt (QtQuick, QtCore, Qt.labs.*,
    # Qt5Compat.* - every Qt module root starts with "Qt").
    PROVIDED_MODULE_ROOTS = ("qs", "Caelestia", "M3Shapes", "Quickshell")

    @classmethod
    def is_provided(cls, module: str) -> bool:
        root = module.split(".")[0]
        return root in cls.PROVIDED_MODULE_ROOTS or root.startswith("Qt")

    @classmethod
    def smoke_callers(cls) -> dict[str, dict]:
        """Every workflow step that calls the smoke action, with its inputs."""
        callers: dict[str, dict] = {}
        for workflow in sorted((ROOT / ".github" / "workflows").glob("*.yml")):
            document = yaml.safe_load(workflow.read_text(encoding="utf-8")) or {}
            for job_name, job in (document.get("jobs") or {}).items():
                for step in (job or {}).get("steps") or []:
                    if step.get("uses") == SMOKE_ACTION:
                        callers[f"{workflow.name}:{job_name}"] = step.get("with") or {}
        return callers

    def test_smoke_callers_pass_workspace_relative_directories(self) -> None:
        callers = self.smoke_callers()
        self.assertTrue(callers, f"no workflow step calls {SMOKE_ACTION}")

        for caller, inputs in callers.items():
            for name in self.DIRECTORY_INPUTS:
                with self.subTest(caller=caller, input=name):
                    value = inputs.get(name)
                    self.assertIsNotNone(value, f"{caller} does not pass {name}")
                    self.assertFalse(
                        value.startswith("/"),
                        f"{caller} passes the absolute path {value!r} as {name}; it has to be "
                        "relative to the workspace so the container resolves it",
                    )
                    self.assertNotIn(
                        "${{", value, f"{caller} passes an interpolated path as {name}"
                    )

    def test_the_environment_provides_the_qml_modules_the_shell_imports(self) -> None:
        imported = {
            module
            for path in (ROOT / "shell").rglob("*.qml")
            for module in imported_modules(path.read_text(encoding="utf-8"))
        }
        external = sorted(module for module in imported if not self.is_provided(module))
        self.assertEqual(
            external,
            sorted(self.EXTERNAL_QML_MODULES),
            "shell/ imports external QML modules that this test does not map to a package; "
            "add the providing package to EXTERNAL_QML_MODULES and to install-build-deps",
        )

        deps_action = (ROOT / ".github" / "actions" / "install-build-deps" / "action.yml").read_text(
            encoding="utf-8"
        )
        nightly = (ROOT / ".github" / "workflows" / "runtime-smoke.yml").read_text(encoding="utf-8")
        for module, package in self.EXTERNAL_QML_MODULES.items():
            with self.subTest(module=module):
                self.assertRegex(
                    deps_action,
                    rf"(?<![\w-]){re.escape(package)}(?![\w-])",
                    f"shell/ imports {module}, but install-build-deps never installs {package}",
                )
                self.assertIn(
                    f"/usr/lib/qt6/qml/{module.replace('.', '/')}",
                    nightly,
                    f"the self-hosted runtime image should be verified to provide {module}",
                )


if __name__ == "__main__":
    unittest.main()
