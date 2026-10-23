"""Integration fixtures only: no user's project, SDK, cache, or menu registration is changed."""
import json, os, pathlib, pty, select, shutil, subprocess, tempfile, time, unittest
ROOT = pathlib.Path(__file__).resolve().parents[1]
DART = pathlib.Path(os.environ.get('JOBS_TEST_DART', str(ROOT/'.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dart')))
ENGINE = ROOT/'Scripts/Tools/FlutterProjectTools.dart'

def write(p, text, executable=False):
    p.parent.mkdir(parents=True, exist_ok=True); p.write_text(text)
    if executable: p.chmod(0o755)

def terminal(argv, env, answer='\n'):
    master, slave = pty.openpty()
    proc = subprocess.Popen(argv, stdin=slave, stdout=slave, stderr=slave, env=env, close_fds=True)
    os.close(slave); os.write(master, answer.encode()); data=b''; deadline=time.time()+25
    try:
        while time.time()<deadline:
            if select.select([master],[],[],0.1)[0]:
                try: chunk=os.read(master,65536)
                except OSError: break
                if not chunk:break
                data+=chunk
            if proc.poll() is not None:
                try:
                    while select.select([master],[],[],0)[0]:data+=os.read(master,65536)
                except OSError:pass
                break
        try: proc.wait(timeout=1)
        except subprocess.TimeoutExpired: proc.kill(); raise AssertionError('timeout: '+data.decode(errors='replace'))
        return proc.wait(),data.decode(errors='replace')
    finally:os.close(master)

class ToolsTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='jobs-flutter-fixture-');self.base=pathlib.Path(self.temp.name).resolve()
        self.project=self.base/"工程 space ' $(literal)"; self.sdk=self.base/'fvm/versions/3.22.0'
        write(self.project/'pubspec.yaml','name: fixture\ndependencies:\n  flutter:\n    sdk: flutter\n');(self.project/'lib').mkdir()
        write(self.project/'.fvmrc','{"flutter":"3.22.0"}')
        write(self.sdk/'bin/flutter', '''#!/bin/sh
printf '%s\\n' "$*" >> "$JOBS_TRACE"
case "$1" in
 --version) echo '{"frameworkVersion":"3.22.0","dartSdkVersion":"3.4.0"}' ;;
 doctor) if [ "$JOBS_BAD_BASE" = 1 ]; then echo '[!] Android toolchain'; echo 'Doctor found issues in 1 category.'; else echo 'No issues found!'; fi ;;
 build) echo '  hap    Build a Harmony application.' ;;
 *) exit 19 ;;
esac
''',True)
        dart=self.sdk/'bin/cache/dart-sdk/bin/dart';dart.parent.mkdir(parents=True);dart.symlink_to(DART)
        (self.project/'.fvm').mkdir();(self.project/'.fvm/flutter_sdk').symlink_to(self.sdk)
        write(self.base/'bin/fvm','#!/bin/sh\necho 4.0.0\n',True)
        self.env=dict(os.environ,HOME=str(self.base),PATH=str(self.base/'bin')+':/usr/bin:/bin',JOBS_TRACE=str(self.base/'trace'))
        write(self.sdk/'packages/flutter/pubspec.yaml','name: flutter\n')
        self.packages=[{'name':'flutter','rootUri':(self.sdk/'packages/flutter').as_uri()}]
    def tearDown(self):self.temp.cleanup()
    def action(self,action,answer='\n',preview=False):return terminal([str(DART),str(ENGINE),action,str(self.project)]+(['--dry-run'] if preview else []),self.env,answer)
    def plugin(self,name,kotlin=False,namespace=False):
        root=self.base/'shared-cache'/name
        write(root/'pubspec.yaml',f'name: {name}\nflutter:\n  plugin:\n    platforms:\n      android:\n        package: dev.{name}\n')
        write(root/'android/src/main/AndroidManifest.xml',f'<manifest package="dev.{name}"/>')
        path=root/('android/build.gradle.kts' if kotlin else 'android/build.gradle')
        write(path,'// namespace in comment is not a declaration\nandroid {\n'+('    namespace = "dev.existing"\n' if namespace else '')+'}\n')
        self.packages.append({'name':name,'rootUri':root.as_uri()})
        write(self.project/'.dart_tool/package_config.json',json.dumps({'configVersion':2,'packages':self.packages}))
        return path
    def test_missing_fvm_never_runs_global(self):
        (self.project/'.fvmrc').unlink();write(self.base/'bin/flutter','#!/bin/sh\ntouch "$HOME/global-called"\n',True)
        code,out=self.action('native-doctor');self.assertNotEqual(code,0);self.assertFalse((self.base/'global-called').exists());self.assertFalse((self.base/'trace').exists())
    def test_namespace_only_resolved_plugins_and_backup_collisions(self):
        a=self.plugin('one');b=self.plugin('two');c=self.plugin('kotlin',True);existing=self.plugin('existing',namespace=True)
        untouched=self.base/'shared-cache/unused/android/build.gradle';write(untouched,'android {}\n');before=[p.read_text() for p in [a,b,c,existing,untouched]]
        code,out=self.action('repair-namespace','REPAIR\n');self.assertEqual(code,0,out)
        self.assertIn("namespace 'dev.one'",a.read_text());self.assertIn("namespace 'dev.two'",b.read_text());self.assertIn('namespace = "dev.kotlin"',c.read_text())
        self.assertEqual(existing.read_text(),before[3]);self.assertEqual(untouched.read_text(),before[4])
        manifest=next((self.project/'.jobs_flutter_backups').glob('*/manifest.json'));records=json.loads(manifest.read_text());self.assertEqual(len(records),3)
        self.assertEqual(len({r['backup'] for r in records}),3)
        for r in records:self.assertIn((manifest.parent/r['backup']).read_text(),before[:3])
        code,out=self.action('repair-namespace',preview=True);self.assertEqual(code,0,out);self.assertIn('0 个文件',out)
    def test_namespace_cancel_and_preview_do_not_write(self):
        p=self.plugin('one');before=p.read_bytes()
        for preview,answer in [(True,'\n'),(False,'\n')]:
            code,out=self.action('repair-namespace',answer,preview);self.assertEqual(code,0,out);self.assertEqual(p.read_bytes(),before);self.assertFalse((self.project/'.jobs_flutter_backups').exists())
    def test_imports_only_real_directives_and_keep_encoded_delimiters(self):
        content="""/* outer /* nested */ import '%E4%B8%AD.dart'; */
// import '%E4%B8%AD.dart';
const text = "import '%E4%B8%AD.dart';";
import 'package:app/%E4%B8%AD.dart';
export '%E4%B8%AD%2Fsecret.dart';
"""
        a=self.project/'lib/a/same.dart';b=self.project/'lib/b/same.dart';write(a,content);write(b,content)
        ignored=self.project/'build/generated.dart';write(ignored,content)
        code,out=self.action('repair-imports','REPAIR\n');self.assertEqual(code,0,out)
        self.assertEqual(a.read_text(),content.replace("import 'package:app/%E4%B8%AD.dart'","import 'package:app/中.dart'"));self.assertEqual(a.read_text(),b.read_text());self.assertEqual(ignored.read_text(),content)
        records=json.loads(next((self.project/'.jobs_flutter_backups').glob('*/manifest.json')).read_text());self.assertEqual(len(records),2)
    def test_backup_symlink_refused(self):
        p=self.plugin('one');before=p.read_bytes();(self.base/'external').mkdir();(self.project/'.jobs_flutter_backups').symlink_to(self.base/'external')
        code,out=self.action('repair-namespace','REPAIR\n');self.assertNotEqual(code,0);self.assertEqual(p.read_bytes(),before);self.assertEqual(list((self.base/'external').iterdir()),[])
    def harmony(self):
        tool=self.base/'clt';self.env['TOOL_HOME']=str(tool)
        for d in ['ets','native','toolchains']:(tool/f'sdk/default/openharmony/{d}').mkdir(parents=True)
        for path in ['node/bin/node','ohpm/bin/ohpm','hvigor/bin/hvigorw','sdk/default/openharmony/toolchains/hdc','jbr/bin/java']:write(tool/path,'#!/bin/sh\necho fixture-tool-version\n',True)
        for path in ['ohos/build-profile.json5','ohos/oh-package.json5','ohos/AppScope/app.json5','ohos/hvigorfile.ts']:write(self.project/path,'{}')
        write(self.project/'.dart_tool/package_config.json',json.dumps({'configVersion':2,'packages':self.packages}))
    def test_harmony_requires_base_and_adaptation_together(self):
        self.harmony();self.env['JOBS_BAD_BASE']='1';code,out=self.action('harmony-doctor');self.assertNotEqual(code,0,out);self.assertIn('基础环境存在问题',out);self.assertIn('当前 FVM SDK 的 Harmony 构建能力',out);self.assertNotIn('所有检查均通过',out)
        self.env.pop('JOBS_BAD_BASE');code,out=self.action('harmony-doctor');self.assertEqual(code,0,out);self.assertIn('基础 Flutter 与 Harmony 所有检查均通过',out)
        self.plugin('unsupported');code,out=self.action('harmony-doctor');self.assertNotEqual(code,0);self.assertIn('unsupported',out)
    def test_maintenance_blank_and_failed_clean_do_not_upgrade(self):
        lock=self.project/'pubspec.lock';write(lock,'keep')
        code,out=self.action('maintenance');self.assertEqual(code,0,out);self.assertFalse((self.base/'trace').exists())
        code,out=self.action('maintenance','2\n\n');self.assertNotEqual(code,0);self.assertEqual((self.base/'trace').read_text(),'clean\n');self.assertEqual(lock.read_text(),'keep')
    def test_cache_ancestor_link_is_rejected_before_deletion(self):
        external=self.base/'external';write(external/'caches/keep','keep');(self.base/'.gradle').symlink_to(external)
        code,out=self.action('maintenance','6\nCLEAN\n');self.assertNotEqual(code,0);self.assertTrue((external/'caches/keep').exists())
    def test_android_repair_honors_project_sdk_and_pinned_build_tools(self):
        tools=self.base/'tools';tools.mkdir();shutil.copy2(ROOT/'Scripts/Tools/RepairAndroidSdk.zsh',tools/'RepairAndroidSdk.zsh')
        sdk=self.base/'Android SDK';write(self.project/'android/local.properties','sdk.dir='+str(sdk).replace(' ','\\ ')+'\nflutter.sdk=keep\n')
        write(self.project/'android/app/build.gradle','android { compileSdk = 36; buildToolsVersion "35.0.0" }')
        write(tools/'AndroidSdkSupport.zsh', '''android_prepare_context() { ANDROID_SIM_SDK_PROXY=(); }
android_initialize_runtime() { LOG_FILE="$HOME/mock-sdk.log"; }
android_configure_network() { :; }
android_detect_architecture() { :; }
android_ensure_sdk() { ANDROID_SIM_SDK="$ANDROID_HOME"; }
android_ensure_java() { :; }
android_ensure_command_tools() { ANDROID_SIM_SDKMANAGER=fixture; }
android_timed() { print 'platforms;android-38 | unused'; print 'build-tools;36.0.0 | unused'; }
android_log() { print -r -- "$*"; }
android_install_package() {
  print -r -- "$1" >> "$HOME/packages"
  case "$1" in
    platform-tools) file="$ANDROID_SIM_SDK/platform-tools/adb" ;;
    platforms\\;android-*) file="$ANDROID_SIM_SDK/platforms/${1#platforms;}/android.jar" ;;
    build-tools\\;*) file="$ANDROID_SIM_SDK/build-tools/${1#build-tools;}/aapt2" ;;
    *) return 1 ;;
  esac
  /bin/mkdir -p "${file:h}"; /usr/bin/touch "$file"; /bin/chmod +x "$file"
}
''')
        code,out=terminal(['/bin/zsh',str(tools/'RepairAndroidSdk.zsh'),str(self.project)],self.env);self.assertEqual(code,0,out)
        self.assertEqual(set((self.base/'packages').read_text().splitlines()),{'platform-tools','platforms;android-36','build-tools;35.0.0'})
        self.assertIn('flutter.sdk=keep',(self.project/'android/local.properties').read_text());self.assertTrue((sdk/'platforms/android-36/android.jar').exists())

    def test_menu_migration_requires_enabled_group_and_preserves_other_choices(self):
        config=self.base/'Library/Application Support/JobsTerminalOpener/EnabledFinderMenuFeatures.txt'
        write(config,'pod-install,flutter-pub-get,open')
        kit=self.base/'fake-pluginkit'
        write(kit, '#!/bin/zsh\nif [[ "$1" == -m ]]; then print -r -- "$JOBS_REGISTRATION"; else print -r -- "$*" >> "$HOME/registrations"; fi\n',True)
        script=self.base/'migration.zsh'
        write(script,(ROOT/'Scripts/Tools/RetireLegacyFlutterMenus.zsh').read_text().replace('/usr/bin/pluginkit',str(kit)))
        env=dict(self.env,JOBS_REGISTRATION='- com.jobs.JobsFlutterTools.FinderSyncExtension')
        result=subprocess.run(['/bin/zsh',str(script)],env=env,capture_output=True,text=True)
        self.assertNotEqual(result.returncode,0);self.assertEqual(config.read_text(),'pod-install,flutter-pub-get,open');self.assertFalse((self.base/'registrations').exists())
        env['JOBS_REGISTRATION']='+ com.jobs.JobsFlutterTools.FinderSyncExtension'
        result=subprocess.run(['/bin/zsh',str(script)],env=env,capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr);self.assertEqual(config.read_text(),'pod-install,open\n')
        entries=(self.base/'registrations').read_text().splitlines();self.assertEqual(len(entries),7);self.assertTrue(all('-e ignore -i com.jobs.JobsFlutter' in e for e in entries))
        backups=list(config.parent.glob('FlutterMenuMigration.*'));self.assertEqual(len(backups),1);self.assertEqual((backups[0]/config.name).read_text(),'pod-install,flutter-pub-get,open')
        subprocess.run(['/bin/zsh',str(script)],env=env,check=True,capture_output=True)
        self.assertEqual(len(list(config.parent.glob('FlutterMenuMigration.*'))),1)

    def test_namespace_preserves_bom_and_exact_backup_bytes(self):
        path=self.plugin('bom');before=b'\xef\xbb\xbf'+path.read_bytes().replace(b'\n',b'\r\n');path.write_bytes(before)
        code,out=self.action('repair-namespace','REPAIR\n');self.assertEqual(code,0,out)
        self.assertTrue(path.read_bytes().startswith(b'\xef\xbb\xbf'));self.assertIn(b'\r\n',path.read_bytes())
        backup=next((self.project/'.jobs_flutter_backups').glob('*/0.original'));self.assertEqual(backup.read_bytes(),before)

if __name__=='__main__':unittest.main(verbosity=2)
