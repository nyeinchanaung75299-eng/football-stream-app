#!/usr/bin/env python3
"""Prepare isolated buyer source trees. Never changes the NCA working tree or deploys."""
import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1]
OLD_OWNER = 'nyeinchanaung75299-eng'
OLD_PROJECT = 'woggzixprvyjnfjzsglz'
OWNED_HOSTS = {
 'football-api.nyeinchanaung.us.ci':'api', 'football-api.nyeinchanaung.ccwu.cc':'api_alt',
 'football-public-api.nyeinchanaung75299-eng.workers.dev':'api_workers',
 'supabase-api.nyeinchanaung.us.ci':'auth', 'supabase-api.nyeinchanaung.ccwu.cc':'auth_alt',
 'nca-network-backup-test.vercel.app':'relay','nca25-live-relay.vercel.app':'relay_alt',
 'nca.nyeinchanaung.us.ci':'web','nca25-web.vercel.app':'web_alt',
 'my-channels-match-guide.vercel.app':'guide',
 'fawa41-origin.nyeinchanaung.us.ci':'fawa41',
 'fawa44-origin.nyeinchanaung.us.ci':'fawa44',
 'fawa55-origin.nyeinchanaung.us.ci':'fawa55',
 'fawa59-origin.nyeinchanaung.us.ci':'fawa59',

}
ALLOWED = ('admin_app/lib/', 'admin_app/web/', 'user_app/lib/', 'user_app/web/',
           'user_app/assets/', 'user_app/android_patch/', 'scripts/', 'supabase/')

def load_profile(path):
 p=json.loads(Path(path).read_text())
 required={'id','test_only','viewer_name','admin_name','viewer_package','admin_package',
           'supabase_ref','publishable_key','repository','hosts','primary_color','logo_png'}
 if set(p)!=required:raise ValueError('Profile has missing or unknown fields')
 if not re.fullmatch(r'[a-z][a-z0-9-]{2,40}',p['id']):raise ValueError('Invalid customer id')
 if type(p['test_only']) is not bool:raise ValueError('test_only must be boolean')
 for key in ('viewer_name','admin_name'):
  if not isinstance(p[key],str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9 ._-]{1,49}',p[key]):raise ValueError('Use a simple display name')
 for key in ('viewer_package','admin_package'):
  if not re.fullmatch(r'[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*){2,}',p[key]) or p[key].startswith('com.example.'):
   raise ValueError('A customer-owned package identity is required')
 if p['viewer_package']==p['admin_package']:raise ValueError('Viewer and Admin identities must differ')
 if not re.fullmatch(r'[a-z]{20}',p['supabase_ref']) or p['supabase_ref']==OLD_PROJECT:raise ValueError('Separate Supabase project required')
 if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+',p['repository']) or OLD_OWNER in p['repository']:
  raise ValueError('Separate release repository required')
 if not re.fullmatch(r'#[A-Fa-f0-9]{6}',p['primary_color']):raise ValueError('Invalid theme color')
 if set(p['hosts'])!=set(OWNED_HOSTS.values()):raise ValueError('Every backend/relay/guide/origin route must be configured')
 if len(set(p['hosts'].values()))!=len(p['hosts']):raise ValueError('Endpoint aliases must be distinct to preserve constant route sets')
 for host in p['hosts'].values():
  if not isinstance(host,str) or not re.fullmatch(r'[a-z0-9-]+(?:\.[a-z0-9-]+)+',host) or 'nyeinchanaung' in host or host in OWNED_HOSTS:
   raise ValueError('Invalid or production-owned host')
 if not isinstance(p['publishable_key'],str) or not p['publishable_key'].startswith('sb_publishable_'):
  raise ValueError('Only a client publishable key belongs in a profile')
 if not p['test_only'] and (any(h.endswith('.example') for h in p['hosts'].values()) or 'placeholder' in p['publishable_key']):
  raise ValueError('Production profile cannot contain demo endpoints or keys')
 if not isinstance(p['logo_png'],str):raise ValueError('A relative PNG logo path is required')
 relative=Path(p['logo_png'])
 if relative.is_absolute() or '..' in relative.parts:raise ValueError('Logo path must stay relative to the source checkout')
 logo=ROOT/relative
 if any(path.is_symlink() for path in [logo,*logo.parents] if path!=ROOT) or ROOT not in logo.resolve().parents or not logo.is_file() or not logo.read_bytes().startswith(b'\x89PNG\r\n\x1a\n'):raise ValueError('A local PNG buyer logo is required')
 return p

def mapping(p):
 owner,repo=p['repository'].split('/')
 return {**{old:p['hosts'][role] for old,role in OWNED_HOSTS.items()},
  OLD_PROJECT:p['supabase_ref'], OLD_OWNER+'.github.io':owner+'.github.io',
  OLD_OWNER:owner, 'football-stream-app':repo,
  'com/example/football_viewer':p['viewer_package'].replace('.','/'),
  'com/example/football_admin':p['admin_package'].replace('.','/'),
  'com.example.football_viewer':p['viewer_package'], 'com.example.football_admin':p['admin_package']}

