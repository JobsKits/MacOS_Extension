// Created by Jobs on 2026年10月28日，星期三。
// 隔离测试真实导出 → 导入、配置保留以及快照识别拒绝路径，不运行 pub get。
import 'dart:convert';
import 'dart:io';

import '../Scripts/Tools/ExtractFlutterDependencies.dart' as extraction;
import '../Scripts/Tools/ImportFlutterDependencies.dart' as importing;

void expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

// 同一套回归可读取源码或当前 App 资源目录，不复制改写被测引擎。
Uri toolFile(String name) {
  final configured = Platform.environment['JOBS_TEST_TOOLS_DIR'];
  return configured == null
      ? File.fromUri(Platform.script).parent.parent.uri
            .resolve('Scripts/Tools/$name')
      : Directory(configured).absolute.uri.resolve(name);
}

class Fixture {
  Fixture(this.root);
  final Directory root;
  Directory get target => Directory('${root.path}/目标 Flutter 项目');
  Directory get source => Directory('${root.path}/导出源工程');
  late Directory snapshot;
  File get manifest => File('${snapshot.path}/manifest.json');
  File get overrides => File('${target.path}/pubspec_overrides.yaml');
  static const pubspec = '''name: demo_project
dependencies:
  flutter:
    sdk: flutter
  alpha: ^1.0.0
''';

  static Future<Fixture> create() async {
    final fixture = Fixture(
      Directory.systemTemp.createTempSync('JobsImportTest-'),
    );
    fixture.source.createSync();
    fixture.target.createSync();
    File('${fixture.source.path}/pubspec.yaml').writeAsStringSync(pubspec);
    File('${fixture.target.path}/pubspec.yaml').writeAsStringSync(pubspec);
    File('${fixture.target.path}/pubspec.lock').writeAsStringSync('# 原锁文件不变\n');
    final packageRoots = <String, String>{};
    for (final name in ['alpha', 'beta', 'flutter']) {
      final package = Directory('${fixture.root.path}/本地缓存/$name')
        ..createSync(recursive: true);
      packageRoots[name] = package.uri.toString();
      final manifest = name == 'alpha'
          ? 'name: alpha\nversion: 1.0.0\ndependencies:\n  beta: ^1.0.0\n'
          : 'name: $name\nversion: 1.0.0\n';
      File('${package.path}/pubspec.yaml').writeAsStringSync(manifest);
      Directory('${package.path}/lib').createSync();
      File('${package.path}/lib/$name.dart')
          .writeAsStringSync('// $name 原始源码\n');
      File('${package.path}/LICENSE')
          .writeAsStringSync('original $name license\n');
    }
    final lock = StringBuffer('packages:\n');
    for (final name in ['alpha', 'beta', 'flutter']) {
      lock.write(
        '  $name:\n    version: "1.0.0"\n    source: ${name == 'flutter' ? 'sdk' : 'hosted'}\n',
      );
    }
    File('${fixture.source.path}/pubspec.lock').writeAsStringSync('$lock');
    Directory('${fixture.source.path}/.dart_tool').createSync();
    File(
      '${fixture.source.path}/.dart_tool/package_config.json',
    ).writeAsStringSync(
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {'name': 'demo_project', 'rootUri': fixture.source.uri.toString()},
          for (final entry in packageRoots.entries)
            {'name': entry.key, 'rootUri': entry.value},
        ],
      }),
    );
    final engine = toolFile('ExtractFlutterDependencies.dart');
    final output = '${fixture.root.path}/输出';
    final result = await Process.run(Platform.resolvedExecutable, [
      File.fromUri(engine).path,
      '--project',
      fixture.source.path,
      '--destination',
      output,
    ]);
    expect(result.exitCode == 0, '真实导出准备失败：${result.stdout}\n${result.stderr}');
    fixture.snapshot = Directory(output)
        .listSync()
        .whereType<Directory>()
        .single;
    return fixture;
  }

  void editManifest(void Function(Map<String, dynamic>) change) {
    final data =
        jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
    change(data);
    manifest.writeAsStringSync(jsonEncode(data));
  }

  // 使用真实 exporter 归档带嵌套 Git 覆盖的本地解析证据，不连接 Git 远端。
  Future<void> reexportWithGitOverride(String pubspec) async {
    File('${source.path}/pubspec.yaml').writeAsStringSync(pubspec);
    final lock = File('${source.path}/pubspec.lock');
    lock.writeAsStringSync(
      lock.readAsStringSync().replaceFirst('source: hosted', 'source: git'),
    );
    File('${source.path}/.dart_tool/package_config.json')
        .setLastModifiedSync(DateTime.now().add(const Duration(seconds: 1)));
    final destination = '${root.path}/嵌套 Git 覆盖归档';
    final result = await Process.run(Platform.resolvedExecutable, [
      File.fromUri(toolFile('ExtractFlutterDependencies.dart')).path,
      '--project',
      source.path,
      '--destination',
      destination,
    ]);
    expect(
      result.exitCode == 0,
      '嵌套 Git 覆盖导出失败：${result.stdout}\n${result.stderr}',
    );
    snapshot = Directory(destination).listSync().whereType<Directory>().single;
  }

  Future<ProcessResult> run({bool validateOnly = false}) {
    final engine = toolFile('ImportFlutterDependencies.dart');
    return Process.run(Platform.resolvedExecutable, [
      File.fromUri(engine).path,
      '--project',
      target.path,
      '--source',
      snapshot.path,
      if (validateOnly) '--validate-only',
    ]);
  }

  Map<String, String> targetState() {
    return {
      for (final file
          in target
              .listSync(recursive: true, followLinks: false)
              .whereType<File>())
        file.path: base64Encode(file.readAsBytesSync()),
    };
  }

  Future<void> reject() async {
    final before = targetState();
    final result = await run();
    expect(result.exitCode != 0, '异常快照必须失败：${result.stdout}');
    expect(jsonEncode(before) == jsonEncode(targetState()), '拒绝后目标文件被修改');
    expect(!Directory('${target.path}/vendor').existsSync(), '拒绝后创建了 vendor');
  }
}

