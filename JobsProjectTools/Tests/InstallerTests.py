import json
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FEATURES = ['android_studio_opener', 'vscode_opener', 'xcode_opener', 'git-pull', 'git_remote', 'git_remote_copier']
APPS = ['JobsAndroidStudioOpener', 'JobsVSCodeOpener', 'JobsXcodeOpener', 'JobsGitPuller', 'JobsGitRemoteOpener', 'JobsGitRemoteCopier']
GROUP_ID = 'com.jobs.JobsProjectTools.FinderSyncExtension'


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='project-installer-')
        self.addCleanup(self.temp.cleanup)
        self.base = pathlib.Path(self.temp.name)
        self.config = self.base / 'config/EnabledFeatures.txt'
        self.state = self.base / 'state.json'
        self.state.write_text(json.dumps({f'com.jobs.{app}.FinderSyncExtension': '+' for app in APPS}))
        self.log = self.base / 'calls.log'
        self.extension = self.base / 'work/DerivedData/Build/Products/Debug/JobsProjectTools.app/Contents/PlugIns/JobsProjectToolsFinderSync.appex'
        self.extension.mkdir(parents=True)
        source = (ROOT / 'JobsProjectTools/Scripts/ManageProjectTools.zsh').read_text()
        source = source.replace('PROJECT_ROOT="${0:A:h:h}"', f'PROJECT_ROOT="{self.base}"')
        source = source.replace('CONFIG_DIR="${HOME}/Library/Application Support/JobsProjectTools"', f'CONFIG_DIR="{self.config.parent}"')
        shim = self.base / 'shim.py'
        shim.write_text(f'''#!/usr/bin/env python3
import json,pathlib,sys
base=pathlib.Path({str(self.base)!r})
name=pathlib.Path(sys.argv[0]).name
args=sys.argv[1:]
with (base/'calls.log').open('a') as f: f.write(name+' '+repr(args)+'\\n')
state_path=base/'state.json'
state=json.loads(state_path.read_text())
if name=='xcodebuild' and (base/'fail-build').exists(): sys.exit(9)
if name=='pluginkit':
 if '-m' in args:
  identifier=args[args.index('-i')+1]
  if identifier in state:
   location={str(self.extension)!r} if identifier=={GROUP_ID!r} else '/old.app/Contents/PlugIns/old.appex'
   print(state[identifier]+' '+identifier+'(1.0) '+location)
 elif '-e' in args:
  if (base/'fail-register').exists(): sys.exit(8)
  state[args[args.index('-i')+1]]='+' if args[args.index('-e')+1]=='use' else '-'
  state_path.write_text(json.dumps(state))
''')
        shim.chmod(0o755)
        for name in ['xcodebuild', 'pluginkit', 'pkill', 'killall', 'lsregister']:
            path = self.base / name
            path.symlink_to(shim)
            if name == 'lsregister':
                start = source.index('LSREGISTER=')
                end = source.index('\n', start)
                source = source[:start] + f'LSREGISTER="{path}"' + source[end:]
            else:
                source = source.replace(f'/usr/bin/{name}', str(path))
        self.script = self.base / 'manage.zsh'
        self.script.write_text(source)

    def run_script(self, operation, *features, success=True):
        result = subprocess.run(['zsh', str(self.script), operation, *features], capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stdout + result.stderr)
        return result

    def configured(self):
        return set(filter(None, self.config.read_text().split(',')))

    def test_migration_partial_uninstall_reinstall_and_full_uninstall(self):
        self.run_script('install', 'vscode_opener')
        self.assertEqual(self.configured(), set(FEATURES))
        state = json.loads(self.state.read_text())
        self.assertEqual(state[GROUP_ID], '+')
        self.assertTrue(all(state[f'com.jobs.{app}.FinderSyncExtension'] == '-' for app in APPS))
        self.run_script('uninstall', 'git_remote')
        self.assertEqual(self.configured(), set(FEATURES) - {'git_remote'})
        self.assertEqual(json.loads(self.state.read_text())[GROUP_ID], '+')
        self.run_script('install', 'git_remote')
        self.assertEqual(self.configured(), set(FEATURES))
        self.run_script('uninstall', *FEATURES)
        self.assertEqual(self.configured(), set())
        self.assertEqual(json.loads(self.state.read_text())[GROUP_ID], '-')
        self.run_script('install', 'vscode_opener')
        self.assertEqual(self.configured(), {'vscode_opener'})

    def test_build_and_registration_failures_keep_legacy_and_configuration(self):
        for marker in ['fail-build', 'fail-register']:
            with self.subTest(marker=marker):
                (self.base / marker).touch()
                self.run_script('install', 'vscode_opener', success=False)
                self.assertFalse(self.config.exists())
                state = json.loads(self.state.read_text())
                self.assertTrue(all(value == '+' for value in state.values()))
                (self.base / marker).unlink()

    def test_clean_install_does_not_enable_unselected_features(self):
        self.state.write_text('{}')
        self.run_script('install', 'xcode_opener', 'git-pull')
        self.assertEqual(self.configured(), {'xcode_opener', 'git-pull'})

    def test_unknown_feature_has_no_side_effects(self):
        self.run_script('install', 'unknown', success=False)
        self.assertFalse(self.log.exists())
        self.assertFalse(self.config.exists())

    def test_legacy_uninstall_does_not_create_group_configuration(self):
        self.run_script('uninstall', 'git_remote')
        self.assertFalse(self.config.exists())
        state = json.loads(self.state.read_text())
        self.assertEqual(state['com.jobs.JobsGitRemoteOpener.FinderSyncExtension'], '-')
        self.assertEqual(state['com.jobs.JobsVSCodeOpener.FinderSyncExtension'], '+')

    def test_all_entry_points_route_to_the_group(self):
        installer = (ROOT / '【MacOS】🧩安装Finder扩展.command').read_text()
        uninstaller = (ROOT / '【MacOS】🧩卸载Finder扩展.command').read_text()
        for feature, app in zip(FEATURES, APPS):
            self.assertIn(f'SELECTABLE_FUNCTION_PROJECT_KEY[{feature}]="project-tools"', installer)
            self.assertIn(feature, uninstaller.split('case "$key" in')[1].split('esac')[0])
            for operation in ['安装', '卸载']:
                entry = next((ROOT / app).glob(f'【MacOS】{operation}*Finder扩展.command')).read_text()
                self.assertIn(f'JobsProjectTools/【MacOS】{operation}项目工具Finder扩展.command', entry)
                self.assertIn(f'exec /bin/zsh "$entry" {feature}', entry)


if __name__ == '__main__':
    unittest.main()
