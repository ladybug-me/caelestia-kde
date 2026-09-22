#!/usr/bin/env python3
"""Repository integrity test suite.

Validates cross-cutting concerns:
  - All shell scripts parse cleanly
  - All Python files compile cleanly
  - version.env is the single source of truth; the CMake build derives from it
  - Submodules are properly initialized
  - Workflow files are valid YAML
  - No duplicate script step names in Runner.cpp
  - Git-tracked docs/ files referenced in .github/CONTRIBUTING.md exist
"""

import re
import shutil
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def repo_files(pattern: str) -> list[Path]:
    return sorted(
        path for path in ROOT.rglob(pattern)
        if ".git" not in path.parts and "__pycache__" not in path.parts and "build" not in path.parts
    )


def git_tracked_files(glob_pattern: str) -> list[str]:
    """Return list of git-tracked files matching glob_pattern, relative to ROOT."""
    result = subprocess.run(
        ["git", "ls-files", "--", glob_pattern],
        capture_output=True, text=True, cwd=ROOT,
    )
    if result.returncode != 0:
        return []
    return [f.strip() for f in result.stdout.splitlines() if f.strip()]


class ScriptSyntaxTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("bash"), "bash is required for shell syntax checks")
    def test_shell_scripts_parse(self) -> None:
        """Every shell script THIS REPOSITORY tracks must parse.

        Only git-tracked files are checked, for the same reason the Python test below
        does it: a filesystem walk also picks up an untracked scratch directory, an
        initialized submodule or a vendored virtualenv, and reports a syntax error in
        somebody else's file as a failure of the change under review.
        """
        failures: list[str] = []

        tracked = git_tracked_files("*.sh")
        rel_paths = tracked or [path.relative_to(ROOT).as_posix() for path in repo_files("*.sh")]

        for rel_path in rel_paths:
            result = subprocess.run(
                ["bash", "-n", rel_path],
                capture_output=True,
                text=True,
                cwd=ROOT,
            )
            if result.returncode != 0:
                message = (result.stderr or result.stdout).strip()
                failures.append(f"{rel_path}\n{message}")

        self.assertFalse(failures, "Shell syntax failures:\n\n" + "\n\n".join(failures))

    def test_python_scripts_compile(self) -> None:
        """Syntax-check every Python file without writing bytecode.

        py_compile drops a .pyc next to the source, which fails with EIO on a
        read-only checkout (a shared folder, a container image, a Nix store).
        compile() checks the same thing and touches nothing.

        Only git-tracked files are checked. A filesystem walk also picks up a
        checked-out virtualenv - thousands of files that are not ours, and slow
        to read over a network mount.
        """
        failures: list[str] = []
        paths = git_tracked_files("*.py") or [
            path.relative_to(ROOT).as_posix() for path in repo_files("*.py")
        ]

        for rel_path in paths:
            try:
                compile((ROOT / rel_path).read_text(encoding="utf-8"), rel_path, "exec")
            except (SyntaxError, ValueError, UnicodeDecodeError) as exc:
                failures.append(f"{rel_path}\n{exc}")

        self.assertFalse(failures, "Python compile failures:\n\n" + "\n\n".join(failures))


class BashHelperTestSuite(unittest.TestCase):
    """Run tests/run-tests.sh so the shell helpers get real behavior coverage.

    scripts/lib/ helpers cannot be exercised from Python, so this delegates to
    the bash runner and fails on any non-zero exit. Adding a test there is
    enough to have it enforced here and in CI.
    """

    @unittest.skipUnless(shutil.which("bash"), "bash is required for the helper suite")
    def test_bash_helper_suite_passes(self) -> None:
        runner = Path("tests", "run-tests.sh")
        self.assertTrue((ROOT / runner).is_file(), f"expected {runner.as_posix()} to exist")

        result = subprocess.run(
            ["bash", runner.as_posix()],
            capture_output=True,
            text=True,
            cwd=ROOT,
        )
        self.assertEqual(
            result.returncode,
            0,
            "bash helper suite failed:\n" + (result.stdout or "") + (result.stderr or ""),
        )


