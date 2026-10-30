// Created by Jobs on 2026年10月29日，星期四。
// 文件型平台依赖快照：只复制经过核验的普通文件，不执行快照内容或安装脚本。
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

const _format = 'JobsNativeDependencyArchive';
const _kinds = {'gradle', 'pods', 'spm', 'ohos', 'native', 'precache', 'web'};
const _platforms = {'android', 'ios', 'macos', 'web', 'ohos', 'windows'};
const _ignoredDirectories = {'.git', '.svn', '.hg'};
const _ignoredFiles = {
  '.DS_Store',
  '.lock',
  '.lck',
  '.npmrc',
  '.netrc',
  '.git-credentials',
  '.gitconfig',
  'credentials',
};

class ArchiveException implements Exception {
  ArchiveException(this.message);
  final String message;
  @override
  String toString() => message;
}

Never _fail(String message) => throw ArchiveException(message);

String _join(String root, String relative) =>
    '$root${Platform.pathSeparator}${relative.split('/').join(Platform.pathSeparator)}';

bool _inside(String root, String path) {
  var left = root;
  var right = path;
  if (Platform.isWindows) {
    left = left.toLowerCase();
    right = right.toLowerCase();
  }
  return right == left || right.startsWith('$left${Platform.pathSeparator}');
}

String _relativePath(Object? value) {
  if (value is! String ||
      value.isEmpty ||
      value.length > 4096 ||
      RegExp(r'[\x00-\x1f\x7f\\:]').hasMatch(value) ||
      value.startsWith('/')) {
    _fail('清单包含不安全的相对路径。');
  }
  for (final part in value.split('/')) {
    if (part.isEmpty ||
        part == '.' ||
        part == '..' ||
        part.endsWith(' ') ||
        part.endsWith('.') ||
        RegExp(
          r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\.|$)',
          caseSensitive: false,
        ).hasMatch(part)) {
      _fail('清单包含不安全的路径分量。');
    }
  }
  return value;
}

bool _excluded(String name, bool directory, String kind) {
  if (directory)
    return _ignoredDirectories.contains(name) ||
        (kind == 'gradle' && {'daemon', 'init.d'}.contains(name));
  if (kind == 'gradle' && name == 'gradle.properties') return true;
  if (kind == 'gradle' &&
      RegExp(
        r'^(?:file|modules-[0-9]+|metadata-[0-9.]+|journal-[0-9]+|gc|caches-journal|fileHashes|fileContent|executionHistory|buildOutputCleanup)\.lock$',
      ).hasMatch(name))
    return true;
  return _ignoredFiles.contains(name) ||
      RegExp(r'\.(?:lck|log|tmp|part)$', caseSensitive: false).hasMatch(name);
}

String _directory(String argument, {bool required = true}) {
  final directory = Directory(argument);
  if (!directory.isAbsolute) _fail('目录必须使用绝对路径。');
  final type = FileSystemEntity.typeSync(argument, followLinks: false);
  if (type == FileSystemEntityType.notFound && !required) {
    final parent = Directory(argument).parent;
    if (parent.path == argument) _fail('无法解析目标目录。');
    return _join(
      _directory(parent.path, required: false),
      directory.uri.pathSegments.where((s) => s.isNotEmpty).last,
    );
  }
  if (type != FileSystemEntityType.directory) _fail('目录不存在、不是普通目录或为符号链接。');
  return directory.resolveSymbolicLinksSync();
}

