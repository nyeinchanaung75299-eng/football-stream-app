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
KOTLIN = {
    'jar': '9588fa696ac5507af764fd5660df6894185e12704ec1bc3f5cb772af4987f295',
    'pom': '0b33c64f2622ba3bc8283378bdb7505f2be330a2275807038ad54359b33ddf9b',
}

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

def kotlin_init(repository_uri):
    # Limit the local replacement to the exact artifact that the generated
    # Flutter Gradle build requests. All other dependency resolution is intact.
    return '''def addVerifiedCompiler = { repos ->
 repos.exclusiveContent {
  forRepository { repos.maven { url = uri('%s'); metadataSources { mavenPom(); artifact() } } }
  filter { includeVersion('org.jetbrains.kotlin', 'kotlin-compiler-embeddable', '2.2.21') }
 }
}
gradle.beforeProject { project ->
 addVerifiedCompiler(project.repositories)
 addVerifiedCompiler(project.buildscript.repositories)
}
''' % repository_uri.replace("'", "\\'")

def prefetch_kotlin():
    repository = Path(os.environ.get('RUNNER_TEMP','/tmp'))/'nca-verified-maven'
    relative='org/jetbrains/kotlin/kotlin-compiler-embeddable/2.2.21'
    folder=repository/relative
    folder.mkdir(parents=True,exist_ok=True)
    for extension,digest in KOTLIN.items():
        path=folder/f'kotlin-compiler-embeddable-2.2.21.{extension}'
        def valid(candidate):
            if not candidate.exists():return False
            with candidate.open('rb') as handle:return hashlib.file_digest(handle,'sha256').hexdigest()==digest
        if valid(path):continue
        for base in ['https://repo.huaweicloud.com/repository/maven','https://repo.maven.apache.org/maven2']:
            temp=path.with_suffix(path.suffix+'.download')
            result=subprocess.run(['curl','--fail','--location','--silent','--show-error','--connect-timeout','15','--max-time','120','--output',str(temp),base+'/'+relative+'/'+path.name],check=False)
            if result.returncode==0 and valid(temp):temp.replace(path);break
            temp.unlink(missing_ok=True)
        if not valid(path):raise RuntimeError('A checksum-verified Kotlin compiler could not be downloaded')
    init=Path(os.environ.get('GRADLE_USER_HOME',str(Path.home()/'.gradle')))/'init.d'/'nca-verified-compiler.gradle'
    init.parent.mkdir(parents=True,exist_ok=True)
    init.write_text(kotlin_init(repository.as_uri()))

if __name__ == '__main__':
    path = Path(sys.argv[1])
    updated=configure(path.read_text())
    if os.environ.get('GITHUB_ACTIONS')=='true':
        version=re.search(r'gradle-([\d.]+)-bin.zip',updated)[1]
        digest=re.search(r'distributionSha256Sum=([a-f0-9]+)',updated)[1]
        updated=configure(updated,distribution_url=prefetch(version,digest))
        prefetch_kotlin()
    path.write_text(updated)
