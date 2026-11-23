#!/usr/bin/env python3
"""Stage verified, customer-specific updater files. Never deploy or approve QA."""
import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
from pathlib import Path
from customer_profile import load_profile

NAMES = {
    'viewer': ('NCA-arm64-v8a-latest.apk', 'latest.json', 'nca_viewer'),
    'admin': ('NCA-admin-arm64-v8a-latest.apk', 'admin-latest.json', 'nca_admin'),
}

def version_from_pubspec(path):
    match = re.search(r'^version:\s*(\d+\.\d+\.\d+)(?:\+\d+)?\s*$',
                      path.read_text(), re.M)
    if not match:
        raise ValueError('App version must be X.Y.Z in pubspec.yaml')
    return match.group(1)

def stage(profile, build_results, output, build_number, *, apksigner='apksigner', aapt='aapt'):
    profile=load_profile(profile)
    if profile['test_only']:
        raise ValueError('Demo builds must never create a buyer release candidate')
    if build_number<=0:
        raise ValueError('A positive, verified Android versionCode is required')
    report_file=Path(build_results).resolve()
    report=json.loads(report_file.read_text())
    if report.get('customer')!=profile['id'] or report.get('published') is not False:
        raise ValueError('Build report does not match an unpublished customer build')
    rows=report.get('builds',[])
    if not isinstance(rows,list) or len(rows)!=2 or {r.get('app') for r in rows}!={'viewer','admin'}:
        raise ValueError('Both signed buyer Viewer/Admin APKs are required')
    target=Path(output).resolve()
    if target.exists():
        raise ValueError('Never overwrite an existing release candidate')
    checked={}
    for row in rows:
        app=row['app']
        if row.get('signed_release') is not True or row.get('package')!=profile[app+'_package']:
            raise ValueError('Unsigned or wrong-package build; refusing updater feed')
        path=Path(row.get('path','')).resolve()
        if not path.is_file() or not path.is_relative_to(report_file.parent):
            raise ValueError('APK must exist inside the isolated buyer export')
        digest=hashlib.sha256(path.read_bytes()).hexdigest()
        if digest!=row.get('sha256'):
            raise ValueError('APK hash differs from signed build result')
        cert=subprocess.check_output([apksigner,'verify','--print-certs',str(path)],text=True)
        match=re.search(r'certificate SHA-256 digest:\s*([a-fA-F0-9]{64})',cert)
        expected=os.environ.get('CUSTOMER_'+app.upper()+'_CERT_SHA256','')
        if not match or not expected or match.group(1).lower()!=expected.lower():
            raise ValueError('Release signer changed or is not enrolled')
        badging=subprocess.check_output([aapt,'dump','badging',str(path)],text=True)
        expected_version=version_from_pubspec(report_file.parent/('user_app' if app=='viewer' else 'admin_app')/'pubspec.yaml')
        if (f"name='{profile[app+'_package']}'" not in badging or
            f"versionCode='{build_number}'" not in badging or
            f"versionName='{expected_version}'" not in badging):
            raise ValueError('Buyer package/version mismatch')
        checked[app]=(path,digest,expected_version)
    # All verification is complete before writing any file.
    release=target/'feed/public/releases'
    release.mkdir(parents=True,exist_ok=False)
    for app in ('viewer','admin'):
        path,digest,version=checked[app]
        apk_name,manifest_name,app_name=NAMES[app]
        shutil.copyfile(path,release/apk_name)
        url=f"https://raw.githubusercontent.com/{profile['repository']}/feed/public/releases/{apk_name}"
        metadata={'app':app_name,'version_name':version,'build_number':build_number,
                  'apk_url':url,'abi':'arm64-v8a','sha256':digest,
                  'size_bytes':path.stat().st_size,'mandatory':False,
                  'notes':'Buyer-specific signed release candidate; publish after verified device QA.'}
        (release/manifest_name).write_text(json.dumps(metadata,indent=2)+'\n')
    (target/'RELEASE-CANDIDATE.json').write_text(json.dumps({
        'customer':profile['id'],'published':False,'real_device_qa':'required',
        'requires':'Customer-owned backend, exact signing identity, installed-app update test',
        'build_number':build_number,'files':{
            name:hashlib.sha256((release/name).read_bytes()).hexdigest()
            for name in (NAMES['viewer'][0],NAMES['admin'][0])
        },
    },indent=2)+'\n')
    return target

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--profile',required=True)
    p.add_argument('--build-results',required=True)
    p.add_argument('--output',required=True)
    p.add_argument('--build-number',type=int,required=True)
    a=p.parse_args()
    try:
        stage(a.profile,a.build_results,a.output,a.build_number)
    except (OSError,ValueError,subprocess.CalledProcessError) as error:
        p.exit(1,str(error)+'\n')
