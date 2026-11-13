#!/usr/bin/env python3
"""Write updater manifests using verified APK versionCodes, including ABI offsets."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re

from verify_android_update_signing import RELEASE_BASE, RELEASES, apk_identity

NOTES = {
    'Viewer': 'Repository stream lines now show concise server names in Web and Android players. Existing stream playback remains unchanged.',
    'Admin': 'Repository match line names are shorter in Live Links and Viewer. Private Telegram Highlights now supports Next for more verified public MP4 matches.',
}


def release_metadata(label: str, apk: Path, version: str, *, apksigner: str, aapt: str) -> dict:
    if not re.fullmatch(r'\d+\.\d+\.\d+', version):
        raise ValueError('A numeric release version is required.')
    _, actual_code, _ = apk_identity(apk, apksigner=apksigner, aapt=aapt)
    payload = apk.read_bytes()
    if not payload:
        raise ValueError('The release APK is empty.')
    data = {
        'version_name': version,
        # Flutter split-per-ABI may add 2000 to the input --build-number.
        # The installed PackageInfo buildNumber is the actual APK versionCode.
        'build_number': actual_code,
        'apk_url': RELEASE_BASE + RELEASES[label][1],
        'abi': 'arm64-v8a',
        'sha256': hashlib.sha256(payload).hexdigest(),
        'size_bytes': len(payload),
        'mandatory': False,
        'notes': NOTES[label],
    }
    if label == 'Admin':
        data['app'] = 'nca_admin'
    return data


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--viewer-apk', type=Path, required=True)
    parser.add_argument('--admin-apk', type=Path, required=True)
    parser.add_argument('--viewer-version', required=True)
    parser.add_argument('--admin-version', required=True)
    parser.add_argument('--apksigner', required=True)
    parser.add_argument('--aapt', required=True)
    args = parser.parse_args()
    rows = {
        label: release_metadata(label, apk, version, apksigner=args.apksigner, aapt=args.aapt)
        for label, apk, version in [('Viewer', args.viewer_apk, args.viewer_version),
                                    ('Admin', args.admin_apk, args.admin_version)]
    }
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for label, data in rows.items():
        (args.output_dir / RELEASES[label][0]).write_text(json.dumps(data, separators=(',', ':')), encoding='utf-8')
        print(f"{label} updater manifest: actual APK versionCode {data['build_number']}")


if __name__ == '__main__':
    main()
