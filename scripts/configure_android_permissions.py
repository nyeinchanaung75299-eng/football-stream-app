#!/usr/bin/env python3
"""Remove dependency media permissions; updater uses its private cache + FileProvider."""
from pathlib import Path
import argparse
import xml.etree.ElementTree as ET

ANDROID = 'http://schemas.android.com/apk/res/android'
TOOLS = 'http://schemas.android.com/tools'
MEDIA_PERMISSIONS = (
    'android.permission.READ_EXTERNAL_STORAGE',
    'android.permission.WRITE_EXTERNAL_STORAGE',
    'android.permission.READ_MEDIA_IMAGES',
    'android.permission.READ_MEDIA_VIDEO',
    'android.permission.READ_MEDIA_AUDIO',
    'android.permission.READ_MEDIA_VISUAL_USER_SELECTED',
)


def configure(path: Path) -> None:
    ET.register_namespace('android', ANDROID)
    ET.register_namespace('tools', TOOLS)
    tree = ET.parse(path)
    root = tree.getroot()
    for child in list(root):
        if child.tag in ('uses-permission', 'uses-permission-sdk-23') and child.get('{' + ANDROID + '}name') in MEDIA_PERMISSIONS:
            root.remove(child)
    for name in MEDIA_PERMISSIONS:
        ET.SubElement(root, 'uses-permission', {
            '{' + ANDROID + '}name': name, '{' + TOOLS + '}node': 'remove',
        })
    tree.write(path, encoding='utf-8', xml_declaration=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('manifest', type=Path)
    configure(parser.parse_args().manifest)
