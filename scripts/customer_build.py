#!/usr/bin/env python3
"""One customer profile -> isolated Viewer/Admin builds. No deployment/publication."""
import argparse,hashlib,json,os,re,shutil,subprocess,xml.etree.ElementTree as ET
from pathlib import Path
from customer_profile import prepare,load_profile

def run(args,cwd):subprocess.run([str(x) for x in args],cwd=cwd,check=True)
def android(app,kind,p,mode):
 package=p[kind+'_package'];name=p[kind+'_name'];android=app/'android'
 for f in android.rglob('*'):
  if f.is_file() and f.suffix in ('.kt','.java','.kts','.gradle','.xml'):
   s=f.read_text();s=s.replace('com.example.football_viewer',p['viewer_package']).replace('com.example.football_admin',p['admin_package']);f.write_text(s)
 for f in (android/'app/src/main/kotlin').rglob('MainActivity.kt'):f.unlink()
 dest=android/'app/src/main/kotlin'/package.replace('.','/');dest.mkdir(parents=True,exist_ok=True)
 if kind=='viewer':
  for f in (app/'android_patch').glob('*'):
   if f.suffix in ('.kt','.java'):shutil.copy2(f,dest/f.name)
 else:
  (dest/'MainActivity.kt').write_text(f'package {package}\nimport io.flutter.embedding.android.FlutterActivity\nclass MainActivity: FlutterActivity()\n')
 manifest=android/'app/src/main/AndroidManifest.xml';ns='{http://schemas.android.com/apk/res/android}'
 ET.register_namespace('android',ns[1:-1]);tree=ET.parse(manifest);root=tree.getroot();application=root.find('application');application.set(ns+'label',name);application.set(ns+'icon','@drawable/customer_icon')
 for permission in ['INTERNET','ACCESS_NETWORK_STATE','REQUEST_INSTALL_PACKAGES']:
  if not any(e.get(ns+'name')=='android.permission.'+permission for e in root.findall('uses-permission')):ET.SubElement(root,'uses-permission',{ns+'name':'android.permission.'+permission})
 ET.SubElement(application,'meta-data',{ns+'name':'com.posthog.posthog.AUTO_INIT',ns+'value':'false'})
 if kind=='viewer':ET.SubElement(application,'activity',{ns+'name':'.NativePlayerActivity',ns+'exported':'false',ns+'screenOrientation':'unspecified',ns+'configChanges':'orientation|screenSize|keyboardHidden',ns+'theme':'@style/LaunchTheme'})
 tree.write(manifest,encoding='unicode')
 icon=android/'app/src/main/res/drawable/customer_icon.png';icon.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(app.parent/'user_app/assets/customer_icon.png',icon)
 gradle=android/'app/build.gradle.kts'
 if not gradle.exists():raise ValueError('This builder requires the Flutter Kotlin Gradle template')
 s=gradle.read_text().replace('minSdk = flutter.minSdkVersion','minSdk = 24')
 if kind=='viewer':s+='\ndependencies {\n'+''.join(f' implementation("androidx.media3:{part}:1.4.1")\n' for part in ['media3-exoplayer','media3-exoplayer-hls','media3-exoplayer-dash','media3-ui'])+'}\n'
 if mode=='release':
  prefix='CUSTOMER_'+kind.upper()+'_'
  block='signingConfigs { create("customerRelease") {\n'+f' storeFile = file(System.getenv("{prefix}KEYSTORE"))\n storePassword = System.getenv("{prefix}STORE_PASSWORD")\n keyAlias = System.getenv("{prefix}KEY_ALIAS")\n keyPassword = System.getenv("{prefix}KEY_PASSWORD")\n'+'} }\n'
  s=s.replace('    buildTypes {',block+'    buildTypes {').replace('signingConfigs.getByName("debug")','signingConfigs.getByName("customerRelease")')
  if 'customerRelease' not in s:raise ValueError('Signing patch failed')
 gradle.write_text(s)

