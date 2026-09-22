#!/usr/bin/env python3
"""Installer wiring tests.

The invariants the installer's step scripts have to keep: that the entrypoints exist,
that every numbered scripts/*.sh is run by one of the step lists, that the update path
sparsifies only paths src/bin/caelestia-update writes, and a few ordering guarantees
inside those scripts. They read the same few installer files and change for their own
reasons, which is why they are not in test_repo_integrity.py.
"""

import re
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
INSTALLER_ENTRYPOINTS = [
    Path("scripts", "setup.sh"),
    Path("update.sh"),
    Path("uninstall.sh"),
]


class InstallerTests(unittest.TestCase):
    def test_installer_entrypoints_exist(self) -> None:
        for rel_path in INSTALLER_ENTRYPOINTS:
            self.assertTrue((ROOT / rel_path).is_file(), f"Missing installer entrypoint: {rel_path.as_posix()}")

    def test_setup_references_existing_step_scripts(self) -> None:
        runner_text = (ROOT / "installer/tui/Runner.cpp").read_text(encoding="utf-8")
        matches = re.findall(r'\{"[^"]+",\s*"(scripts/[^"]+)",\s*"[^"]+",\s*"[^"]+"\}', runner_text)

        self.assertTrue(matches, "No installer steps found in Runner.cpp")

        for rel_path in matches:
            normalized = Path(rel_path.replace("\\", "/"))
            resolved = ROOT / normalized
            self.assertTrue(resolved.is_file(), f"Missing installer step referenced by Runner.cpp: {resolved.relative_to(ROOT).as_posix()}")

    def test_no_duplicate_step_names(self) -> None:
        """Runner.cpp must not define two steps with the same display name."""
        runner_text = (ROOT / "installer/tui/Runner.cpp").read_text(encoding="utf-8")
        names = re.findall(r'\{"([^"]+)",\s*"(scripts/[^"]+)",\s*"[^"]+",\s*"[^"]+"\}', runner_text)
        display_names = [n[0] for n in names]

        seen: dict[str, int] = {}
        for name in display_names:
            seen[name] = seen.get(name, 0) + 1

        duplicates = {name: count for name, count in seen.items() if count > 1}
        self.assertFalse(
            duplicates,
            f"Duplicate installer step names: {duplicates}",
        )

    def test_every_step_script_is_wired_into_a_step_list(self) -> None:
        """A numbered scripts/*.sh must be run by a step list, and every listed step must exist.

        Three lists run step scripts: the full install (installer/tui/Runner.cpp), the
        user's half of a packaged install (src/bin/caelestia), and the subset
        08-build-shell.sh runs on its own when a checkout updates itself. A script in none
        of them is dead weight that every other check still reports as covered; a list
        entry with no file fails at install time instead of here. The step numbers are not
        an order: the TUI runs 00-backup-themes after 02a-submodules, deliberately. The
        lists differ in failure policy - the installer stops, the update path warns and
        carries on - so only their membership is comparable, which is all this checks.
        """
        runner_text = (ROOT / "installer" / "tui" / "Runner.cpp").read_text(encoding="utf-8")
        packaged_text = (ROOT / "src" / "bin" / "caelestia").read_text(encoding="utf-8")
        update_text = (ROOT / "scripts" / "08-build-shell.sh").read_text(encoding="utf-8")

        runner_steps = set(re.findall(r"scripts/([0-9][0-9a-z]*-[A-Za-z0-9._-]+\.sh)", runner_text))
        packaged_steps = set(
            re.findall(r"^\s+([0-9][0-9a-z]*-[A-Za-z0-9._-]+\.sh)$", packaged_text, re.MULTILINE)
        )
        update_steps = set(
            re.findall(r"scripts/([0-9][0-9a-z]*-[A-Za-z0-9._-]+\.sh)", update_text)
        )
        listed = runner_steps | packaged_steps | update_steps
        self.assertTrue(listed, "No step scripts found in Runner.cpp, src/bin/caelestia or 08-build-shell.sh")

        scripts_dir = ROOT / "scripts"
        numbered = {
            path.name for path in scripts_dir.glob("*.sh")
            if re.match(r"^\d+[a-z]?-", path.name)
        }

        self.assertEqual(
            sorted(numbered - listed), [],
            "Step script(s) no step list runs:",
        )
        self.assertEqual(
            sorted(listed - numbered), [],
            "Step list(s) reference script(s) that do not exist in scripts/:",
        )

    def test_the_update_fallback_sparsifies_only_paths_the_updater_writes(self) -> None:
        """08-build-shell.sh adds to the sparse-checkout list src/bin/caelestia-update owns.

        The updater writes that list before it checks the tree out, so a helper cannot
        live in the tree and be called from there: the two name the same paths twice.
        This is what stops the second copy from drifting to a path nothing sparsifies,
        which would leave the fallback silently doing nothing.
        """
        updater = (ROOT / "src" / "bin" / "caelestia-update").read_text(encoding="utf-8")
        build = (ROOT / "scripts" / "08-build-shell.sh").read_text(encoding="utf-8")

        owned = set(re.findall(r'echo "([^"]+)" >+ \.git/info/sparse-checkout', updater))
        added = set(re.findall(r'echo "([^"]+)" >> "\$sparse_file"', build))

        self.assertTrue(owned, "caelestia-update should still write the sparse-checkout list")
        self.assertTrue(added, "08-build-shell.sh should still name the path it adds")
        self.assertEqual(
            sorted(added - owned),
            [],
            "08-build-shell.sh sparsifies path(s) caelestia-update never writes:",
        )


