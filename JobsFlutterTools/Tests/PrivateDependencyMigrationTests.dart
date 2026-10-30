// 私库迁移的行为回归：真实脚本、损坏拒绝、配置备份，以及独立 Pub 离线解析。
import 'dart:convert';
import 'dart:io';

import '../Scripts/Tools/ExtractFlutterDependencies.dart' as extraction;
import '../Scripts/Tools/ImportFlutterDependencies.dart' as importing;

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void write(String path, String content) {
  final file = File(path)..parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

const sdk = "environment:\n  sdk: '>=3.0.0 <4.0.0'\n";
const projectManifest =
    '''name: private_fixture
${sdk}dependencies:
  flutter:
    sdk: flutter
  private_a:
    git:
      url: https://private.invalid/team/monorepo.git
      ref: pinned
      path: packages/private_a
  local_plugin:
    path: ../old-machine/local_plugin
  public_pkg: ^1.0.0
''';

Future<void> main() async {
  final root = Directory.systemTemp.createTempSync('JobsPrivate 迁移 ');
  final tools =
      Platform.environment['JOBS_TEST_TOOLS_DIR'] ??
      File.fromUri(Platform.script).parent.parent.uri
          .resolve('Scripts/Tools/')
          .toFilePath();
  var assertions = 0;
  void expect(bool condition, String message) {
    assertions++;
    check(condition, message);
  }

  try {
    final source = '${root.path}/source';
    write('$source/pubspec.yaml', projectManifest);
    final names = ['private_a', 'private_b', 'local_plugin', 'custom_hosted'];
    for (final name in names) {
      write(
        '${root.path}/cache/$name/pubspec.yaml',
        'name: $name\nversion: 1.0.0\n$sdk${name == 'private_a' ? 'dependencies:\n  private_b:\n    git: https://private.invalid/b.git\n  custom_hosted:\n    hosted: https://pub.private.invalid\n    version: ^1.0.0\n  public_pkg: ^1.0.0\n' : ''}',
      );
      write('${root.path}/cache/$name/lib/$name.dart', '// original $name\n');
      write('${root.path}/cache/$name/LICENSE', 'original license\n');
    }
    write('$source/pubspec.lock', '''packages:
  private_a:
    description:
      path: packages/private_a
      resolved-ref: abcdef
      url: https://private.invalid/team/monorepo.git
    source: git
    version: "1.0.0"
  private_b:
    source: git
    version: "1.0.0"
  local_plugin:
    source: path
    version: "1.0.0"
  custom_hosted:
    description:
      name: custom_hosted
      url: "https://pub.private.invalid"
    source: hosted
    version: "1.0.0"
  public_pkg:
    description:
      name: public_pkg
      url: "https://pub.dev"
    source: hosted
    version: "1.0.0"
  flutter:
    source: sdk
    version: "0.0.0"
''');
    void resolve() => write(
      '$source/.dart_tool/package_config.json',
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {
            'name': 'private_fixture',
            'rootUri': Directory(source).uri.toString(),
          },
          for (final name in [...names, 'public_pkg', 'flutter'])
            {
              'name': name,
              'rootUri': Directory('${root.path}/cache/$name').uri.toString(),
            },
        ],
      }),
    );
    resolve();
    Future<ProcessResult> run(String script, List<String> args) => Process.run(
      Platform.resolvedExecutable,
      ['$tools/$script', ...args],
      environment: {
        'DART_SUPPRESS_ANALYTICS': 'true',
        'CI': 'true',
        'PUB_CACHE': '${root.path}/empty-cache',
      },
    );
    Future<Directory> export(String label) async {
      final output = '${root.path}/$label';
      final result = await run('ExtractFlutterDependencies.dart', [
        '--project',
        source,
        '--destination',
        output,
        '--private-only',
      ]);
      expect(result.exitCode == 0, '私库提取失败：${result.stdout}\n${result.stderr}');
      return Directory(output).listSync().whereType<Directory>().single;
    }

    final snapshot = await export('exports');
    final metadata = jsonDecode(
      File('${snapshot.path}/manifest.json').readAsStringSync(),
    ) as Map;
    expect(
      (metadata['packages'] as List).length == 4,
      '只提取直接、间接、path 与 custom hosted 四包',
    );
    expect(
      !Directory('${snapshot.path}/packages/public_pkg').existsSync(),
      '缺失公共缓存也能成功，且不复制公共包',
    );
    expect(
      metadata['snapshotKind'] == 'flutter-private-dependencies',
      '私库快照类型',
    );
    final known = '${root.path}/known';
    write(known, 'abc');
    expect(
      extraction.fileDigest(File(known)) ==
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      'SHA-256 known vector',
    );
    String target(String name, {String manifest = projectManifest}) {
      final path = '${root.path}/$name';
      write('$path/pubspec.yaml', manifest);
      return path;
    }

    final crlfTarget = target(
      'Windows CRLF',
      manifest: projectManifest.replaceAll('\n', '\r\n'),
    );
    final crlfCheck = await run('ImportFlutterDependencies.dart', [
      '--project',
      crlfTarget,
      '--source',
      snapshot.path,
      '--private-only',
      '--validate-only',
    ]);
    expect(crlfCheck.exitCode == 0, '跨平台换行兼容：${crlfCheck.stderr}');
    expect(
      extraction.dependencyEvidence(projectManifest, 'dependencies', 'path') ==
          null,
      'Git 子目录 path 字段不能误认成根依赖',
    );
    final dest = target('目标工程');
    write(
      '$dest/pubspec_overrides.yaml',
      '# unrelated stays\ndependency_overrides:\n  public_pkg:\n    path: public\n',
    );
    write(
      '$dest/public/pubspec.yaml',
      'name: public_pkg\nversion: 1.0.0\n$sdk',
    );
    final original = File('$dest/pubspec_overrides.yaml').readAsStringSync();
    final args = [
      '--project',
      dest,
      '--source',
      snapshot.path,
      '--private-only',
    ];
    final preflight = await run('ImportFlutterDependencies.dart', [
      ...args,
      '--validate-only',
    ]);
    expect(preflight.exitCode == 0, '私库预检：${preflight.stderr}');
    expect(!Directory('$dest/vendor').existsSync(), '预检不写入');
    final imported = await run('ImportFlutterDependencies.dart', args);
    expect(
      imported.exitCode == 0,
      '导入失败：${imported.stdout}\n${imported.stderr}',
    );
    final vendor = Directory('$dest/vendor/flutter_dependencies')
        .listSync()
        .whereType<Directory>()
        .single;
    expect(
      File('${vendor.path}/pubspec_overrides.yaml.before-import')
              .readAsStringSync() ==
          original,
      '精确备份',
    );
    expect(
      File('$dest/pubspec.yaml').readAsStringSync() == projectManifest,
      '项目声明原样保留',
    );
    expect(
      File('$dest/pubspec_overrides.yaml')
          .readAsStringSync()
          .contains('# unrelated stays'),
      '保留已有无关配置',
    );
    // Pub 独立校验：保留真实 Git / 旧 path 引用，移除 Flutter SDK；公共包用本地模拟缓存。
    write(
      '$dest/pubspec.yaml',
      projectManifest.replaceFirst('  flutter:\n    sdk: flutter\n', ''),
    );
    final pub = await Process.run(
      Platform.resolvedExecutable,
      ['pub', 'get', '--offline', '--no-precompile'],
      workingDirectory: dest,
      environment: {
        'PUB_CACHE': '${root.path}/empty-cache',
        'DART_SUPPRESS_ANALYTICS': 'true',
        'CI': 'true',
      },
    );
    expect(
      pub.exitCode == 0,
      '无私库网络/原路径/原缓存，Pub 仍须成功：${pub.stdout}\n${pub.stderr}',
    );
    final config = jsonDecode(
      File('$dest/.dart_tool/package_config.json').readAsStringSync(),
    );
    for (final name in names) {
      final package = (config['packages'] as List).singleWhere(
        (p) => p['name'] == name,
      );
      expect(
        (package['rootUri'] as String).contains('vendor/flutter_dependencies/'),
        'Pub 实际指向迁移源码 $name',
      );
    }
    Future<void> rejects(
      String label, {
      String? path,
      String? snap,
      bool private = true,
    }) async {
      final project = path ?? target(label);
      final result = await run('ImportFlutterDependencies.dart', [
        '--project',
        project,
        '--source',
        snap ?? snapshot.path,
        if (private) '--private-only',
        '--validate-only',
      ]);
      expect(result.exitCode != 0, '$label 应拒绝');
      expect(!Directory('$project/vendor').existsSync(), '$label 不应写入');
    }

    await rejects('错误入口', private: false);
    await rejects(
      'Git-ref冲突',
      path: target(
        'changed-ref',
        manifest: projectManifest.replaceFirst('ref: pinned', 'ref: different'),
      ),
    );
    final conflict = target('conflict');
    write(
      '$conflict/pubspec_overrides.yaml',
      'dependency_overrides:\n  private_a:\n    path: another-copy\n',
    );
    await rejects('覆盖冲突', path: conflict);
    final damaged = File(
      '${snapshot.path}/packages/private_a/lib/private_a.dart',
    );
    final originalBytes = damaged.readAsBytesSync();
    damaged.writeAsStringSync('// tampered private_a\n');
    await rejects('源码损坏');
    damaged.writeAsBytesSync(originalBytes);
    final removed = Directory('${snapshot.path}/packages/private_b');
    removed.renameSync('${root.path}/removed');
    await rejects('缺失间接私库');
    Directory('${root.path}/removed').renameSync(removed.path);
    final manifestFile = File('${snapshot.path}/manifest.json');
    final saved = manifestFile.readAsStringSync();
    (metadata['packages'] as List).removeWhere((p) => p['name'] == 'private_b');
    manifestFile.writeAsStringSync(jsonEncode(metadata));
    await rejects('伪造不完整包清单');
    manifestFile.writeAsStringSync(saved);
    // 已有同源覆盖可以迁移；目标没有覆盖文件的干净 clone 也可以迁移。
    for (final form in ['block', 'flow']) {
      final override = form == 'block'
          ? '# source overrides\ndependency_overrides:\n  private_a:\n    path: ../cache/private_a\n  untouched: ^1.0.0\n'
          : 'dependency_overrides: {private_a: {path: ../cache/private_a}, untouched: ^1.0.0}\n';
      write('$source/pubspec_overrides.yaml', override);
      resolve();
      final exported = await export('overrides-$form');
      for (final existing in [false, true]) {
        final destination = target('overrides-$form-$existing');
        if (existing) write('$destination/pubspec_overrides.yaml', override);
        final result = await run('ImportFlutterDependencies.dart', [
          '--project',
          destination,
          '--source',
          exported.path,
          '--private-only',
        ]);
        expect(
          result.exitCode == 0,
          '同源覆盖 $form / $existing：${result.stdout}\n${result.stderr}',
        );
        final resultText = File('$destination/pubspec_overrides.yaml')
            .readAsStringSync();
        expect(
          resultText.contains('vendor/flutter_dependencies/'),
          '同源覆盖转换本地引用',
        );
        if (existing)
          expect(resultText.contains('untouched: ^1.0.0'), '无关覆盖继续保留');
      }
    }
    // 校验后源码变化必须阻止发布配置。
    final verifyDest = target('二次校验');
    final plan = importing.validate(
      verifyDest,
      snapshot.path,
      privateOnly: true,
    );
    damaged.writeAsStringSync('// another change\n');
    var failed = false;
    try {
      importing.execute(plan);
    } catch (_) {
      failed = true;
    }
    expect(
      failed && !Directory('$verifyDest/vendor').existsSync(),
      '变化在写入前被拒绝',
    );
    print(
      'PASS: $assertions private migration assertions; independent offline Pub resolved all private sources.',
    );
  } finally {
    root.deleteSync(recursive: true);
  }
}
