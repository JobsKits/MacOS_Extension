// Created by Jobs on 2026年10月29日，星期四。
// 仅在临时目录运行真实归档CLI；不调用包管理器、不联网、不执行归档文件。
import 'dart:convert';
import 'dart:io';

final engine =
    Platform.environment['JOBS_NATIVE_ARCHIVE_ENGINE'] ??
    File.fromUri(
      Platform.script.resolve('../Scripts/Tools/NativeDependencyArchive.dart'),
    ).path;
var assertions = 0;
var completed = 0;

void check(bool condition, String message) {
  assertions++;
  if (!condition) throw StateError(message);
}

class Fixture {
  Fixture() {
    root = Directory.systemTemp
        .createTempSync('jobs-native-archive-tests-')
        .resolveSymbolicLinksSync();
    project = '$root/项目 空格 \' \$(touch INJECTED)';
    source = '$root/source';
    output = '$root/exported';
    target = '$root/target';
    for (final directory in [project, source, output])
      Directory(directory).createSync();
    File('$project/pubspec.yaml').writeAsStringSync(
      'name: fixture\ndependencies:\n  flutter:\n    sdk: flutter\n',
    );
    File('$project/pubspec.lock').writeAsStringSync('packages: fixture');
    File('$source/a.bin').writeAsStringSync('abc');
  }
  late final String root, project, source, output, target;
  String kind = 'gradle';
  String platform = 'android';
  String version = 'Gradle 8.14 modules';
  List<String> arguments(
    String operation, {
    String? directory,
    bool checkOnly = false,
    bool confirm = true,
    String? destination,
  }) => [
    operation,
    '--project',
    project,
    '--kind',
    kind,
    '--platform',
    platform,
    '--tool-version',
    version,
    '--directory',
    directory ?? output,
    operation == 'export' ? '--source-root' : '--target-root',
    destination ?? (operation == 'export' ? source : target),
    if (checkOnly) '--check',
    if (operation == 'import' && confirm && !checkOnly) ...['--confirm', 'YES'],
  ];
  ProcessResult execute(List<String> arguments) =>
      Process.runSync(Platform.resolvedExecutable, [engine, ...arguments]);
  String export({bool checkOnly = false}) {
    final result = execute(arguments('export', checkOnly: checkOnly));
    check(result.exitCode == 0, '导出失败：${result.stderr}');
    if (checkOnly) return result.stdout.toString();
    final marker = result.stdout
        .toString()
        .split('\n')
        .firstWhere((line) => line.startsWith('ARCHIVE_DIRECTORY='));
    return marker.substring('ARCHIVE_DIRECTORY='.length);
  }

  Map<String, dynamic> manifest(String snapshot) =>
      jsonDecode(File('$snapshot/manifest.json').readAsStringSync())
          as Map<String, dynamic>;
  void writeManifest(String snapshot, Map<String, dynamic> data) =>
      File('$snapshot/manifest.json').writeAsStringSync(jsonEncode(data));
  void reject(List<String> args, String reason) {
    final result = execute(args);
    check(result.exitCode != 0, '错误被接受：$reason\n${result.stdout}');
  }

  void dispose() => Directory(root).deleteSync(recursive: true);
}

Future<void> test(String name, Future<void> Function(Fixture) body) async {
  final fixture = Fixture();
  try {
    await body(fixture);
    completed++;
    stdout.writeln('PASS $name');
  } finally {
    fixture.dispose();
  }
}

