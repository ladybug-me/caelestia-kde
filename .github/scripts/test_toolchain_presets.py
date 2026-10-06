#!/usr/bin/env python3
"""CMake preset wiring tests.

The build configuration lives in shell/CMakePresets.json and
installer/tui/CMakePresets.json. The Makefile and the CI jobs that configure a
tree by preset name it, so a preset renamed in one file and not in the other is
either a build that cannot configure or, worse, a CI job that quietly builds
something other than what a contributor builds. These tests keep the two sides
of that contract in step.

They also keep the contract closed. A build entry point that configures CMake by
hand is a second configuration that nothing compares against the presets, which
is the failure this file exists to prevent.
"""

import json
import re
import unittest
from functools import lru_cache
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

RELEASE_INSTALL_LAYOUT = {
    "INSTALL_BINDIR": "usr/bin",
    "INSTALL_DATADIR": "usr/lib/caelestia",
    "INSTALL_LIBDIR": "usr/lib/caelestia",
    "INSTALL_QSCONFDIR": "etc/xdg/quickshell/caelestia",
    "INSTALL_QMLDIR": "usr/lib/qt6/qml",
}

# Where a contributor or a CI job starts one of our two builds. The installer's
# per-distro scripts are deliberately not here: they build third-party sources
# cloned from elsewhere, not either of our projects.
BUILD_ENTRY_POINTS = [
    ROOT / "Makefile",
    *sorted((ROOT / ".github" / "workflows").glob("*.yml")),
    *sorted((ROOT / ".github" / "actions").glob("*/action.yml")),
    *sorted((ROOT / "scripts").rglob("*.sh")),
]

# Configuring CMake without a preset, on purpose. These run on the end user's own
# machine or on a bare distro image, where the CMake the presets need is not
# guaranteed, so they set the cache the way the installer always has. The count is
# part of the contract: another hand-written configuration, in one of these files
# or anywhere else, has to be a deliberate edit here.
MANUAL_CMAKE_BUDGET = {
    "scripts/setup.sh": 1,
    "scripts/08-build-shell.sh": 2,
    ".github/workflows/test-dependencies.yml": 3,
    ".github/workflows/version-release.yml": 1,
}

MAKEFILE = ROOT / "Makefile"

ASSIGNMENT_RE = re.compile(r"^(?P<name>[A-Za-z_]\w*)\s*(?::=|\?=|\+=|=)\s*(?P<value>\S+)\s*$", re.M)
REFERENCE_RE = re.compile(r"\$\((?P<name>\w+)\)")

PRESET_RE = re.compile(r"(?P<build>--build\s+)?--preset(?:=|\s+)(?P<name>\$\(\w+\)|[A-Za-z0-9_.-]+)")
CD_RE = re.compile(r"\bcd\s+(?P<dir>\$\(\w+\)|[^\s&;|]+)")
CMAKE_RE = re.compile(r"\bcmake\b(?P<arguments>[^\n]*)")
MANUAL_FLAG_RE = re.compile(r"(?:^|\s)-(?:B|S|D[A-Za-z_])")


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


@lru_cache(maxsize=1)
def makefile_variables() -> dict[str, str]:
    """The Makefile's assignments, with `$(OTHER)` references expanded.

    Restating them here instead would mean the tests check their own copy of the
    directories rather than the directories the Makefile actually uses.
    """
    variables = {
        match.group("name"): match.group("value")
        for match in ASSIGNMENT_RE.finditer(MAKEFILE.read_text(encoding="utf-8"))
    }
    for _ in range(len(variables)):
        for name, value in variables.items():
            variables[name] = REFERENCE_RE.sub(
                lambda reference: variables.get(reference.group("name"), reference.group(0)),
                value,
            )
    return variables


def resolve_makefile_variable(token: str) -> str:
    reference = REFERENCE_RE.fullmatch(token)
    if reference is None:
        return token
    return makefile_variables().get(reference.group("name"), token)


def preset_calls():
    """Every `--preset` a build entry point makes, with the project it configures.

    The directory is read from the `cd` on the call's line or the two lines above
    it, which is where a `run:` block puts it. A call with no `cd` in reach yields
    None, and fails rather than falling back to matching the name against every
    preset file there is.
    """
    for path in BUILD_ENTRY_POINTS:
        lines = path.read_text(encoding="utf-8").splitlines()
        for index, line in enumerate(lines):
            for match in PRESET_RE.finditer(line):
                window = "\n".join(lines[max(0, index - 2):index + 1])
                directories = [resolve_makefile_variable(cd.group("dir")) for cd in CD_RE.finditer(window)]
                yield (
                    path.relative_to(ROOT).as_posix(),
                    index + 1,
                    directories[-1] if directories else None,
                    "build" if match.group("build") else "configure",
                    resolve_makefile_variable(match.group("name")),
                )


