import json
import tempfile
import unittest
from pathlib import Path

from check_provenance import validate
from packaging_contract import PACKAGE_ONLY_PREFIXES, PROVENANCE_RELATIVE
from write_provenance_hash import update


class ProvenanceTests(unittest.TestCase):
    def test_template_has_required_path_independent_fields(self) -> None:
        template = Path(__file__).parents[2] / "shell" / "build-provenance.json.in"
        fields = set(json.loads(template.read_text(encoding="utf-8")).keys())
        self.assertEqual(fields, {
            "source_revision", "dependency_revision", "build_type", "compiler",
            "cmake_version", "qt_version", "hash_algorithm", "artifact_root_hash",
        })

    def test_valid_metadata_passes(self) -> None:
        data = {
            "source_revision": "a" * 40,
            "dependency_revision": "b" * 40,
            "build_type": "Release",
            "compiler": "GNU 14.2",
            "cmake_version": "3.31.0",
            "qt_version": "6.8.0",
            "hash_algorithm": "sha256",
            "artifact_root_hash": "c" * 64,
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "provenance.json"
            path.write_text(json.dumps(data), encoding="utf-8")
            self.assertEqual(validate(path), [])

    def test_user_paths_and_invalid_revisions_are_rejected(self) -> None:
        data = {field: "ok" for field in (
            "source_revision", "dependency_revision", "build_type", "compiler",
            "cmake_version", "qt_version", "hash_algorithm", "artifact_root_hash",
        )}
        data["source_revision"] = "C:/Users/camus/repo"
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "provenance.json"
            path.write_text(json.dumps(data), encoding="utf-8")
            failures = validate(path)
            self.assertTrue(any("source_revision" in failure for failure in failures))

    def test_artifact_hash_is_deterministic_and_excludes_metadata(self) -> None:
        data = {
            "source_revision": "unknown", "dependency_revision": "unknown",
            "build_type": "Release", "compiler": "GNU", "cmake_version": "3",
            "qt_version": "unknown", "hash_algorithm": "sha256",
            "artifact_root_hash": "pending-install",
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            metadata = root / PROVENANCE_RELATIVE
            metadata.parent.mkdir(parents=True)
            (root / "usr/bin/tool").parent.mkdir(parents=True)
            (root / "usr/bin/tool").write_text("stable", encoding="utf-8")
            metadata.write_text(json.dumps(data), encoding="utf-8")
            update(metadata, root)
            first = json.loads(metadata.read_text(encoding="utf-8"))["artifact_root_hash"]
            update(metadata, root)
            second = json.loads(metadata.read_text(encoding="utf-8"))["artifact_root_hash"]
            self.assertEqual(first, second)
            self.assertEqual(len(first), 64)

    def _metadata(self, root: Path) -> Path:
        metadata = root / PROVENANCE_RELATIVE
        metadata.parent.mkdir(parents=True, exist_ok=True)
        metadata.write_text(json.dumps({"hash_algorithm": "sha256"}), encoding="utf-8")
        return metadata

    def _root_hash(self, metadata: Path) -> str:
        return json.loads(metadata.read_text(encoding="utf-8"))["artifact_root_hash"]

    def test_root_hash_ignores_compiled_artifacts(self) -> None:
        """Compiled bytes track the build environment, not the layout."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            metadata = self._metadata(root)
            library = root / "usr/lib/qt6/qml/Caelestia/lib/libcaelestia-core.so"
            library.parent.mkdir(parents=True, exist_ok=True)
            library.write_text("build-source", encoding="utf-8")
            update(metadata, root)
            source_layout = self._root_hash(metadata)
            library.write_text("build-package", encoding="utf-8")
            update(metadata, root)
            self.assertEqual(source_layout, self._root_hash(metadata))

    def test_root_hash_ignores_every_package_only_path(self) -> None:
        """The hash has to cover the same paths the parity check allows, or the
        two staged trees would produce different hashes for the same layout."""
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            metadata = self._metadata(root)
            shell = root / "usr/share/caelestia/shell.qml"
            shell.parent.mkdir(parents=True, exist_ok=True)
            shell.write_text("qml", encoding="utf-8")
            update(metadata, root)
            source_layout = self._root_hash(metadata)

            for prefix in PACKAGE_ONLY_PREFIXES:
                with self.subTest(prefix=prefix):
                    package_only = root / prefix / "content"
                    package_only.parent.mkdir(parents=True, exist_ok=True)
                    package_only.write_text("package only", encoding="utf-8")
                    update(metadata, root)
                    self.assertEqual(source_layout, self._root_hash(metadata))


if __name__ == "__main__":
    unittest.main()
