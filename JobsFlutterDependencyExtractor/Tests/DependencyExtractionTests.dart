//
// DependencyExtractionTests.dart
// JobsFlutterDependencyExtractor
//
// Created by Jobs on 2026年10月19日，星期一.
//

import 'dart:convert';
import 'dart:io';

/// 不依赖 package:test，也不运行 pub get；所有工程与缓存都在临时目录中。
Future<void> main(List<String> arguments) async {
  final script = File.fromUri(Platform.script).absolute;
  final engine = arguments.isEmpty
      ? File.fromUri(
          script.parent.parent.uri.resolve(
            'Scripts/ExtractFlutterDependencies.dart',
          ),
        )
      : File(arguments.first).absolute;
  if (!engine.existsSync()) {
    stderr.writeln('找不到提取引擎：${engine.path}');
    exitCode = 2;
    return;
  }

  final cases = <String, Future<void> Function(_Fixture)>{
    '完整提取 hosted / git / path、直接 / 开发 / 传递依赖与中文空格路径': (fixture) =>
        _fullExtraction(fixture, engine),
    '没有第三方依赖的 Flutter 工程也能完成': (fixture) => _emptyExtraction(fixture, engine),
    '重复执行生成独立目录，不覆盖先前结果': (fixture) => _repeatExtraction(fixture, engine),
    '缺少 package_config.json 时失败': (fixture) =>
        _missingMetadata(fixture, engine, 'config'),
    '缺少 pubspec.lock 时失败': (fixture) =>
        _missingMetadata(fixture, engine, 'lock'),
    '缺少 pubspec.yaml 时失败': (fixture) =>
        _missingMetadata(fixture, engine, 'pubspec'),
    '非 Flutter 项目不能伪装为成功导出': (fixture) => _notFlutter(fixture, engine),
    '锁文件中存在但配置中缺失的依赖必须报告失败': (fixture) =>
        _missingConfigPackage(fixture, engine),
    '配置中存在但锁文件中缺失的依赖必须报告失败': (fixture) => _missingLockPackage(fixture, engine),
    '缓存中的依赖源目录缺失时失败': (fixture) => _missingSource(fixture, engine),
    '目的地位于依赖源目录中时拒绝复制': (fixture) => _destinationInsideSource(fixture, engine),
    '目的地可与依赖源共用父目录且不改变源': (fixture) =>
        _destinationAncestorOfSource(fixture, engine),
    '恶意依赖名称不能逃逸 packages 目录': (fixture) => _maliciousName(fixture, engine),
    '外部链接与循环链接不会读取源包范围外的数据': (fixture) => _symlinkBoundaries(fixture, engine),
    '内部链接物化为导出文件': (fixture) => _internalSymlink(fixture, engine),
    '锁定版本与实际包版本不符时失败': (fixture) => _versionMismatch(fixture, engine),
    '包根目录的 pubspec 名称不符时失败': (fixture) => _packageNameMismatch(fixture, engine),
    '非本地 rootUri 与重复配置项不能被当作本地依赖': (fixture) => _invalidConfig(fixture, engine),
    '新修改的依赖声明不能复用过期解析结果': (fixture) => _staleConfig(fixture, engine),
    'workspace 仅提取所选成员的依赖闭包': (fixture) =>
        _workspaceExtraction(fixture, engine),
    '缓存与构建目录不会混入第三方源码': (fixture) => _excludedDirectories(fixture, engine),
    'Flutter 平台临时目录中的失效链接不影响源码提取': (fixture) =>
        _flutterGeneratedDirectories(fixture, engine),
    '普通源码中的失效链接跳过且记录明确告警': (fixture) => _brokenSourceSymlink(fixture, engine),
    '别名指向平台生成目录时不能混入构建缓存': (fixture) =>
        _generatedDirectoryAlias(fixture, engine),
    '普通源码文件无法读取仍须失败且保留源件': (fixture) => _unreadableSourceFile(fixture, engine),
    '目的地中的不存在父目录加 .. 按用户路径归一化': (fixture) =>
        _destinationDotDot(fixture, engine),
    'Pub 生成的带引号描述和 Git 修订不影响锁解析': (fixture) =>
        _quotedLockDescription(fixture, engine),
    '项目声明新于解析配置时拒绝陈旧结果': (fixture) => _staleProjectManifest(fixture, engine),
    '包根软链能解析到真实源且保持权限': (fixture) => _linkedPackageRoot(fixture, engine),
    'workspace 必须由祖先 workspace 声明成员关系': (fixture) =>
        _workspaceExtraction(fixture, engine, validWorkspace: false),
    'workspace 不能将未声明的配置包冒充本地成员': (fixture) =>
        _workspaceExtraction(fixture, engine, declareLocalMember: false),
    'workspace 支持行内成员列表与 * / ** / ? glob': (fixture) =>
        _workspaceExtraction(fixture, engine, globWorkspace: true),
    'workspace 支持经嵌套成员声明的成员链': (fixture) =>
        _workspaceExtraction(fixture, engine, nestedWorkspace: true),
    'workspace 根 Flutter 项目仅提取自身 main/dev 闭包': (fixture) =>
        _workspaceRootExtraction(fixture, engine),
    'pubspec_overrides 空 resolution 可使用独立解析': (fixture) =>
        _clearedWorkspaceResolution(fixture, engine),
    '目的地折叠 .. 后出现的软链不能绕过源目录保护': (fixture) =>
        _destinationDotDotSymlink(fixture, engine),
    'macOS 不执行项目伪装的 Dart Shell shim': (fixture) =>
        _rejectProjectDartShim(fixture, engine),
  };

  var passed = 0;
  for (final entry in cases.entries) {
    final fixture = _Fixture.create();
    try {
      await entry.value(fixture);
      stdout.writeln('PASS ${entry.key}');
      passed++;
    } catch (error, stack) {
      stderr.writeln('FAIL ${entry.key}\n$error\n$stack');
    } finally {
      fixture.dispose();
    }
  }
  stdout.writeln('$passed / ${cases.length} 项通过');
  if (passed != cases.length) {
    exitCode = 1;
  }
}