class ShellSurfaceTests(unittest.TestCase):
    """Invariants for shell QML surfaces that CI cannot execute.

    There is no Qt/Quickshell toolchain in this job, so the checks here pin the
    specific behavior the reports describe as silent - a surface that claims
    success while doing nothing.
    """

    def test_ai_key_writes_wait_for_the_keyring_result(self) -> None:
        """#652: committing the field before secret-tool replies claims a save that may not have happened."""
        page = (ROOT / "shell" / "modules" / "nexus" / "pages" / "AiSettingsPage.qml").read_text(encoding="utf-8")

        store_at = page.find("function storeApiKey")
        start_at = page.find("function startKeyStore")
        self.assertNotEqual(store_at, -1, "the page should still have storeApiKey")
        self.assertNotEqual(start_at, -1, "the page should still have startKeyStore")
        self.assertNotEqual(
            page.find("function finishKeyStore"),
            -1,
            "the key write result must be applied by finishKeyStore",
        )

        self.assertNotIn(
            "keyringKeys",
            page[store_at:start_at],
            "storeApiKey must not commit the key before the write result is known",
        )
        self.assertIn(
            "queuedKeyWrites",
            page,
            "a second key write must wait for the one in flight, or its exit code is applied to the wrong key",
        )
        self.assertIn(
            "stderr: StdioCollector",
            page,
            "a failed write needs the reason from secret-tool, not just an exit code",
        )

    def test_shortcut_descriptions_are_translatable(self) -> None:
        """#692: shortcut labels are rendered from this data, so it must be extractable.

        The shortcut manager renders `GlobalShortcut.description` verbatim, and
        lupdate can only extract `qsTr()` calls with a literal argument. A bare
        literal is therefore invisible to the catalog and stays English no
        matter which locale is active. This checks the source is extractable;
        it cannot check that a translation exists, which is Crowdin's job.
        """
        offenders: list[str] = []

        for path in sorted((ROOT / "shell").rglob("*.qml")):
            for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                match = re.match(r'^\s*description:\s*"([^"]*)"', line)
                if not match or not match.group(1):
                    continue
                if "${" in match.group(1):
                    continue
                offenders.append(f"{path.relative_to(ROOT).as_posix()}:{number}")

        self.assertEqual(
            offenders,
            [],
            "shortcut descriptions must be wrapped in qsTr() so lupdate can extract them:\n"
            + "\n".join(offenders),
        )

    def test_about_page_links_the_plugin_count_to_the_plugin_manager(self) -> None:
        """#578: a plugin count with no way through to the plugin page is a dead end."""
        page = (ROOT / "shell" / "modules" / "nexus" / "pages" / "AboutPage.qml").read_text(encoding="utf-8")

        self.assertIn(
            'PageRegistry.indexForKey("plugins")',
            page,
            "the plugin count must link to the plugin manager, resolved by page key",
        )
        self.assertNotIn(
            "value: root.pluginCount",
            page,
            "the plugin count must be rendered by a navigating row, not a static info row",
        )

    def test_a_missing_github_token_is_announced_in_the_ui(self) -> None:
        """The GitHub widget hides itself from the bar unless a fetch has succeeded.

        Aborting inside the provider script therefore made the shell log the only
        place that mentioned the missing token: the widget vanished and the Nexus
        page that fixes it said nothing about why. The state has to be visible
        where the token is configured, not just in an error line.
        """

        def handler_body(source: str, marker: str) -> str:
            start = source.index(marker)
            depth = 0
            for index in range(start, len(source)):
                if source[index] == "{":
                    depth += 1
                elif source[index] == "}":
                    depth -= 1
                    if depth == 0:
                        return source[start : index + 1]
            raise AssertionError(f"unbalanced braces after {marker!r}")

        bar_dir = ROOT / "shell" / "modules" / "bar"
        activity = (bar_dir / "components" / "GithubActivity.qml").read_text(encoding="utf-8")
        store = (bar_dir / "components" / "GithubStore.qml").read_text(encoding="utf-8")
        page = (
            ROOT / "shell" / "modules" / "nexus" / "pages" / "panels" / "taskbar" / "BarGithub.qml"
        ).read_text(encoding="utf-8")

        self.assertNotIn(
            ': "\\${GITHUB_TOKEN:?',
            activity,
            "a bare bash expansion failure reports a configuration state as an error; "
            "use an exit status that can only mean 'no token stored'",
        )
        self.assertIn("exit 3", activity, "the provider needs its own status for 'no token stored'")
        self.assertIn("code === 3", activity, "the widget must route 'no token' away from the failure path")

        self.assertIn(
            "function setTokenMissing",
            activity,
            "the widget needs a handler for the unconfigured state",
        )
        body = handler_body(activity, "function setTokenMissing")
        self.assertNotIn("console.error", body, "an unconfigured widget is not a failure")
        self.assertIn("Toaster.toast", body, "the user must be told on screen, not only in the log")
        self.assertIn(
            "GithubStore.tokenNoticeShown",
            body,
            "the notice must be tracked on the singleton, or every screen's bar repeats it",
        )

        self.assertIn(
            "property bool tokenMissing",
            store,
            "the widget and the settings page must share the state",
        )
        self.assertIn(
            "GithubStore.tokenMissing = false",
            activity,
            "a saved token must clear the missing-token state, or the page keeps reporting it",
        )
        self.assertIn(
            "GithubStore.tokenMissing",
            page,
            "the settings page is where the token is set, so it must report a missing one",
        )
        self.assertIn(
            "GithubStore.lastError",
            page,
            "a token that GitHub rejects must be readable here too, not only in the log",
        )

    def test_the_github_widget_ships_disabled(self) -> None:
        """The widget needs a personal access token, so default-on nags every fresh install.

        The bar only builds entries with enabled: true, so shipping it off is also
        what keeps the missing-token notice away from people who never asked for
        GitHub activity.
        """
        config = (
            ROOT / "shell" / "plugin" / "src" / "Caelestia" / "Config" / "barconfig.hpp"
        ).read_text(encoding="utf-8")
        compiled = re.search(r'u"id"_s, u"github"_s \}, \{ u"enabled"_s, (\w+) \}', config)
        self.assertIsNotNone(compiled, "the compiled defaults must still list a github entry")
        self.assertEqual(compiled.group(1), "false", "the GitHub widget must ship disabled")

        page = (
            ROOT / "shell" / "modules" / "nexus" / "pages" / "panels" / "taskbar" / "BarComponents.qml"
        ).read_text(encoding="utf-8")
        mirrored = re.search(r'\{ id: "github", enabled: (\w+)', page)
        self.assertIsNotNone(mirrored, "the Nexus defaults must still list a github entry")
        self.assertEqual(
            mirrored.group(1),
            "false",
            "the Nexus defaults must match the compiled default, or resetting re-enables it",
        )

    def test_settings_search_waits_for_a_pause_in_typing(self) -> None:
        """The published query drives two fzf searches, each building a delegate per hit.

        Publishing it straight from the text field meant both panes were rebuilt on
        every keystroke, which is what made typing feel laggy. Clearing the field is
        the exception: the locations list has to come back without a delay.
        """
        pane = (ROOT / "shell" / "modules" / "nexus" / "NavPane.qml").read_text(encoding="utf-8")

        self.assertNotIn(
            "onTextChanged: root.nState.searchQuery = text",
            pane,
            "the query must not be published on every keystroke",
        )
        self.assertIn("Timer {", pane, "a debounce timer has to gate the query")
        self.assertIn(
            "searchDebounce.restart()",
            pane,
            "each keystroke must restart the debounce window",
        )
        self.assertIn("root.clearQuery()", pane, "emptying the field must bypass the debounce")
        self.assertIn(
            'root.nState.searchQuery = ""',
            pane,
            "clearing the field must apply at once, not after the debounce window",
        )

        window = re.search(r"id: searchDebounce\s*\n\s*interval: (\d+)", pane)
        self.assertIsNotNone(window, "the debounce timer needs an interval to be read here")
        self.assertGreaterEqual(
            int(window.group(1)),
            300,
            "a window shorter than the gap between two keystrokes still fires mid-word",
        )

    def test_a_search_result_opens_its_subpage_on_the_first_try(self) -> None:
        """Opening a sub-page of a page that has not been built yet has to be queued.

        The page swap is animated, so openSubPage right after changing page still
        reaches the page on its way out. When that page has no sub-page at that
        index it calls closeSubPage, which pops the request, and the page that
        arrives opens at the top: the first search lands on the page, and only a
        second search, now that the page is already showing, lands on the section.
        """
        results = (
            ROOT / "shell" / "modules" / "nexus" / "navpane" / "SearchResults.qml"
        ).read_text(encoding="utf-8")
        self.assertNotIn(
            "nState.openSubPage(",
            results,
            "a search result must not open a sub-page itself: the outgoing page would take it",
        )
        self.assertIn(
            "nState.goToSubPage(",
            results,
            "both the click and the Enter key have to navigate through goToSubPage",
        )

        state = (ROOT / "shell" / "modules" / "nexus" / "NexusState.qml").read_text(encoding="utf-8")
        self.assertIn(
            "property int pendingSubPageIdx",
            state,
            "the request has to outlive the page swap, so it needs somewhere to wait",
        )
        self.assertIn(
            "function goToSubPage(pageIdx: int, subPageIdx: int)",
            state,
            "page plus sub-page navigation needs one entry point that knows about the swap",
        )

        stack = (
            ROOT / "shell" / "modules" / "nexus" / "common" / "StackPage.qml"
        ).read_text(encoding="utf-8")
        self.assertIn(
            "nState.pendingSubPageIdx",
            stack,
            "the incoming page is the only one that can open a queued sub-page",
        )

    def test_the_font_controls_are_reachable_from_search(self) -> None:
        """Search is driven by PageDictionary, so a section missing from it is invisible.

        The Appearance page holds the font and monospace font pickers, but the only
        entry that mentioned fonts was the page description, so searching "font"
        returned the page and nothing that leads to those pickers.
        """
        lines = (
            ROOT / "shell" / "modules" / "nexus" / "PageDictionary.qml"
        ).read_text(encoding="utf-8").splitlines()

        for label in ("Font", "Monospace font", "Font scale"):
            entries = [line for line in lines if f'label: qsTr("{label}")' in line]
            self.assertTrue(entries, f'"{label}" must be a searchable settings entry')
            self.assertTrue(
                any("font" in line.lower() for line in entries),
                f'the "{label}" entry needs a font keyword, or searching "font" misses it',
            )

    def test_every_settings_subpage_is_reachable_from_search(self) -> None:
        """PageDictionary is the only thing search indexes, so a page missing from it is a dead end.

        Nothing else notices: the page still renders and is still reachable by
        clicking through, so a sub-page can sit unsearchable indefinitely. The
        audit also reports the section headers and setting rows that are not
        indexed individually; only the sub-pages are gated.
        """
        script = Path(".github", "scripts", "audit_search_coverage.py")
        self.assertTrue((ROOT / script).is_file(), f"expected {script.as_posix()} to exist")

        result = subprocess.run(
            [sys.executable, script.as_posix()],
            capture_output=True,
            text=True,
            cwd=ROOT,
        )
        self.assertEqual(
            result.returncode,
            0,
            "search coverage audit failed:\n" + (result.stdout or "") + (result.stderr or ""),
        )

    def test_the_dev_timeline_rewrites_commit_subjects(self) -> None:
        """Raw subjects read as a git log dump rather than as what changed.

        On the dev branch every row showed the commit subject verbatim, so half the
        list was "Merge pull request #697 from somebody/branch" and the type was
        printed twice, once as a chip and once as the "fix(scope):" prefix.
        """
        timeline = (
            ROOT / "shell" / "modules" / "nexus" / "common" / "UpdateTimeline.qml"
        ).read_text(encoding="utf-8")

        self.assertNotIn(
            'text: entry.modelData.subject || ""',
            timeline,
            "the raw subject must be rewritten before it is rendered",
        )
        self.assertIn(
            "function mergedSubject",
            timeline,
            "a pull-request merge must be shown as what landed, not as the merge itself",
        )
        self.assertIn(
            "function typeStrippedSubject",
            timeline,
            "the type chip already names the commit type, so the subject must not repeat it",
        )

    def test_the_dev_timeline_hides_merge_commits(self) -> None:
        """Merges carry no change of their own and made up half of the dev list.

        The commit the running shell is installed at has to stay, though: it is how
        the timeline marks where the user is.
        """
        page = (
            ROOT / "shell" / "modules" / "nexus" / "pages" / "UpdatesPage.qml"
        ).read_text(encoding="utf-8")

        self.assertIn(
            'filter(e => !e.isMerge || e.state === "current")',
            page,
            "merge commits must be dropped from the dev timeline, except the installed one",
        )

    def test_the_shortcut_list_does_not_animate_endlessly(self) -> None:
        """An endless animation in a settings list recomposites the window every frame.

        The collision marker pulsed forever; on a translucent window with a backdrop
        blur that reads as the whole window blinking. A static dot and its tooltip
        carry the same warning.
        """
        row = (
            ROOT / "shell" / "modules" / "nexus" / "common" / "ShortcutRow.qml"
        ).read_text(encoding="utf-8")

        self.assertNotIn(
            "Animation.Infinite",
            row,
            "nothing in the shortcut list may run an endless animation, or the window repaints forever",
        )
        self.assertIn("partCollisionName", row, "the collision must still be reported")

    def test_the_desktop_is_not_painted_black_while_the_wallpaper_loads(self) -> None:
        """The desktop went black whenever the shell started or restarted.

        The background window was created black, while the wallpaper is loaded
        asynchronously and only starts loading a couple of event loop turns later,
        so a starting shell showed a black desktop for as long as the image took to
        decode. The fallback color now waits for the wallpaper to report that it
        has something to show, and until then the desktop the compositor already
        has keeps showing through.
        """
        background = (
            ROOT / "shell" / "modules" / "background" / "Background.qml"
        ).read_text(encoding="utf-8")

        self.assertNotIn(
            'color: Config.background.wallpaperEnabled ? "black" : "transparent"',
            background,
            "the desktop must not be painted black before the wallpaper is up",
        )
        self.assertIn(
            "wallpaperUp: wallpaper.item?.shown",
            background,
            "the fallback black has to wait for the wallpaper to be shown",
        )
        self.assertIn(
            "Config.background.wallpaperEnabled && wallpaperHasBeenUp",
            background,
            "readiness must latch, or a flipping status blinks the desktop surface",
        )

        wallpaper = (
            ROOT / "shell" / "modules" / "background" / "Wallpaper.qml"
        ).read_text(encoding="utf-8")
        self.assertIn(
            "readonly property bool shown",
            wallpaper,
            "the wallpaper has to report being shown",
        )
        self.assertIn(
            "? wallpaperVideo.playing : wallpaperImage.status === Image.Ready",
            wallpaper,
            "an image is shown once it has decoded, a video once it plays",
        )

    def test_the_visualiser_does_not_spin_without_audio(self) -> None:
        """The desktop repainted every frame from boot, which reads as flashing.

        VisualiserBars::setValues() cleared settled on every update, including an
        empty value list, and advance() returns early for an empty list, so nothing
        ever set it back. The frame loop in Visualiser.qml is gated on !settled, so
        it ran every frame for as long as the shell was up, repainting the whole
        desktop surface and its blurred wallpaper again and again. Nothing on
        screen changes while that happens, which is why a screenshot looks static.
        """
        bars = (
            ROOT / "shell" / "plugin" / "src" / "Caelestia" / "Components" / "visualiserbars.cpp"
        ).read_text(encoding="utf-8")

        start = bars.find("void VisualiserBars::setValues")
        end = bars.find("bool VisualiserBars::settled")
        self.assertNotEqual(start, -1, "setValues should still exist")
        self.assertNotEqual(end, -1, "settled() should still exist")
        body = bars[start:end]

        self.assertIn(
            "values.isEmpty()",
            body,
            "an empty value list means the bars have nothing to animate",
        )
        self.assertIn(
            "m_settled = true",
            body,
            "nothing to animate has to report settled, or the frame loop never stops",
        )

        visualiser = (
            ROOT / "shell" / "modules" / "background" / "Visualiser.qml"
        ).read_text(encoding="utf-8")
        frame_at = visualiser.find("FrameAnimation")
        self.assertNotEqual(frame_at, -1, "the visualiser should still drive the bars by frame")
        self.assertIn(
            "Audio.cava?.values?.length",
            visualiser[frame_at:frame_at + 600],
            "the frame loop must not run without values to advance",
        )

    def test_a_startup_reseed_takes_the_scheme_from_the_wallpaper(self) -> None:
        """The CLI derives dynamic colors from the wallpaper it was last told about.

        path.txt is written directly by the deploy script and by the wallpaper
        picker's still-frame path, so the CLI can be left without a wallpaper.
        `scheme set -n dynamic` then writes nothing, the palette stays on the
        shell's built-in default, and that default is what the whole desktop
        shows until something re-derives. Deriving once per start from the
        wallpaper on screen fixes it at the source; leaving a scheme the user
        picked alone is what keeps this from undoing their choice.
        """
        colours = (ROOT / "shell" / "services" / "Colours.qml").read_text(encoding="utf-8")
        self.assertIn(
            'Quickshell.shellPath("scripts/reseed-scheme.sh")',
            colours,
            "the shell has to re-derive its scheme at start, not only when the user picks one",
        )
        self.assertIn(
            "reseedTimer.start()",
            colours,
            "the reseed has to run on its own at startup",
        )

        script_path = ROOT / "shell" / "scripts" / "reseed-scheme.sh"
        self.assertTrue(script_path.is_file(), "reseed-scheme.sh must exist to be run")
        script = script_path.read_text(encoding="utf-8")

        self.assertIn(
            '"$CURRENT" != "dynamic"',
            script,
            "a scheme the user picked must not be overwritten, even by a fix for this",
        )
        self.assertIn(
            "caelestia wallpaper -f",
            script,
            "the CLI needs the wallpaper before it can derive dynamic colors",
        )


