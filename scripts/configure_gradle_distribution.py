#!/usr/bin/env python3
"""Keep the generated Gradle version, use its smaller verified binary archive."""
import re
import sys
import os
import hashlib
import subprocess
import urllib.request
from pathlib import Path

KNOWN = {'9.3.1': 'b266d5ff6b90eada6dc3b20cb090e3731302e553a27c5d3e4df1f0d76beaff06'}

def configure(text, checksum=None, distribution_url=None):
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
    address = distribution_url or f'https://downloads.gradle.org/distributions/gradle-{version}-bin.zip'
    text = text[:match.start()] + 'distributionUrl='+address.replace(':',r'\:')+'\n' + text[match.end():]
    text = re.sub(r'^distributionSha256Sum=.*\n?', '', text, flags=re.M)
    return text.rstrip() + f'\ndistributionSha256Sum={digest}\n'

def prefetch(version, digest):
    folder = Path(os.environ.get('RUNNER_TEMP','/tmp'))/'nca-gradle-distributions'
    folder.mkdir(parents=True,exist_ok=True)
    archive = folder/f'gradle-{version}-bin.zip'
    def valid(path):
        if not path.exists(): return False
        with path.open('rb') as handle:
            return hashlib.file_digest(handle,'sha256').hexdigest()==digest
    if valid(archive): return archive.as_uri()
    # Java's wrapper download currently receives 504 from the release host.
    # Fetch with curl, then require the official SHA before Gradle uses it.
    for base in ['https://downloads.gradle.org/distributions','https://repo.huaweicloud.com/gradle','https://mirrors.cloud.tencent.com/gradle']:
        temporary=archive.with_suffix('.download')
        result=subprocess.run(['curl','--fail','--location','--silent','--show-error','--connect-timeout','15','--max-time','120','--output',str(temporary),base+'/'+archive.name],check=False)
        if result.returncode==0 and valid(temporary):
            temporary.replace(archive)
            return archive.as_uri()
        temporary.unlink(missing_ok=True)
    raise RuntimeError('A checksum-verified Gradle archive could not be downloaded')

if __name__ == '__main__':
    path = Path(sys.argv[1])
    updated=configure(path.read_text())
    if os.environ.get('GITHUB_ACTIONS')=='true':
        version=re.search(r'gradle-([\d.]+)-bin.zip',updated)[1]
        digest=re.search(r'distributionSha256Sum=([a-f0-9]+)',updated)[1]
        updated=configure(updated,distribution_url=prefetch(version,digest))
    path.write_text(updated)