Future<void> _fullExtraction(_Fixture fixture, File engine) async {
  fixture.addPackage('alpha', dependency: 'direct main');
  fixture.addPackage('dev_tool', dependency: 'direct dev', absoluteUri: true);
  fixture.addPackage('git_plugin', source: 'git', absoluteUri: true);
  fixture.addPackage('local_package', source: 'path');
  fixture.writeMetadata();
  final before = fixture.sourceSnapshot();
  final result = await fixture.run(engine);
  _expect(result.code == 0, '应成功提取：$result');
  final output = fixture.onlyCompleteOutput();
  final manifest = _readManifest(output);
  final packages = _manifestPackages(manifest);
  _expect(packages.length == 4, '应该只提取 4 个非 SDK 包：$packages');
  _expect(!packages.containsKey('flutter'), 'Flutter SDK 不能当作第三方包导出');
  _expect(!packages.containsKey('sky_engine'), '引擎 SDK 不能当作第三方包导出');
  _expect(!packages.containsKey('demo_project'), '项目自身不能当作依赖导出');
  for (final package in fixture.packages) {
    final item = packages[package.name];
    _expect(item != null, '缺少依赖 ${package.name}');
    _expect(item!['source'] == package.source, '来源类型错误：$item');
    _expect(item['version'] == package.version, '版本错误：$item');
    _expect(item['dependency'] == package.dependency, '依赖分组错误：$item');
    _expect(item['copiedPath'] is String, 'manifest 缺少 copiedPath：$item');
    final copied = Directory('${output.path}/packages/${package.name}');
    _expect(copied.existsSync(), '缺少 ${copied.path}');
    _expect(
      File('${copied.path}/lib/${package.name}.dart').readAsStringSync() ==
          '// ${package.name} fixture\n',
      '复制文件内容不一致',
    );
    _expect(File('${copied.path}/LICENSE').existsSync(), '应保留第三方包许可证');
    _expect(
      File('${copied.path}/assets/中文 资源.txt').readAsStringSync() ==
          '资源 ${package.name}\n',
      '嵌套中文资源没有完整复制',
    );
  }
  _expect(File('${output.path}/README.md').existsSync(), '导出目录缺少 README.md');
  for (final name in ['pubspec.yaml', 'pubspec.lock']) {
    _expect(
      File('${output.path}/$name').readAsStringSync() ==
          File('${fixture.project.path}/$name').readAsStringSync(),
      '应保留项目原始 $name 供追溯',
    );
  }
  _expect(
    _sameJson(before, fixture.sourceSnapshot()),
    '提取必须保持项目与依赖源的内容、修改时间及文件权限不变',
  );
  if (!Platform.isWindows) {
    final original = File(
      '${fixture.packages.first.directory.path}/tool/run.sh',
    );
    final copied = File('${output.path}/packages/alpha/tool/run.sh');
    _expect(
      (original.statSync().mode & 0x1ff) == (copied.statSync().mode & 0x1ff),
      '应保留可执行脚本的权限',
    );
  }
}

Future<void> _emptyExtraction(_Fixture fixture, File engine) async {
  fixture.writeMetadata();
  final result = await fixture.run(engine);
  _expect(result.code == 0, '没有第三方依赖时也应成功：$result');
  _expect(
    _manifestPackages(_readManifest(fixture.onlyCompleteOutput())).isEmpty,
    'SDK 和主工程不能进入第三方依赖列表',
  );
}

Future<void> _repeatExtraction(_Fixture fixture, File engine) async {
  fixture.addPackage('alpha');
  fixture.writeMetadata();
  final first = await fixture.run(engine);
  _expect(first.code == 0, '首次提取失败：$first');
  final firstOutput = fixture.onlyCompleteOutput();
  final marker = File('${firstOutput.path}/user-marker.txt')
    ..writeAsStringSync('保留');
  final firstManifest = File('${firstOutput.path}/manifest.json')
      .readAsStringSync();
  final second = await fixture.run(engine);
  _expect(second.code == 0, '再次提取失败：$second');
  _expect(fixture.completeOutputs().length == 2, '重复执行必须产生两个不同的完整目录');
  _expect(marker.readAsStringSync() == '保留', '不能覆盖已有导出内容');
  _expect(
    File('${firstOutput.path}/manifest.json').readAsStringSync() ==
        firstManifest,
    '不能改写已有 manifest',
  );
}

Future<void> _missingMetadata(
  _Fixture fixture,
  File engine,
  String which,
) async {
  fixture.addPackage('alpha');
  fixture.writeMetadata();
  final missing = <String, String>{
    'config': '.dart_tool/package_config.json',
    'lock': 'pubspec.lock',
    'pubspec': 'pubspec.yaml',
  }[which]!;
  File('${fixture.project.path}/$missing').deleteSync();
  await _expectFailure(fixture, engine);
}

Future<void> _notFlutter(_Fixture fixture, File engine) async {
  fixture.addPackage('alpha');
  fixture.writeMetadata();
  final manifests = <String>[
    'dependencies:\n  alpha: ^1.2.3\n',
    'dependencies:\n  flutter:\n    nested:\n      sdk: flutter\n'
        '  alpha: ^1.2.3\n',
    'dependencies:\n  flutter: |\n    sdk: flutter\n'
        '  alpha: ^1.2.3\n',
    'description: |\n  dependencies:\n    flutter:\n      sdk: flutter\n'
        'dependencies:\n  alpha: ^1.2.3\n',
  ];
  for (final declaration in manifests) {
    File('${fixture.project.path}/pubspec.yaml').writeAsStringSync(
      'name: demo_project\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\n'
      '$declaration',
    );
    // 本用例验证声明形状，不能被新写入文件的陈旧时间检查提前挡住。
    File('${fixture.project.path}/.dart_tool/package_config.json')
        .setLastModifiedSync(DateTime.now().add(const Duration(seconds: 1)));
    await _expectFailure(fixture, engine);
  }
}

Future<void> _missingConfigPackage(_Fixture fixture, File engine) async {
  fixture.addPackage('alpha');
  fixture.writeMetadata();
  final file = File('${fixture.project.path}/.dart_tool/package_config.json');
  final config = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  (config['packages'] as List).removeWhere(
    (dynamic item) => item['name'] == 'alpha',
  );
  file.writeAsStringSync(jsonEncode(config));
  await _expectFailure(fixture, engine);
}

Future<void> _missingLockPackage(_Fixture fixture, File engine) async {
  fixture.addPackage('alpha');
  fixture.writeMetadata();
  final lock = File('${fixture.project.path}/pubspec.lock');
  lock.writeAsStringSync(fixture.lockContent(includeThirdParty: false));
  await _expectFailure(fixture, engine);
}

Future<void> _missingSource(_Fixture fixture, File engine) async {
  fixture.addPackage('alpha');
  fixture.writeMetadata();
  fixture.packages.first.directory.deleteSync(recursive: true);
  await _expectFailure(fixture, engine);
}