class WhatsNewEntryTests(unittest.TestCase):
    """The release notes are data, and nothing validates them at runtime.

    A duplicate revision means one of the two entries is never shown to anybody,
    a media file that is not there renders an empty entry, and a bare title or
    description is invisible to lupdate so it stays English in every locale.
    None of those fail loudly on their own, so they are checked here.
    """

    ENTRIES = ROOT / "shell" / "modules" / "whatsnew" / "Entries.qml"
    ASSETS = ROOT / "shell" / "assets" / "whatsnew"
    SHELL = ROOT / "shell"

    def entries(self) -> list[dict]:
        """Parse the entry list. Field order within an entry is fixed by the file."""
        text = self.ENTRIES.read_text(encoding="utf-8")
        start = text.index("readonly property var list: [")
        end = text.index("\n    ]", start)
        chunks = text[start:end].split('"id":')[1:]
        self.assertTrue(chunks, "Entries.qml declares no entries")

        parsed = []
        for chunk in chunks:
            identifier = re.match(r'\s*"([^"]*)"', chunk)
            revision = re.search(r'"revision":\s*(\d+)', chunk)
            media = re.search(r'"mediaUrl":\s*"([^"]*)"', chunk)
            parsed.append(
                {
                    "id": identifier.group(1) if identifier else "",
                    "revision": int(revision.group(1)) if revision else None,
                    "title": bool(re.search(r'"title":\s*qsTr\(', chunk)),
                    "description": bool(re.search(r'"description":\s*qsTr\(', chunk)),
                    "media": media.group(1) if media else "",
                }
            )
        return parsed

    def test_revisions_are_unique_and_ascending(self) -> None:
        revisions = [entry["revision"] for entry in self.entries()]

        self.assertNotIn(None, revisions, "every entry needs a numeric revision")
        self.assertEqual(len(revisions), len(set(revisions)), f"duplicate revisions: {revisions}")
        self.assertEqual(
            revisions,
            sorted(revisions),
            "entries are listed oldest first, so appending an entry is what raises its revision",
        )

    def test_ids_are_unique(self) -> None:
        ids = [entry["id"] for entry in self.entries()]

        self.assertNotIn("", ids, "every entry needs an id")
        self.assertEqual(len(ids), len(set(ids)), f"duplicate ids: {ids}")

    def test_text_is_extractable(self) -> None:
        bare = [entry["id"] for entry in self.entries() if not (entry["title"] and entry["description"])]

        self.assertEqual(
            bare,
            [],
            "titles and descriptions must be wrapped in qsTr() so lupdate can extract them: " + ", ".join(bare),
        )

    def test_media_files_exist(self) -> None:
        missing = []
        for entry in self.entries():
            url = entry["media"]
            if not url:
                continue
            if ".." in url:
                missing.append(f"{entry['id']}: {url} (must stay inside the assets directory)")
                continue

            path = self.SHELL / url[len("root:/") :] if url.startswith("root:/") else self.ASSETS / url
            if not path.is_file():
                missing.append(f"{entry['id']}: {url}")

        self.assertEqual(
            missing,
            [],
            "media referenced by the release notes must exist:\n" + "\n".join(missing),
        )


