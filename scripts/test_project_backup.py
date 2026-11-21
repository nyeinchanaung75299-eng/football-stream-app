import json,subprocess,tempfile,unittest,zipfile
from pathlib import Path
from project_backup import create
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
if __name__=='__main__':unittest.main()
