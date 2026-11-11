"""Exercise appcast validation without network access or real signing keys."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
GENERATOR = REPO / "scripts/generate-appcast.sh"


class AppcastTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.tools = self.root / "bin"
        self.tools.mkdir()
        self.work = self.root / "work"
        self.work.mkdir()
        self.archive = self.root / "rankbuddy-v1.2.3.dmg"
        self.archive.write_bytes(b"synthetic update archive")
        self.log = self.root / "download.json"
        self.tar_log = self.root / "extracted"
        self.secret = "synthetic-private-signing-material-for-test-only"
        curl = self.tools / "curl"
        curl.write_text('''#!/usr/bin/env python3
import json, os, pathlib, sys
secret = os.environ["SPARKLE_PRIVATE_ED_KEY"].encode()
visible = any(secret in p.read_bytes() for p in pathlib.Path(os.environ["TMPDIR"]).rglob("*") if p.is_file())
pathlib.Path(os.environ["TEST_DOWNLOAD_LOG"]).write_text(json.dumps({"args": sys.argv[1:], "key_visible": visible}))
pathlib.Path(sys.argv[sys.argv.index("-o") + 1]).write_bytes(b"untrusted downloaded archive")
''')
        curl.chmod(0o755)
        tar = self.tools / "tar"
        tar.write_text('#!/bin/sh\ntouch "$TEST_TAR_LOG"\nexit 99\n')
        tar.chmod(0o755)
        self.env = os.environ.copy()
        for name in ("SPARKLE_VERSION", "GITHUB_REPOSITORY", "GITHUB_SERVER_URL"):
            self.env.pop(name, None)
        self.env.update(PATH=str(self.tools) + os.pathsep + self.env["PATH"],
                        TMPDIR=str(self.work), SPARKLE_PRIVATE_ED_KEY=self.secret,
                        TEST_DOWNLOAD_LOG=str(self.log), TEST_TAR_LOG=str(self.tar_log))

    def run_generator(self, tag="v1.2.3", archive=None, **environment):
        return subprocess.run([str(GENERATOR), tag, str(archive or self.archive)],
                              cwd=self.root, env=self.env | environment,
                              capture_output=True, text=True)

    def assert_rejected_before_download(self, **arguments):
        self.log.unlink(missing_ok=True)
        result = self.run_generator(**arguments)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.log.exists(), result.stdout + result.stderr)

    def test_resolved_tool_version_reaches_download_stage(self):
        result = self.run_generator()
        self.assertIn("Sparkle archive checksum mismatch", result.stderr)
        data = json.loads(self.log.read_text())
        resolved = json.loads((REPO / "rankbuddy-macos.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved").read_text())
        version = next(pin["state"]["version"] for pin in resolved["pins"] if pin["identity"] == "sparkle")
        self.assertIn(f"https://github.com/sparkle-project/Sparkle/releases/download/{version}/Sparkle-{version}.tar.xz", data["args"])

    def test_untrusted_archive_cannot_reach_extraction_or_signing_key(self):
        self.assertNotEqual(self.run_generator().returncode, 0)
        self.assertFalse(json.loads(self.log.read_text())["key_visible"])
        self.assertFalse(self.tar_log.exists())
        self.assertEqual(list(self.work.iterdir()), [])

    def test_failed_generation_preserves_existing_feed(self):
        feed = self.root / "appcast.xml"
        feed.write_text("existing signed feed")
        self.assertNotEqual(self.run_generator().returncode, 0)
        self.assertEqual(feed.read_text(), "existing signed feed")

    def test_invalid_tags_stop_before_download(self):
        for tag in ("../latest", "v1.2", "v01.2.3", "v1.2.3?x", "v1.2.3#x"):
            with self.subTest(tag=tag):
                self.assert_rejected_before_download(tag=tag)

    def test_archive_name_must_identify_the_same_release(self):
        for name in ("update.dmg", "rankbuddy-v1.2.3 copy.dmg", "rankbuddy-v1.2.4.dmg", "rankbuddy-v1.2.3.dmg?x"):
            with self.subTest(name=name):
                archive = self.root / name
                archive.write_bytes(b"archive")
                self.assert_rejected_before_download(archive=archive)

    def test_invalid_download_destinations_stop_before_download(self):
        for origin in ("http://example.com", "https://user@example.com", "https://example.com/path", "https://example.com?query"):
            with self.subTest(origin=origin):
                self.assert_rejected_before_download(GITHUB_SERVER_URL=origin)
        for repository in ("owner", "owner/repo/extra", "owner/../repo", "owner /repo", "owner/repo?x"):
            with self.subTest(repository=repository):
                self.assert_rejected_before_download(GITHUB_REPOSITORY=repository)

    def test_symlink_output_does_not_replace_its_target(self):
        target = self.root / "target"
        target.write_text("unchanged")
        (self.root / "appcast.xml").symlink_to(target)
        self.assert_rejected_before_download()
        self.assertEqual(target.read_text(), "unchanged")

    def test_packager_is_directly_executable_and_validates_missing_input(self):
        result = subprocess.run([str(REPO / "scripts/package-and-notarize.sh")],
                                capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("usage:", result.stderr.lower())

    def test_unknown_tool_version_stops_before_download(self):
        self.assert_rejected_before_download(SPARKLE_VERSION="999.0.0")


if __name__ == "__main__":
    unittest.main()