class _Options {
  _Options(List<String> arguments) {
    if (arguments.isEmpty || !{'export', 'import'}.contains(arguments.first)) {
      _fail(
        '用法：NativeDependencyArchive.dart export|import --project <绝对路径> --kind <类别> --directory <目录> --source-root|--target-root <目录> --platform <平台> --tool-version <版本> [--check] [--confirm YES]',
      );
    }
    operation = arguments.first;
    for (var index = 1; index < arguments.length; index++) {
      final key = arguments[index];
      if (key == '--check') {
        if (check) _fail('参数重复：--check');
        check = true;
        continue;
      }
      if (!{
            '--project',
            '--kind',
            '--directory',
            '--source-root',
            '--target-root',
            '--platform',
            '--tool-version',
            '--confirm',
          }.contains(key) ||
          index + 1 >= arguments.length ||
          values.containsKey(key)) {
        _fail('未知、缺值或重复参数：$key');
      }
      values[key] = arguments[++index];
    }
    kind = values['--kind'] ?? '';
    platform = values['--platform'] ?? '';
    toolVersion = values['--tool-version'] ?? '';
    if (!_kinds.contains(kind) || !_platforms.contains(platform))
      _fail('依赖类别或目标平台无效。');
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9 ._+()=-]{0,255}$')
            .hasMatch(toolVersion) ||
        !RegExp(r'[0-9]').hasMatch(toolVersion)) {
      _fail('工具版本不能为空，且必须是已核验的安全版本文字。');
    }
    project = _directory(values['--project'] ?? '');
    final spec = File(_join(project, 'pubspec.yaml'));
    if (FileSystemEntity.typeSync(spec.path, followLinks: false) !=
        FileSystemEntityType.file)
      _fail('目标缺少普通 pubspec.yaml。');
    final key = operation == 'export' ? '--source-root' : '--target-root';
    if (values[key] == null ||
        values[operation == 'export' ? '--target-root' : '--source-root'] !=
            null) {
      _fail('导出只能指定 source-root，导入只能指定 target-root。');
    }
    root = _directory(values[key]!, required: operation == 'export');
    final userHome =
        Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
    if (Directory(root).parent.path == root ||
        root == project ||
        (userHome != null &&
            Directory(userHome).existsSync() &&
            root == Directory(userHome).resolveSymbolicLinksSync())) {
      _fail('来源 / 目标必须是明确的依赖层目录，不能选择系统根、整个用户目录或整个工程。');
    }
    directory = _directory(values['--directory'] ?? '');
    if (_inside(root, directory) || _inside(directory, root))
      _fail('快照目录与来源 / 目标根不能相互包含。');
    if (operation == 'import' && !check && values['--confirm'] != 'YES')
      _fail('导入必须先审阅 --check，并显式传入 --confirm YES。');
    if (operation == 'export' && values.containsKey('--confirm'))
      _fail('导出不接受 confirm 参数。');
  }
  late final String operation,
      kind,
      platform,
      toolVersion,
      project,
      root,
      directory;
  final Map<String, String> values = {};
  bool check = false;
}

class _Record {
  _Record(
    this.path,
    this.source,
    this.size,
    this.sha256, [
    this.executable = false,
  ]);
  final String path, source, sha256;
  final int size;
  final bool executable;
  Map<String, Object> toJson() => {
    'path': path,
    'size': size,
    'sha256': sha256,
    'executable': executable,
  };
}

String _hash(File file) {
  final input = file.openSync();
  final hash = _Sha256();
  try {
    while (true) {
      final bytes = input.readSync(1024 * 1024);
      if (bytes.isEmpty) break;
      hash.add(bytes);
    }
  } finally {
    input.closeSync();
  }
  return hash.finish();
}

_Record _record(String logical, String physical) {
  final file = File(physical);
  final before = file.statSync();
  if (before.type != FileSystemEntityType.file) _fail('只接受普通文件：$logical');
  final digest = _hash(file);
  final after = file.statSync();
  if (before.size != after.size ||
      before.modified != after.modified ||
      before.changed != after.changed ||
      after.type != FileSystemEntityType.file) {
    _fail('读取过程中来源发生变化：$logical');
  }
  return _Record(
    _relativePath(logical),
    physical,
    after.size,
    digest,
    !Platform.isWindows && (after.mode & 0x49) != 0,
  );
}

