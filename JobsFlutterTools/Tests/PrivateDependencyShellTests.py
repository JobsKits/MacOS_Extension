"""Exercise the shipped zsh dispatcher with a real native Dart; never touch user projects."""
import json
import os
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
TOOLS = pathlib.Path(os.environ.get('JOBS_TEST_TOOLS_DIR', ROOT / 'Scripts/Tools'))
DART = pathlib.Path(os.environ['JOBS_TEST_DART']).resolve()

with tempfile.TemporaryDirectory(prefix='Jobs private 菜单 ') as temporary:
    base = pathlib.Path(temporary)
    source, target, output = [base / name for name in ['来源', '目标 无 lib', '导出']]
    manifest = 'name: demo\ndependencies:\n  flutter:\n    sdk: flutter\n  private_pkg:\n    git: https://private.invalid/pkg.git\n'
    for project in [source, target]:
        project.mkdir()
        (project / 'pubspec.yaml').write_text(manifest)
        sdk = project / '.fvm/flutter_sdk'
        dart = sdk / 'bin/cache/dart-sdk/bin/dart'
        dart.parent.mkdir(parents=True)
        dart.symlink_to(DART)
        flutter = sdk / 'bin/flutter'
        flutter.write_text('#!/bin/zsh\nexit 97\n')
        flutter.chmod(0o755)
        (project / '.fvmrc').write_text('{"flutter":"fixture"}')
    (source / 'lib').mkdir()
    package = base / '缓存/pkg'
    package.mkdir(parents=True)
    (package / 'pubspec.yaml').write_text('name: private_pkg\nversion: 1.0.0\n')
    (package / 'LICENSE').write_text('license\n')
    (source / 'pubspec.lock').write_text('packages:\n  private_pkg:\n    source: git\n    version: "1.0.0"\n')
    (source / '.dart_tool').mkdir()
    (source / '.dart_tool/package_config.json').write_text(json.dumps({'configVersion': 2, 'packages': [{'name': 'demo', 'rootUri': source.as_uri()+'/'}, {'name': 'private_pkg', 'rootUri': package.as_uri()+'/'}]}))
    env = dict(os.environ, TMPDIR=str(base)+'/', NO_COLOR='1', DART_SUPPRESS_ANALYTICS='true', CI='true')
    def dispatch(action, project, stdin):
        result = subprocess.run(['/bin/zsh', str(TOOLS / 'DispatchFlutterTools.zsh'), action, str(project)], input=stdin, text=True, capture_output=True, env=env, timeout=60)
        assert result.returncode == 0, result.stdout + result.stderr
        return result.stdout
    exported = dispatch('export-private-dependencies', source, '\n'+str(output)+'\n')
    assert '私库模式' in exported
    snapshot, = output.iterdir()
    assert json.loads((snapshot/'manifest.json').read_text())['snapshotKind'] == 'flutter-private-dependencies'
    cancelled = dispatch('import-private-dependencies', target, '\n'+str(snapshot)+'\nNO\n')
    assert '已取消' in cancelled and not (target/'vendor').exists()
    imported = dispatch('import-private-dependencies', target, '\n\n'+str(snapshot)+'\nYES\n')
    assert '尚未输入依赖目录' in imported and '导入完成' in imported
    assert 'vendor/flutter_dependencies/' in (target/'pubspec_overrides.yaml').read_text()
    assert (target/'pubspec.yaml').read_text() == manifest
print('PASS: private export/import dispatcher, cancellation, empty input retry, no-lib target, native Dart and local overrides')
