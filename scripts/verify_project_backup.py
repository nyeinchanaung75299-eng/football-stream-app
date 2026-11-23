#!/usr/bin/env python3
"""Verify an NCA source backup and optionally restore to a NEW, empty directory."""
import argparse
import hashlib
import json
import re
import stat
import zipfile
from pathlib import Path, PurePosixPath
from project_backup import DENY

MAX_UNCOMPRESSED = 200 * 1024 * 1024

def verify_archive(archive_path, extract_to=None):
    archive_path=Path(archive_path)
    verified={}
    with zipfile.ZipFile(archive_path) as archive:
        infos=archive.infolist()
        if not infos or len(infos)>20000 or sum(i.file_size for i in infos)>MAX_UNCOMPRESSED:
            raise ValueError('Backup exceeds verified source limits')
        names=[i.filename for i in infos]
        if len(names)!=len(set(names)) or 'BACKUP-INVENTORY.json' not in names:
            raise ValueError('Duplicate files or missing inventory')
        for info in infos:
            name=info.filename
            parts=PurePosixPath(name)
            mode=info.external_attr >> 16
            if (not name or name.startswith('/') or '\\' in name or
                '..' in parts.parts or name!=str(parts) or info.is_dir() or
                stat.S_ISLNK(mode) or DENY.search(name) or
                name.startswith(('public/releases/','customer_profiles/private/'))):
                raise ValueError('Unsafe path in source archive')
        inventory=json.loads(archive.read('BACKUP-INVENTORY.json'))
        expected=inventory.get('files')
        if not isinstance(expected,dict) or not re.fullmatch(r'[a-f0-9]{40}',str(inventory.get('source_commit',''))):
            raise ValueError('Invalid backup inventory')
        if set(names)!=set(expected)|{'BACKUP-INVENTORY.json'}:
            raise ValueError('Source archive differs from inventory')
        for name,digest in expected.items():
            if not isinstance(digest,str) or not re.fullmatch(r'[0-9a-f]{64}',digest):
                raise ValueError('Invalid inventory checksum')
            contents=archive.read(name)
            if hashlib.sha256(contents).hexdigest()!=digest:
                raise ValueError('Backup file checksum mismatch: '+name)
            verified[name]=contents
        if 'RESTORE-README.txt' not in verified:
            raise ValueError('Recovery instructions are missing')
    if extract_to is not None:
        output=Path(extract_to).resolve()
        if output.exists():
            raise ValueError('Refusing to overwrite existing recovery folder')
        output.mkdir(parents=True)
        for name,contents in verified.items():
            dest=output/Path(*PurePosixPath(name).parts)
            dest.parent.mkdir(parents=True,exist_ok=True)
            dest.write_bytes(contents)
        (output/'BACKUP-INVENTORY.json').write_text(json.dumps(inventory,indent=2)+'\n')
    return {'source_commit':inventory['source_commit'],'files_verified':len(verified),
            'extracted':extract_to is not None}

if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--archive',required=True)
    p.add_argument('--extract-to')
    args=p.parse_args()
    try:
        print(json.dumps(verify_archive(args.archive,args.extract_to)))
    except (ValueError,OSError,KeyError,zipfile.BadZipFile) as error:
        p.exit(1,str(error)+'\n')
