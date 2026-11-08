#!/usr/bin/env python3
"""Keep the generated Gradle version, use its smaller verified binary archive."""
import re
import sys
import urllib.request
from pathlib import Path

KNOWN = {'9.3.1': 'b266d5ff6b90eada6dc3b20cb090e3731302e553a27c5d3e4df1f0d76beaff06'}

def configure(text, checksum=None):
    match = re.search(r'^distributionUrl=.*?/gradle-([\d.]+)-(?:all|bin)\.zip\s*$', text, re.M)
    if not match:
        raise ValueError('Expected a versioned Gradle distribution')
    version = match[1]
    digest = checksum or KNOWN.get(version)
    if not digest:
        url = f'https://downloads.gradle.org/distributions/gradle-{version}-bin.zip.sha256'
        with urllib.request.urlopen(url, timeout=20) as response:
            digest = response.read(256).decode().strip()
    if not re.fullmatch(r'[a-f0-9]{64}', digest):
        raise ValueError('Invalid official Gradle checksum')
    text = text[:match.start()] + f'distributionUrl=https\\://downloads.gradle.org/distributions/gradle-{version}-bin.zip\n' + text[match.end():]
    text = re.sub(r'^distributionSha256Sum=.*\n?', '', text, flags=re.M)
    return text.rstrip() + f'\ndistributionSha256Sum={digest}\n'

if __name__ == '__main__':
    path = Path(sys.argv[1])
    path.write_text(configure(path.read_text()))