Future<void> main() async {
  await test('SHA256 known vectors and large streaming input', (f) async {
    File('${f.source}/empty').writeAsBytesSync([]);
    File('${f.source}/padding').writeAsStringSync(
      'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq',
    );
    File('${f.source}/million').writeAsBytesSync(List<int>.filled(1000000, 97));
    final snapshot = f.export();
    final rows = {
      for (final row in f.manifest(snapshot)['files'] as List)
        row['path']: row['sha256'],
    };
    check(
      rows['a.bin'] ==
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      'abc SHA256',
    );
    check(
      rows['empty'] ==
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      'empty SHA256',
    );
    check(
      rows['padding'] ==
          '248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1',
      'SHA256 padding boundary',
    );
    check(
      rows['million'] ==
          'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0',
      'streaming million-a SHA256',
    );
  });

  await test('unique export, safe inventory, sensitive transient exclusion', (
    f,
  ) async {
    for (final name in [
      'cache.lck',
      'trace.log',
      '.lock',
      'gradle.properties',
      '.npmrc',
      '.netrc',
    ])
      File('${f.source}/$name').writeAsStringSync('secret');
    Directory('${f.source}/daemon').createSync();
    File('${f.source}/daemon/transient').writeAsStringSync('secret');
    final first = f.export();
    final second = f.export();
    check(first != second, '不能覆盖之前快照');
    final manifest = f.manifest(first);
    check((manifest['files'] as List).length == 1, '锁/日志/凭据配置不能进入payload');
    check(manifest['hostOS'] == Platform.operatingSystem, '实际宿主');
    check(!jsonEncode(manifest).contains(f.root), '清单不得持久化开发机绝对路径');
    check(!File('${f.project}/INJECTED').existsSync(), '路径保持字面数据');
    if (!Platform.isWindows)
      check((Directory(first).statSync().mode & 0x3f) == 0, '私有目录权限');
  });

  await test('check-only never creates snapshot or target', (f) async {
    final plan = jsonDecode(f.export(checkOnly: true));
    check(plan['fileCount'] == 1 && plan['check'] == true, '导出计划');
    check(Directory(f.output).listSync().isEmpty, 'check不创建快照');
    final snapshot = f.export();
    final result = f.execute(
      f.arguments('import', directory: snapshot, checkOnly: true),
    );
    check(
      result.exitCode == 0 && jsonDecode(result.stdout)['writeCount'] == 1,
      '导入计划',
    );
    check(!Directory(f.target).existsSync(), '导入check不创建目标');
  });

  await test(
    'Gradle exclusions do not remove legitimate other-layer packages',
    (f) async {
      f.kind = 'web';
      f.platform = 'web';
      f.version = 'Node 24.0.0 arch arm64';
      Directory('${f.source}/daemon').createSync();
      File('${f.source}/daemon/index.js')
          .writeAsStringSync('module.exports = 1;');
      final snapshot = f.export();
      check(
        File('$snapshot/payload/daemon/index.js').existsSync(),
        'Web daemon 包不是Gradle daemon缓存',
      );
    },
  );

  await test(
    'functional lockfiles survive while known transient locks do not',
    (f) async {
      const functional = [
        'Manifest.lock',
        'Cargo.lock',
        'yarn.lock',
        'custom-semantic.lock',
      ];
      const gradleTransient = [
        'file.lock',
        'modules-2.lock',
        'metadata-2.107.lock',
        'fileHashes.lock',
      ];
      for (final name in [
        ...functional,
        ...gradleTransient,
        '.lock',
        'worker.lck',
      ]) {
        File('${f.source}/$name').writeAsStringSync('contents-$name');
      }
      for (final entry in {
        'gradle': 'android',
        'pods': 'ios',
        'native': 'android',
        'web': 'web',
      }.entries) {
        f.kind = entry.key;
        f.platform = entry.value;
        final snapshot = f.export();
        for (final name in functional) {
          check(
            File('$snapshot/payload/$name').readAsStringSync() ==
                'contents-$name',
            '${entry.key}保留功能锁$name',
          );
        }
        for (final name in gradleTransient) {
          check(
            File('$snapshot/payload/$name').existsSync() ==
                (entry.key != 'gradle'),
            'Gradle专属瞬时锁$name仅在Gradle层排除',
          );
        }
        check(
          !File('$snapshot/payload/.lock').existsSync() &&
              !File('$snapshot/payload/worker.lck').existsSync(),
          '通用进程锁仍排除',
        );
        final result = f.execute(f.arguments('import', directory: snapshot));
        check(result.exitCode == 0, '${entry.key}带功能锁快照可恢复：${result.stderr}');
        for (final name in functional) {
          check(
            File('${f.target}/$name').readAsStringSync() == 'contents-$name',
            '${entry.key}导入功能锁$name',
          );
        }
      }
    },
  );

  await test('successful import, repeat reuse and user confirmation', (
    f,
  ) async {
    final snapshot = f.export();
    f.reject(
      f.arguments('import', directory: snapshot, confirm: false),
      '无YES不写入',
    );
    check(!Directory(f.target).existsSync(), '无确认无目标');
    var result = f.execute(f.arguments('import', directory: snapshot));
    check(result.exitCode == 0, '导入成功：${result.stderr}');
    check(File('${f.target}/a.bin').readAsStringSync() == 'abc', '真实内容');
    final before = File('${f.target}/a.bin').statSync().modified;
    result = f.execute(f.arguments('import', directory: snapshot));
    check(
      result.exitCode == 0 && jsonDecode(result.stdout)['reuseCount'] == 1,
      '重复导入复用',
    );
    check(
      File('${f.target}/a.bin').statSync().modified == before,
      '不重写已存在相同文件',
    );
  });

  await test('batch conflict preflight performs zero writes', (f) async {
    File('${f.source}/z.bin').writeAsStringSync('locked');
    final snapshot = f.export();
    Directory(f.target).createSync();
    File('${f.target}/z.bin').writeAsStringSync('user-content');
    f.reject(f.arguments('import', directory: snapshot), '同名不同内容');
    check(!File('${f.target}/a.bin').existsSync(), '冲突前置，不先写前几个文件');
    check(
      File('${f.target}/z.bin').readAsStringSync() == 'user-content',
      '保留用户文件',
    );
  });

  await test('payload changes and unlisted files fail before target writes', (
    f,
  ) async {
    final snapshot = f.export();
    File('$snapshot/payload/a.bin').writeAsStringSync('tampered');
    f.reject(f.arguments('import', directory: snapshot), '哈希不符');
    check(!Directory(f.target).existsSync(), '篡改不写入');
    File('$snapshot/payload/a.bin').writeAsStringSync('abc');
    File('$snapshot/payload/extra').writeAsStringSync('unlisted');
    f.reject(f.arguments('import', directory: snapshot), '额外文件');
    check(!Directory(f.target).existsSync(), '额外文件不写入');
  });

  await test('malicious manifest paths, duplicate paths and parent conflicts', (
    f,
  ) async {
    final snapshot = f.export();
    final original = File('$snapshot/manifest.json').readAsStringSync();
    for (final path in [
      '../outside',
      '/tmp/outside',
      'C:/outside',
      'nested/../outside',
      'a\\b',
      'a//b',
      'CON',
      'a.',
    ]) {
      final manifest = jsonDecode(original) as Map<String, dynamic>;
      manifest['files'][0]['path'] = path;
      f.writeManifest(snapshot, manifest);
      f.reject(f.arguments('import', directory: snapshot), '不安全路径 $path');
      check(!Directory(f.target).existsSync(), '不安全路径不写入');
    }
    final manifest = jsonDecode(original) as Map<String, dynamic>;
    manifest['files'].add({...manifest['files'][0], 'path': 'A.BIN'});
    f.writeManifest(snapshot, manifest);
    f.reject(f.arguments('import', directory: snapshot), '大小写重复');
    check(!File('${f.root}/outside').existsSync(), '没有越界写入');
  });

  await test('same host, platform, kind and exact tool version gates', (
    f,
  ) async {
    final snapshot = f.export();
    final original = File('$snapshot/manifest.json').readAsStringSync();
    for (final replacement in [
      {'hostOS': 'another-system'},
      {'platform': 'ios'},
      {'kind': 'web'},
      {'toolVersion': 'Gradle 9.8 modules'},
      {'formatVersion': 99},
    ]) {
      final manifest = jsonDecode(original) as Map<String, dynamic>;
      manifest.addAll(replacement);
      f.writeManifest(snapshot, manifest);
      f.reject(
        f.arguments('import', directory: snapshot),
        '不兼容字段 $replacement',
      );
      check(!Directory(f.target).existsSync(), '不兼容不写入');
    }
  });

  await test('project configuration and lock signatures are mandatory', (
    f,
  ) async {
    Directory('${f.project}/android/gradle/wrapper')
        .createSync(recursive: true);
    final wrapper = File(
      '${f.project}/android/gradle/wrapper/gradle-wrapper.properties',
    )..writeAsStringSync('distributionUrl=gradle-8.14-bin.zip');
    final snapshot = f.export();
    wrapper.writeAsStringSync('distributionUrl=gradle-9.8-bin.zip');
    f.reject(f.arguments('import', directory: snapshot), 'Wrapper版本配置变化');
    wrapper.writeAsStringSync('distributionUrl=gradle-8.14-bin.zip');
    File('${f.project}/pubspec.lock').writeAsStringSync('changed lock');
    f.reject(f.arguments('import', directory: snapshot), 'Pub锁变化');
    check(!Directory(f.target).existsSync(), '锁不一致不写入');
  });

  await test(
    'each layer captures selected locks while precache stays SDK-specific',
    (f) async {
      final files = <String, String>{
        'ios/Podfile.lock': 'pods',
        'ios/Podfile': 'podfile',
        'ios/Custom.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved':
            'spm',
        'ohos/oh-package-lock.json5': 'ohpm',
        'web/package-lock.json': 'npm',
        'android/gradle.lockfile': 'maven',
      };
      for (final entry in files.entries) {
        File('${f.project}/${entry.key}').createSync(recursive: true);
        File('${f.project}/${entry.key}').writeAsStringSync(entry.value);
      }
      final kinds = {
        'pods': 'ios',
        'spm': 'ios',
        'ohos': 'ohos',
        'web': 'web',
        'gradle': 'android',
        'native': 'android',
      };
      for (final entry in kinds.entries) {
        f.kind = entry.key;
        f.platform = entry.value;
        f.version = 'Tool 1.2.3';
        final snapshot = f.export();
        final locks = (f.manifest(snapshot)['projectLocks'] as List)
            .map((row) => row['path'])
            .toList();
        check(locks.length >= 2, '${entry.key}受控工程签名');
      }
      f.kind = 'precache';
      f.version = 'Flutter 3.47.8';
      final snapshot = f.export();
      check(
        (f.manifest(snapshot)['projectLocks'] as List).isEmpty,
        'precache只绑定SDK版本',
      );
      File('${f.project}/pubspec.lock').writeAsStringSync('a different app');
      final result = f.execute(f.arguments('import', directory: snapshot));
      check(result.exitCode == 0, '同SDK可在不同项目复用：${result.stderr}');
    },
  );

  if (!Platform.isWindows) {
    await test(
      'Pods headers from verified resolved Pub roots materialize safely',
      (f) async {
        f.kind = 'pods';
        f.platform = 'ios';
        f.version = 'CocoaPods 1.16.2';
        final plugin = Directory('${f.root}/Pub 插件 root')..createSync();
        File('${plugin.path}/pubspec.yaml')
            .writeAsStringSync('name: test_plugin\nversion: 1.2.3\n');
        File('${plugin.path}/ios/Classes/Plugin.h').createSync(recursive: true);
        File('${plugin.path}/ios/Classes/Plugin.h')
            .writeAsStringSync('verified plugin header');
        Directory('${f.project}/.dart_tool').createSync();
        final config = File('${f.project}/.dart_tool/package_config.json')
          ..writeAsStringSync(
            jsonEncode({
              'configVersion': 2,
              'packages': [
                {
                  'name': 'fixture',
                  'rootUri': Directory(f.project).uri.toString(),
                },
                {'name': 'test_plugin', 'rootUri': plugin.uri.toString()},
              ],
            }),
          );
        Directory('${f.source}/Headers/Public/test_plugin')
            .createSync(recursive: true);
        Link('${f.source}/Headers/Public/test_plugin/Plugin.h')
            .createSync('${plugin.path}/ios/Classes/Plugin.h');
        final snapshot = f.export();
        final payload = '$snapshot/payload/Headers/Public/test_plugin/Plugin.h';
        check(
          FileSystemEntity.typeSync(payload, followLinks: false) ==
              FileSystemEntityType.file,
          '解析插件头链接物化为普通文件',
        );
        check(
          File(payload).readAsStringSync() == 'verified plugin header',
          '物化正确插件内容',
        );
        check(
          !jsonEncode(f.manifest(snapshot)).contains(plugin.path),
          '清单不保存包根绝对路径',
        );
        config.deleteSync();
        final result = f.execute(f.arguments('import', directory: snapshot));
        check(
          result.exitCode == 0,
          '导入只校验锁签名，不绑定旧机器package_config绝对路径：${result.stderr}',
        );
        check(
          File('${f.target}/Headers/Public/test_plugin/Plugin.h')
                  .readAsStringSync() ==
              'verified plugin header',
          '导入真实头文件',
        );
      },
    );

    await test(
      'Pods rejects forged package roots, mismatched names and undeclared links',
      (f) async {
        f.kind = 'pods';
        f.platform = 'ios';
        f.version = 'CocoaPods 1.16.2';
        final plugin = Directory('${f.root}/plugin')..createSync();
        final spec = File('${plugin.path}/pubspec.yaml')
          ..writeAsStringSync('name: another_plugin\n');
        File('${plugin.path}/Plugin.h').writeAsStringSync('header');
        Link('${f.source}/Plugin.h').createSync('${plugin.path}/Plugin.h');
        Directory('${f.project}/.dart_tool').createSync();
        final config = File('${f.project}/.dart_tool/package_config.json');
        void setRoot(Uri uri, {String name = 'test_plugin'}) =>
            config.writeAsStringSync(
              jsonEncode({
                'configVersion': 2,
                'packages': [
                  {'name': name, 'rootUri': uri.toString()},
                ],
              }),
            );
        setRoot(plugin.uri);
        f.reject(f.arguments('export'), 'package_config包名与真实pubspec不符');
        final home = Platform.environment['HOME'];
        if (home != null) {
          setRoot(Directory(home).uri);
          f.reject(f.arguments('export'), '伪造用户目录不能进入包根白名单');
        }
        setRoot(Directory(f.root).uri);
        f.reject(f.arguments('export'), '工程祖先不能成为包根');
        spec.writeAsStringSync('name: test_plugin\n');
        config.writeAsStringSync('{"configVersion":2,"packages":[]}');
        f.reject(f.arguments('export'), '未解析外部包不获授权');
        setRoot(plugin.uri);
        Link('${f.source}/Plugin.h').deleteSync();
        final outside = File('${f.root}/outside-secret')
          ..writeAsStringSync('secret');
        Link('${plugin.path}/Plugin.h.link').createSync(outside.path);
        Link('${f.source}/Plugin.h').createSync('${plugin.path}/Plugin.h.link');
        f.reject(f.arguments('export'), '解析包中的二次链接也不能越过已确认包根');
        check(Directory(f.output).listSync().isEmpty, '所有未授权外链不发布快照');
      },
    );

    await test(
      'Pub-root allowance is Pods-only and never trusts a linked configuration',
      (f) async {
        final plugin = Directory('${f.root}/plugin')..createSync();
        File('${plugin.path}/pubspec.yaml')
            .writeAsStringSync('name: test_plugin\n');
        File('${plugin.path}/Plugin.h').writeAsStringSync('header');
        Link('${f.source}/Plugin.h').createSync('${plugin.path}/Plugin.h');
        Directory('${f.project}/.dart_tool').createSync();
        final config = File('${f.project}/.dart_tool/package_config.json')
          ..writeAsStringSync(
            jsonEncode({
              'configVersion': 2,
              'packages': [
                {'name': 'test_plugin', 'rootUri': plugin.uri.toString()},
              ],
            }),
          );
        f.kind = 'native';
        f.reject(f.arguments('export'), 'native层不继承Pods外链白名单');
        f.kind = 'pods';
        f.platform = 'ios';
        config.deleteSync();
        final externalConfig = File('${f.root}/external-config')
          ..writeAsStringSync('{"configVersion":2,"packages":[]}');
        Link(config.path).createSync(externalConfig.path);
        f.reject(f.arguments('export'), '不读取链接出去的package_config');
        check(Directory(f.output).listSync().isEmpty, '无半套快照');
      },
    );

    await test(
      'internal links materialize; executable bits restore without execution',
      (f) async {
        File('${f.source}/run-me')
            .writeAsStringSync('#!/bin/sh\ntouch INJECTED\n');
        Process.runSync('/bin/chmod', ['755', '${f.source}/run-me']);
        Link('${f.source}/alias').createSync('a.bin');
        final snapshot = f.export();
        check(
          FileSystemEntity.typeSync(
                '$snapshot/payload/alias',
                followLinks: false,
              ) ==
              FileSystemEntityType.file,
          '内部链接物化',
        );
        final result = f.execute(f.arguments('import', directory: snapshot));
        check(result.exitCode == 0, '链接物化导入：${result.stderr}');
        check(
          (File('${f.target}/run-me').statSync().mode & 0x49) != 0,
          '恢复普通执行位',
        );
        check(
          !File('${f.project}/INJECTED').existsSync() &&
              !File('${f.target}/INJECTED').existsSync(),
          '不运行归档脚本',
        );
      },
    );

    await test(
      'outside, dangling and circular source links abort unpublished export',
      (f) async {
        final outside = File('${f.root}/outside')..writeAsStringSync('private');
        final link = Link('${f.source}/external')..createSync(outside.path);
        f.reject(f.arguments('export'), '包外链接');
        check(Directory(f.output).listSync().isEmpty, '包外链接不发布');
        link.deleteSync();
        link.createSync('${f.root}/missing');
        f.reject(f.arguments('export'), '失效链接');
        link.deleteSync();
        link.createSync(f.source);
        f.reject(f.arguments('export'), '循环目录链接');
        check(Directory(f.output).listSync().isEmpty, '坏链接不留下半套快照');
      },
    );

    await test('archive and destination symlinks are rejected before writing', (
      f,
    ) async {
      final snapshot = f.export();
      File('$snapshot/payload/a.bin').deleteSync();
      Link('$snapshot/payload/a.bin').createSync('${f.source}/a.bin');
      f.reject(f.arguments('import', directory: snapshot), '归档payload链接');
      check(!Directory(f.target).existsSync(), '归档链接零写入');
      Link('$snapshot/payload/a.bin').deleteSync();
      File('$snapshot/payload/a.bin').writeAsStringSync('abc');
      Directory(f.target).createSync();
      Link('${f.target}/a.bin').createSync('${f.source}/a.bin');
      f.reject(f.arguments('import', directory: snapshot), '目标文件链接');
      check(File('${f.source}/a.bin').readAsStringSync() == 'abc', '外部目标保留');
    });
  }

  await test('empty source, missing version and overlapping roots fail', (
    f,
  ) async {
    File('${f.source}/a.bin').deleteSync();
    f.reject(f.arguments('export'), '空快照');
    f.version = '';
    f.reject(f.arguments('export'), '缺失真实版本');
    f.version = 'Tool 1.0';
    f.reject(f.arguments('export', directory: f.source), '快照落在来源内');
    check(Directory(f.output).listSync().isEmpty, '错误不发布');
  });

  await test('mutation during import rolls back only newly created files', (
    f,
  ) async {
    File('${f.source}/a.bin')
        .writeAsBytesSync(List<int>.filled(8 * 1024 * 1024, 23));
    File('${f.source}/b.bin').writeAsStringSync('later source');
    final snapshot = f.export();
    Directory(f.target).createSync();
    File('${f.target}/keep').writeAsStringSync('existing user file');
    final process = await Process.start(Platform.resolvedExecutable, [
      engine,
      ...f.arguments('import', directory: snapshot),
    ]);
    final out = process.stdout.transform(utf8.decoder).join();
    final err = process.stderr.transform(utf8.decoder).join();
    var observed = false;
    for (var attempt = 0; attempt < 10000; attempt++) {
      if (File('${f.target}/a.bin').existsSync()) {
        observed = true;
        File('$snapshot/payload/b.bin').deleteSync();
        break;
      }
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    final code = await process.exitCode.timeout(const Duration(seconds: 30));
    await out;
    final error = await err;
    check(observed, '已观察到本次首个新建文件');
    check(code != 0, '源变化应失败：$error');
    check(
      !File('${f.target}/a.bin').existsSync() &&
          !File('${f.target}/b.bin').existsSync(),
      '仅撤销本次新建文件',
    );
    check(
      File('${f.target}/keep').readAsStringSync() == 'existing user file',
      '保留已有文件',
    );
  });
  stdout.writeln('$completed cases, $assertions assertions passed.');
}