Future<void> _destinationInsideSource(_Fixture fixture, File engine) async {
  fixture.addPackage('alpha');
  fixture.writeMetadata();
  final destination = Directory(
    '${fixture.packages.first.directory.path}/exported',
  );
  await _expectFailure(fixture, engine, destination: destination);
  _expect(
    !destination.existsSync() || destination.listSync().isEmpty,
    '拒绝源目录内的目的地时不应写入依赖源',
  );
}

Future<void> _destinationAncestorOfSource(_Fixture fixture, File engine) async {
  fixture.addPackage('alpha');
  fixture.writeMetadata();
  final before = fixture.sourceSnapshot();
  final result = await fixture.run(engine, destination: fixture.root);
  _expect(result.code == 0, '共同父目录中的独立导出应成功：$result');
  _expect(
    fixture.completeOutputs(destination: fixture.root).length == 1,
    '共同父目录中应生成独立的完整导出',
  );
  _expect(_sameJson(before, fixture.sourceSnapshot()), '共同父目录导出不能改变源');
}

Future<void> _internalSymlink(_Fixture fixture, File engine) async {
  if (Platform.isWindows) return;
  fixture.addPackage('alpha');
  fixture.writeMetadata();
  final package = fixture.packages.first.directory;
  Link('${package.path}/asset-alias').createSync('assets/中文 资源.txt');
  final result = await fixture.run(engine);
  _expect(result.code == 0, '包内文件链接应可物化：$result');
  final output = fixture.onlyCompleteOutput();
  final alias = File('${output.path}/packages/alpha/asset-alias');
  _expect(
    FileSystemEntity.typeSync(alias.path, followLinks: false) ==
        FileSystemEntityType.file,
    '内部链接应成为普通文件，不保留指向原缓存的链接',
  );
  _expect(alias.readAsStringSync() == '资源 alpha\n', '内部链接内容不符');
}

Future<void> _versionMismatch(_Fixture fixture, File engine) async {
  fixture.addPackage('alpha');
  fixture.writeMetadata();
  File('${fixture.packages.first.directory.path}/pubspec.yaml')
      .writeAsStringSync('name: alpha\nversion: 9.9.9\n');
  await _expectFailure(fixture, engine);
}

Future<void> _packageNameMismatch(_Fixture fixture, File engine) async {
  fixture.addPackage('alpha');
  fixture.writeMetadata();
  File('${fixture.packages.first.directory.path}/pubspec.yaml')
      .writeAsStringSync('name: different_package\nversion: 1.2.3\n');
  await _expectFailure(fixture, engine);
}

Future<void> _invalidConfig(_Fixture fixture, File engine) async {
  fixture.addPackage('alpha');
  fixture.writeMetadata();
  final config = File('${fixture.project.path}/.dart_tool/package_config.json');
  final value = jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
  final entries = value['packages'] as List;
  final alpha = entries.singleWhere(
    (dynamic entry) => entry['name'] == 'alpha',
  );
  final originalRoot = alpha['rootUri'];
  alpha['rootUri'] = 'https://example.invalid/alpha';
  config.writeAsStringSync(jsonEncode(value));
  await _expectFailure(fixture, engine);
  alpha['rootUri'] = originalRoot;
  entries.add(Map<String, dynamic>.from(alpha as Map));
  config.writeAsStringSync(jsonEncode(value));
  await _expectFailure(fixture, engine);
}

Future<void> _staleConfig(_Fixture fixture, File engine) async {
  fixture.addPackage('alpha');
  fixture.writeMetadata();
  File('${fixture.project.path}/.dart_tool/package_config.json')
      .setLastModifiedSync(DateTime(2000));
  await _expectFailure(fixture, engine);
}

Future<void> _workspaceExtraction(
  _Fixture fixture,
  File engine, {
  bool validWorkspace = true,
  bool declareLocalMember = true,
  bool globWorkspace = false,
  bool nestedWorkspace = false,
}) async {
  fixture.addPackage('alpha', dependency: 'direct main');
  fixture.addPackage('beta');
  fixture.addPackage('dev_tool', dependency: 'direct dev');
  fixture.addPackage('unrelated');
  final lock = fixture.lockContent();
  fixture.addPackage('local_member', source: 'path', dependency: 'direct main');
  fixture.writeMetadata();
  final localMember = fixture.packages.singleWhere(
    (package) => package.name == 'local_member',
  );
  final localManifest = File('${localMember.directory.path}/pubspec.yaml');
  localManifest.writeAsStringSync(
    '${localManifest.readAsStringSync()}resolution: workspace\n',
  );
  final projectManifest = File('${fixture.project.path}/pubspec.yaml');
  projectManifest.writeAsStringSync(
    '${projectManifest.readAsStringSync()}resolution: workspace\n',
  );
  final alpha = fixture.packages.singleWhere(
    (package) => package.name == 'alpha',
  );
  File('${alpha.directory.path}/pubspec.yaml').writeAsStringSync(
    'name: alpha\nversion: 1.2.3\ndependencies:\n  beta: ^1.2.3\n'
    'dev_dependencies:\n  unrelated: ^1.2.3\n',
  );
  final projectPath = fixture.project.uri.pathSegments
      .where((part) => part.isNotEmpty)
      .last;
  final workspacePaths = <String>[
    validWorkspace ? (globWorkspace ? '工程*' : projectPath) : 'other_member',
    if (declareLocalMember)
      nestedWorkspace
          ? 'dependency cache'
          : globWorkspace
          ? 'dependency cache/**/local_??????'
          : 'dependency cache/path/local_member',
  ];
  final workspaceDeclaration = globWorkspace
      ? 'workspace: ${jsonEncode(workspacePaths)}\n'
      : 'workspace:\n${workspacePaths.map((path) => '  - ${jsonEncode(path)}\n').join()}';
  File('${fixture.root.path}/pubspec.yaml').writeAsStringSync(
    'name: workspace_root\nenvironment:\n  sdk: ">=3.6.0 <4.0.0"\n'
    '$workspaceDeclaration',
  );
  File('${fixture.root.path}/pubspec.lock').writeAsStringSync(lock);
  File('${fixture.project.path}/pubspec.lock').deleteSync();
  final oldConfig = File(
    '${fixture.project.path}/.dart_tool/package_config.json',
  );
  final config =
      jsonDecode(oldConfig.readAsStringSync()) as Map<String, dynamic>;
  for (final dynamic entry in config['packages'] as List) {
    entry['rootUri'] = oldConfig.uri
        .resolve(entry['rootUri'] as String)
        .toString();
  }
  if (nestedWorkspace) {
    final nested = Directory('${fixture.root.path}/dependency cache');
    File('${nested.path}/pubspec.yaml').writeAsStringSync(
      'name: workspace_group\nresolution: workspace\n'
      'environment:\n  sdk: ">=3.6.0 <4.0.0"\n'
      'workspace:\n  - "path/*"\n',
    );
    (config['packages'] as List).add({
      'name': 'workspace_group',
      'rootUri': nested.uri.toString(),
      'packageUri': 'lib/',
      'languageVersion': '3.6',
    });
  }
  Directory('${fixture.project.path}/.dart_tool').deleteSync(recursive: true);
  Directory('${fixture.root.path}/.dart_tool').createSync();
  final sharedConfig = File(
    '${fixture.root.path}/.dart_tool/package_config.json',
  )..writeAsStringSync(jsonEncode(config));
  sharedConfig.setLastModifiedSync(
    DateTime.now().add(const Duration(seconds: 1)),
  );
  final before = fixture.sourceSnapshot();
  final result = await fixture.run(engine);
  if (!validWorkspace || !declareLocalMember) {
    _expect(result.code != 0, '不属于祖先 workspace 的目录不能借用其共享解析文件：$result');
    _expect(fixture.completeOutputs().isEmpty, '不合法的 workspace 不能有完整导出');
    return;
  }
  _expect(result.code == 0, 'workspace 共享解析应成功：$result');
  final packages = _manifestPackages(
    _readManifest(fixture.onlyCompleteOutput()),
  );
  _expect(
    _sameJson(packages.keys.toList()..sort(), [
      'alpha',
      'beta',
      'dev_tool',
      'local_member',
    ]),
    'workspace 应只包含选中项目 main/dev 及传递 main：${packages.keys}',
  );
  _expect(
    packages['local_member']!['source'] == 'workspace',
    '无 lock 记录的成员来源应标明 workspace',
  );
  _expect(
    packages['dev_tool']!['dependency'] == 'direct dev',
    'workspace 应保留开发依赖',
  );
  _expect(_sameJson(before, fixture.sourceSnapshot()), 'workspace 导出不能改变源');
}