class InstallStepSafetyTests(unittest.TestCase):
    """Ordering and wiring invariants for the install/update step scripts.

    These are guarantees no single-file syntax or lint check can see, and that
    the reports behind them describe as silent: the step reports success while
    doing the wrong thing.
    """

    def test_shell_config_backup_precedes_the_prebuilt_install(self) -> None:
        """#663: the prebuilt path extracts over $HOME, so it must be backed up first."""
        script = (ROOT / "scripts" / "08-build-shell.sh").read_text(encoding="utf-8")

        backup_at = script.find("backup_shell_config ||")
        prebuilt_at = script.find("if try_download_prebuilt_shell;")

        self.assertNotEqual(backup_at, -1, "08-build-shell.sh should back up the shell config")
        self.assertNotEqual(prebuilt_at, -1, "08-build-shell.sh should still use the prebuilt download")
        self.assertLess(
            backup_at,
            prebuilt_at,
            "the shell-config backup must run before the prebuilt archive is extracted over $HOME",
        )

    def test_privileged_package_installs_go_through_the_escalation_helper(self) -> None:
        """#664: a GUI-triggered update has no terminal, so bare sudo fails silently."""
        script = (ROOT / "scripts" / "08-build-shell.sh").read_text(encoding="utf-8")

        self.assertIn(
            "install_linguist_tools",
            script,
            "08-build-shell.sh should install the Linguist tools via the shared helper",
        )
        self.assertNotIn(
            "sudo pacman -S --needed --noconfirm qt6-tools",
            script,
            "the Linguist tools install must not escalate with bare sudo",
        )

    def test_scheme_wait_happens_after_the_shell_restart(self) -> None:
        """#666: waiting before the restart polls for a file from a killed process."""
        script = (ROOT / "update.sh").read_text(encoding="utf-8")

        start_at = script.find('"$SHELL_IPC" start')
        wait_at = script.find("wait_for_nonempty_file")

        self.assertNotEqual(start_at, -1, "update.sh should still start the shell through the IPC wrapper")
        self.assertNotEqual(wait_at, -1, "update.sh should wait for the restarted shell to persist the scheme")
        self.assertLess(
            start_at,
            wait_at,
            "the scheme.json wait must run after the shell is restarted, not before",
        )

    def test_the_tui_build_configures_from_a_clean_directory(self) -> None:
        """cmake refuses a CMakeCache.txt that names another source directory.

        One checkout routinely has two names - ~/Desktop/caelestia-kwin and
        /mnt/c/.../caelestia-kwin are the same tree - so a cache left behind by the other
        name made the build fail with "the current CMakeCache.txt directory is different
        than the directory where CMakeCache.txt was created", and the installer stopped
        there. Nothing clears that cache, so the directory has to go before cmake runs.
        """
        script = (ROOT / "scripts" / "setup.sh").read_text(encoding="utf-8")

        wipe_at = script.find('rm -rf "$BUILD_DIR"')
        configure_at = script.find('cmake -DCMAKE_BUILD_TYPE=Release "$BUNDLE_DIR/installer/tui"')

        self.assertNotEqual(wipe_at, -1, "setup.sh should clear the TUI build directory")
        self.assertNotEqual(configure_at, -1, "setup.sh should still configure the TUI build")
        self.assertLess(
            wipe_at,
            configure_at,
            "the TUI build directory must be cleared before cmake configures into it",
        )