List<_Record> _inventory(
  String root, {
  bool snapshot = false,
  String kind = '',
  List<String> resolvedPubRoots = const [],
}) {
  final records = <_Record>[];
  final names = <String>{};
  void visit(String physical, String logical, Set<String> ancestors) {
    final real = Directory(physical).resolveSymbolicLinksSync();
    if (!ancestors.add(real)) _fail('来源包含循环链接。');
    final entries = Directory(physical).listSync(followLinks: false)
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final entry in entries) {
      final name = entry.uri.pathSegments.where((part) => part.isNotEmpty).last;
      final relative = logical.isEmpty ? name : '$logical/$name';
      final type = FileSystemEntity.typeSync(entry.path, followLinks: false);
      if (!snapshot &&
          _excluded(name, type == FileSystemEntityType.directory, kind))
        continue;
      if (type == FileSystemEntityType.link) {
        if (snapshot) _fail('快照不接受符号链接：$relative');
        String target;
        try {
          target = entry.resolveSymbolicLinksSync();
        } on FileSystemException {
          _fail('来源包含失效链接：$relative');
        }
        if (!_inside(root, target) &&
            !(kind == 'pods' &&
                resolvedPubRoots.any(
                  (packageRoot) => _inside(packageRoot, target),
                ))) {
          _fail('来源链接越界，且不属于已核验的 Pub 包根：$relative');
        }
        final targetType = FileSystemEntity.typeSync(
          target,
          followLinks: false,
        );
        if (targetType == FileSystemEntityType.directory) {
          visit(target, relative, {...ancestors});
        } else if (targetType == FileSystemEntityType.file) {
          if (!names.add(relative.toLowerCase())) _fail('路径大小写冲突。');
          records.add(_record(relative, target));
        } else {
          _fail('链接未指向普通文件或目录：$relative');
        }
      } else if (type == FileSystemEntityType.directory) {
        visit(entry.path, relative, {...ancestors});
      } else if (type == FileSystemEntityType.file) {
        if (!names.add(relative.toLowerCase())) _fail('路径大小写冲突。');
        records.add(_record(relative, entry.path));
      } else {
        _fail('来源包含特殊文件：$relative');
      }
    }
  }

  visit(root, '', {});
  records.sort((a, b) => a.path.compareTo(b.path));
  return records;
}

// 只承认本次实际解析的本地 Pub 包；绝不把整个用户目录或项目祖先提升为可信来源。
List<String> _resolvedPubRoots(_Options options) {
  final configuration = File(
    _join(options.project, '.dart_tool/package_config.json'),
  );
  final type = FileSystemEntity.typeSync(
    configuration.path,
    followLinks: false,
  );
  if (type == FileSystemEntityType.notFound) return [];
  if (FileSystemEntity.typeSync(
            configuration.parent.path,
            followLinks: false,
          ) !=
          FileSystemEntityType.directory ||
      type != FileSystemEntityType.file ||
      configuration.lengthSync() > 16 * 1024 * 1024) {
    _fail('Pub 解析配置不是普通小型文件。');
  }
  final data = jsonDecode(configuration.readAsStringSync());
  if (data is! Map || data['configVersion'] != 2 || data['packages'] is! List)
    _fail('Pub 解析配置格式无效。');
  final names = <String>{};
  final roots = <String>{};
  final home =
      Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
  final canonicalHome = home != null && Directory(home).existsSync()
      ? Directory(home).resolveSymbolicLinksSync()
      : null;
  for (final entry in data['packages'] as List) {
    if (entry is! Map ||
        entry['name'] is! String ||
        !RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(entry['name']) ||
        entry['rootUri'] is! String ||
        entry['rootUri'].isEmpty ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(entry['rootUri']) ||
        !names.add(entry['name']))
      _fail('Pub 包条目无效或重名。');
    final uri = configuration.uri.resolve(entry['rootUri']);
    if (uri.scheme != 'file' ||
        (uri.host.isNotEmpty && uri.host != 'localhost') ||
        uri.hasQuery ||
        uri.hasFragment)
      _fail('Pub 包根必须是本地文件 URI。');
    final root = _directory(Directory.fromUri(uri).path);
    if (root != options.project &&
        (Directory(root).parent.path == root ||
            _inside(root, options.project) ||
            (canonicalHome != null && _inside(root, canonicalHome)))) {
      _fail('Pub 包根不能是系统根、用户目录或工程祖先。');
    }
    final spec = File(_join(root, 'pubspec.yaml'));
    if (FileSystemEntity.typeSync(spec.path, followLinks: false) !=
            FileSystemEntityType.file ||
        spec.lengthSync() > 1024 * 1024)
      _fail('Pub 包根缺少普通 pubspec.yaml。');
    final content = spec.readAsStringSync().replaceFirst('\ufeff', '');
    if (content.contains('\x00')) _fail('Pub 包声明包含无效字符。');
    final declarations = RegExp(
      r'''^(?:name|"name"|'name')[ \t]*:[ \t]*(?:"([A-Za-z_][A-Za-z0-9_]*)"|'([A-Za-z_][A-Za-z0-9_]*)'|([A-Za-z_][A-Za-z0-9_]*))[ \t]*(?:#.*)?\r?$''',
      multiLine: true,
    ).allMatches(content).toList();
    if (declarations.length != 1) _fail('Pub 包名无法安全识别。');
    final declaration = declarations.single;
    final actualName =
        declaration.group(1) ?? declaration.group(2) ?? declaration.group(3);
    if (actualName != entry['name']) _fail('Pub 包根声明的 name 与解析记录不一致。');
    // package_config 的当前工程条目是正常情况，但不能授权归档工程内任意其它文件。
    if (root != options.project) roots.add(root);
  }
  final result = roots.toList()..sort();
  return result;
}

