import tempfile
import unittest
from pathlib import Path
import xml.etree.ElementTree as ET
from configure_android_permissions import ANDROID, TOOLS, MEDIA_PERMISSIONS, configure


class PermissionTests(unittest.TestCase):
    def test_dependency_media_permissions_removed_without_breaking_updater(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'AndroidManifest.xml'
            path.write_text(f'''<manifest xmlns:android="{ANDROID}">
              <uses-permission android:name="android.permission.INTERNET"/>
              <uses-permission android:name="android.permission.REQUEST_INSTALL_PACKAGES"/>
              <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>
              <uses-permission-sdk-23 android:name="android.permission.READ_MEDIA_VIDEO"/>
              <application android:label="NCA"><provider android:name="FileProvider" android:grantUriPermissions="true"/></application>
            </manifest>''')
            configure(path)
            first = path.read_bytes()
            configure(path)
            self.assertEqual(first, path.read_bytes())
            root = ET.parse(path).getroot()
            nodes = {p.get(f'{{{ANDROID}}}name'): p for p in root.findall('uses-permission')}
            for name in MEDIA_PERMISSIONS:
                self.assertEqual(nodes[name].get('{' + TOOLS + '}node'), 'remove')
            self.assertIsNone(nodes['android.permission.REQUEST_INSTALL_PACKAGES'].get('{' + TOOLS + '}node'))
            self.assertIsNotNone(root.find('application/provider'))


if __name__ == '__main__':
    unittest.main()