class MetadataConsistencyTests(unittest.TestCase):
    def test_shell_version_matches_about_page(self) -> None:
        cmake_text = (ROOT / "shell" / "CMakeLists.txt").read_text(encoding="utf-8")
        about_text = (ROOT / "shell" / "modules" / "nexus" / "pages" / "AboutPage.qml").read_text(
            encoding="utf-8"
        )

        self.assertIn(
            ".github/version.env",
            cmake_text,
            "shell/CMakeLists.txt must read the version from version.env",
        )
        self.assertNotRegex(
            cmake_text,
            r'set\(VERSION\s+"[^"]*\d[^"]*"\)',
            "shell/CMakeLists.txt hardcodes a version - bump version.env only",
        )
        self.assertIn("CUtils.version", about_text, "About page must use dynamic CUtils.version logic")

    def test_validation_scripts_referenced_by_docs_exist(self) -> None:
        contributing_text = (ROOT / ".github" / "CONTRIBUTING.md").read_text(encoding="utf-8")

        referenced = [
            "shell/scripts/qml-lint-conventions.py",
        ]

        for rel_path in referenced:
            if rel_path in contributing_text:
                self.assertTrue((ROOT / rel_path).is_file(), f"Missing referenced file: {rel_path}")


class VersionConsistencyTests(unittest.TestCase):
    def test_cmake_has_no_hardcoded_version(self) -> None:
        """version.env is the single source of truth - CMakeLists derives from it."""
        env_text = (ROOT / ".github" / "version.env").read_text(encoding="utf-8").strip()
        env_match = re.match(r"^VERSION=(v[\d.]+)$", env_text)
        self.assertIsNotNone(env_match, f"Invalid version.env format: {env_text!r}")

        cmake_text = (ROOT / "shell" / "CMakeLists.txt").read_text(encoding="utf-8")
        self.assertIn(
            ".github/version.env",
            cmake_text,
            "shell/CMakeLists.txt must derive its version from version.env",
        )
        self.assertIsNone(
            re.search(r'set\(VERSION\s+"[^"]*\d[^"]*"\)', cmake_text),
            "shell/CMakeLists.txt must not hardcode a version - bump version.env only",
        )

    def test_version_format_valid(self) -> None:
        """Version must follow semver-like vX.Y.Z format."""
        env_text = (ROOT / ".github" / "version.env").read_text(encoding="utf-8").strip()
        env_match = re.match(r"^VERSION=(v\d+\.\d+\.\d+)$", env_text)
        self.assertIsNotNone(
            env_match,
            f"version.env must contain VERSION=vX.Y.Z, got: {env_text!r}"
        )

    def test_updater_records_the_installed_revision_through_the_shared_helper(self) -> None:
        """Update scripts must record the installed commit for delta checks.

        Writing it inline here is what let the updater claim a revision whose
        build was skipped (#651); the shared helper refuses to in that case.
        """
        update_script = ROOT / "src" / "bin" / "caelestia-update"
        if not update_script.is_file():
            return  # not required if file doesn't exist yet

        content = update_script.read_text(encoding="utf-8")
        self.assertIn(
            "record_installed_revision",
            content,
            "caelestia-update must record the installed revision for update detection",
        )
        self.assertNotIn(
            "> ~/.config/quickshell/caelestia/.current_commit",
            content,
            "the revision must be written by the shared helper, not inline",
        )


class SubmoduleTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("git"), "git is required for submodule checks")
    def test_submodule_references_valid(self) -> None:
        """If .gitmodules exists, referenced paths and URLs should be consistent."""
        gitmodules = ROOT / ".gitmodules"
        if not gitmodules.is_file():
            return

        content = gitmodules.read_text(encoding="utf-8")
        paths = re.findall(r"^\s*path\s*=\s*(.+)$", content, re.MULTILINE)
        urls = re.findall(r"^\s*url\s*=\s*(.+)$", content, re.MULTILINE)

        self.assertTrue(paths, ".gitmodules exists but has no 'path' entries")
        self.assertEqual(
            len(paths), len(urls),
            f"Mismatch: {len(paths)} paths but {len(urls)} URLs in .gitmodules"
        )

        for sub_path in paths:
            full_path = ROOT / sub_path.strip()
            self.assertTrue(
                full_path.is_dir(),
                f"Submodule path '{sub_path}' does not exist - run git submodule update --init"
            )


class WorkflowYamlTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("python3"), "python3 required for YAML parse")
    def test_workflow_files_parse(self) -> None:
        """All .yml files in .github/workflows/ should be valid YAML."""
        try:
            import yaml  # type: ignore[import-untyped]
        except ImportError:
            return

        workflows_dir = ROOT / ".github" / "workflows"
        if not workflows_dir.is_dir():
            return

        for wf_file in sorted(workflows_dir.glob("*.yml")):
            with self.subTest(file=wf_file.name):
                try:
                    with open(wf_file, encoding="utf-8") as f:
                        yaml.safe_load(f)
                except yaml.YAMLError as e:
                    self.fail(f"Invalid YAML in {wf_file.name}: {e}")