String _pubConfigurationStamp(_Options options) {
  final file = File(_join(options.project, '.dart_tool/package_config.json'));
  final type = FileSystemEntity.typeSync(file.path, followLinks: false);
  if (type == FileSystemEntityType.notFound) return 'absent';
  if (type != FileSystemEntityType.file ||
      FileSystemEntity.typeSync(file.parent.path, followLinks: false) !=
          FileSystemEntityType.directory ||
      file.lengthSync() > 16 * 1024 * 1024)
    _fail('Pub 解析配置不是普通小型文件。');
  return _hash(file);
}

List<_Record> _projectLocks(_Options options) {
  if (options.kind == 'precache') return [];
  final selected = <String>{'pubspec.yaml'};
  if ({'gradle', 'pods', 'spm', 'native'}.contains(options.kind))
    selected.add('pubspec.lock');
  if (options.kind == 'gradle')
    selected.add('android/gradle/wrapper/gradle-wrapper.properties');
  if (options.kind == 'pods')
    selected.addAll([
      '${options.platform}/Podfile',
      '${options.platform}/Podfile.lock',
    ]);
  if (options.kind == 'ohos')
    selected.addAll([
      'ohos/oh-package.json5',
      'ohos/oh-package-lock.json5',
      'ohos/hvigor/hvigor-config.json5',
    ]);
  if (options.kind == 'web') {
    for (final prefix in ['', 'web/']) {
      selected.addAll(
        [
          'package.json',
          'package-lock.json',
          'npm-shrinkwrap.json',
          'pnpm-lock.yaml',
          'yarn.lock',
        ].map((file) => '$prefix$file'),
      );
    }
  }
  final scan = options.kind == 'gradle' ? 'android' : options.platform;
  if ({'gradle', 'spm', 'native'}.contains(options.kind)) {
    final base = Directory(_join(options.project, scan));
    if (base.existsSync()) {
      if (FileSystemEntity.typeSync(base.path, followLinks: false) !=
          FileSystemEntityType.directory) {
        _fail('工程平台目录不是普通目录。');
      }
      const excluded = {
        'Pods',
        '.symlinks',
        '.gradle',
        '.dart_tool',
        'build',
        'node_modules',
        'oh_modules',
        'SourcePackages',
        'ephemeral',
        '.git',
      };
      void visit(Directory directory, String prefix) {
        for (final item in directory.listSync(followLinks: false)) {
          final name = item.uri.pathSegments
              .where((part) => part.isNotEmpty)
              .last;
          final relative = '$prefix/$name';
          final type = FileSystemEntity.typeSync(item.path, followLinks: false);
          if (type == FileSystemEntityType.directory &&
              !excluded.contains(name)) {
            visit(Directory(item.path), relative);
          } else if (name == 'Package.resolved' ||
              name.endsWith('.lockfile') ||
              (options.kind == 'native' &&
                  {
                    'CMakeLists.txt',
                    'build.gradle',
                    'build.gradle.kts',
                    'settings.gradle',
                    'settings.gradle.kts',
                    'Podfile',
                    'Podfile.lock',
                    'oh-package.json5',
                    'oh-package-lock.json5',
                    'hvigor-config.json5',
                    'package.json',
                    'package-lock.json',
                    'npm-shrinkwrap.json',
                    'pnpm-lock.yaml',
                    'yarn.lock',
                    'project.pbxproj',
                  }.contains(name))) {
            if (type != FileSystemEntityType.file)
              _fail('工程锁 / 配置不是普通文件：$relative');
            selected.add(relative);
          }
        }
      }

      visit(base, scan);
    }
  }
  final records = <_Record>[];
  for (final path in selected) {
    final physical = _join(options.project, path);
    final type = FileSystemEntity.typeSync(physical, followLinks: false);
    if (type == FileSystemEntityType.notFound) continue;
    if (type != FileSystemEntityType.file) _fail('工程锁 / 配置不是普通文件：$path');
    final real = File(physical).resolveSymbolicLinksSync();
    if (!_inside(options.project, real)) _fail('工程锁 / 配置越界。');
    records.add(_record(path, physical));
  }
  records.sort((a, b) => a.path.compareTo(b.path));
  return records;
}

