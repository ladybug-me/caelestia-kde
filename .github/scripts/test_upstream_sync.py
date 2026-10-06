import importlib.util
import pathlib
import subprocess
import sys
import tempfile
import unittest


ROOT = pathlib.Path(__file__).parents[2]
TOOL_PATH = ROOT / "tools" / "sync-shell.py"


spec = importlib.util.spec_from_file_location("sync_shell", TOOL_PATH)
assert spec and spec.loader
sync_shell = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync_shell)


class UpstreamBoundaryTests(unittest.TestCase):
    def make_fixture_repo(self, directory: pathlib.Path) -> None:
        def git(*args: str) -> None:
            subprocess.run(["git", *args], cwd=directory, check=True, capture_output=True)

        git("init", "-q")
        git("config", "user.email", "test@example.com")
        git("config", "user.name", "Test")
        (directory / "shell").mkdir()
        (directory / "shell" / "shared.qml").write_text("same", encoding="utf-8")
        (directory / "shell" / "adapted.qml").write_text("kde-adaptation", encoding="utf-8")
        (directory / "shell" / "kde-only.qml").write_text("port-only", encoding="utf-8")
        git("add", ".")
        git("commit", "-qm", "shell baseline")
        git("branch", "upstream/main")
        git("checkout", "-q", "upstream/main")
        (directory / "shell" / "adapted.qml").unlink()
        (directory / "shell" / "kde-only.qml").unlink()
        (directory / "adapted.qml").write_text("upstream-version", encoding="utf-8")
        (directory / "upstream-only.qml").write_text("upstream-only", encoding="utf-8")
        git("add", ".")
        git("commit", "-qm", "upstream snapshot")
        git("checkout", "-q", "-B", "main", "HEAD~1")

    def run_tool(self, root: pathlib.Path, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(TOOL_PATH), "--root", str(root), *args],
            capture_output=True, text=True, check=True,
        )

    def test_report_classifies_real_fixture_repository(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            self.make_fixture_repo(root)
            result = self.run_tool(root, "report", "--full")

            self.assertIn("adapted.qml", result.stdout)
            self.assertIn("upstream-only.qml", result.stdout)
            self.assertIn("kde-only: 2", result.stdout)

    def test_fixture_paths_are_classified_by_ownership_and_content(self) -> None:
        shell = {
            "shared.qml": "same",
            "adapted.qml": "kde-adaptation",
            "kde-only.qml": "port-only",
        }
        upstream = {
            "shared.qml": "same",
            "adapted.qml": "upstream-version",
            "upstream-only.qml": "upstream-only",
        }

        result = sync_shell.classify_paths(shell, upstream)

        self.assertEqual(result.in_sync, ["shared.qml"])
        self.assertEqual(result.diverged, ["adapted.qml"])
        self.assertEqual(result.missing, ["upstream-only.qml"])
        self.assertEqual(result.kde_only, ["kde-only.qml"])

    def test_classification_does_not_treat_kde_files_as_missing(self) -> None:
        result = sync_shell.classify_paths(
            {"modules/kde.qml": "local"},
            {"modules/upstream.qml": "remote"},
        )

        self.assertEqual(result.missing, ["modules/upstream.qml"])
        self.assertEqual(result.kde_only, ["modules/kde.qml"])

    def test_bring_refuses_to_overwrite_an_existing_file_without_force(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            self.make_fixture_repo(root)
            target = root / "shell" / "adapted.qml"

            result = self.run_tool(root, "bring", "adapted.qml")
            self.assertIn("already exists in shell/", result.stdout)
            self.assertEqual("kde-adaptation", target.read_text(encoding="utf-8"))

            result = self.run_tool(root, "bring", "--force", "adapted.qml")
            self.assertIn("overwrite adapted.qml", result.stdout)
            self.assertEqual("upstream-version", target.read_text(encoding="utf-8"))

    def test_bring_reports_paths_absent_from_upstream(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            self.make_fixture_repo(root)

            result = self.run_tool(root, "bring", "kde-only.qml")

            self.assertIn("not present in upstream/main", result.stdout)
            self.assertEqual("port-only", (root / "shell" / "kde-only.qml").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