Future<void> _workspaceRootExtraction(_Fixture fixture, File engine) async {
  fixture.addPackage('alpha', dependency: 'direct main');
  fixture.addPackage('beta');
  fixture.addPackage('dev_tool', dependency: 'direct dev');
  fixture.addPackage('unrelated');
  fixture.writeMetadata();
  final alpha = fixture.packages.singleWhere(
    (package) => package.name == 'alpha',
  );
  File('${alpha.directory.path}/pubspec.yaml').writeAsStringSync(
    'name: alpha\nversion: 1.2.3\ndependencies:\n  beta: ^1.2.3\n'
    'dev_dependencies:\n  unrelated: ^1.2.3\n',
  );
  final member = Directory('${fixture.project.path}/members/other')
    ..createSync(recursive: true);
  File('${member.path}/pubspec.yaml').writeAsStringSync(
    'name: other_member\nresolution: workspace\n'
    'dependencies:\n  unrelated: ^1.2.3\n',
  );
  final manifest = File('${fixture.project.path}/pubspec.yaml');
  manifest.writeAsStringSync(
    '${manifest.readAsStringSync()}workspace: ["members/*"]\n',
  );
  final configFile = File(
    '${fixture.project.path}/.dart_tool/package_config.json',
  );
  final config =
      jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
  (config['packages'] as List).add({
    'name': 'other_member',
    'rootUri': member.uri.toString(),
    'packageUri': 'lib/',
    'languageVersion': '3.6',
  });
  configFile.writeAsStringSync(jsonEncode(config));
  configFile.setLastModifiedSync(
    DateTime.now().add(const Duration(seconds: 1)),
  );
  final before = fixture.sourceSnapshot();
  final result = await fixture.run(engine);
  _expect(result.code == 0, 'workspace 根 Flutter 项目应成功：$result');
  final packages = _manifestPackages(
    _readManifest(fixture.onlyCompleteOutput()),
  );
  _expect(
    _sameJson(packages.keys.toList()..sort(), ['alpha', 'beta', 'dev_tool']),
    '根项目应排除其它成员和依赖包的 dev 依赖：${packages.keys}',
  );
  _expect(_sameJson(before, fixture.sourceSnapshot()), '根项目导出不能改变源');
}

Future<void> _clearedWorkspaceResolution(_Fixture fixture, File engine) async {
  fixture.addPackage('alpha', dependency: 'direct main');
  fixture.writeMetadata();
  final manifest = File('${fixture.project.path}/pubspec.yaml');
  manifest.writeAsStringSync(
    '${manifest.readAsStringSync()}resolution: workspace\n',
  );
  File('${fixture.project.path}/pubspec_overrides.yaml')
      .writeAsStringSync('resolution:\n');
  File('${fixture.project.path}/.dart_tool/package_config.json')
      .setLastModifiedSync(DateTime.now().add(const Duration(seconds: 1)));
  final result = await fixture.run(engine);
  _expect(result.code == 0, '空 resolution 应使用项目自己的解析结果：$result');
  final packages = _manifestPackages(
    _readManifest(fixture.onlyCompleteOutput()),
  );
  _expect(_sameJson(packages.keys.toList(), ['alpha']), '独立解析不能丢失依赖');
}

Future<void> _excludedDirectories(_Fixture fixture, File engine) async {
  fixture.addPackage('alpha');
  fixture.writeMetadata();
  for (final name in [
    '.git',
    'node_modules',
    'Pods',
    '.dart_tool',
    'build',
    'DerivedData',
  ]) {
    final dir = Directory('${fixture.packages.first.directory.path}/$name')
      ..createSync();
    File('${dir.path}/excluded.txt').writeAsStringSync('generated fixture');
  }
  final result = await fixture.run(engine);
  _expect(result.code == 0, '排除缓存目录后应可提取：$result');
  final output = fixture.onlyCompleteOutput();
  for (final name in [
    '.git',
    'node_modules',
    'Pods',
    '.dart_tool',
    'build',
    'DerivedData',
  ]) {
    _expect(
      !Directory('${output.path}/packages/alpha/$name').existsSync(),
      '不应复制 $name',
    );
  }
}

