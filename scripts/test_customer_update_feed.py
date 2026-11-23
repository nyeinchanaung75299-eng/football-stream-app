import hashlib
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from customer_profile import ROOT
from customer_update_feed import stage

CERT_A = 'a'*64
CERT_B = 'b'*64

class FeedTests(unittest.TestCase):
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory()
  self.addCleanup(self.tmp.cleanup)
  self.dir=Path(self.tmp.name)
  profile=json.loads((ROOT/'customer_profiles/demo-a.json').read_text())
  profile['test_only']=False
  profile['publishable_key']='sb_publishable_customer_test'
  profile['repository']='independent-buyer/football-suite'
  profile['hosts']={k:k.replace('_','-')+'.buyer-example.test' for k in profile['hosts']}
  self.profile=self.dir/'customer.json'
  self.profile.write_text(json.dumps(profile))
  self.out=self.dir/'buyer-build'
  self.out.mkdir()
  for app,folder,version in [('viewer','user_app','9.8.18+1'),('admin','admin_app','2.5.29+1')]:
   path=self.out/folder
   path.mkdir()
   (path/'pubspec.yaml').write_text('version: '+version+'\n')
  self.apks={}
  self.rows=[]
  for app in ('viewer','admin'):
   file=self.out/(app+'.apk')
   file.write_bytes(('buyer-'+app).encode())
   self.apks[app]=file
   self.rows.append({'app':app,'package':profile[app+'_package'],
     'path':str(file),'sha256':hashlib.sha256(file.read_bytes()).hexdigest(),
     'signed_release':True})
  self.report=self.out/'build-results.json'
  self.report.write_text(json.dumps({'customer':profile['id'],
    'published':False,'builds':self.rows}))
  self.env={'CUSTOMER_VIEWER_CERT_SHA256':CERT_A,
            'CUSTOMER_ADMIN_CERT_SHA256':CERT_B}

 def fake_verify(self,command,**kwargs):
  app='viewer' if str(command[-1]).endswith('/viewer.apk') else 'admin'
  if command[0]=='apksigner':
   return 'Signer #1 certificate SHA-256 digest: '+(CERT_A if app=='viewer' else CERT_B)
  package=self.rows[0 if app=='viewer' else 1]['package']
  version='9.8.18' if app=='viewer' else '2.5.29'
  return f"package: name='{package}' versionCode='43' versionName='{version}'"

 def test_signed_isolated_feed_staged_not_published(self):
  with patch.dict(os.environ,self.env),patch('subprocess.check_output',side_effect=self.fake_verify):
   output=stage(self.profile,self.report,self.dir/'release',43)
  root=output/'feed/public/releases'
  for name,app in [('latest.json','viewer'),('admin-latest.json','admin')]:
   data=json.loads((root/name).read_text())
   self.assertEqual(data['version_name'],'9.8.18' if app=='viewer' else '2.5.29')
   self.assertEqual(data['build_number'],43)
   self.assertEqual(data['sha256'],self.rows[0 if app=='viewer' else 1]['sha256'])
   self.assertIn('independent-buyer/football-suite/feed/',data['apk_url'])
   self.assertNotIn('nyeinchanaung75299-eng',data['apk_url'])
  self.assertFalse(json.loads((output/'RELEASE-CANDIDATE.json').read_text())['published'])
  with patch.dict(os.environ,self.env),patch('subprocess.check_output',side_effect=self.fake_verify):
   with self.assertRaises(ValueError):stage(self.profile,self.report,output,43)

 def test_rejects_debug_build_and_modified_apk(self):
  self.rows[0]['signed_release']=False
  self.report.write_text(json.dumps({'customer':'customer-a','published':False,'builds':self.rows}))
  with self.assertRaisesRegex(ValueError,'Unsigned'):
   stage(self.profile,self.report,self.dir/'not-created',43)
  self.assertFalse((self.dir/'not-created').exists())
  self.rows[0]['signed_release']=True
  self.apks['viewer'].write_bytes(b'changed')
  with self.assertRaisesRegex(ValueError,'hash differs'):
   stage(self.profile,self.report,self.dir/'not-created',43)

 def test_certificate_mismatch_and_demo_profiles_rejected(self):
  with patch.dict(os.environ,{'CUSTOMER_VIEWER_CERT_SHA256':'f'*64, 'CUSTOMER_ADMIN_CERT_SHA256':CERT_B}),patch('subprocess.check_output',side_effect=self.fake_verify):
   with self.assertRaisesRegex(ValueError,'signer changed'):
    stage(self.profile,self.report,self.dir/'not-created',43)
  with self.assertRaisesRegex(ValueError,'Demo builds'):
   stage(ROOT/'customer_profiles/demo-a.json',self.report,self.dir/'not-created',43)

if __name__=='__main__':unittest.main()
