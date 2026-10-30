import json
import pathlib
import subprocess
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[2]
FEATURES = ['android_studio_opener', 'vscode_opener', 'xcode_opener', 'git-pull', 'git_remote', 'git_remote_copier', 'git-proxy-configure', 'git_empty_commit_push', 'git-rollback']
APPS = ['JobsAndroidStudioOpener', 'JobsVSCodeOpener', 'JobsXcodeOpener', 'JobsGitPuller', 'JobsGitRemoteOpener', 'JobsGitRemoteCopier']
GROUP_ID = 'com.jobs.JobsProjectTools.FinderSyncExtension'


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='project-installer-')
        self.addCleanup(self.temp.cleanup)
        self.base = pathlib.Path(self.temp.name)
        self.config = self.base / 'config/EnabledFeatures.txt'
        self.state = self.base / 'state.json'
        self.state.write_text(json.dumps({**{f'com.jobs.{app}.FinderSyncExtension': '+' for app in APPS}, 'com.jobs.gitproxyconfigurator.findersync': '+', 'com.jobs.JobsTerminalOpener.FinderSyncExtension': '+', 'com.jobs.JobsGitRollback.FinderSyncExtension': '+'}))
        self.terminal = self.base / 'terminal/EnabledFinderMenuFeatures.txt'
        self.terminal.parent.mkdir()
        self.terminal.write_text('open,pod-install,git-empty-commit-push,unknown')
        self.log = self.base / 'calls.log'
        self.extension = self.base / 'work/DerivedData/Build/Products/Debug/JobsProjectTools.app/Contents/PlugIns/JobsProjectToolsFinderSync.appex'
        self.extension.mkdir(parents=True)
        source = (ROOT / 'JobsProjectTools/Scripts/ManageProjectTools.zsh').read_text()
        source = source.replace('PROJECT_ROOT="${0:A:h:h}"', f'PROJECT_ROOT="{self.base}"')
        source = source.replace('CONFIG_DIR="${HOME}/Library/Application Support/JobsProjectTools"', f'CONFIG_DIR="{self.config.parent}"')
        source = source.replace('TERMINAL_CONFIG_PATH="${HOME}/Library/Application Support/JobsTerminalOpener/EnabledFinderMenuFeatures.txt"', f'TERMINAL_CONFIG_PATH="{self.terminal}"')
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
        self.assertEqual(state['com.jobs.gitproxyconfigurator.findersync'], '-')
        self.assertEqual(self.terminal.read_text(), 'open,pod-install,unknown')
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

    def test_retired_sourcetree_rejects_install_and_legacy_uninstall_preserves_siblings(self):
        self.state.write_text('{}')
        self.run_script('install', 'xcode_opener')
        self.config.write_text('xcode_opener,git-sourcetree')
        before = self.config.read_bytes()
        self.run_script('install', 'git-sourcetree', success=False)
        self.assertEqual(self.config.read_bytes(), before)
        self.run_script('uninstall', 'git-sourcetree')
        self.assertEqual(self.configured(), {'xcode_opener'})
        self.assertEqual(json.loads(self.state.read_text())[GROUP_ID], '+')

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

    def test_existing_group_migrates_once_and_preserves_other_terminal_entries(self):
        self.config.parent.mkdir()
        self.config.write_text('vscode_opener')
        self.run_script('install', 'git_remote')
        self.assertEqual(self.configured(), {'vscode_opener', 'git_remote', 'git-proxy-configure', 'git_empty_commit_push', 'git-rollback'})
        self.run_script('uninstall', 'git-proxy-configure', 'git_empty_commit_push')
        self.run_script('install', 'xcode_opener')
        self.assertEqual(self.configured(), {'vscode_opener', 'git_remote', 'xcode_opener', 'git-rollback'})
        self.assertEqual(self.terminal.read_text(), 'open,pod-install,unknown')

    def test_uninstalling_ide_before_migration_preserves_legacy_git_choice(self):
        self.config.parent.mkdir()
        self.config.write_text('vscode_opener')
        self.run_script('uninstall', 'vscode_opener')
        self.assertEqual(self.terminal.read_text(), 'open,pod-install,git-empty-commit-push,unknown')
        self.assertFalse((self.config.parent / 'GitMenuMigrationVersion.txt').exists())
        self.run_script('install', 'xcode_opener')
        self.assertIn('git_empty_commit_push', self.configured())

    def test_explicit_empty_commit_uninstall_only_removes_its_legacy_menu(self):
        self.run_script('uninstall', 'git_empty_commit_push')
        self.assertEqual(self.terminal.read_text(), 'open,pod-install,unknown')
        self.assertFalse(self.config.exists())

    def test_rollback_migrates_once_then_respects_uninstall(self):
        self.run_script('install', 'git-rollback')
        self.assertIn('git-rollback', self.configured())
        state = json.loads(self.state.read_text())
        self.assertEqual(state['com.jobs.JobsGitRollback.FinderSyncExtension'], '-')
        self.assertTrue((self.config.parent / 'GitRollbackMigrationVersion.txt').exists())
        self.run_script('uninstall', 'git-rollback')
        self.assertNotIn('git-rollback', self.configured())
        self.run_script('install', 'vscode_opener')
        self.assertNotIn('git-rollback', self.configured())

    def test_rollback_uninstall_preserves_unrelated_legacy_menus(self):
        self.run_script('uninstall', 'git-rollback')
        state = json.loads(self.state.read_text())
        self.assertEqual(state['com.jobs.JobsGitRollback.FinderSyncExtension'], '-')
        self.assertEqual(state['com.jobs.JobsVSCodeOpener.FinderSyncExtension'], '+')
        self.assertFalse(self.config.exists())

    def test_rollback_entries_and_bundle_use_the_shared_implementation(self):
        project = (ROOT / 'JobsProjectTools/JobsProjectTools.xcodeproj/project.pbxproj').read_text()
        self.assertIn('../JobsGitRollback/Scripts/RollbackGitRepository.zsh', project)
        resources = project.split('/* Begin PBXResourcesBuildPhase section */')[1].split('/* End PBXResourcesBuildPhase section */')[0]
        self.assertIn('RollbackGitRepository.zsh', resources)
        manager = (ROOT / 'JobsGitRollback/Scripts/ManageExtension.zsh').read_text()
        self.assertIn('MANAGER_UI_SCOPE="git-rollback"', manager)
        self.assertIn('JobsProjectTools/Scripts/ManageProjectTools.zsh', manager)
        self.assertIn('run_feature_operation install', manager)
        self.assertIn('run_feature_operation uninstall', manager)

    def test_all_entry_points_route_to_the_group(self):
        installer = (ROOT / 'Scripts/ManageFinderExtensions.zsh').read_text()
        self.assertIn('ManageProjectTools.zsh" install', installer)
        self.assertIn('ManageProjectTools.zsh" uninstall', installer)
        for feature, app in zip(FEATURES, APPS):
            self.assertIn(f'SELECTABLE_FUNCTION_PROJECT_KEY[{feature}]="project-tools"', installer)
            manager = (ROOT / app / 'Scripts/ManageExtension.zsh').read_text()
            self.assertIn(f'MANAGER_UI_SCOPE="{feature}"', manager)
            self.assertIn('JobsProjectTools/Scripts/ManageProjectTools.zsh', manager)
            self.assertIn('run_feature_operation install', manager)
            self.assertIn('run_feature_operation uninstall', manager)


if __name__ == '__main__':
    unittest.main()
