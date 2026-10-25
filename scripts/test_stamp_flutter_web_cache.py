"""Regression tests for static-host Flutter cache stamping."""
import tempfile
import unittest
from pathlib import Path

from stamp_flutter_web_cache import stamp_flutter_web


class StampFlutterWebTests(unittest.TestCase):
    def test_stamps_index_404_and_dart2js_entrypoint(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            (base / "index.html").write_text(
                '<link rel="preload" href="main.dart.js" as="script">'
                '<script src="flutter_bootstrap.js" async></script>',
                encoding="utf-8",
            )
            (base / "flutter_bootstrap.js").write_text(
                """_flutter.buildConfig={"builds":[{"mainJsPath":"main.dart.js"}]};""",
                encoding="utf-8",
            )
            stamp_flutter_web(base, "abc123-5")
            self.assertIn(
                'flutter_bootstrap.js?v=abc123-5',
                (base / "index.html").read_text(),
            )
            self.assertIn(
                'main.dart.js?v=abc123-5',
                (base / "flutter_bootstrap.js").read_text(),
            )
            self.assertIn(
                'href="main.dart.js?v=abc123-5"',
                (base / "index.html").read_text(),
            )
            self.assertEqual(
                (base / "index.html").read_text(),
                (base / "404.html").read_text(),
            )

    def test_unsupported_flutter_output_fails_before_modifying(self):
        with tempfile.TemporaryDirectory() as directory:
            base = Path(directory)
            original = '<script src="flutter_bootstrap.js"></script>'
            (base / "index.html").write_text(original, encoding="utf-8")
            (base / "flutter_bootstrap.js").write_text(
                "_flutter.loader.load();", encoding="utf-8"
            )
            with self.assertRaisesRegex(RuntimeError, "no main.dart.js"):
                stamp_flutter_web(base, "test-7")
            self.assertEqual((base / "index.html").read_text(), original)


if __name__ == "__main__":
    unittest.main()