class ScriptNumberingTests(unittest.TestCase):
    def test_install_step_scripts_have_consistent_numbers(self) -> None:
        """Step numbers stay a two-digit base with an optional letter suffix.

        The set is whatever `ls scripts/` shows; the guarantee is only the numbering
        scheme, so a step added with a number that cannot sort next to its neighbours is
        caught here. Use the existing names as the examples.
        """
        scripts_dir = ROOT / "scripts"
        if not scripts_dir.is_dir():
            return

        numbers = set()
        for f in scripts_dir.glob("*.sh"):
            match = re.match(r"^(\d+)[a-z]?-", f.name)
            if match:
                numbers.add(int(match.group(1)))

        if numbers:
            max_num = max(numbers)
            self.assertLessEqual(
                max_num, 99,
                f"Script number {max_num} seems too high - consider renumbering"
            )


class InstallerEnvironmentTests(unittest.TestCase):
    """The TUI reads its directories from the environment, and HOME is optional here.

    POSIX does not promise HOME. UI.cpp already treats it as optional for its state
    directory, but three other call sites built a std::string straight from
    getenv("HOME"), and libstdc++ throws std::logic_error ("basic_string: construction
    from null is not valid") on a null pointer rather than yielding an empty string.
    That aborts the installer: in Runner::execute before the first step runs, and again
    on the success path in phase 5. Nothing executes the TUI - no test, no CI job - so
    only reading the source catches it. Every caller now goes through xdg_cache_dir()
    in Globals.cpp, which is where the checked form lives.
    """

    TUI = ROOT / "installer" / "tui"
    # A direct argument to string()/std::string(), with or without the "std::" prefix. A
    # ternary whose condition is itself a getenv() call counts too: it is the false
    # branch that decides what gets constructed.
    UNCHECKED_GETENV = re.compile(r"\bstring\(\s*(?:std::)?getenv\(")

    def tui_sources(self) -> list[Path]:
        return sorted(self.TUI.glob("*.cpp"))

    def test_the_tui_sources_are_where_this_expects_them(self) -> None:
        """Keeps the check below from passing just because it read no files."""
        names = [path.name for path in self.tui_sources()]
        self.assertIn("main.cpp", names)
        self.assertIn("Runner.cpp", names)

    def test_no_string_is_constructed_from_an_unchecked_getenv(self) -> None:
        offenders = []
        for path in self.tui_sources():
            text = path.read_text(encoding="utf-8")
            for number, line in enumerate(text.splitlines(), start=1):
                if self.UNCHECKED_GETENV.search(line):
                    offenders.append(f"{path.relative_to(ROOT).as_posix()}:{number}")

        self.assertEqual(
            offenders,
            [],
            "string is built from getenv() without checking the pointer for null:",
        )


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)