def transform(text,p):
 # Parallel replacement avoids re-replacing a buyer value that contains a key.
 replacements=mapping(p)
 for old,new in list(replacements.items()):
  if '.' in old:
   replacements[old.replace('.','[.]')]=new.replace('.','[.]')
   replacements[old.replace('.',r'\.')]=new.replace('.',r'\.')
 text=re.sub('|'.join(re.escape(x) for x in sorted(replacements,key=len,reverse=True)),lambda m:replacements[m[0]],text)
 text=re.sub(r'sb_publishable_[A-Za-z0-9_-]+',lambda _:p['publishable_key'],text)
 # A buyer must never send analytics into the NCA analytics project.
 text=re.sub(r'phc_[A-Za-z0-9_-]+','',text)
 text=text.replace('final config = PostHogConfig(_projectToken);','if (_projectToken.isEmpty) return;\n      final config = PostHogConfig(_projectToken);')
 text=text.replace('assets/nca_icon.webp','assets/customer_icon.png').replace('assets/nca_icon.png','assets/customer_icon.png')
 text=text.replace("title: 'NCA Admin'",'title: '+json.dumps(p['admin_name'])).replace("title: 'NCA'",'title: '+json.dumps(p['viewer_name']))
 text=text.replace('Color(0xFF16A34A)','Color(0xFF'+p['primary_color'][1:]+')')
 text=text.replace('Color(0xFF22D67B)','Color(0xFF'+p['primary_color'][1:]+')')
 text=text.replace("'NCA Admin'",json.dumps(p['admin_name'])).replace("'NCA'",json.dumps(p['viewer_name']))
 text=re.sub(r'\bNCA\b',p['id'].upper(),text)
 return text

def prepare(profile,output,root=ROOT):
 p=load_profile(profile);out=Path(output).resolve();root=Path(root).resolve()
 if out==root or root in out.parents:raise ValueError('Output must be outside the production repository')
 if out.exists():raise ValueError('Output must not exist; existing customer builds are never overwritten')
 files=subprocess.check_output(['git','ls-files','-z'],cwd=root).decode().split('\0')
 selected=[f for f in files if f and (f.startswith(ALLOWED) or f in ('admin_app/pubspec.yaml','admin_app/pubspec.lock','user_app/pubspec.yaml','user_app/pubspec.lock'))
           and not f.startswith(('scripts/test_', 'supabase/.temp/')) and not any(x in Path(f).parts for x in ('node_modules','build','.dart_tool'))
           and not re.search(r'(\.env(?:\.|$)|\.(?:jks|keystore|pem|p12|pfx)$)',f)]
 rendered={}
 for name in selected:
  src=root/name
  if src.is_symlink():raise ValueError('Symlinks are not allowed in an export')
  data=src.read_bytes()
  try:
   if name in ('scripts/customer_profile.py','scripts/customer_build.py'):
    rendered[name]=data;continue
   text=transform(data.decode(),p)
   if re.search(r'nyeinchanaung(?:[.]|[0-9])|woggzixprvyjnfjzsglz|phc_[A-Za-z0-9]',text,re.I):
    raise ValueError('Unmapped production reference in '+name)
   data=text.encode()
  except UnicodeDecodeError:pass
  if name.endswith('pubspec.yaml'):
   lines=data.decode().splitlines();seen=False;clean=[]
   for line in lines:
    if '- assets/customer_icon.png' in line:
     if seen:continue
     seen=True
    clean.append(line)
   data=('\n'.join(clean)+'\n').encode()
  rendered[name]=data
 logo=(ROOT/p['logo_png']).read_bytes()
 rendered['user_app/assets/customer_icon.png']=logo
 rendered[p['logo_png']]=logo
 for name in list(rendered):
  if name.endswith('nca_icon.png'):rendered[name]=logo
 out.mkdir(parents=True)
 for name,data in rendered.items():
  dest=out/name;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data)
 (out/'customer-profile.json').write_text(json.dumps(p,indent=2))
 report={'customer':p['id'],'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),
  'test_only':p['test_only'],'commercial_release_approved':False,'files':{k:hashlib.sha256(v).hexdigest() for k,v in rendered.items()},
  'viewer_package':p['viewer_package'],'admin_package':p['admin_package'],
  'required_gates':['buyer logos','separate backend provisioning','buyer signing certificate enrollment','signed Android builds','real-device A/B isolation and update QA']}
 (out/'customer-build-report.json').write_text(json.dumps(report,indent=2))
 (out/'BUYER_SETUP.txt').write_text('Prepared customer sources only. No backend was provisioned and no release was published.\n'
  'Never copy the NCA keystore, production environment, deployment bindings or release feed.\n'
  'Provide customer-owned logos, configure native Android identities, provision the separate backend, enroll buyer signing keys, and complete device QA before release.\n'
  'Automatic deployment workflows are intentionally not included. Commercial approval is false until every gate is independently verified.\n')
 return report

if __name__=='__main__':
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--profile',required=True);parser.add_argument('--output',required=True)
 args=parser.parse_args()
 try:
  result=prepare(args.profile,args.output);print(json.dumps({k:v for k,v in result.items() if k!='files'},indent=2))
 except (ValueError,OSError) as e:parser.exit(1,str(e)+'\n')