def manual_cmake_calls() -> dict[str, int]:
    """How many `cmake` calls per entry point configure instead of using a preset.

    A call that names a `--preset` is one configuration whatever `-D` overrides
    sit next to it, so those lines do not count.
    """
    counts: dict[str, int] = {}
    for path in BUILD_ENTRY_POINTS:
        relative = path.relative_to(ROOT).as_posix()
        for match in CMAKE_RE.finditer(path.read_text(encoding="utf-8")):
            arguments = match.group("arguments")
            if "--preset" in arguments or not MANUAL_FLAG_RE.search(arguments):
                continue
            counts[relative] = counts.get(relative, 0) + 1
    return counts


class PresetFileTests(unittest.TestCase):
    def test_every_preset_file_declares_exactly_the_expected_presets(self) -> None:
        for directory, expected in EXPECTED_PRESETS.items():
            with self.subTest(directory=directory):
                presets = load_presets(directory)
                self.assertEqual(presets["version"], 3, "the preset file version this project standardised on")
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

    def test_every_preset_file_declares_the_cmake_floor_preset_version_3_needs(self) -> None:
        """Preset version 3 is CMake 3.21. Each project's own
        cmake_minimum_required is older, and that is exactly why the installer and
        the release scripts configure CMake by hand: the CMake they run under is
        not guaranteed to be able to read a preset at all. Writing the floor down
        keeps that a decision rather than something nobody notices."""
        for directory in PRESET_FILES:
            with self.subTest(directory=directory):
                floor = load_presets(directory)["cmakeMinimumRequired"]
                self.assertEqual(
                    (floor["major"], floor["minor"]),
                    (3, 21),
                    f"{directory} declares a floor that preset version 3 does not need",
                )

    def test_the_release_preset_is_the_layout_the_release_job_ships(self) -> None:
        """The release job tars up bin, lib and quickshell out of the staged
        install tree, so the published layout is exactly what this preset pins."""
        cache = resolved_cache_variables(load_presets("shell"), "release")
        self.assertEqual(
            {key: cache.get(key) for key in RELEASE_INSTALL_LAYOUT},
            RELEASE_INSTALL_LAYOUT,
            "the release layout moved; the tarball the release job builds follows this preset",
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
    def test_every_preset_call_names_the_project_it_configures(self) -> None:
        for source, line, directory, kind, name in preset_calls():
            with self.subTest(source=source, line=line, preset=name):
                self.assertIsNotNone(
                    directory,
                    f"{source}:{line} names the {kind} preset {name!r} with no `cd` into the project "
                    f"in the lines above it; put the cd next to the call",
                )

    def test_every_preset_a_caller_names_is_declared(self) -> None:
        declared = {
            directory: {
                kind: {preset["name"] for preset in load_presets(directory).get(f"{kind}Presets", [])}
                for kind in ("configure", "build")
            }
            for directory in PRESET_FILES
        }
        for source, line, directory, kind, name in preset_calls():
            with self.subTest(source=source, line=line, preset=name):
                self.assertIn(
                    directory,
                    declared,
                    f"{source}:{line} names a preset in {directory}, which has no presets",
                )
                self.assertIn(
                    name,
                    declared[directory][kind],
                    f"{source}:{line} names {directory} {kind} preset {name!r}, which is not declared there",
                )

    def test_every_declared_preset_is_actually_used(self) -> None:
        """A preset no caller names is a configuration nobody builds, and it
        drifts out of date unnoticed because nothing exercises it."""
        used = {(directory, kind, name) for _, _, directory, kind, name in preset_calls() if directory}
        for directory, expected in EXPECTED_PRESETS.items():
            for kind, names in expected.items():
                for name in names:
                    with self.subTest(directory=directory, preset=name):
                        self.assertIn(
                            (directory, kind, name),
                            used,
                            f"no Makefile or CI file builds the {directory} {kind} preset {name!r}",
                        )

    def test_no_build_entry_point_configures_cmake_by_hand(self) -> None:
        """The presets are the configuration. A second, hand-written set of -D
        flags is how a local build and a CI build came to disagree, so a new one
        has to be an edit to MANUAL_CMAKE_BUDGET rather than an accident."""
        counts = manual_cmake_calls()
        for path in BUILD_ENTRY_POINTS:
            relative = path.relative_to(ROOT).as_posix()
            with self.subTest(source=relative):
                self.assertEqual(
                    counts.get(relative, 0),
                    MANUAL_CMAKE_BUDGET.get(relative, 0),
                    f"{relative} configures cmake {counts.get(relative, 0)} time(s) without a preset; "
                    f"use one of the presets, or record the exception in MANUAL_CMAKE_BUDGET",
                )


if __name__ == "__main__":
    unittest.main()
