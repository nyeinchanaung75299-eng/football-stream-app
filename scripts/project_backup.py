#!/usr/bin/env python3
"""Create a reproducible source recovery ZIP, never database rows or secret files."""
import argparse,hashlib,json,re,subprocess,zipfile
from pathlib import Path
DENY=re.compile(r'(^|/)(\.env(?:\.[^/]*)?|key\.properties|local\.properties|credentials[^/]*|service.account[^/]*)(/|$)|\.(jks|keystore|p12|pfx|pem)$',re.I)
def create(root,output):
 root=Path(root).resolve();out=Path(output).resolve();out.mkdir(parents=True,exist_ok=True)
 sha=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip()
 paths=subprocess.check_output(['git','ls-files','-z'],cwd=root).decode().split('\0')
 files={}
 for name in sorted(filter(None,paths)):
  if DENY.search(name) or name.startswith(('public/releases/','customer_profiles/private/')):continue
  path=root/name
  if path.is_symlink():raise ValueError('Refusing symlink: '+name)
  data=path.read_bytes()
  if re.search(rb'-----BEGIN (?:RSA |EC |OPENSSH |ENCRYPTED )?PRIVATE KEY-----',data):raise ValueError('Private key found; backup blocked')
  files[name]=data
 files['RESTORE-README.txt']=(f'Source snapshot: {sha}\\nVerify files using BACKUP-INVENTORY.json.\\nRestore Git repository, install pinned dependencies, provision the backend and apply migrations in filename order to a NEW empty database. Never replay historical migrations on production.\\nSigning keys, provider tokens, GitHub/Supabase/Cloudflare secrets and database DATA are not in this archive. Store those separately in an encrypted recovery vault. Do not generate a new signing key when updating an installed app.\\nAPK files: use private Admin bot /apk_admin and /apk_viewer.\\n').encode()
 inventory={'source_commit':sha,'files':{k:hashlib.sha256(v).hexdigest() for k,v in files.items()},'scope':'source-and-recovery-instructions','excluded':['database rows and user data','environment secrets','signing keystores','private customer profiles','APK binaries (available through /apk)']}
 files['BACKUP-INVENTORY.json']=json.dumps(inventory,indent=2).encode()
 target=out/'NCA-project-source.zip'
 with zipfile.ZipFile(target,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
  for name,data in sorted(files.items()):
   info=zipfile.ZipInfo(name,date_time=(2020,1,1,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED;info.external_attr=0o100644<<16;archive.writestr(info,data)
 payload=target.read_bytes()
 if not 0<len(payload)<=45*1024*1024:raise ValueError('Source archive exceeds bot delivery limit')
 manifest={'source_commit':sha,'filename':target.name,'size_bytes':len(payload),'sha256':hashlib.sha256(payload).hexdigest(),'scope':inventory['scope']}
 (out/'source-latest.json').write_text(json.dumps(manifest,indent=2)+'\n');return manifest
if __name__=='__main__':
 p=argparse.ArgumentParser();p.add_argument('--output',required=True);a=p.parse_args();print(json.dumps(create(Path(__file__).resolve().parents[1],a.output)))