Future<void> main() async {
  const gitOverride = '''dependency_overrides:
  alpha:
    git:
      url: https://example.invalid/team/packages.git
      ref: revision-a
      path: packages/alpha
''';
  final cases = <String, Future<void> Function(Fixture)>{
    '真实导出快照可原样导入并启用全部本地依赖': (f) async {
      final original = f.targetState();
      final sourceBefore = File(
        '${f.snapshot.path}/packages/alpha/lib/alpha.dart',
      ).readAsStringSync();
      final result = await f.run();
      expect(result.exitCode == 0, '${result.stdout}\n${result.stderr}');
      final overrides = extraction.section(
        f.overrides.readAsStringSync(),
        'dependency_overrides',
      );
      expect(
        overrides.keys.toSet().containsAll(['alpha', 'beta']),
        '缺少直接或间接覆盖',
      );
      for (final name in ['alpha', 'beta']) {
        final path = extraction.scalar(
          extraction.flowMapping(overrides[name]!)['path']!,
        );
        expect(
          File('${f.target.path}/$path/pubspec.yaml').existsSync(),
          '本地覆盖路径错误',
        );
        expect(
          File('${f.target.path}/$path/LICENSE').readAsStringSync() ==
              'original $name license\n',
          '许可证被改写',
        );
        expect(
          File('${f.target.path}/$path/lib/$name.dart').readAsStringSync() ==
              '// $name 原始源码\n',
          '第三方源码被改写',
        );
      }
      for (final entry in original.entries) {
        expect(
          base64Encode(File(entry.key).readAsBytesSync()) == entry.value,
          '原 pubspec / lock 被改写',
        );
      }
      expect(
        File('${f.snapshot.path}/packages/alpha/lib/alpha.dart')
                .readAsStringSync() ==
            sourceBefore,
        '原快照被改写',
      );
    },
    'validate-only 只读且没有 vendor / 配置 / 备份': (f) async {
      final before = f.targetState();
      final result = await f.run(validateOnly: true);
      expect(result.exitCode == 0, '${result.stderr}');
      expect(jsonEncode(before) == jsonEncode(f.targetState()), '预检改写了目标');
      expect(!Directory('${f.target.path}/vendor').existsSync(), '预检新建了目录');
    },
    if (!Platform.isWindows)
      '真实带告警导出在导入预检显示数量且保留原清单字节': (f) async {
        Link('${f.root.path}/本地缓存/alpha/lib/skipped.dart')
            .createSync('not-present.dart');
        final destination = '${f.root.path}/带告警输出';
        final exported = await Process.run(Platform.resolvedExecutable, [
          File.fromUri(toolFile('ExtractFlutterDependencies.dart')).path,
          '--project',
          f.source.path,
          '--destination',
          destination,
        ]);
        expect(
          exported.exitCode == 0,
          '带告警导出失败：${exported.stdout}\n${exported.stderr}',
        );
        f.snapshot = Directory(destination)
            .listSync()
            .whereType<Directory>()
            .single;
        final before = f.manifest.readAsBytesSync();
        final manifest = jsonDecode(utf8.decode(before)) as Map;
        expect((manifest['warnings'] as List).length == 1, '真实导出应记录一条告警');
        final preflight = await f.run(validateOnly: true);
        expect(
          preflight.exitCode == 0 &&
              preflight.stdout.toString().contains('1 条提取告警') &&
              preflight.stdout.toString().contains(f.manifest.path),
          '预检未明确显示告警数量及原清单位置',
        );
        final result = await f.run();
        expect(result.exitCode == 0, '带告警快照导入失败：${result.stderr}');
        final run = Directory('${f.target.path}/vendor/flutter_dependencies')
            .listSync()
            .whereType<Directory>()
            .single;
        expect(
          base64Encode(
                File('${run.path}/source-manifest.json').readAsBytesSync(),
              ) ==
              base64Encode(before),
          '导入没有原字节保留带告警源清单',
        );
        expect(
          base64Encode(f.manifest.readAsBytesSync()) == base64Encode(before),
          '导入改写了源清单',
        );
      },
    '已有覆盖的正文 CRLF BOM 注释与精确备份保留': (f) async {
      const original =
          '\uFEFF# 现有配置\r\ndependency_overrides:\r\n  another: ^2.0.0 # 保留\r\nresolution: null\r\n';
      f.overrides.writeAsStringSync(original);
      final result = await f.run();
      expect(result.exitCode == 0, '${result.stderr}');
      final text = f.overrides.readAsStringSync();
      expect(
        text.startsWith(
              '# 现有配置\r\ndependency_overrides:\r\n  another: ^2.0.0 # 保留\r\n',
            ) &&
            f.overrides.readAsBytesSync().take(3).join(',') == '239,187,191',
        '已有覆盖正文被重写',
      );
      expect(text.endsWith('resolution: null\r\n'), '非依赖键丢失');
      final backup = Directory('${f.target.path}/vendor')
          .listSync(recursive: true)
          .whereType<File>()
          .singleWhere((file) => file.path.endsWith('.before-import'));
      expect(
        base64Encode(backup.readAsBytesSync()) ==
            base64Encode(utf8.encode(original)),
        '备份没有保留逐字原文',
      );
      expect(
        extraction.section(text, 'dependency_overrides').containsKey('alpha'),
        '新覆盖未正确合并',
      );
    },
    '行内 flow 覆盖保留既有值': (f) async {
      f.overrides.writeAsStringSync(
        'dependency_overrides: {another: ^2.0.0} # 原注释\n',
      );
      final result = await f.run();
      expect(result.exitCode == 0, '${result.stderr}');
      final text = f.overrides.readAsStringSync();
      final values = extraction.section(text, 'dependency_overrides');
      expect(
        values['another'] == '^2.0.0' && values.containsKey('alpha'),
        '行内映射合并错误',
      );
      expect(text.endsWith(' # 原注释\n'), '原注释丢失');
    },
    '空 flow 覆盖与注释可合并': (f) async {
      f.overrides.writeAsStringSync(
        'dependency_overrides: {} # 原注释\nresolution: null\n',
      );
      final result = await f.run();
      expect(result.exitCode == 0, '${result.stderr}');
      expect(
        extraction
            .section(f.overrides.readAsStringSync(), 'dependency_overrides')
            .containsKey('beta'),
        '空 flow 合并错误',
      );
    },
    '四空格覆盖缩进保持一致': (f) async {
      f.overrides.writeAsStringSync(
        'dependency_overrides:\n    another: ^2.0.0\nresolution: null\n',
      );
      final result = await f.run();
      expect(result.exitCode == 0, '${result.stderr}');
      final text = f.overrides.readAsStringSync();
      expect(text.contains('\n    alpha:\n      path:'), '插入缩进与已有映射不一致');
      final mapping = extraction.section(text, 'dependency_overrides');
      expect(
        mapping.containsKey('another') && mapping.containsKey('alpha'),
        '原覆盖或新增覆盖丢失',
      );
    },
    'YAML 文档结束标记之前加入新覆盖': (f) async {
      f.overrides.writeAsStringSync('---\nresolution: null\n...\n');
      final result = await f.run();
      expect(result.exitCode == 0, '${result.stderr}');
      final text = f.overrides.readAsStringSync();
      expect(
        text.startsWith('---\nresolution: null\n') && text.endsWith('...\n'),
        '文档边界或原文丢失',
      );
      expect(
        text.indexOf('dependency_overrides:') < text.indexOf('...'),
        '覆盖写入文档之外',
      );
    },
    '多 YAML 文档在预检拒绝且不写入': (f) async {
      f.overrides.writeAsStringSync(
        '---\nresolution: null\n---\nother: null\n',
      );
      final preflight = await f.run(validateOnly: true);
      expect(preflight.exitCode != 0, '多文档预检不应通过');
      await f.reject();
    },
    '含空格的空 flow 覆盖可合并': (f) async {
      f.overrides.writeAsStringSync('dependency_overrides: { } # 注释内含 }\n');
      final result = await f.run();
      expect(result.exitCode == 0, '${result.stderr}');
      final text = f.overrides.readAsStringSync();
      expect(
        extraction.section(text, 'dependency_overrides').containsKey('alpha'),
        '空 flow 变成无效映射',
      );
      expect(text.endsWith('# 注释内含 }\n'), '错误修改注释内的大括号');
    },
    '预检发现元数据变化则实际执行停止且不创建目录': (f) async {
      final plan = importing.validate(f.target.path, f.snapshot.path);
      File('${f.target.path}/pubspec.yaml')
          .writeAsStringSync('${Fixture.pubspec}# 并发编辑\n');
      var rejected = false;
      try {
        importing.execute(plan);
      } catch (_) {
        rejected = true;
      }
      expect(rejected, '并发编辑未被拦截');
      expect(
        !Directory('${f.target.path}/vendor').existsSync() &&
            !f.overrides.existsSync(),
        '复检失败后写入了目录或配置',
      );
    },
    '既有同名覆盖拒绝且不写入': (f) async {
      f.overrides.writeAsStringSync('dependency_overrides:\n  alpha: ^9.0.0\n');
      await f.reject();
    },
    'pubspec.yaml 内同名覆盖拒绝': (f) async {
      File('${f.target.path}/pubspec.yaml').writeAsStringSync(
        '${Fixture.pubspec}dependency_overrides:\n  beta: ^2.0.0\n',
      );
      await f.reject();
    },
    '快照原文一致的嵌套 Git 覆盖可恢复且原声明和锁文件不改': (f) async {
      final pubspec = '${Fixture.pubspec}$gitOverride';
      await f.reexportWithGitOverride(pubspec);
      File('${f.target.path}/pubspec.yaml').writeAsStringSync(pubspec);
      final before = f.targetState();
      final preflight = await f.run(validateOnly: true);
      expect(
        preflight.exitCode == 0 &&
            preflight.stdout.toString().contains('恢复 1 个'),
        '应预览同源覆盖恢复：${preflight.stdout}\n${preflight.stderr}',
      );
      final result = await f.run();
      expect(result.exitCode == 0, '同源 Git 覆盖恢复失败：${result.stderr}');
      final after = f.targetState();
      for (final entry in before.entries) {
        expect(after[entry.key] == entry.value, '恢复覆盖改写了原声明或锁文件');
      }
      final run = Directory('${f.target.path}/vendor/flutter_dependencies')
          .listSync()
          .whereType<Directory>()
          .single;
      final receipt =
          jsonDecode(File('${run.path}/import.json').readAsStringSync()) as Map;
      expect(
        (receipt['restoredPubspecOverrides'] as List).single == 'alpha',
        '恢复记录没有声明原覆盖',
      );
      expect(
        extraction
            .section(f.overrides.readAsStringSync(), 'dependency_overrides')
            .containsKey('alpha'),
        '没有为已确认的原覆盖配置本地路径',
      );
    },
    '嵌套 Git 覆盖仅 ref 不同也必须拒绝': (f) async {
      final source = '${Fixture.pubspec}$gitOverride';
      await f.reexportWithGitOverride(source);
      File('${f.target.path}/pubspec.yaml').writeAsStringSync(
        source.replaceFirst('ref: revision-a', 'ref: revision-b'),
      );
      // 证明旧扁平解析会漏掉差异，新门禁必须依完整原文拒绝。
      expect(
        importing.declarationKey(
              extraction.section(source, 'dependency_overrides')['alpha']!,
            ) ==
            importing.declarationKey(
              extraction.section(
                File('${f.target.path}/pubspec.yaml').readAsStringSync(),
                'dependency_overrides',
              )['alpha']!,
            ),
        '夹具没有覆盖嵌套字段丢失风险',
      );
      await f.reject();
    },
    '原 pubspec 覆盖同源但独立覆盖文件同名仍严格拒绝': (f) async {
      final source = '${Fixture.pubspec}$gitOverride';
      await f.reexportWithGitOverride(source);
      File('${f.target.path}/pubspec.yaml').writeAsStringSync(source);
      f.overrides.writeAsStringSync(gitOverride);
      await f.reject();
    },
    '普通目录缺少 manifest 不能导入': (f) async {
      f.manifest.deleteSync();
      await f.reject();
    },
    '失败快照拒绝': (f) async {
      f.editManifest((m) => m['status'] = 'incomplete');
      await f.reject();
    },
    '完整快照位于名称含 incomplete 的父目录仍可预检': (f) async {
      final parent = Directory('${f.root.path}/archives-incomplete-backups')
        ..createSync();
      f.snapshot = f.snapshot.renameSync('${parent.path}/完整快照');
      final result = await f.run(validateOnly: true);
      expect(result.exitCode == 0, '不应根据无关祖先目录名拒绝：${result.stderr}');
    },
    'exporter 未完成目录即使已有完整 manifest 也拒绝': (f) async {
      final parent = f.snapshot.parent;
      f.snapshot = f.snapshot.renameSync(
        '${parent.path}/.FlutterDependencies-demo_project-incomplete-123',
      );
      await f.reject();
    },
    '未知格式拒绝': (f) async {
      f.editManifest((m) => m['formatVersion'] = 2);
      await f.reject();
    },
    'copiedPath 越界拒绝': (f) async {
      f.editManifest(
        (m) => (m['packages'] as List).first['copiedPath'] = '../outside',
      );
      await f.reject();
    },
    '非法包名拒绝': (f) async {
      f.editManifest(
        (m) => (m['packages'] as List).first['name'] = '../outside',
      );
      await f.reject();
    },
    '重复包记录拒绝': (f) async {
      f.editManifest(
        (m) => (m['packages'] as List).add((m['packages'] as List).first),
      );
      await f.reject();
    },
    '包版本与清单不符拒绝': (f) async {
      File('${f.snapshot.path}/packages/alpha/pubspec.yaml')
          .writeAsStringSync('name: alpha\nversion: 2.0.0\n');
      await f.reject();
    },
    '锁文件版本与清单不符拒绝': (f) async {
      final lock = File('${f.snapshot.path}/pubspec.lock');
      lock.writeAsStringSync(
        lock.readAsStringSync().replaceFirst('1.0.0', '9.0.0'),
      );
      await f.reject();
    },
    '缺失文件拒绝': (f) async {
      File('${f.snapshot.path}/packages/alpha/LICENSE').deleteSync();
      await f.reject();
    },
    '额外包目录拒绝': (f) async {
      Directory('${f.snapshot.path}/packages/unlisted').createSync();
      await f.reject();
    },
    '缺失传递依赖拒绝': (f) async {
      f.editManifest(
        (m) => (m['packages'] as List).removeWhere((p) => p['name'] == 'beta'),
      );
      Directory('${f.snapshot.path}/packages/beta').deleteSync(recursive: true);
      await f.reject();
    },
    '不同直接依赖声明拒绝': (f) async {
      File('${f.target.path}/pubspec.yaml')
          .writeAsStringSync(Fixture.pubspec.replaceFirst('^1.0.0', '^9.0.0'));
      await f.reject();
    },
    '不相关项目直接依赖拒绝': (f) async {
      File(
        '${f.target.path}/pubspec.yaml',
      ).writeAsStringSync(Fixture.pubspec.replaceFirst('alpha', 'unrelated'));
      await f.reject();
    },
    '没有第三方直接依赖不伪装导入成功': (f) async {
      File('${f.target.path}/pubspec.yaml').writeAsStringSync(
        Fixture.pubspec.replaceFirst('  alpha: ^1.0.0\n', ''),
      );
      await f.reject();
    },
    'workspace 目标拒绝': (f) async {
      File('${f.target.path}/pubspec.yaml')
          .writeAsStringSync('${Fixture.pubspec}resolution: workspace\n');
      await f.reject();
    },
    '快照项目名证据不符拒绝': (f) async {
      f.editManifest((m) => m['projectName'] = 'another_project');
      await f.reject();
    },
    if (!Platform.isWindows)
      '包内链接不跟随': (f) async {
        final package = '${f.snapshot.path}/packages/alpha';
        File('$package/LICENSE').deleteSync();
        Link('$package/LICENSE').createSync('${f.root.path}/outside');
        await f.reject();
      },
    if (!Platform.isWindows)
      '配置软链接拒绝': (f) async {
        final outside = File('${f.root.path}/outside.yaml')
          ..writeAsStringSync('# 不改\n');
        Link(f.overrides.path).createSync(outside.path);
        await f.reject();
        expect(outside.readAsStringSync() == '# 不改\n', '链接外目标被改写');
      },
    if (!Platform.isWindows)
      'vendor 软链接拒绝': (f) async {
        Link('${f.target.path}/vendor').createSync(f.root.path);
        final result = await f.run();
        expect(result.exitCode != 0, 'vendor 链接绕过了校验');
        expect(!f.overrides.existsSync(), '拒绝后改写配置');
      },
    '再次导入拒绝覆盖已有结果': (f) async {
      final first = await f.run();
      expect(first.exitCode == 0, '${first.stderr}');
      final before = f.targetState();
      final second = await f.run();
      expect(second.exitCode != 0, '重复导入不应覆盖已有配置');
      expect(jsonEncode(before) == jsonEncode(f.targetState()), '重复导入改写了文件');
    },
  };
  var passed = 0;
  for (final entry in cases.entries) {
    final fixture = await Fixture.create();
    try {
      await entry.value(fixture);
      stdout.writeln('PASS ${entry.key}');
      passed++;
    } catch (error, stack) {
      stderr.writeln('FAIL ${entry.key}\n$error\n$stack');
    } finally {
      fixture.root.deleteSync(recursive: true);
    }
  }
  stdout.writeln('$passed / ${cases.length} 项通过');
  if (passed != cases.length) exitCode = 1;

  // 直接验证空值格式，保持原有非覆盖正文。
  for (final value in ['{}', 'null', '~', '']) {
    final text = importing.mergeOverrides(
      'dependency_overrides: $value\nresolution: null\n',
      {'alpha': 'vendor/alpha'},
    );
    expect(
      extraction.section(text, 'dependency_overrides').containsKey('alpha'),
      '$value 合并结果不合法',
    );
    expect(text.endsWith('resolution: null\n'), '$value 丢失非依赖正文');
  }
}
