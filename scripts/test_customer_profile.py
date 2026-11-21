import json,tempfile,unittest
from pathlib import Path
from customer_profile import ROOT,load_profile,prepare
class ProfileTests(unittest.TestCase):
 def test_two_customers_export_without_production_fallback(self):
  with tempfile.TemporaryDirectory() as tmp:
   for name in ('a','b'):
    report=prepare(ROOT/f'customer_profiles/demo-{name}.json',Path(tmp)/name)
    self.assertFalse(report['commercial_release_approved'])
    for app in ('admin_app','user_app'):
     text=(Path(tmp)/name/app/'lib/main.dart').read_text()
     self.assertNotIn('woggzixprvyjnfjzsglz',text);self.assertIn(f'sb_publishable_placeholder_{name}',text)
    self.assertFalse((Path(tmp)/name/'.github').exists())
    with self.assertRaises(ValueError):prepare(ROOT/f'customer_profiles/demo-{name}.json',Path(tmp)/name)
   self.assertNotEqual((Path(tmp)/'a/user_app/lib/main.dart').read_text(),(Path(tmp)/'b/user_app/lib/main.dart').read_text())
 def test_production_alias_and_unknown_field_rejected(self):
  p=json.loads((ROOT/'customer_profiles/demo-a.json').read_text())
  with tempfile.TemporaryDirectory() as tmp:
   path=Path(tmp)/'profile.json';p['supabase_ref']='woggzixprvyjnfjzsglz';path.write_text(json.dumps(p))
   with self.assertRaises(ValueError):load_profile(path)
   p['supabase_ref']='aaaaaaaaaaaaaaaaaaaa';p['service_role_key']='must-not-export';path.write_text(json.dumps(p))
   with self.assertRaises(ValueError):load_profile(path)
 def test_logo_path_cannot_escape_export_or_overwrite_checkout(self):
  p=json.loads((ROOT/'customer_profiles/demo-a.json').read_text())
  with tempfile.TemporaryDirectory() as tmp:
   profile=Path(tmp)/'profile.json'
   for logo in [str(ROOT/'customer_profiles/assets/demo-a.png'),'customer_profiles/../customer_profiles/assets/demo-a.png']:
    p['logo_png']=logo;profile.write_text(json.dumps(p))
    with self.assertRaises(ValueError):load_profile(profile)
if __name__=='__main__':unittest.main()