Future<void> _flutterGeneratedDirectories(_Fixture fixture, File engine) async {
  fixture.addPackage('alpha', source: 'git');
  fixture.writeMetadata();
  final source = fixture.packages.first.directory;
  const generated = [
    'linux/flutter/ephemeral',
    'windows/flutter/ephemeral',
    'macos/Flutter/ephemeral',
    'example/linux/flutter/ephemeral',
    'example/windows/flutter/ephemeral',
    'example/macos/Flutter/ephemeral',
    'nested/example/linux/flutter/ephemeral',
    '.plugin_symlinks',
  ];
  for (final relative in generated) {
    final directory = Directory('${source.path}/$relative')
      ..createSync(recursive: true);
    File('${directory.path}/generated.txt').writeAsStringSync('build output');
    if (!Platform.isWindows) {
      final links = Directory('${directory.path}/.plugin_symlinks')
        ..createSync();
      Link('${links.path}/connectivity_plus').createSync(
        '${fixture.root.path}/missing-developer/.pub-cache/connectivity_plus',
      );
      // 临时目录自身也可能是指向另一台机器的链接，必须在解析前排除。
      if (relative == 'windows/flutter/ephemeral') {
        directory.deleteSync(recursive: true);
        Link(directory.path).createSync('${fixture.root.path}/missing-flutter');
      }
    }
  }
  const retained = [
    'linux/flutter/CMakeLists.txt',
    'windows/flutter/CMakeLists.txt',
    'macos/Flutter/Flutter-Debug.xcconfig',
    'lib/ephemeral/keep.dart',
    'assets/ephemeral/keep.txt',
  ];
  for (final relative in retained) {
    final file = File('${source.path}/$relative');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('source: $relative');
  }
  final before = fixture.sourceSnapshot();
  final result = await fixture.run(engine);
  _expect(result.code == 0, '平台临时目录不应阻止提取：$result');
  final output = fixture.onlyCompleteOutput();
  for (final relative in generated) {
    _expect(
      FileSystemEntity.typeSync(
            '${output.path}/packages/alpha/$relative',
            followLinks: false,
          ) ==
          FileSystemEntityType.notFound,
      '不应导出平台临时目录：$relative',
    );
  }
  for (final relative in retained) {
    _expect(
      File('${output.path}/packages/alpha/$relative').readAsStringSync() ==
          'source: $relative',
      '不能误删平台源码或普通 ephemeral 目录：$relative',
    );
  }
  final manifest = _readManifest(output);
  _expect(
    (manifest['excludedDirectories'] as List).contains('.plugin_symlinks') &&
        (manifest['excludedRelativePaths'] as List).contains(
          'linux/flutter/ephemeral',
        ),
    '清单必须说明新增的平台临时目录排除规则',
  );
  _expect(
    _sameJson(
      manifest['excludedRelativePaths'],
      manifest['excludedGeneratedDirectorySuffixes'],
    ),
    '旧排除字段应作为新字段的等值兼容别名',
  );
  _expect(_sameJson(before, fixture.sourceSnapshot()), '不能修改源包及失效链接');
}

Future<void> _brokenSourceSymlink(_Fixture fixture, File engine) async {
  if (Platform.isWindows) return;
  fixture.addPackage('alpha');
  fixture.writeMetadata();
  final source = fixture.packages.first.directory;
  Link('${source.path}/lib/missing.dart').createSync('not-present.dart');
  final before = fixture.sourceSnapshot();
  final result = await fixture.run(engine);
  _expect(result.code == 0, '失效链接应告警跳过，不中断其它源码提取：$result');
  final output = fixture.onlyCompleteOutput();
  _expect(
    FileSystemEntity.typeSync(
          '${output.path}/packages/alpha/lib/missing.dart',
          followLinks: false,
        ) ==
        FileSystemEntityType.notFound,
    '失效链接不能进入结果',
  );
  _expectWarning(_readManifest(output), 'alpha/lib/missing.dart', '无法解析');
  _expect(
    File('${output.path}/packages/alpha/lib/alpha.dart').readAsStringSync() ==
        '// alpha fixture\n',
    '跳过失效链接不能丢失正常源码',
  );
  _expect(_sameJson(before, fixture.sourceSnapshot()), '跳过链接不能改变源包');
}

Future<void> _generatedDirectoryAlias(_Fixture fixture, File engine) async {
  if (Platform.isWindows) return;
  fixture.addPackage('alpha');
  fixture.writeMetadata();
  final source = fixture.packages.single.directory;
  final generated = Directory('${source.path}/linux/flutter/ephemeral')
    ..createSync(recursive: true);
  File('${generated.path}/generated-secret.txt')
      .writeAsStringSync('GENERATED_MUST_NOT_COPY');
  Link('${source.path}/lib/cache-alias').createSync(generated.path);
  final before = fixture.sourceSnapshot();
  final result = await fixture.run(engine);
  _expect(result.code == 0, '生成目录别名应被跳过：$result');
  final output = fixture.onlyCompleteOutput();
  _expectWarning(
    _readManifest(output),
    'alpha/lib/cache-alias',
    '真实路径位于缓存或构建目录',
  );
  _expect(
    FileSystemEntity.typeSync(
          '${output.path}/packages/alpha/lib/cache-alias',
          followLinks: false,
        ) ==
        FileSystemEntityType.notFound,
    '别名带入了排除目录',
  );
  for (final entity in output.listSync(recursive: true, followLinks: false)) {
    if (entity is File) {
      _expect(
        !utf8
            .decode(entity.readAsBytesSync(), allowMalformed: true)
            .contains('GENERATED_MUST_NOT_COPY'),
        '生成目录内容经别名泄漏进入归档',
      );
    }
  }
  _expect(_sameJson(before, fixture.sourceSnapshot()), '别名识别修改了源目录');
}

Future<void> _unreadableSourceFile(_Fixture fixture, File engine) async {
  if (Platform.isWindows) return;
  fixture.addPackage('alpha');
  fixture.writeMetadata();
  final source = File(
    '${fixture.packages.single.directory.path}/lib/alpha.dart',
  );
  final before = fixture.sourceSnapshot();
  final originalMode = source.statSync().mode & 0x1ff;
  _expect(
    (await Process.run('/bin/chmod', ['000', source.path])).exitCode == 0,
    '不能建立只限夹具的普通源码不可读场景',
  );
  try {
    final result = await fixture.run(engine);
    _expect(
      result.code != 0 && !result.timedOut,
      '普通源码读取失败不能被当成链接告警跳过：$result',
    );
    _expect(fixture.completeOutputs().isEmpty, '复制真实文件失败不能发布完整结果');
    _expect(
      result.error.contains('Cannot copy') ||
          result.error.contains('Permission denied'),
      '应明确显示真实文件复制错误：$result',
    );
  } finally {
    await Process.run('/bin/chmod', [
      originalMode.toRadixString(8),
      source.path,
    ]);
  }
  _expect(_sameJson(before, fixture.sourceSnapshot()), '失败后源码内容或权限未保留');
}

