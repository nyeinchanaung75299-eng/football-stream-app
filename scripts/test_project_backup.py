import json,subprocess,tempfile,unittest,zipfile
from pathlib import Path
from project_backup import create
from verify_project_backup import verify_archive
class BackupTests(unittest.TestCase):
 def test_scope_integrity_and_secret_exclusion(self):
  with tempfile.TemporaryDirectory() as temp:
   root=Path(temp)/'repo';root.mkdir();subprocess.run(['git','init','-q',str(root)],check=True)
   for name,data in [('main.dart','source'),('.env','SECRET'),('signing.jks','SECRET')]: (root/name).write_text(data)
   subprocess.run(['git','add','.'],cwd=root,check=True);subprocess.run(['git','-c','user.name=Test','-c','user.email=test@example.com','commit','-qm','fixture'],cwd=root,check=True)
   out=Path(temp)/'out';manifest=create(root,out)
   with zipfile.ZipFile(out/manifest['filename']) as archive:
    self.assertIn('main.dart',archive.namelist());self.assertNotIn('.env',archive.namelist());self.assertNotIn('signing.jks',archive.namelist());self.assertIn('RESTORE-README.txt',archive.namelist())
   self.assertEqual(manifest,create(root,out))
   recovery=Path(temp)/'restore'
   summary=verify_archive(out/manifest['filename'],recovery)
   self.assertEqual(summary['files_verified'],2)
   self.assertEqual((recovery/'main.dart').read_text(),'source')
   self.assertFalse((recovery/'.env').exists())
   self.assertIn('RESTORE-README.txt',recovery.joinpath('BACKUP-INVENTORY.json').read_text())
   with self.assertRaisesRegex(ValueError,'overwrite'):
    verify_archive(out/manifest['filename'],recovery)

 def test_rejects_tampered_backup_and_traversal(self):
  with tempfile.TemporaryDirectory() as temp:
   root=Path(temp)/'repo';root.mkdir();subprocess.run(['git','init','-q',str(root)],check=True)
   (root/'main.dart').write_text('source')
   subprocess.run(['git','add','.'],cwd=root,check=True)
   subprocess.run(['git','-c','user.name=Test','-c','user.email=test@example.com','commit','-qm','fixture'],cwd=root,check=True)
   out=Path(temp)/'out';manifest=create(root,out)
   tampered=Path(temp)/'tampered.zip'
   with zipfile.ZipFile(out/manifest['filename']) as source,zipfile.ZipFile(tampered,'w') as target:
    for member in source.infolist():
     contents=source.read(member.filename)
     if member.filename=='RESTORE-README.txt':contents+=b'modified'
     target.writestr(member,contents)
   with self.assertRaisesRegex(ValueError,'checksum mismatch'):
    verify_archive(tampered)
   hostile=Path(temp)/'traversal.zip'
   with zipfile.ZipFile(hostile,'w') as target:
    target.writestr('../escape.txt','unexpected')
    target.writestr('BACKUP-INVENTORY.json','{}')
   with self.assertRaisesRegex(ValueError,'Unsafe path'):
    verify_archive(hostile)
if __name__=='__main__':unittest.main()