class DocsReferenceTests(unittest.TestCase):
    def test_contributing_references_existing_files(self) -> None:
        """Files mentioned in CONTRIBUTING.md should exist."""
        contributing = ROOT / ".github" / "CONTRIBUTING.md"
        if not contributing.is_file():
            return

        text = contributing.read_text(encoding="utf-8")
        doc_refs = re.findall(r"`(docs/[^`]+\.md)`", text)
        for ref in doc_refs:
            self.assertTrue(
                (ROOT / ref).is_file(),
                f"CONTRIBUTING.md references '{ref}' which does not exist"
            )


class KrohnkiteIgnoreClassTests(unittest.TestCase):
    """The C++ fallback and the startup task must name the same window classes.

    Nexus renders DEFAULT_IGNORE_CLASS when kwinrc has no ignoreClass key and writes it
    back on the first edit, so a fallback that lags IGNORE_CLASSES drops every class it is
    missing from kwinrc for the rest of the session.
    """

    def test_default_ignore_class_matches_the_startup_task(self) -> None:
        cpp_path = ROOT / "shell" / "plugin" / "src" / "Caelestia" / "Services" / "krohnkiteconfig.cpp"
        cpp = cpp_path.read_text(encoding="utf-8")
        literal = re.search(r"DEFAULT_IGNORE_CLASS\s*=\s*QStringLiteral\((.*?)\);", cpp, re.DOTALL)
        self.assertIsNotNone(literal, "DEFAULT_IGNORE_CLASS should be built from a QStringLiteral")

        cpp_classes: list[str] = []
        for chunk in re.findall(r'"([^"]*)"', literal.group(1)):
            cpp_classes.extend(entry for entry in chunk.split(",") if entry)

        script_path = ROOT / "shell" / "services" / "startuptasks" / "02-krohnkite-setup.sh"
        script = script_path.read_text(encoding="utf-8")
        block = re.search(r"IGNORE_CLASSES=\((.*?)\n\)", script, re.DOTALL)
        self.assertIsNotNone(block, "the startup task should declare IGNORE_CLASSES")
        script_classes = [line.strip() for line in block.group(1).splitlines() if line.strip()]

        self.assertEqual(
            cpp_classes,
            script_classes,
            "DEFAULT_IGNORE_CLASS in krohnkiteconfig.cpp and IGNORE_CLASSES in 02-krohnkite-setup.sh have drifted",
        )


if __name__ == "__main__":
    suite = unittest.defaultTestLoader.loadTestsFromModule(sys.modules[__name__])
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    sys.exit(0 if result.wasSuccessful() else 1)