void _expectWarning(Map<String, dynamic> manifest, String path, String reason) {
  final warnings = manifest['warnings'];
  _expect(
    warnings is List &&
        warnings.any(
          (warning) =>
              warning is String &&
              warning.startsWith('$path：') &&
              warning.contains(reason),
        ),
    '清单缺少具体路径及原因的告警：$path / $reason；实际：$warnings',
  );
}

Future<void> _destinationDotDot(_Fixture fixture, File engine) async {
  fixture.addPackage('alpha');
  fixture.writeMetadata();
  final leaf = fixture.destination.uri.pathSegments
      .where((part) => part.isNotEmpty)
      .last;
  final input = Directory('${fixture.root.path}/不存在中间目录/../$leaf');
  final result = await fixture.run(engine, destination: input);
  _expect(result.code == 0, '含 .. 的有效目标路径应归一化后提取：$result');
  _expect(
    fixture.completeOutputs().length == 1,
    '应在用户指定路径的实际终点生成导出：${fixture.destination.path}\n$result',
  );
  _expect(
    !Directory('${fixture.root.path}/不存在中间目录').existsSync(),
    '词法归一化不应意外创建 .. 之前的目录',
  );
}

Future<void> _destinationDotDotSymlink(_Fixture fixture, File engine) async {
  if (Platform.isWindows) return;
  fixture.addPackage('alpha');
  fixture.writeMetadata();
  final source = fixture.packages.first.directory;
  Link('${fixture.root.path}/source alias').createSync(source.path);
  final input = Directory(
    '${fixture.root.path}/不存在中间目录/../source alias/exported',
  );
  await _expectFailure(fixture, engine, destination: input);
  _expect(
    !Directory('${source.path}/exported').existsSync(),
    '归一化后目标落入源目录时必须在创建目录前拒绝',
  );
  _expect(
    !Directory('${fixture.root.path}/不存在中间目录').existsSync(),
    '失败时也不应创建 .. 之前的目录',
  );
}

Future<void> _quotedLockDescription(_Fixture fixture, File engine) async {
  fixture.addPackage('alpha', dependency: 'direct main');
  fixture.addPackage('git_plugin', source: 'git');
  fixture.writeMetadata();
  final lock = File('${fixture.project.path}/pubspec.lock');
  lock.writeAsStringSync(
    lock
        .readAsStringSync()
        .replaceAll('description: flutter', 'description: "flutter"')
        .replaceAll('ref: main', 'ref: "feature/hello: # world"')
        .replaceAll('resolved-ref: deadbeef', 'resolved-ref: "deadbeef"')
        .replaceAll('path: packages/plugin', "path: 'packages/plugin'"),
  );
  File('${fixture.project.path}/.dart_tool/package_config.json')
      .setLastModifiedSync(DateTime.now().add(const Duration(seconds: 1)));
  final result = await fixture.run(engine);
  _expect(result.code == 0, '标准锁定描述中的引号应被接受：$result');
  _expect(
    _manifestPackages(_readManifest(fixture.onlyCompleteOutput())).length == 2,
    '带引号的标准锁描述不能漏包',
  );
}

Future<void> _staleProjectManifest(_Fixture fixture, File engine) async {
  fixture.addPackage('alpha');
  fixture.writeMetadata();
  final manifest = File('${fixture.project.path}/pubspec.yaml');
  manifest.setLastModifiedSync(DateTime.now().add(const Duration(seconds: 2)));
  await _expectFailure(fixture, engine);
}

Future<void> _linkedPackageRoot(_Fixture fixture, File engine) async {
  if (Platform.isWindows) return;
  fixture.addPackage('alpha');
  fixture.writeMetadata();
  final source = fixture.packages.first.directory;
  final link = Link('${fixture.root.path}/linked package')
    ..createSync(source.path);
  final config = File('${fixture.project.path}/.dart_tool/package_config.json');
  final value = jsonDecode(config.readAsStringSync()) as Map<String, dynamic>;
  final entries = value['packages'] as List;
  final alpha = entries.singleWhere(
    (dynamic entry) => entry['name'] == 'alpha',
  );
  alpha['rootUri'] = link.uri.toString();
  config.writeAsStringSync(jsonEncode(value));
  final result = await fixture.run(engine);
  _expect(result.code == 0, '包根软链应解析到实际路径：$result');
  final output = fixture.onlyCompleteOutput();
  final copied = File('${output.path}/packages/alpha/tool/run.sh');
  _expect((copied.statSync().mode & 0x1ff) == 0x1ed, '包根软链不能丢失执行权限');
}

Future<void> _rejectProjectDartShim(_Fixture fixture, File engine) async {
  if (!Platform.isMacOS) return;
  fixture.writeMetadata();
  final fakeDart = File(
    '${fixture.project.path}/.fvm/flutter_sdk/bin/cache/dart-sdk/bin/dart',
  );
  fakeDart.parent.createSync(recursive: true);
  final marker = File('${fixture.root.path}/unexpected-shim-executed');
  final quotedMarker = "'${marker.path.replaceAll("'", "'\\''")}'";
  fakeDart.writeAsStringSync(
    '#!/bin/sh\nprintf executed > $quotedMarker\nexit 0\n',
  );
  final chmod = Process.runSync('/bin/chmod', ['755', fakeDart.path]);
  _expect(chmod.exitCode == 0, '无法准备伪造 shim 的安全 fixture');
  final wrapper = File.fromUri(
    engine.parent.uri.resolve('ExtractFlutterDependencies.zsh'),
  );
  final process = await Process.start(
    '/bin/zsh',
    [wrapper.path, fixture.project.path],
    environment: {'TMPDIR': '${fixture.root.path}/'},
  );
  final stdoutFuture = process.stdout.transform(utf8.decoder).join();
  final stderrFuture = process.stderr.transform(utf8.decoder).join();
  process.stdin.write('\n${fixture.destination.path}\n');
  await process.stdin.close();
  final code = await process.exitCode.timeout(
    const Duration(seconds: 20),
    onTimeout: () {
      process.kill();
      return -999;
    },
  );
  final output = await stdoutFuture;
  final error = await stderrFuture;
  _expect(
    !marker.existsSync(),
    '仅提取依赖不能运行项目内伪装成 Dart 的 Shell shim：exit=$code\n$output\n$error',
  );
}