bool _sameRecords(List<_Record> left, List<_Record> right) =>
    jsonEncode(left.map((r) => r.toJson()).toList()) ==
    jsonEncode(right.map((r) => r.toJson()).toList());

List<_Record> _readRecords(Object? data) {
  if (data is! List || data.length > 2000000) _fail('清单文件表无效。');
  final paths = <String>{};
  final result = <_Record>[];
  for (final item in data) {
    if (item is! Map ||
        item.keys.toSet().difference({
          'path',
          'size',
          'sha256',
          'executable',
        }).isNotEmpty ||
        item['size'] is! int ||
        item['size'] < 0 ||
        item['executable'] is! bool ||
        item['sha256'] is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(item['sha256']))
      _fail('清单文件项无效。');
    final path = _relativePath(item['path']);
    if (!paths.add(path.toLowerCase())) _fail('清单路径重复。');
    result.add(
      _Record(path, '', item['size'], item['sha256'], item['executable']),
    );
  }
  result.sort((a, b) => a.path.compareTo(b.path));
  for (var index = 1; index < result.length; index++) {
    if (result[index].path.startsWith('${result[index - 1].path}/'))
      _fail('清单文件与目录路径冲突。');
  }
  return result;
}

Map<String, Object> _plan(
  _Options options,
  List<_Record> files, {
  int reused = 0,
}) => {
  'operation': options.operation,
  'kind': options.kind,
  'platform': options.platform,
  'hostOS': Platform.operatingSystem,
  'toolVersion': options.toolVersion,
  'fileCount': files.length,
  'bytes': files.fold<int>(0, (sum, record) => sum + record.size),
  'reuseCount': reused,
  'writeCount': files.length - reused,
  'check': options.check,
};

void _ensureParents(String root, String relative, [List<String>? created]) {
  var current = root;
  if (FileSystemEntity.typeSync(root, followLinks: false) ==
      FileSystemEntityType.notFound) {
    final parent = Directory(root).parent.path;
    if (parent == root) _fail('无法创建目标目录。');
    _ensureParents(parent, 'placeholder', created);
    Directory(root).createSync();
    created?.add(root);
  }
  if (FileSystemEntity.typeSync(root, followLinks: false) !=
      FileSystemEntityType.directory)
    _fail('目标根被替换或为链接。');
  final parts = relative.split('/')..removeLast();
  for (final part in parts) {
    current = _join(current, part);
    final type = FileSystemEntity.typeSync(current, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      if (created != null) {
        Directory(current).createSync();
        created.add(current);
      }
    } else if (type != FileSystemEntityType.directory) {
      _fail('目标父目录存在文件或链接冲突。');
    }
  }
}