def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--profile',required=True);parser.add_argument('--output',required=True);parser.add_argument('--flutter',default='flutter');parser.add_argument('--target',choices=['web','qa-android','release-android'],default='web');parser.add_argument('--build-number',type=int,required=True)
 a=parser.parse_args();p=load_profile(a.profile)
 if a.build_number<=0:raise ValueError('Positive monotonic build number required')
 if a.target=='release-android':
  if p['test_only']:raise ValueError('Demo profiles cannot create commercial release APKs')
  for kind in ['VIEWER','ADMIN']:
   for key in ['KEYSTORE','STORE_PASSWORD','KEY_ALIAS','KEY_PASSWORD','CERT_SHA256']:
    value=os.environ.get('CUSTOMER_'+kind+'_'+key,'')
    if not value:raise ValueError('Customer signing environment is incomplete')
   path=Path(os.environ['CUSTOMER_'+kind+'_KEYSTORE'])
   if not path.is_absolute() or not path.is_file():raise ValueError('Use an existing absolute customer keystore path')
   if os.environ['CUSTOMER_'+kind+'_CERT_SHA256'].lower()=='9e5074f9e3195d70b0b80adf963b7f0f18a04ee2a3c3808c702ab07fda733b1e':raise ValueError('NCA production certificate cannot be used for a customer')
   if not re.fullmatch('[a-fA-F0-9]{64}',os.environ['CUSTOMER_'+kind+'_CERT_SHA256']):raise ValueError('Pin the enrolled customer certificate fingerprint')
  if os.environ['CUSTOMER_VIEWER_KEYSTORE']==os.environ['CUSTOMER_ADMIN_KEYSTORE']:raise ValueError('Use separate enrolled Viewer/Admin keystores')
  for tool in ['apksigner','aapt']:
   if shutil.which(tool) is None:raise ValueError('Android verification tools must be on PATH')
 prepare(a.profile,a.output);out=Path(a.output).resolve();results=[]
 for kind,folder in [('viewer','user_app'),('admin','admin_app')]:
  app=out/folder
  run([a.flutter,'create','--platforms='+('web' if a.target=='web' else 'android'),'.'],app)
  run([a.flutter,'pub','get'],app)
  if a.target=='web':
   manifest=app/'web/manifest.json'
   if manifest.exists():
    data=json.loads(manifest.read_text());data.update({'name':p[kind+'_name'],'short_name':p[kind+'_name'],'theme_color':p['primary_color'],'icons':[{'src':'icons/customer.png','sizes':'64x64','type':'image/png'}]});manifest.write_text(json.dumps(data))
    icon=app/'web/icons/customer.png';icon.parent.mkdir(exist_ok=True);shutil.copy2(out/'user_app/assets/customer_icon.png',icon)
   base='/'+p['repository'].split('/')[1]+'/'+('admin/' if kind=='admin' else '')
   run([a.flutter,'build','web','--release','--base-href',base,'--build-number',a.build_number,'--no-web-resources-cdn'],app)
   results.append({'app':kind,'path':str(app/'build/web')});continue
  mode='release' if a.target=='release-android' else 'debug';android(app,kind,p,mode)
  run([a.flutter,'build','apk','--'+mode,'--target-platform','android-arm64','--build-number',a.build_number],app)
  apk=app/f'build/app/outputs/flutter-apk/app-{mode}.apk'
  if mode=='release':
   verify=subprocess.check_output(['apksigner','verify','--print-certs',str(apk)],text=True)
   cert=re.search(r'certificate SHA-256 digest: ([a-fA-F0-9]+)',verify)
   if not cert or cert[1].lower()!=os.environ['CUSTOMER_'+kind.upper()+'_CERT_SHA256'].lower():raise ValueError('Unexpected signing certificate; do not publish')
   badging=subprocess.check_output(['aapt','dump','badging',str(apk)],text=True)
   if f"name='{p[kind+'_package']}'" not in badging or f"versionCode='{a.build_number}'" not in badging:raise ValueError('APK identity/version mismatch')
  results.append({'app':kind,'package':p[kind+'_package'],'path':str(apk),'sha256':hashlib.sha256(apk.read_bytes()).hexdigest(),'signed_release':mode=='release'})
 (out/'build-results.json').write_text(json.dumps({'customer':p['id'],'builds':results,'published':False,'real_device_qa':'required'},indent=2))
if __name__=='__main__':
 try:main()
 except (ValueError,OSError) as error:raise SystemExit(str(error))