Future<void> _maliciousName(_Fixture fixture, File engine) async {
  fixture.addPackage('../escape');
  fixture.writeMetadata();
  await _expectFailure(fixture, engine);
  _expect(
    !File('${fixture.destination.path}/escape/lib/escape.dart').existsSync(),
    '恶意名称写出了 packages 目录',
  );
}

Future<void> _symlinkBoundaries(_Fixture fixture, File engine) async {
  if (Platform.isWindows) {
    stdout.writeln('SKIP Windows 上创建符号链接可能需要额外权限');
    return;
  }
  fixture.addPackage('alpha');
  fixture.writeMetadata();
  final source = fixture.packages.first.directory;
  final outside = Directory('${fixture.root.path}/private 外部')..createSync();
  final secret = File('${outside.path}/outside-secret.txt')
    ..writeAsStringSync('THIS_FILE_MUST_NEVER_BE_EXPORTED');
  Link('${source.path}/external-file').createSync(secret.path);
  Link('${source.path}/external-directory').createSync(outside.path);
  Link('${source.path}/loop').createSync(source.path);
  final before = fixture.sourceSnapshot();
  final result = await fixture.run(engine);
  _expect(!result.timedOut, '循环符号链接导致提取挂起');
  _expect(_sameJson(before, fixture.sourceSnapshot()), '符号链接处理改变了源文件');
  _expect(result.code == 0, '包外与循环链接须告警跳过，正常源码仍应完成：$result');
  {
    final output = fixture.onlyCompleteOutput();
    final manifest = _readManifest(output);
    _expectWarning(manifest, 'alpha/external-file', '指向包外');
    _expectWarning(manifest, 'alpha/external-directory', '指向包外');
    _expectWarning(manifest, 'alpha/loop', '循环符号链接');
    final copied = Directory('${output.path}/packages/alpha');
    for (final name in ['external-file', 'external-directory', 'loop']) {
      _expect(
        FileSystemEntity.typeSync('${copied.path}/$name', followLinks: false) ==
            FileSystemEntityType.notFound,
        '导出中应跳过外部或循环链接：$name',
      );
    }
    for (final entity in output.listSync(recursive: true, followLinks: false)) {
      if (entity is File) {
        _expect(
          !utf8
              .decode(entity.readAsBytesSync(), allowMalformed: true)
              .contains('THIS_FILE_MUST_NEVER_BE_EXPORTED'),
          '提取读取了依赖源范围外的数据',
        );
      }
    }
  }
}

Future<void> _expectFailure(
  _Fixture fixture,
  File engine, {
  Directory? destination,
}) async {
  final before = fixture.sourceSnapshot();
  final result = await fixture.run(engine, destination: destination);
  _expect(!result.timedOut, '失败场景不应挂起：$result');
  _expect(result.code != 0, '应返回非零退出码：$result');
  _expect(
    fixture.completeOutputs(destination: destination).isEmpty,
    '失败不得留下 status=complete 的导出目录',
  );
  _expect(_sameJson(before, fixture.sourceSnapshot()), '失败场景也不能改变源文件');
}

Map<String, dynamic> _readManifest(Directory output) {
  final manifest = File('${output.path}/manifest.json');
  _expect(manifest.existsSync(), '缺少 manifest.json');
  final value = jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
  _expect(value['status'] == 'complete', '完成的导出必须标明 status=complete');
  return value;
}

Map<String, Map<String, dynamic>> _manifestPackages(
  Map<String, dynamic> manifest,
) {
  _expect(manifest['packages'] is List, 'manifest.packages 必须是列表');
  final result = <String, Map<String, dynamic>>{};
  for (final dynamic item in manifest['packages'] as List) {
    final package = item as Map<String, dynamic>;
    _expect(package['name'] is String, '包必须包含 name');
    final name = package['name'] as String;
    _expect(!result.containsKey(name), 'manifest 中重复依赖：$name');
    result[name] = package;
  }
  return result;
}

bool _sameJson(Object a, Object b) => jsonEncode(a) == jsonEncode(b);

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

class _Fixture {
  _Fixture(this.root, this.project, this.destination);

  factory _Fixture.create() {
    final root = Directory.systemTemp.createTempSync(
      'jobs_flutter_extract_测试 ',
    );
    final project = Directory('${root.path}/工程 中文 空格')..createSync();
    final destination = Directory('${root.path}/提取终点 空格')..createSync();
    for (final name in ['flutter', 'sky_engine']) {
      Directory('${root.path}/flutter sdk/packages/$name')
          .createSync(recursive: true);
      File('${root.path}/flutter sdk/packages/$name/pubspec.yaml')
          .writeAsStringSync('name: $name\n');
    }
    return _Fixture(root, project, destination);
  }

  final Directory root;
  final Directory project;
  final Directory destination;
  final List<_Package> packages = [];

  void addPackage(
    String name, {
    String source = 'hosted',
    String dependency = 'transitive',
    bool absoluteUri = false,
  }) {
    // 名称本身独立于 fixture 目录名，以便安全构造恶意名称用例。
    final folder = name.replaceAll(RegExp('[^a-zA-Z0-9_]'), '_');
    final directory = Directory(
      '${root.path}/dependency cache/$source/$folder',
    );
    Directory('${directory.path}/lib').createSync(recursive: true);
    Directory('${directory.path}/assets').createSync();
    Directory('${directory.path}/tool').createSync();
    File('${directory.path}/lib/$folder.dart')
        .writeAsStringSync('// $name fixture\n');
    File('${directory.path}/assets/中文 资源.txt').writeAsStringSync('资源 $name\n');
    File('${directory.path}/LICENSE')
        .writeAsStringSync('Fixture license for $name\n');
    File('${directory.path}/pubspec.yaml')
        .writeAsStringSync('name: "$name"\nversion: 1.2.3\n');
    final executable = File('${directory.path}/tool/run.sh')
      ..writeAsStringSync('#!/bin/sh\nexit 0\n');
    if (!Platform.isWindows) {
      final result = Process.runSync('chmod', ['755', executable.path]);
      _expect(result.exitCode == 0, '无法准备可执行文件 fixture');
    }
    packages.add(_Package(name, source, dependency, directory, absoluteUri));
  }