void _verifyTargetParents(String root, String relative) {
  var current = root;
  final parts = relative.split('/')..removeLast();
  for (final part in parts) {
    current = _join(current, part);
    final type = FileSystemEntity.typeSync(current, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory)
      _fail('目标父目录不是普通目录。');
  }
}

void _copy(_Record record, File destination) {
  final input = File(record.source).openSync();
  RandomAccessFile? output;
  final hash = _Sha256();
  var size = 0;
  try {
    output = destination.openSync(mode: FileMode.writeOnly);
    while (true) {
      final bytes = input.readSync(1024 * 1024);
      if (bytes.isEmpty) break;
      output.writeFromSync(bytes);
      hash.add(bytes);
      size += bytes.length;
    }
    output.flushSync();
    if (size != record.size || hash.hexSoFar() != record.sha256)
      _fail('复制期间来源发生变化：${record.path}');
  } catch (_) {
    output?.closeSync();
    output = null;
    if (FileSystemEntity.typeSync(destination.path, followLinks: false) ==
            FileSystemEntityType.file &&
        destination.lengthSync() == size &&
        _hash(destination) == hash.hexSoFar())
      destination.deleteSync();
    rethrow;
  } finally {
    input.closeSync();
    output?.closeSync();
  }
  if (_hash(destination) != record.sha256 ||
      _hash(File(record.source)) != record.sha256)
    _fail('复制后校验失败：${record.path}');
  if (!Platform.isWindows) {
    final result = Process.runSync('/bin/chmod', [
      record.executable ? '700' : '600',
      destination.path,
    ]);
    if (result.exitCode != 0) _fail('无法恢复普通文件权限。');
  }
}

bool _matchesTarget(_Record record, File file) =>
    file.lengthSync() == record.size &&
    _hash(file) == record.sha256 &&
    (Platform.isWindows ||
        ((file.statSync().mode & 0x49) != 0) == record.executable);

void _export(_Options options) {
  final locks = _projectLocks(options);
  final pubConfiguration = options.kind == 'pods'
      ? _pubConfigurationStamp(options)
      : '';
  final pubRoots = options.kind == 'pods'
      ? _resolvedPubRoots(options)
      : <String>[];
  final files = _inventory(
    options.root,
    kind: options.kind,
    resolvedPubRoots: pubRoots,
  );
  if (files.isEmpty) _fail('来源没有可归档的普通文件。');
  if (options.check) {
    stdout.writeln(jsonEncode(_plan(options, files)));
    return;
  }
  final temporary = Directory(options.directory)
      .createTempSync('.jobs-${options.kind}-export-');
  try {
    if (!Platform.isWindows) {
      final result = Process.runSync('/bin/chmod', ['700', temporary.path]);
      if (result.exitCode != 0) _fail('无法保护新快照目录权限。');
    }
    final payload = Directory(_join(temporary.path, 'payload'))..createSync();
    for (final record in files) {
      _ensureParents(payload.path, record.path, []);
      _copy(record, File(_join(payload.path, record.path)));
    }
    if (!_sameRecords(
          files,
          _inventory(
            options.root,
            kind: options.kind,
            resolvedPubRoots: pubRoots,
          ),
        ) ||
        !_sameRecords(locks, _projectLocks(options)) ||
        (options.kind == 'pods' &&
            (pubConfiguration != _pubConfigurationStamp(options) ||
                jsonEncode(pubRoots) !=
                    jsonEncode(_resolvedPubRoots(options)))))
      _fail('归档期间来源或工程锁发生变化，未发布快照。');
    final manifest = {
      'format': _format,
      'formatVersion': 1,
      'kind': options.kind,
      'hostOS': Platform.operatingSystem,
      'platform': options.platform,
      'toolVersion': options.toolVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'projectLocks': locks.map((record) => record.toJson()).toList(),
      'files': files.map((record) => record.toJson()).toList(),
    };
    File(_join(temporary.path, 'manifest.json')).writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(manifest),
      flush: true,
    );
    final suffix = Random.secure().nextInt(0x7fffffff).toRadixString(16);
    final date = DateTime.now().toUtc().toIso8601String().replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    final finalPath = _join(
      options.directory,
      'Jobs-${options.kind}-dependencies-$date-$suffix',
    );
    if (FileSystemEntity.typeSync(finalPath, followLinks: false) !=
        FileSystemEntityType.notFound)
      _fail('唯一快照目录碰撞，未覆盖。');
    temporary.renameSync(finalPath);
    stdout.writeln(jsonEncode(_plan(options, files)));
    stdout.writeln('ARCHIVE_DIRECTORY=$finalPath');
  } catch (_) {
    if (temporary.existsSync()) temporary.deleteSync(recursive: true);
    rethrow;
  }
}

