#!/usr/bin/env python3
"""Regression checks for the fail-closed Android in-app update release gate."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from verify_android_update_signing import (  # noqa: E402
    IncompatibleUpdate,
    RELEASE_BASE,
    RELEASES,
    check_update,
    package_identity,
    published_apk,
    signer_digest,
)

SHA = "ab" * 32


class AndroidUpdateGateTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.feed = Path(self.tmp.name)
        self.new = self.feed / "new-arm64.apk"
        self.new.write_bytes(b"fresh-signed-apk-mock")
        self.old = {}
        for label, (manifest, filename) in RELEASES.items():
            old = self.feed / filename
            payload = ("published-" + label).encode()
            old.write_bytes(payload)
            self.old[label] = old
            (self.feed / manifest).write_text(json.dumps({
                "app": "nca_admin" if label == "Admin" else "nca_viewer",
                "apk_url": RELEASE_BASE + filename,
                "abi": "arm64-v8a",
                "sha256": hashlib.sha256(payload).hexdigest(),
                "size_bytes": len(payload),
                "version_name": "2.5.3" if label == "Admin" else "9.8.0",
                "build_number": 30739,
            }), encoding="utf-8")

    def test_valid_single_signer(self):
        self.assertEqual(signer_digest(
            "Signer #1 certificate SHA-256 digest: " + SHA + "\n"), SHA)

    def test_rejects_two_signers_or_bad_digest(self):
        for output in [
            "", "Signer #1 certificate SHA-256 digest: 1234\n",
            "Signer #2 certificate SHA-256 digest: " + SHA + "\n",
            "Signer #1 certificate SHA-256 digest: " + SHA + "\n" +
            "Signer #2 certificate SHA-256 digest: " + SHA + "\n",
        ]:
            with self.subTest(output=output), self.assertRaises(IncompatibleUpdate):
                signer_digest(output)

    def test_package_identity_reads_code_not_version_name(self):
        text = "package: name='com.example.nca' versionCode='30739003' versionName='9.8.0'\n"
        self.assertEqual(package_identity(text), ("com.example.nca", 30739003))
        with self.assertRaises(IncompatibleUpdate):
            package_identity("not a badging response")

    def test_published_feed_is_verified_against_manifest(self):
        self.assertEqual(published_apk(self.feed, "Viewer"), self.old["Viewer"])
        self.old["Viewer"].write_bytes(b"tampered")
        with self.assertRaisesRegex(IncompatibleUpdate, "size does not match"):
            published_apk(self.feed, "Viewer")

    def test_rejects_forged_manifest_url_or_digest(self):
        path = self.feed / RELEASES["Admin"][0]
        for value in [
            {"apk_url": "https://attacker.example/changed.apk"},
            {"sha256": "0" * 64},
            {"abi": "universal"},
            {"app": "not-admin"},
        ]:
            original = json.loads(path.read_text())
            path.write_text(json.dumps({**original, **value}))
            try:
                with self.assertRaises(IncompatibleUpdate):
                    published_apk(self.feed, "Admin")
            finally:
                path.write_text(json.dumps(original))

    def test_same_package_cert_and_newer_version_pass_for_both(self):
        import verify_android_update_signing as gate
        for label in RELEASES:
            with patch.object(gate, "apk_identity", side_effect=[
                ("com.example.nca", 30739003, SHA),
                ("com.example.nca", 30740003, SHA),
            ]):
                check_update(label, feed_dir=self.feed, new_path=self.new,
                             apksigner="signer", aapt="aapt")

    def test_signing_rotation_package_change_and_old_version_are_blocked(self):
        import verify_android_update_signing as gate
        mismatches = [
            ("com.example.nca", 30740003, "cd" * 32),
            ("com.example.other", 30740003, SHA),
            ("com.example.nca", 30739003, SHA),
            ("com.example.nca", 30738003, SHA),
        ]
        for candidate in mismatches:
            with self.subTest(candidate=candidate):
                with patch.object(gate, "apk_identity", side_effect=[
                    ("com.example.nca", 30739003, SHA), candidate,
                ]):
                    with self.assertRaisesRegex(IncompatibleUpdate, "BLOCKED"):
                        check_update("Viewer", feed_dir=self.feed,
                                     new_path=self.new, apksigner="signer", aapt="aapt")

    def test_missing_old_release_fails_closed(self):
        self.old["Admin"].unlink()
        with self.assertRaisesRegex(IncompatibleUpdate, "missing"):
            published_apk(self.feed, "Admin")


if __name__ == "__main__":
    unittest.main()
