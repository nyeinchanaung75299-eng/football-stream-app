import hashlib
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from write_android_release_metadata import release_metadata


class ReleaseMetadataTests(unittest.TestCase):
    def test_split_arm64_update_is_newer_than_installed_app_for_both_products(self):
        # Regression: --build-number 40763 produces ARM64 versionCode 42763.
        # Publishing 40763 incorrectly tells installed 42750 that it is current.
        with tempfile.TemporaryDirectory() as tmp:
            apk = Path(tmp) / 'signed.apk'
            apk.write_bytes(b'verified-signed-apk')
            for label, version in [('Viewer', '9.8.1'), ('Admin', '2.5.4')]:
                with self.subTest(label=label), patch('write_android_release_metadata.apk_identity', return_value=('package', 42763, 'ab' * 32)):
                    data = release_metadata(label, apk, version, apksigner='signer', aapt='aapt')
                    self.assertEqual(data['build_number'], 42763)
                    self.assertGreater(data['build_number'], 42750)
                    self.assertEqual(data['version_name'], version)
                    self.assertEqual(data['sha256'], hashlib.sha256(apk.read_bytes()).hexdigest())
                    self.assertEqual(data['size_bytes'], apk.stat().st_size)
                    self.assertEqual(data['abi'], 'arm64-v8a')
                    self.assertFalse(data['mandatory'])

    def test_failed_apk_verification_prevents_manifest_generation(self):
        with patch('write_android_release_metadata.apk_identity', side_effect=ValueError('Invalid APK')):
            with self.assertRaises(ValueError):
                release_metadata('Viewer', Path('invalid.apk'), '9.8.1', apksigner='signer', aapt='aapt')


if __name__ == '__main__':
    unittest.main()
