#!/usr/bin/env python3
"""Release gate: final APKs keep updater install permission, no media access."""
import argparse
import re
import subprocess
from pathlib import Path
from configure_android_permissions import MEDIA_PERMISSIONS


def verify(apk: Path, aapt: str) -> set[str]:
    result = subprocess.run([aapt, 'dump', 'permissions', str(apk)],
                            check=True, text=True, capture_output=True)
    permissions = set(re.findall(r"uses-permission: name='([^']+)'", result.stdout))
    unexpected = permissions.intersection(MEDIA_PERMISSIONS)
    if unexpected:
        raise RuntimeError('Unnecessary media permissions remain: ' + ', '.join(sorted(unexpected)))
    for needed in ['android.permission.INTERNET', 'android.permission.REQUEST_INSTALL_PACKAGES']:
        if needed not in permissions:
            raise RuntimeError('Required network/updater permission missing: ' + needed)
    print(f'{apk.name}: no media/storage permissions; updater permission retained')
    return permissions


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--aapt', required=True)
    parser.add_argument('apks', nargs='+', type=Path)
    args = parser.parse_args()
    for apk in args.apks:
        verify(apk, args.aapt)
