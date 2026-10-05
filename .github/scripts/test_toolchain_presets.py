#!/usr/bin/env python3
"""CMake preset wiring tests.

The build configuration lives in shell/CMakePresets.json and
installer/tui/CMakePresets.json. The Makefile and every CI job that builds a
tree pick it up by name, so a preset renamed in one file and not in the other is
either a build that cannot configure or, worse, a CI job that quietly builds
something other than what a contributor builds. These tests keep the two sides
of that contract in step.
"""

import json
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

PRESET_FILES = {
    "shell": ROOT / "shell" / "CMakePresets.json",
    "installer/tui": ROOT / "installer" / "tui" / "CMakePresets.json",
}

EXPECTED_PRESETS = {
    "shell": {
        "configure": {"dev", "source-offline", "package-offline", "release", "runtime", "sanitizers"},
        "build": {"dev", "source-offline", "package-offline", "release", "runtime", "sanitizers"},
    },
    "installer/tui": {
        "configure": {"dev", "release", "sanitizers"},
        "build": {"dev", "release", "sanitizers"},
    },
}

OFFLINE_SHELL_PRESETS = {"source-offline", "package-offline", "release", "runtime", "sanitizers"}

CALLER_FILES = [
    ROOT / "Makefile",
    *sorted((ROOT / ".github" / "workflows").glob("*.yml")),
    *sorted((ROOT / ".github" / "actions").glob("*/action.yml")),
]

MAKEFILE_VARIABLES = {
    "$(SHELL_DIR)": "shell",
    "$(TUI_DIR)": "installer/tui",
    "$(SHELL_PRESET)": "dev",
    "$(INSTALLER_PRESET)": "dev",
}

PRESET_RE = re.compile(r"(?P<build>--build\s+)?--preset(?:=|\s+)(?P<name>\$\(\w+\)|[A-Za-z0-9_.-]+)")
CD_RE = re.compile(r"\bcd\s+(?P<dir>\$\(\w+\)|[^\s&;|]+)")


def load_presets(directory: str) -> dict:
    return json.loads(PRESET_FILES[directory].read_text(encoding="utf-8"))


def resolved_cache_variables(presets: dict, name: str) -> dict:
    """The cache variables a configure preset ends up with, `inherits` included."""
    by_name = {preset["name"]: preset for preset in presets.get("configurePresets", [])}
    merged: dict = {}
    chain = []
    current = name
    while current:
        preset = by_name.get(current)
        if preset is None:
            break
        chain.append(preset)
        inherits = preset.get("inherits")
        current = inherits[0] if isinstance(inherits, list) else inherits
    for preset in reversed(chain):
        merged.update(preset.get("cacheVariables", {}))
    return merged


def resolve_makefile_variable(token: str) -> str:
    return MAKEFILE_VARIABLES.get(token, token)


def preset_calls():
    """Every `--preset` a caller makes, with the project directory in scope.

    The directory is read from the same line or the two lines above it, which is
    where a `run:` block puts the `cd`. A call with no directory in reach yields
    None, and is only checked against the union of declared names.
    """
    for path in CALLER_FILES:
        lines = path.read_text(encoding="utf-8").splitlines()
        for index, line in enumerate(lines):
            for match in PRESET_RE.finditer(line):
                window = "\n".join(lines[max(0, index - 2):index + 1])
                directories = [resolve_makefile_variable(cd.group("dir")) for cd in CD_RE.finditer(window)]
                yield (
                    path.relative_to(ROOT).as_posix(),
                    directories[-1] if directories else None,
                    "build" if match.group("build") else "configure",
                    resolve_makefile_variable(match.group("name")),
                )


class PresetFileTests(unittest.TestCase):
    def test_every_preset_file_declares_exactly_the_expected_presets(self) -> None:
        for directory, expected in EXPECTED_PRESETS.items():
            with self.subTest(directory=directory):
                presets = load_presets(directory)
                self.assertEqual(presets["version"], 3, "a preset version every supported cmake reads")
                for kind in ("configure", "build"):
                    declared = {
                        preset["name"]
                        for preset in presets.get(f"{kind}Presets", [])
                        if not preset.get("hidden")
                    }
                    self.assertEqual(
                        declared,
                        expected[kind],
                        f"{directory} {kind} presets changed; update EXPECTED_PRESETS if that is deliberate",
                    )

    def test_every_build_preset_names_a_declared_configure_preset(self) -> None:
        for directory in PRESET_FILES:
            with self.subTest(directory=directory):
                presets = load_presets(directory)
                configure = {preset["name"] for preset in presets["configurePresets"]}
                for preset in presets.get("buildPresets", []):
                    self.assertIn(
                        preset["configurePreset"],
                        configure,
                        f"{directory} build preset {preset['name']} configures an undeclared preset",
                    )

    def test_each_preset_writes_to_its_own_build_directory(self) -> None:
        """Two presets sharing a binaryDir would fight over one cache, and the
        generator and flags baked into a CMakeCache.txt are not interchangeable.
        """
        for directory in PRESET_FILES:
            with self.subTest(directory=directory):
                presets = load_presets(directory)
                binary_dirs = [
                    preset["binaryDir"] for preset in presets["configurePresets"] if "binaryDir" in preset
                ]
                self.assertEqual(
                    len(binary_dirs),
                    len(set(binary_dirs)),
                    f"{directory} configures two presets into the same build directory",
                )

    def test_the_offline_presets_actually_configure_offline(self) -> None:
        presets = load_presets("shell")
        for name in OFFLINE_SHELL_PRESETS:
            with self.subTest(preset=name):
                cache = resolved_cache_variables(presets, name)
                self.assertEqual(
                    cache.get("CAELESTIA_OFFLINE"),
                    "ON",
                    f"{name} is a CI build with the network blocked, so it must configure offline",
                )
        self.assertNotEqual(
            resolved_cache_variables(presets, "dev").get("CAELESTIA_OFFLINE"),
            "ON",
            "the developer preset has to be able to fetch the pinned dependency itself",
        )


class PresetCallerTests(unittest.TestCase):
    def test_every_preset_a_caller_names_is_declared(self) -> None:
        declared = {
            directory: {
                kind: {preset["name"] for preset in load_presets(directory).get(f"{kind}Presets", [])}
                for kind in ("configure", "build")
            }
            for directory in PRESET_FILES
        }
        for source, directory, kind, name in preset_calls():
            with self.subTest(source=source, preset=name):
                if directory is None:
                    known = {preset for per_kind in declared.values() for preset in per_kind[kind]}
                    self.assertIn(
                        name,
                        known,
                        f"{source} names the {kind} preset {name!r}, which no presets file declares",
                    )
                    continue
                self.assertIn(directory, declared, f"{source} names a preset in {directory}, which has no presets")
                self.assertIn(
                    name,
                    declared[directory][kind],
                    f"{source} names {directory} {kind} preset {name!r}, which is not declared there",
                )

    def test_every_declared_preset_is_actually_used(self) -> None:
        """A preset no caller names is a configuration nobody builds, and it
        drifts out of date unnoticed because nothing exercises it."""
        used = {(directory, kind, name) for _, directory, kind, name in preset_calls() if directory}
        for directory, expected in EXPECTED_PRESETS.items():
            for kind, names in expected.items():
                for name in names:
                    with self.subTest(directory=directory, preset=name):
                        self.assertIn(
                            (directory, kind, name),
                            used,
                            f"no Makefile or CI file builds the {directory} {kind} preset {name!r}",
                        )


if __name__ == "__main__":
    unittest.main()
