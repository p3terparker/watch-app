#!/usr/bin/env python3
"""Exercise build/install replacement safety without touching user apps."""
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

import watch_build
import watch_helpers
from types import SimpleNamespace


class ReplacementSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        # /var can itself be a system symlink on macOS.
        self.root = Path(self.temporary.name).resolve()
        self.destination = self.root / "Example.app"
        self.destination.mkdir()
        (self.destination / "old").write_text("old app")
        self.staged = self.root / "staged.app"
        self.staged.mkdir()
        (self.staged / "new").write_text("new app")

    def tearDown(self):
        self.temporary.cleanup()

    def test_success_replaces_only_selected_bundle(self):
        unrelated = self.root / "Other.app"
        unrelated.mkdir()
        watch_build.publish_directory(self.staged, self.destination)
        self.assertEqual((self.destination / "new").read_text(), "new app")
        self.assertTrue(unrelated.is_dir())
        self.assertFalse(self.destination.with_name("Example.app.previous").exists())

    def test_failed_publication_restores_previous_bundle(self):
        original_rename = Path.rename
        staged = self.staged

        def fail_staged(path, target):
            if path == staged:
                raise OSError("simulated filesystem failure")
            return original_rename(path, target)

        with patch.object(Path, "rename", fail_staged):
            with self.assertRaises(OSError):
                watch_build.publish_directory(self.staged, self.destination)
        self.assertEqual((self.destination / "old").read_text(), "old app")
        self.assertTrue(self.staged.exists())

    def test_symlink_cannot_replace_an_unrelated_directory(self):
        link = self.root / "Linked.app"
        link.symlink_to(self.destination)
        with self.assertRaises(ValueError):
            watch_build.publish_directory(self.staged, link)
        self.assertEqual((self.destination / "old").read_text(), "old app")
        self.assertTrue(link.is_symlink())

    def test_previous_backup_requires_inspection(self):
        backup = self.destination.with_name("Example.app.previous")
        backup.mkdir()
        with self.assertRaises(ValueError):
            watch_build.publish_directory(self.staged, self.destination)
        self.assertEqual((self.destination / "old").read_text(), "old app")
        self.assertTrue(backup.is_dir())

    def test_output_symlink_is_rejected_before_creation(self):
        link = self.root / "build"
        link.symlink_to(self.destination)
        with self.assertRaises(ValueError):
            watch_build.output_directory(link / "native")
        self.assertFalse((self.destination / "native").exists())

    def test_wrong_app_metadata_is_rejected(self):
        import json
        config = json.loads(watch_build.CONFIG.read_text())
        config['name'] = 'Other'
        with self.assertRaisesRegex(ValueError, 'metadata'):
            watch_build.metadata(config)


class WatchHelperSafetyTests(unittest.TestCase):
    def inspect(self, archs='arm64 x86_64', library='/usr/lib/libSystem.B.dylib', loads='cmd LC_BUILD_VERSION\n minos 13.0'):
        results = [SimpleNamespace(stdout=archs), SimpleNamespace(stdout='fixture:\n\t' + library + ' (compatibility version 1.0.0)'), SimpleNamespace(stdout=loads)]
        with patch.object(watch_helpers, 'run', side_effect=results):
            watch_helpers.inspect_binary(Path('/fixture'))

    def test_universal_system_only_accepted(self):
        self.inspect()

    def test_thin_binary_rejected(self):
        with self.assertRaises(ValueError): self.inspect(archs='arm64')

    def test_homebrew_library_rejected(self):
        with self.assertRaises(ValueError): self.inspect(library='/opt/homebrew/lib/libmp3lame.dylib')

    def test_newer_macos_rejected(self):
        with self.assertRaises(ValueError): self.inspect(loads='cmd LC_BUILD_VERSION\n minos 14.0')

    def test_legacy_newer_macos_rejected(self):
        with self.assertRaises(ValueError): self.inspect(loads='cmd LC_VERSION_MIN_MACOSX\n version 14.0')

    def test_dylib_version_not_confused_with_os(self):
        self.inspect(loads='cmd LC_ID_DYLIB\n version 99.0')

    def test_corrupted_download_rejected_without_network(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / 'helper').write_bytes(b'corrupt')
            with patch.object(watch_helpers, 'CACHE', root), patch.object(watch_helpers.urllib.request, 'urlopen') as network:
                with self.assertRaises(ValueError):
                    watch_helpers.fetch('helper', {'sha256': 'not-matching', 'url': 'https://invalid.test'})
                network.assert_not_called()

    def test_matching_download_reused_without_network(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            path = root / 'helper'; path.write_bytes(b'verified fixture')
            with patch.object(watch_helpers, 'CACHE', root), patch.object(watch_helpers.urllib.request, 'urlopen') as network:
                self.assertEqual(watch_helpers.fetch('helper', {'sha256': watch_helpers.digest(path)}), path)
                network.assert_not_called()


if __name__ == "__main__":
    unittest.main()