  void writeMetadata() {
    final direct = packages.where(
      (package) => package.dependency == 'direct main',
    );
    final development = packages.where(
      (package) => package.dependency == 'direct dev',
    );
    final pubspec = StringBuffer(
      'name: demo_project\n'
      'environment:\n  sdk: ">=3.0.0 <4.0.0"\n'
      'dependencies:\n  flutter:\n    sdk: flutter\n',
    );
    for (final package in direct) {
      pubspec.writeln('  "${package.name}": ^1.2.3');
    }
    if (development.isNotEmpty) {
      pubspec.writeln('dev_dependencies:');
      for (final package in development) {
        pubspec.writeln('  "${package.name}": ^1.2.3');
      }
    }
    File('${project.path}/pubspec.yaml').writeAsStringSync(pubspec.toString());
    File('${project.path}/pubspec.lock').writeAsStringSync(lockContent());
    Directory('${project.path}/.dart_tool').createSync();
    final entries = <Map<String, dynamic>>[
      {
        'name': 'demo_project',
        'rootUri': '../',
        'packageUri': 'lib/',
        'languageVersion': '3.0',
      },
      for (final name in ['flutter', 'sky_engine'])
        {
          'name': name,
          'rootUri': Directory('${root.path}/flutter sdk/packages/$name').uri
              .toString(),
          'packageUri': 'lib/',
          'languageVersion': '3.0',
        },
      for (final package in packages)
        {
          'name': package.name,
          'rootUri': package.absoluteUri
              ? package.directory.uri.toString()
              : '../../dependency%20cache/${package.source}/${package.directory.uri.pathSegments.where((part) => part.isNotEmpty).last}/',
          'packageUri': 'lib/',
          'languageVersion': '3.0',
        },
    ];
    File('${project.path}/.dart_tool/package_config.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ')
          .convert({'configVersion': 2, 'packages': entries}),
    );
  }

  String lockContent({bool includeThirdParty = true}) {
    final lock = StringBuffer('packages:\n');
    for (final name in ['flutter', 'sky_engine']) {
      lock.writeln(
        '  $name:\n'
        '    dependency: "${name == 'flutter' ? 'direct main' : 'transitive'}"\n'
        '    description: flutter\n'
        '    source: sdk\n'
        '    version: "0.0.0"',
      );
    }
    if (includeThirdParty) {
      for (final package in packages) {
        lock.writeln(
          '  "${package.name}":\n'
          '    dependency: "${package.dependency}"\n'
          '    description:',
        );
        if (package.source == 'hosted') {
          lock.writeln(
            '      name: "${package.name}"\n'
            '      sha256: "fixture-not-a-network-operation"\n'
            '      url: "https://pub.dev"',
          );
        } else if (package.source == 'git') {
          lock.writeln(
            '      path: packages/plugin\n'
            '      ref: main\n'
            '      resolved-ref: deadbeef\n'
            '      url: "https://example.invalid/fixture.git"',
          );
        } else {
          lock.writeln(
            '      path: "${package.directory.path}"\n'
            '      relative: false',
          );
        }
        lock.writeln(
          '    source: ${package.source}\n'
          '    version: "${package.version}"',
        );
      }
    }
    lock.writeln('sdks:\n  dart: ">=3.0.0 <4.0.0"\n  flutter: ">=3.0.0"');
    return lock.toString();
  }

  Future<_RunResult> run(File engine, {Directory? destination}) async {
    final process = await Process.start(
      Platform.resolvedExecutable,
      [
        engine.path,
        '--project',
        project.path,
        '--destination',
        (destination ?? this.destination).path,
      ],
      workingDirectory: root.path,
      environment: {'CI': 'true', 'DART_SUPPRESS_ANALYTICS': 'true'},
    );
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    var timedOut = false;
    final code = await process.exitCode.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        timedOut = true;
        process.kill();
        return -999;
      },
    );
    return _RunResult(code, await stdoutFuture, await stderrFuture, timedOut);
  }

  List<Directory> completeOutputs({Directory? destination}) {
    final target = destination ?? this.destination;
    if (!target.existsSync()) {
      return [];
    }
    final result = <Directory>[];
    for (final entity in target.listSync(followLinks: false)) {
      if (entity is! Directory) {
        continue;
      }
      final manifest = File('${entity.path}/manifest.json');
      if (!manifest.existsSync()) {
        continue;
      }
      try {
        final value = jsonDecode(manifest.readAsStringSync());
        if (value is Map && value['status'] == 'complete') {
          result.add(entity);
        }
      } on FormatException {
        // 故意保留的 .incomplete 目录不算完整导出。
      }
    }
    return result;
  }

  Directory onlyCompleteOutput() {
    final outputs = completeOutputs();
    _expect(
      outputs.length == 1,
      '应恰好有一个完整导出，实际为 ${outputs.map((dir) => dir.path).toList()}',
    );
    final output = outputs.single;
    _expect(
      output.uri.pathSegments.any(
        (segment) => segment.startsWith('FlutterDependencies-'),
      ),
      '导出目录应使用 FlutterDependencies- 前缀',
    );
    return output;
  }

  Map<String, Object> sourceSnapshot() {
    final result = <String, Object>{};
    final roots = [project, ...packages.map((package) => package.directory)];
    for (final source in roots) {
      if (!source.existsSync()) {
        continue;
      }
      final entities = source.listSync(recursive: true, followLinks: false)
        ..sort((a, b) => a.path.compareTo(b.path));
      for (final entity in entities) {
        if (entity is Link) {
          result[entity.path] = {'link': entity.targetSync()};
        } else if (entity is File) {
          final stat = entity.statSync();
          result[entity.path] = {
            'bytes': base64Encode(entity.readAsBytesSync()),
            'modified': stat.modified.microsecondsSinceEpoch,
            'mode': stat.mode,
          };
        }
      }
    }
    return result;
  }

  void dispose() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  }
}

class _Package {
  _Package(
    this.name,
    this.source,
    this.dependency,
    this.directory,
    this.absoluteUri,
  );

  final String name;
  final String source;
  final String dependency;
  final Directory directory;
  final bool absoluteUri;
  final String version = '1.2.3';
}

class _RunResult {
  _RunResult(this.code, this.output, this.error, this.timedOut);

  final int code;
  final String output;
  final String error;
  final bool timedOut;

  @override
  String toString() =>
      'exit=$code, timeout=$timedOut\nstdout: $output\nstderr: $error';
}