void _import(_Options options) {
  final manifestFile = File(_join(options.directory, 'manifest.json'));
  if (FileSystemEntity.typeSync(manifestFile.path, followLinks: false) !=
          FileSystemEntityType.file ||
      manifestFile.lengthSync() > 64 * 1024 * 1024)
    _fail('缺少普通 manifest.json 或清单过大。');
  final manifest = jsonDecode(manifestFile.readAsStringSync());
  if (manifest is! Map ||
      manifest['format'] != _format ||
      manifest['formatVersion'] != 1 ||
      manifest.keys.toSet().difference({
        'format',
        'formatVersion',
        'kind',
        'hostOS',
        'platform',
        'toolVersion',
        'createdAt',
        'projectLocks',
        'files',
      }).isNotEmpty)
    _fail('快照清单格式不支持。');
  if (manifest['hostOS'] != Platform.operatingSystem ||
      manifest['kind'] != options.kind ||
      manifest['platform'] != options.platform ||
      manifest['toolVersion'] != options.toolVersion)
    _fail('快照宿主、类别、平台或工具版本不兼容，未写入。');
  final expected = _readRecords(manifest['files']);
  final expectedLocks = _readRecords(manifest['projectLocks']);
  if (expected.isEmpty || !_sameRecords(expectedLocks, _projectLocks(options)))
    _fail('工程锁 / 配置签名不一致或快照为空，未写入。');
  final payload = _directory(_join(options.directory, 'payload'));
  final files = _inventory(payload, snapshot: true);
  if (!_sameRecords(expected, files)) _fail('快照文件清单或哈希不匹配，未写入。');
  var reused = 0;
  for (final record in files) {
    _verifyTargetParents(options.root, record.path);
    final path = _join(options.root, record.path);
    final type = FileSystemEntity.typeSync(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) continue;
    if (type != FileSystemEntityType.file ||
        !_matchesTarget(record, File(path)))
      _fail('目标存在同名不同内容、权限或链接冲突：${record.path}；未写入。');
    reused++;
  }
  if (options.check) {
    stdout.writeln(jsonEncode(_plan(options, files, reused: reused)));
    return;
  }
  final createdFiles = <_Record>[];
  final createdDirectories = <String>[];
  try {
    for (final record in files) {
      _ensureParents(options.root, record.path, createdDirectories);
      final destination = File(_join(options.root, record.path));
      final type = FileSystemEntity.typeSync(
        destination.path,
        followLinks: false,
      );
      if (type != FileSystemEntityType.notFound) {
        if (type == FileSystemEntityType.file &&
            _matchesTarget(record, destination))
          continue;
        _fail('写入前发现目标并发冲突：${record.path}');
      }
      destination.createSync(exclusive: true);
      createdFiles.add(
        _Record(
          record.path,
          destination.path,
          record.size,
          record.sha256,
          record.executable,
        ),
      );
      _copy(record, destination);
    }
    if (!_sameRecords(expectedLocks, _projectLocks(options)) ||
        !_sameRecords(expected, _inventory(payload, snapshot: true)))
      _fail('导入期间快照或工程锁变化。');
    stdout.writeln(jsonEncode(_plan(options, files, reused: reused)));
  } catch (_) {
    for (final record in createdFiles.reversed) {
      final file = File(record.source);
      if (FileSystemEntity.typeSync(file.path, followLinks: false) ==
              FileSystemEntityType.file &&
          (file.lengthSync() == 0 || _hash(file) == record.sha256))
        file.deleteSync();
    }
    for (final path in createdDirectories.reversed) {
      if (FileSystemEntity.typeSync(path, followLinks: false) ==
              FileSystemEntityType.directory &&
          Directory(path).listSync().isEmpty)
        Directory(path).deleteSync();
    }
    rethrow;
  }
}

void main(List<String> arguments) {
  try {
    final options = _Options(arguments);
    if (options.operation == 'export') {
      _export(options);
    } else {
      _import(options);
    }
  } catch (error) {
    stderr.writeln(
      '✖ 平台依赖归档失败：${error is ArchiveException ? error.message : error.runtimeType}',
    );
    exitCode = 1;
  }
}

// 流式 SHA-256 不引入 Pub 依赖，避免归档工具本身需要先联网安装包。
class _Sha256 {
  final _state = <int>[
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ];
  final _buffer = Uint8List(64);
  var _length = 0;
  var _used = 0;
  static const _constants = <int>[
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];
  int _rotate(int value, int bits) =>
      ((value >>> bits) | (value << (32 - bits))) & 0xffffffff;
  void add(List<int> bytes) {
    _length += bytes.length;
    for (final byte in bytes) {
      _buffer[_used++] = byte;
      if (_used == 64) {
        _block();
        _used = 0;
      }
    }
  }

  void _block() {
    final words = Uint32List(64);
    for (var index = 0; index < 16; index++) {
      final offset = index * 4;
      words[index] =
          (_buffer[offset] << 24) |
          (_buffer[offset + 1] << 16) |
          (_buffer[offset + 2] << 8) |
          _buffer[offset + 3];
    }
    for (var index = 16; index < 64; index++) {
      final a = words[index - 15], b = words[index - 2];
      final s0 = _rotate(a, 7) ^ _rotate(a, 18) ^ (a >>> 3);
      final s1 = _rotate(b, 17) ^ _rotate(b, 19) ^ (b >>> 10);
      words[index] =
          (words[index - 16] + s0 + words[index - 7] + s1) & 0xffffffff;
    }
    var a = _state[0], b = _state[1], c = _state[2], d = _state[3];
    var e = _state[4], f = _state[5], g = _state[6], h = _state[7];
    for (var index = 0; index < 64; index++) {
      final s1 = _rotate(e, 6) ^ _rotate(e, 11) ^ _rotate(e, 25);
      final choice = (e & f) ^ ((~e) & g);
      final t1 =
          (h + s1 + choice + _constants[index] + words[index]) & 0xffffffff;
      final s0 = _rotate(a, 2) ^ _rotate(a, 13) ^ _rotate(a, 22);
      final majority = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + majority) & 0xffffffff;
      h = g;
      g = f;
      f = e;
      e = (d + t1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xffffffff;
    }
    final values = [a, b, c, d, e, f, g, h];
    for (var index = 0; index < 8; index++)
      _state[index] = (_state[index] + values[index]) & 0xffffffff;
  }

  String finish() {
    final bits = _length * 8;
    add([0x80]);
    while (_used != 56) add([0]);
    add(List<int>.generate(8, (index) => (bits >>> ((7 - index) * 8)) & 0xff));
    return _state.map((word) => word.toRadixString(16).padLeft(8, '0')).join();
  }

  String hexSoFar() {
    final copy = _Sha256();
    copy._state.setAll(0, _state);
    copy._buffer.setAll(0, _buffer);
    copy._length = _length;
    copy._used = _used;
    return copy.finish();
  }
}
