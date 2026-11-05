// Created by Jobs on 2026年11月4日，星期三。
// 一键归档已解析依赖；缓存以内容识别，导入完整预检后仅增加缺失文件。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'ExtractFlutterDependencies.dart' as pub;
import 'ImportFlutterDependencies.dart' as restoring;

const migrationFormat = 'JobsFlutterDependencyMigration';
const _kinds = {
  'pub-cache',
  'gradle',
  'maven',
  'pods-ios',
  'pods-macos',
  'spm-project',
  'spm-ios',
  'spm-macos',
  'ohos',
  'web-root',
  'web',
};
const _nonportable = {
  'pods-ios',
  'pods-macos',
  'spm-project',
  'spm-ios',
  'spm-macos',
  'ohos',
  'web-root',
  'web',
};
const _excluded = {
  '.git',
  '.svn',
  '.hg',
  '.DS_Store',
  '.npmrc',
  '.netrc',
  '.git-credentials',
  '.gitconfig',
  'credentials.json',
  'credentials',
  'auth.json',
  'gradle.properties',
  'init.gradle',
  'init.gradle.kts',
};

Never _fail(String message) => throw FormatException(message);
String _join(String parent, String child) => pub.join(parent, child);
FileSystemEntityType _type(String path) =>
    FileSystemEntity.typeSync(path, followLinks: false);
bool _dir(String path) => _type(path) == FileSystemEntityType.directory;
bool _file(String path) => _type(path) == FileSystemEntityType.file;
String _name(String path) =>
    File(path).uri.pathSegments.where((v) => v.isNotEmpty).last;
String _hash(String path) => pub.fileDigest(File(path));
bool _inside(String child, String root) {
  if (Platform.isWindows) {
    child = child.toLowerCase();
    root = root.toLowerCase();
  }
  return child == root || child.startsWith('$root${Platform.pathSeparator}');
}

String _path(Object? value) {
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
        part.endsWith('.') ||
        part.endsWith(' ') ||
        RegExp(
          r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\.|$)',
          caseSensitive: false,
        ).hasMatch(part)) {
      _fail('清单包含不兼容的文件名。');
    }
  }
  return value;
}

String _absolute(String value, {bool exists = true}) {
  final result = Directory(value).absolute.path;
  if (exists && !_dir(result)) _fail('目录不存在或不是普通文件夹：$value');
  if (exists) return Directory(result).resolveSymbolicLinksSync();
  if (_type(result) != FileSystemEntityType.notFound && !_dir(result))
    _fail('目标是文件或链接：$value');
  if (_dir(result)) return Directory(result).resolveSymbolicLinksSync();
  final parent = Directory(result).parent.path;
  if (parent == result) _fail('无法解析路径。');
  return _join(_absolute(parent, exists: false), _name(result));
}

String _home() {
  final value =
      Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
  if (value == null || value.isEmpty) _fail('无法取得当前用户目录。');
  return _absolute(value);
}

String _cache(String kind) {
  final env = Platform.environment;
  switch (kind) {
    case 'pub-cache':
      return _absolute(
        env['PUB_CACHE'] ??
            (Platform.isWindows
                ? _join(env['LOCALAPPDATA'] ?? _home(), 'Pub/Cache')
                : _join(_home(), '.pub-cache')),
        exists: false,
      );
    case 'gradle':
      return _absolute(
        env['GRADLE_USER_HOME'] ?? _join(_home(), '.gradle'),
        exists: false,
      );
    case 'maven':
      return _absolute(
        env['MAVEN_REPO_LOCAL'] ?? _join(_home(), '.m2/repository'),
        exists: false,
      );
  }
  _fail('未知缓存类别。');
}

String _target(String project, String kind) {
  if ({'pub-cache', 'gradle', 'maven'}.contains(kind)) return _cache(kind);
  final relative = {
    'pods-ios': 'ios/Pods',
    'pods-macos': 'macos/Pods',
    'spm-project': '.jobs/dependencies/spm',
    'spm-ios': 'ios/SourcePackages',
    'spm-macos': 'macos/SourcePackages',
    'ohos': 'ohos/oh_modules',
    'web-root': 'node_modules',
    'web': 'web/node_modules',
  }[kind];
  if (relative == null) _fail('不支持的目标类型。');
  final path = _join(project, relative);
  _validateParents(_join(path, 'placeholder'));
  return _absolute(path, exists: false);
}

// Pub checks Git remotes even in offline mode; retain only non-executable standard cache config.
bool _safeGitConfig(String path) {
  if (!_file(path) || File(path).lengthSync() > 1024 * 1024) return false;
  var section = '';
  for (final raw in _text(path).split('\n')) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#') || line.startsWith(';')) continue;
    if (line.startsWith('[')) {
      if (line == '[core]') {
        section = 'core';
      } else if (line == '[remote "origin"]') {
        section = 'remote';
      } else if (RegExp(r'^\[branch "[A-Za-z0-9_./-]+"\]$').hasMatch(line)) {
        section = 'branch';
      } else {
        return false;
      }
      continue;
    }
    final match = RegExp(r'^([A-Za-z]+)\s*=\s*(.*)$').firstMatch(line);
    if (match == null) return false;
    final key = match.group(1)!.toLowerCase();
    final value = match.group(2)!;
    if (section == 'core') {
      if (key == 'repositoryformatversion') {
        if (value != '0') return false;
      } else if ({
        'filemode',
        'bare',
        'logallrefupdates',
        'ignorecase',
        'precomposeunicode',
        'symlinks',
      }.contains(key)) {
        if (!{'true', 'false'}.contains(value.toLowerCase())) return false;
      } else {
        return false;
      }
    } else if (section == 'remote') {
      if (key == 'url' || key == 'lfsurl') {
        // No credentials, query tokens, remote helpers or command transports are carried.
        final uri = Uri.tryParse(value);
        final standard =
            uri != null &&
            {'https', 'http', 'ssh', 'git', 'file'}.contains(uri.scheme) &&
            !uri.hasQuery &&
            !uri.hasFragment &&
            uri.userInfo.isEmpty;
        final local =
            value.startsWith('/') || RegExp(r'^[A-Za-z]:/').hasMatch(value);
        final scp = RegExp(
          r'^[A-Za-z0-9_.-]+@[A-Za-z0-9_.-]+:[A-Za-z0-9_./~%+-]+$',
        ).hasMatch(value);
        if (!(standard || local || scp) ||
            value.contains('\\') ||
            value.contains('"') ||
            value.contains('::'))
          return false;
      } else if (key == 'fetch') {
        if (!{
          '+refs/*:refs/*',
          '+refs/heads/*:refs/remotes/origin/*',
        }.contains(value))
          return false;
      } else if (key == 'tagopt') {
        if (!{'--no-tags', '--tags'}.contains(value)) return false;
      } else if (key == 'mirror') {
        if (!{'true', 'false'}.contains(value.toLowerCase())) return false;
      } else {
        return false;
      }
    } else if (section == 'branch') {
      if (key == 'remote') {
        if (value != 'origin') return false;
      } else if (key == 'merge') {
        if (!RegExp(r'^refs/heads/[A-Za-z0-9_./-]+$').hasMatch(value))
          return false;
      } else {
        return false;
      }
    } else {
      return false;
    }
  }
  return section.isNotEmpty;
}

bool _gitConfigPath(String kind, String relative) =>
    kind == 'pub-cache' &&
    relative.startsWith('git/') &&
    relative.endsWith('/config') &&
    (relative.startsWith('git/cache/') || relative.contains('/.git/'));

bool _safeGitMetadata(List<String> parts) {
  if (parts.isEmpty) return true;
  if (parts.length == 1 &&
      {
        'HEAD',
        'packed-refs',
        'index',
        'shallow',
        'config',
      }.contains(parts.first))
    return true;
  if (parts.first == 'refs') return true;
  if (parts.first != 'objects') return false;
  if (parts.length == 1) return true;
  if (parts[1] == 'info')
    return parts.length == 2 || (parts.length == 3 && parts[2] == 'packs');
  if (parts[1] == 'pack')
    return parts.length == 2 ||
        (parts.length == 3 &&
            RegExp(r'^pack-[0-9a-f]+\.(pack|idx|rev)$').hasMatch(parts[2]));
  return RegExp(r'^[0-9a-f]{2}$').hasMatch(parts[1]) &&
      (parts.length == 2 ||
          (parts.length == 3 &&
              RegExp(r'^[0-9a-f]{38,62}$').hasMatch(parts[2])));
}

bool _ignore(String relative, {String kind = ''}) {
  final parts = relative.split('/');
  final name = parts.last;
  if (kind == 'pub-cache' && parts.first == 'git') {
    if (parts.length >= 2 && parts[1] == 'cache')
      return parts.length > 3 && !_safeGitMetadata(parts.sublist(3));
    final gitIndex = parts.indexOf('.git');
    if (gitIndex >= 0) return !_safeGitMetadata(parts.sublist(gitIndex + 1));
  }
  return (parts.length > 2 &&
          parts.first == 'hosted' &&
          parts[2] == '.cache') ||
      RegExp(r'^caches/modules-2/metadata-[^/]+/[^/]+$').hasMatch(relative) ||
      (relative.startsWith('caches/') && name.endsWith('.lock')) ||
      name.endsWith('.zip.lck') ||
      parts.any(_excluded.contains) ||
      RegExp(
        r'\.(lck|log|tmp|part|lastUpdated)$',
        caseSensitive: false,
      ).hasMatch(name) ||
      name.endsWith('.sha1-in-progress');
}

class MigrationFile {
  MigrationFile(
    this.kind,
    this.relative,
    this.source,
    this.size,
    this.sha256, [
    this.executable = false,
  ]);
  final String kind, relative, source, sha256;
  final int size;
  final bool executable;
  Map<String, Object> toJson() => {
    'kind': kind,
    'path': relative,
    'size': size,
    'sha256': sha256,
    'executable': executable,
  };
}

class _Inventory {
  final files = <MigrationFile>[];
  final warnings = <String>[];
  final _keys = <String, String>{};
  void add(String kind, String root, {String relative = ''}) {
    if (!_kinds.contains(kind)) _fail('未知依赖类型。');
    if (!_dir(root)) return;
    final canonical = Directory(root).resolveSymbolicLinksSync();
    _visit(
      kind,
      canonical,
      relative.isEmpty ? root : _join(root, relative),
      relative,
      {},
    );
  }

  void _visit(
    String kind,
    String root,
    String physicalInput,
    String relative,
    Set<String> ancestors,
  ) {
    if (relative.isNotEmpty && _ignore(relative, kind: kind)) return;
    var physical = physicalInput;
    var type = _type(physical);
    if (kind == 'pub-cache' &&
        relative.endsWith('/.git') &&
        type == FileSystemEntityType.file) {
      warnings.add('$kind/$relative：旧机器 Git worktree 指针未导入。');
      return;
    }
    if (type == FileSystemEntityType.notFound) return;
    if (type == FileSystemEntityType.link) {
      try {
        physical = Link(physical).resolveSymbolicLinksSync();
      } on FileSystemException {
        warnings.add('$kind/$relative：跳过失效符号链接。');
        return;
      }
      if (!_inside(physical, root) || ancestors.contains(physical)) {
        warnings.add('$kind/$relative：跳过包外或循环符号链接；不会复制旧机器路径。');
        return;
      }
      type = _type(physical);
    }
    if (type == FileSystemEntityType.directory) {
      final real = Directory(physical).resolveSymbolicLinksSync();
      if (ancestors.contains(real)) {
        warnings.add('$kind/$relative：跳过循环目录。');
        return;
      }
      for (final item in Directory(physical).listSync(followLinks: false)) {
        _visit(
          kind,
          root,
          item.path,
          relative.isEmpty ? _name(item.path) : '$relative/${_name(item.path)}',
          {...ancestors, real},
        );
      }
    } else if (type == FileSystemEntityType.file) {
      if (_gitConfigPath(kind, relative) && !_safeGitConfig(physical)) {
        warnings.add(
          '$kind/$relative：Git 配置含未知／认证／命令项，未迁移；该 Git 缓存可能需要原仓权限或源码快照。',
        );
        return;
      }
      final safe = _path(relative);
      final key = '$kind/$safe'.toLowerCase();
      if (_keys.containsKey(key)) {
        if (_keys[key] == physical) return;
        _fail('来源包含同名或大小写冲突：$kind/$safe');
      }
      _keys[key] = physical;
      final before = File(physical).statSync();
      final digest = _hash(physical);
      final after = File(physical).statSync();
      if (before.size != after.size ||
          before.modified != after.modified ||
          before.changed != after.changed ||
          !_file(physical))
        _fail('盘点过程中来源发生变化：$kind/$safe');
      files.add(
        MigrationFile(
          kind,
          safe,
          physical,
          after.size,
          digest,
          !Platform.isWindows && (after.mode & 0x49) != 0,
        ),
      );
    } else {
      _fail('来源含特殊文件：$kind/$relative');
    }
  }
}

String _text(String path) {
  if (!_file(path)) return '';
  if (File(path).lengthSync() > 16 * 1024 * 1024) _fail('配置文件过大。');
  return File(path).readAsStringSync();
}

List<File> _configs(String project) {
  final result = <File>[];
  const skip = {
    '.git',
    '.codegraph',
    '.fvm',
    'Pods',
    '.dart_tool',
    '.gradle',
    'build',
    'DerivedData',
    'vendor',
    'node_modules',
    'oh_modules',
    '.jobs',
    '.symlinks',
    'SourcePackages',
    'ephemeral',
  };
  void visit(String directory, int depth) {
    if (depth > 8 || !_dir(directory)) return;
    for (final item in Directory(directory).listSync(followLinks: false)) {
      final name = _name(item.path);
      if (_dir(item.path) && !skip.contains(name)) {
        visit(item.path, depth + 1);
      } else if (_file(item.path) &&
          (name.endsWith('.gradle') ||
              name.endsWith('.gradle.kts') ||
              name == 'Package.resolved')) {
        result.add(File(item.path));
      }
    }
  }

  visit(project, 0);
  return result;
}

// content 过滤器给出了制品组归属；仅有私有仓地址不能证明全部缓存为私库。
Set<String> privateMavenGroups(String project) {
  final result = <String>{};
  for (final file in _configs(project).where(
    (f) => f.path.endsWith('.gradle') || f.path.endsWith('.gradle.kts'),
  )) {
    final text = _text(file.path)
        .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
        .replaceAll(RegExp(r'^\s*//.*$', multiLine: true), '');
    final blocks = RegExp(r'\bmaven\s*\{').allMatches(text);
    for (final match in blocks) {
      var end = match.end;
      var depth = 1;
      while (end < text.length && depth > 0) {
        if (text[end] == '{') depth++;
        if (text[end] == '}') depth--;
        end++;
      }
      if (depth != 0) continue;
      final block = text.substring(match.end, end - 1);
      final urls = RegExp(r'''https?://[^\s"'<>]+''')
          .allMatches(block)
          .map((v) => v.group(0)!);
      final privateRepo = urls.any((url) {
        final host = Uri.tryParse(url)?.host.toLowerCase() ?? '';
        return host.isNotEmpty &&
            !{
              'repo.maven.apache.org',
              'repo1.maven.org',
              'maven.google.com',
              'dl.google.com',
              'plugins.gradle.org',
              'jitpack.io',
              'storage.googleapis.com',
              'mirrors.cloud.tencent.com',
              'maven.aliyun.com',
            }.contains(host);
      });
      if (!privateRepo) continue;
      for (final include in RegExp(
        r'''\bincludeGroup\s*\(\s*["']([A-Za-z0-9_.-]+)["']\s*\)''',
      ).allMatches(block)) {
        result.add(include.group(1)!);
      }
    }
  }
  return result;
}

Set<String> _privatePods(String lock) {
  final result = <String>{};
  var section = '';
  var customRepo = false;
  for (final line in lock.split('\n')) {
    if (line.isNotEmpty && !line.startsWith(' ')) {
      section = line.trim();
      customRepo = false;
      continue;
    }
    if (section == 'EXTERNAL SOURCES:') {
      final match = RegExp(r'^  ([A-Za-z0-9_.+-]+):').firstMatch(line);
      if (match != null) result.add(match.group(1)!);
    }
    if (section == 'SPEC REPOS:') {
      if (line.startsWith('  ') && !line.startsWith('    ')) {
        final value = line.trim().replaceFirst(RegExp(r':$'), '');
        customRepo =
            value != 'trunk' &&
            !value.contains('github.com/CocoaPods/Specs') &&
            !value.contains('cdn.cocoapods.org');
      } else if (customRepo) {
        final match = RegExp(r'^    - ([A-Za-z0-9_.+-]+)').firstMatch(line);
        if (match != null) result.add(match.group(1)!);
      }
    }
  }
  return result;
}

// A generated npm/OHPM lock may have JSON5 comments and trailing commas.
// Only these extensions are accepted; unsupported syntax is reported, not guessed.
String _generatedLockJson(String input) {
  final output = StringBuffer();
  var quoted = false;
  var escaped = false;
  for (var i = 0; i < input.length; i++) {
    final c = input[i];
    if (quoted) {
      output.write(c);
      if (escaped) {
        escaped = false;
      } else if (c == '\\') {
        escaped = true;
      } else if (c == '"') {
        quoted = false;
      }
      continue;
    }
    if (c == '"') {
      quoted = true;
      output.write(c);
      continue;
    }
    if (c == '/' && i + 1 < input.length && input[i + 1] == '/') {
      while (i < input.length && input[i] != '\n') {
        i++;
      }
      output.write('\n');
      continue;
    }
    if (c == '/' && i + 1 < input.length && input[i + 1] == '*') {
      i += 2;
      while (i + 1 < input.length &&
          !(input[i] == '*' && input[i + 1] == '/')) {
        i++;
      }
      if (i + 1 >= input.length) throw const FormatException('锁文件注释未闭合');
      i++;
      output.write(' ');
      continue;
    }
    if (c == ',') {
      var next = i + 1;
      while (next < input.length && input[next].trim().isEmpty) {
        next++;
      }
      if (next < input.length && (input[next] == '}' || input[next] == ']')) {
        continue;
      }
    }
    output.write(c);
  }
  return output.toString();
}

// Custom hosts, Git and local archives are private candidates, not proof of access control.
Set<String> _privateInstalledPaths(String lock, {bool ohpm = false}) {
  final decoded = jsonDecode(_generatedLockJson(lock));
  if (decoded is! Map || decoded['packages'] is! Map) {
    throw const FormatException('仅支持带 packages 解析表的 npm v2/v3 或 OHPM 生成锁文件');
  }
  final result = <String>{};
  final packages = decoded['packages'] as Map;
  for (final entry in packages.entries) {
    if (entry.key is! String || entry.value is! Map) continue;
    final record = entry.value as Map;
    final resolved = record['resolved'];
    if (resolved is! String || resolved.isEmpty) continue;
    final uri = Uri.tryParse(resolved);
    final publicHosts = ohpm
        ? {'ohpm.openharmony.cn', 'repo.harmonyos.com'}
        : {
            'registry.npmjs.org',
            'registry.yarnpkg.com',
            'registry.npmmirror.com',
            'registry.npm.taobao.org',
          };
    final publicArchive =
        uri != null &&
        {'http', 'https'}.contains(uri.scheme) &&
        publicHosts.contains(uri.host.toLowerCase());
    if (publicArchive) continue;
    String relative;
    if (ohpm) {
      if (record['name'] is! String) continue;
      relative = record['name'] as String;
      if (!RegExp(r'^(?:@[A-Za-z0-9_.-]+/)?[A-Za-z0-9_.-]+$')
          .hasMatch(relative)) {
        throw const FormatException('OHPM 锁文件含不安全包名');
      }
    } else {
      final key = entry.key as String;
      if (!key.startsWith('node_modules/')) continue;
      relative = key.substring('node_modules/'.length);
    }
    result.add(_path(relative));
  }
  return result;
}

void _nativeInventory(String project, _Inventory inventory, bool all) {
  final gradle = _cache('gradle');
  final maven = _cache('maven');
  final groups = privateMavenGroups(project);
  if (all) {
    for (final relative in ['caches/modules-2', 'wrapper/dists']) {
      inventory.add('gradle', gradle, relative: relative);
    }
    inventory.add('maven', maven);
    inventory.warnings.add(
      '全量模式包含当前用户共享 Gradle/Maven 制品与分发缓存，可能属于其它工程；不包含 SDK、daemon、init.d 或认证配置。',
    );
  } else {
    for (final group in groups) {
      final path = 'caches/modules-2/files-2.1/$group';
      inventory.add('gradle', gradle, relative: path);
      final caches = _join(gradle, 'caches/modules-2');
      if (_dir(caches)) {
        for (final metadata in Directory(caches).listSync(followLinks: false)) {
          if (_dir(metadata.path) &&
              _name(metadata.path).startsWith('metadata-')) {
            inventory.add(
              'gradle',
              gradle,
              relative:
                  'caches/modules-2/${_name(metadata.path)}/descriptors/$group',
            );
          }
        }
      }
      inventory.add('maven', maven, relative: group.replaceAll('.', '/'));
      if (!_dir(_join(gradle, path)) &&
          !_dir(_join(maven, group.replaceAll('.', '/')))) {
        inventory.warnings.add(
          '已声明私有 Maven 组 $group 在本机 Gradle/Maven 制品缓存中缺失。',
        );
      }
    }
    inventory.warnings.add(
      '私库 Gradle/Maven 仅提取自建仓库 content.includeGroup 明确限定的组；includeGroupByRegex、动态配置、无组归属的缓存无法可靠判定，未提取。私有组可能含多个版本及其它项目制品。',
    );
  }
  for (final platform in ['ios', 'macos']) {
    final pods = _join(project, '$platform/Pods');
    final lock = _text(_join(project, '$platform/Podfile.lock'));
    if (all) {
      inventory.add('pods-$platform', pods);
    } else {
      for (final name in _privatePods(lock)) {
        inventory.add('pods-$platform', pods, relative: name);
        inventory.add(
          'pods-$platform',
          pods,
          relative: 'Local Podspecs/$name.podspec.json',
        );
        if (!_dir(_join(pods, name)))
          inventory.warnings.add(
            '$platform 私有 Pod $name 缺少普通本地源码目录；外部 path/link 需要随工程另行携带。',
          );
      }
    }
    final spm = _join(project, '$platform/SourcePackages');
    if (all) {
      for (final part in ['checkouts', 'artifacts']) {
        inventory.add('spm-$platform', spm, relative: part);
      }
    } else {
      for (final config in _configs(
        _join(project, platform),
      ).where((f) => _name(f.path) == 'Package.resolved')) {
        final data = jsonDecode(_text(config.path));
        final pins = data is Map
            ? (data['pins'] ??
                  (data['object'] is Map ? data['object']['pins'] : null))
            : null;
        if (pins is! List) continue;
        for (final pin in pins.whereType<Map>()) {
          final identity = pin['identity'] ?? pin['package'];
          if (identity is! String ||
              !RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(identity))
            continue;
          final path = 'checkouts/$identity';
          inventory.add('spm-$platform', spm, relative: path);
          inventory.add('spm-$platform', spm, relative: 'artifacts/$identity');
          if (!_dir(_join(spm, path)))
            inventory.warnings.add(
              '$platform SPM $identity 不在工程 SourcePackages/checkouts；Xcode DerivedData 或自定义缓存需另用 SPM 入口提取。',
            );
        }
      }
    }
  }
  final sharedSpm = _join(project, '.jobs/dependencies/spm');
  if (_dir(sharedSpm)) {
    final hasSpmLock =
        _file(_join(sharedSpm, 'Package.resolved')) ||
        _configs(project).any((file) => _name(file.path) == 'Package.resolved');
    if (all || hasSpmLock) {
      for (final part in ['checkouts', 'artifacts']) {
        inventory.add('spm-project', sharedSpm, relative: part);
      }
      if (!all)
        inventory.warnings.add(
          '工程 .jobs/dependencies/spm 已有 Package.resolved 证据；checkouts/artifacts 按 Git 私库候选保留，可能含公开仓库。',
        );
    } else {
      inventory.warnings.add(
        '.jobs/dependencies/spm 存在，但未发现 Package.resolved，私库模式未提取无法核实的缓存。',
      );
    }
  }
  for (final entry in {
    'ohos': 'ohos/oh_modules',
    'web-root': 'node_modules',
    'web': 'web/node_modules',
  }.entries) {
    final root = _join(project, entry.value);
    if (all) {
      inventory.add(entry.key, root);
    } else if (_dir(root)) {
      final lockPath = _join(
        project,
        entry.key == 'ohos'
            ? 'ohos/oh-package-lock.json5'
            : entry.key == 'web'
            ? 'web/package-lock.json'
            : 'package-lock.json',
      );
      final lockText = _text(lockPath);
      if (lockText.isEmpty) {
        inventory.warnings.add(
          '${entry.value} 缺少可识别的 npm v2/v3 或 OHPM 锁文件，私库模式未提取；pnpm/yarn 可使用全量模式。',
        );
      } else {
        try {
          final paths = _privateInstalledPaths(
            lockText,
            ohpm: entry.key == 'ohos',
          );
          for (final path in paths) {
            if (_type(_join(root, path)) == FileSystemEntityType.notFound) {
              inventory.warnings.add('${entry.value}/$path：锁文件私库候选在本机缺失。');
            }
            inventory.add(entry.key, root, relative: path);
          }
        } on FormatException catch (error) {
          inventory.warnings.add(
            '${entry.value} 锁文件格式未支持，私库模式未提取：${error.message}',
          );
        }
      }
    }
  }
  inventory.warnings.add('SPM 当前保留源码／制品，未重建包管理器解析状态，恢复后可能仍需原仓权限。');
  inventory.warnings.add(
    'SPM 的 Git 来源与 Pub Git/path 都按私库候选保留，可能包含公开 Git 仓库或本地开源包；来源类别不能证明访问权限。',
  );
  inventory.warnings.add(
    'CocoaPods 全局下载缓存、Xcode DerivedData、OHPM/npm 全局缓存、SDK/JDK/Android SDK/鸿蒙工具链及认证信息不在本快照中；缺少材料时不能承诺完整离线构建。',
  );
}

String _digest(String value) {
  final hash = _Sha256();
  hash.add(utf8.encode(value));
  return hash.finish();
}

bool _evidencePath(String path) =>
    path.endsWith('.gradle') ||
    path.endsWith('.gradle.kts') ||
    path.endsWith('/Package.resolved') ||
    {
      'ohos/oh-package.json5',
      'ohos/oh-package-lock.json5',
      'package.json',
      'package-lock.json',
      'web/package.json',
      'web/package-lock.json',
      '.jobs/dependencies/spm/Package.resolved',
    }.contains(path) ||
    ({'android', 'ios', 'macos'}.contains(path.split('/').first) &&
        (path.endsWith('.gradle') ||
            path.endsWith('.gradle.kts') ||
            path.endsWith('/gradle-wrapper.properties') ||
            path.endsWith('/Podfile') ||
            path.endsWith('/Podfile.lock') ||
            path.endsWith('/Package.resolved')));

Map<String, String> _projectEvidence(String project, Set<String> kinds) {
  final paths = <String>{};
  if (kinds.contains('gradle') || kinds.contains('maven')) {
    paths.add('android/gradle/wrapper/gradle-wrapper.properties');
    paths.addAll(
      _configs(project)
          .where(
            (file) =>
                file.path.endsWith('.gradle') ||
                file.path.endsWith('.gradle.kts'),
          )
          .map(
            (file) => file.path
                .substring(project.length + 1)
                .replaceAll(Platform.pathSeparator, '/'),
          ),
    );
  }
  for (final platform in ['ios', 'macos']) {
    if (kinds.contains('pods-$platform'))
      paths.addAll(['$platform/Podfile', '$platform/Podfile.lock']);
  }
  if (kinds.any((kind) => kind.startsWith('spm-'))) {
    paths.add('.jobs/dependencies/spm/Package.resolved');
    paths.addAll(
      _configs(project)
          .where((file) => _name(file.path) == 'Package.resolved')
          .map(
            (file) => file.path
                .substring(project.length + 1)
                .replaceAll(Platform.pathSeparator, '/'),
          ),
    );
  }
  if (kinds.contains('ohos'))
    paths.addAll(['ohos/oh-package.json5', 'ohos/oh-package-lock.json5']);
  if (kinds.contains('web-root'))
    paths.addAll(['package.json', 'package-lock.json']);
  if (kinds.contains('web'))
    paths.addAll(['web/package.json', 'web/package-lock.json']);
  final sorted = paths.toList()..sort();
  return {
    for (final path in sorted)
      path: _file(_join(project, path))
          ? _hash(_join(project, path))
          : 'absent',
  };
}

void _checkEvidence(String project, Object? evidence) {
  if (evidence is! Map) _fail('快照缺少原生依赖的工程声明指纹。');
  for (final entry in evidence.entries) {
    final path = _path(entry.key);
    if (!_evidencePath(path) ||
        entry.value is! String ||
        (entry.value != 'absent' &&
            !RegExp(r'^[0-9a-f]{64}$').hasMatch(entry.value)))
      _fail('工程声明指纹无效。');
    final target = _join(project, path);
    if (entry.value == 'absent') {
      if (_type(target) != FileSystemEntityType.notFound)
        _fail('目标新增了与快照不一致的原生配置：$path');
    } else {
      _validateSourceFile(
        project,
        path,
        File(target).existsSync() ? File(target).lengthSync() : -1,
        entry.value,
      );
    }
  }
}

String migrationPlanDigest(MigrationPlan plan) {
  final nativeStamps = plan.stamps.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return _digest(
    jsonEncode({
      'project': plan.project,
      'source': plan.source,
      'files': plan.files.map((file) => file.toJson()).toList(),
      'writes': plan.writes.map((file) => file.toJson()).toList(),
      'reused': plan.reused,
      'stamps': {for (final entry in nativeStamps) entry.key: entry.value},
      'pubSnapshots': plan.pubPlan == null
          ? null
          : {
              for (final item in plan.pubPlan!.snapshots)
                item.file.path: _digest(base64Encode(item.bytes)),
              if (plan.pubPlan!.originalOverrides != null)
                plan.pubPlan!.originalOverrides!.file.path: _digest(
                  base64Encode(plan.pubPlan!.originalOverrides!.bytes),
                ),
            },
      'pubFiles': plan.pubPlan == null
          ? null
          : [
              for (final package in plan.pubPlan!.packages)
                for (final file in package.files)
                  {
                    'package': package.name,
                    'path': file.relative,
                    'sha256': _hash(file.path),
                  },
            ],
    }),
  );
}

String exportMigration(
  String projectInput,
  String destinationInput, {
  bool all = false,
}) {
  final project = _absolute(projectInput);
  restoring.requireFlutter(_text(_join(project, 'pubspec.yaml')), '所选工程');
  final destination = _absolute(destinationInput);
  if (_inside(destination, project) || _inside(project, destination))
    _fail('输出父目录不能与工程相互包含。');
  for (final kind in ['pub-cache', 'gradle', 'maven']) {
    final root = _cache(kind);
    if (_inside(destination, root) || _inside(root, destination))
      _fail('输出父目录不能与缓存相互包含。');
  }
  final staging = Directory(destination)
      .createTempSync('.FlutterMigration-incomplete-');
  var published = false;
  try {
    final evidenceBefore = _projectEvidence(project, _kinds);
    final inventory = _Inventory();
    _nativeInventory(project, inventory, all);
    String? pubSnapshot;
    final lockText = _text(_join(project, 'pubspec.lock'));
    if (!all && lockText.isNotEmpty) {
      final pathCount = pub
          .lockPackages(lockText)
          .values
          .where((record) => record['source'] == 'path')
          .length;
      if (pathCount > 0)
        inventory.warnings.add(
          '本地 path 私库候选 $pathCount 个，可能包含此前本地化的公共包；私库模式不会凭目录名把它们剔除。',
        );
    }

    final hasPub =
        all ||
        (lockText.isNotEmpty && pub.privatePackageNames(lockText).isNotEmpty);
    if (hasPub) {
      pub.extract(project, staging.path, privateOnly: !all);
      final children = staging
          .listSync(followLinks: false)
          .whereType<Directory>()
          .toList();
      if (children.length != 1) _fail('Pub 提取未生成唯一快照。');
      pubSnapshot = _name(children.single.path);
    } else {
      inventory.warnings.add(
        '没有已解析的私有 Pub 候选；未生成 Pub 源码快照。缺少 pubspec.lock 时无法识别 Pub 私库。',
      );
    }
    final records = <Map<String, Object>>[];
    for (final item in inventory.files) {
      final relative = 'payload/${item.kind}/${item.relative}';
      final file = File(_join(staging.path, relative));
      file.parent.createSync(recursive: true);
      File(item.source).copySync(file.path);
      if (_hash(file.path) != item.sha256 || _hash(item.source) != item.sha256)
        _fail('复制期间源文件变化：${item.kind}/${item.relative}');
      records.add({...item.toJson(), 'storedPath': relative});
    }
    final pubRecords = <Map<String, Object>>[];
    if (pubSnapshot != null) {
      for (final item in restoring.inventory(
        _join(staging.path, pubSnapshot),
      )) {
        pubRecords.add({
          'path': '$pubSnapshot/${item.relative}',
          'size': item.stat.size,
          'sha256': _hash(item.path),
        });
      }
    }
    if (jsonEncode(evidenceBefore) !=
        jsonEncode(_projectEvidence(project, _kinds)))
      _fail('提取期间原生声明或锁文件发生变化。');
    final evidence = _projectEvidence(
      project,
      inventory.files.map((file) => file.kind).toSet(),
    );
    final warnings = inventory.warnings.toSet().toList();
    File(_join(staging.path, 'migration.json')).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({'format': migrationFormat, 'version': 1, 'status': 'complete', 'scope': all ? 'all' : 'private-candidates', 'hostOS': Platform.operatingSystem, 'hostArchitecture': Platform.version.split(' on ').last, 'createdAt': DateTime.now().toUtc().toIso8601String(), 'projectFiles': evidence, 'pubSnapshot': pubSnapshot, 'pubFiles': pubRecords, 'files': records, 'warnings': warnings})}\n',
    );
    File(_join(staging.path, 'README.md')).writeAsStringSync('''# Flutter 依赖迁移快照

范围：${all ? '全部已解析 Pub 包及已发现的平台依赖／共享缓存' : '私库候选'}。Pub 源码和平台缓存分别记录，逐文件 SHA-256 位于 migration.json。
导入需先审阅计划，再明确确认；同名不同内容会阻止整个写入，不覆盖现有环境。
SDK、JDK、平台工具链、凭据、签名与私库权限需要在目标电脑独立准备。架构相关包不保证跨系统／架构可用。
Git/path/自建源只代表私库候选，无法证明访问权限；无法识别的来源和未找到的材料见下列告警。

${warnings.map((w) => '- $w').join('\n')}
''');
    final finalPath = _join(
      destination,
      'FlutterMigration-${DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[^0-9]'), '')}-${_name(staging.path).split('-').last}',
    );
    if (_type(finalPath) != FileSystemEntityType.notFound) _fail('输出目录已存在。');
    staging.renameSync(finalPath);
    published = true;
    for (final warning in warnings) stdout.writeln('⚠ $warning');
    stdout.writeln(
      '✔ 一键提取完成：${inventory.files.length} 个平台／缓存文件${pubSnapshot == null ? '' : ' + Pub 源码快照'}。',
    );
    stdout.writeln('JOBS_MIGRATION_OUTPUT=$finalPath');
    return finalPath;
  } finally {
    if (!published) stderr.writeln('✖ 提取未完成，保留半成品供排查：${staging.path}');
  }
}

class MigrationPlan {
  MigrationPlan(
    this.project,
    this.source,
    this.files,
    this.warnings,
    this.pubPlan,
    this.stamps,
  );
  final String project, source;
  final List<MigrationFile> files;
  final List<String> warnings;
  final restoring.ImportPlan? pubPlan;
  final Map<String, String> stamps;
  final writes = <MigrationFile>[];
  int reused = 0;
  void show() {
    stdout.writeln('来源：$source\n目标工程：$project');
    for (final kind in files.map((f) => f.kind).toSet()) {
      stdout.writeln('➤ $kind → ${_target(project, kind)}');
    }
    stdout.writeln('计划：新增 ${writes.length} 文件，复用 $reused 文件；原有不同内容冲突会阻止全部写入。');
    if (pubPlan != null) restoring.showPlan(pubPlan!);
    for (final warning in warnings.toSet()) stdout.writeln('⚠ $warning');
  }
}

void _validateParents(String absolute) {
  var current = Directory(absolute).parent.path;
  while (Directory(current).parent.path != current) {
    final type = _type(current);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory)
      _fail('目标父目录含链接或文件：$current');
    current = Directory(current).parent.path;
  }
}

bool _pubSnapshot(String root) =>
    _file(_join(root, 'manifest.json')) &&
    _dir(_join(root, 'packages')) &&
    _file(_join(root, 'pubspec.yaml'));
void _raw(String root, _Inventory inventory) {
  final gradle =
      _dir(_join(root, 'caches/modules-2')) ||
      _dir(_join(root, 'wrapper/dists'));
  final pubCache =
      _dir(_join(root, 'hosted')) ||
      (_dir(_join(root, 'git')) &&
          Directory(_join(root, 'git'))
              .listSync(followLinks: false)
              .any(
                (e) => _dir(e.path) && _file(_join(e.path, 'pubspec.yaml')),
              ));
  if (gradle && pubCache) _fail('单个目录同时具有 Gradle 和 Pub 缓存特征，来源含混，未写入。');
  if (gradle) {
    for (final relative in ['caches/modules-2', 'wrapper/dists'])
      inventory.add('gradle', root, relative: relative);
  }
  if (pubCache) {
    for (final relative in ['hosted', 'hosted-hashes', 'git'])
      inventory.add('pub-cache', root, relative: relative);
  }
}

restoring.ImportPlan _restorePlan(String project, String source) {
  final manifest = jsonDecode(_text(_join(source, 'manifest.json')));
  final privateOnly =
      manifest is Map &&
      manifest['snapshotKind'] == 'flutter-private-dependencies';
  return restoring.validate(project, source, privateOnly: privateOnly);
}

MigrationPlan planMigrationImport(String projectInput, String sourceInput) {
  final project = _absolute(projectInput);
  restoring.requireFlutter(_text(_join(project, 'pubspec.yaml')), '目标工程');
  final source = _absolute(sourceInput);
  if (_inside(source, project) || _inside(project, source))
    _fail('导入来源不能与工程相互包含。');
  final inventory = _Inventory();
  final stamps = <String, String>{
    _join(project, 'pubspec.yaml'): _hash(_join(project, 'pubspec.yaml')),
  };
  restoring.ImportPlan? pubPlan;
  final manifest = _join(source, 'migration.json');
  if (_file(manifest)) {
    final data = jsonDecode(_text(manifest));
    if (data is! Map ||
        data['format'] != migrationFormat ||
        data['version'] != 1 ||
        data['status'] != 'complete' ||
        data['files'] is! List ||
        data['pubFiles'] is! List ||
        data['warnings'] is! List)
      _fail('迁移清单格式无效或快照未完成。');
    stamps[manifest] = _hash(manifest);
    _checkEvidence(project, data['projectFiles']);
    for (final entry in (data['projectFiles'] as Map).entries) {
      stamps[_join(project, entry.key)] = entry.value;
    }
    final seen = <String>{};
    final expected = <String>{'migration.json', 'README.md'};
    for (final row in data['files'] as List) {
      if (row is! Map ||
          !_kinds.contains(row['kind']) ||
          row['size'] is! int ||
          row['size'] < 0 ||
          row['executable'] is! bool ||
          row['sha256'] is! String ||
          !RegExp(r'^[0-9a-f]{64}$').hasMatch(row['sha256']))
        _fail('迁移文件清单项无效。');
      final kind = row['kind'] as String;
      final relative = _path(row['path']);
      if (_ignore(relative, kind: kind)) _fail('快照含禁止导入的配置或认证文件。');
      if (kind == 'gradle' &&
          !(relative.startsWith('caches/modules-2/') ||
              relative.startsWith('wrapper/dists/')))
        _fail('Gradle 快照越出允许缓存范围。');
      if (kind == 'pub-cache' &&
          !['hosted/', 'hosted-hashes/', 'git/'].any(relative.startsWith))
        _fail('Pub 缓存快照越出允许范围。');
      final stored = _path(row['storedPath']);
      if (stored != 'payload/$kind/$relative' ||
          !seen.add('$kind/$relative'.toLowerCase()))
        _fail('迁移清单路径冲突。');
      if (_nonportable.contains(kind) &&
          (data['hostOS'] != Platform.operatingSystem ||
              data['hostArchitecture'] != Platform.version.split(' on ').last))
        _fail('平台依赖快照来自不同系统／架构；请在目标系统重新解析，不导入本机原生包。');
      final physical = _join(source, stored);
      _validateSourceFile(
        source,
        stored,
        row['size'] as int,
        row['sha256'] as String,
      );
      if (_gitConfigPath(kind, relative) && !_safeGitConfig(physical))
        _fail('快照含不安全或带认证的 Git 配置。');
      expected.add(stored);
      inventory.files.add(
        MigrationFile(
          kind,
          relative,
          physical,
          row['size'],
          row['sha256'],
          row['executable'],
        ),
      );
    }
    for (final row in data['pubFiles'] as List) {
      if (row is! Map || row['size'] is! int || row['sha256'] is! String)
        _fail('Pub 文件清单无效。');
      final relative = _path(row['path']);
      _validateSourceFile(source, relative, row['size'], row['sha256']);
      if (!expected.add(relative)) _fail('Pub 清单路径重复。');
    }
    final allFiles = restoring.inventory(source);
    if (allFiles.any((f) => !expected.contains(f.relative)) ||
        expected.length != allFiles.length)
      _fail('快照存在额外或缺失文件，未写入。');
    final pubRelative = data['pubSnapshot'];
    if (pubRelative != null) {
      final relative = _path(pubRelative);
      if (relative.contains('/') || !_pubSnapshot(_join(source, relative)))
        _fail('Pub 快照路径无效。');
      pubPlan = _restorePlan(project, _join(source, relative));
    } else if ((data['pubFiles'] as List).isNotEmpty) {
      _fail('Pub 快照清单不完整。');
    }
    inventory.warnings.addAll((data['warnings'] as List).whereType<String>());
  } else {
    final roots = <String>[source];
    if (!_pubSnapshot(source)) {
      roots.addAll(
        Directory(source)
            .listSync(followLinks: false)
            .where((e) => _dir(e.path))
            .map((e) => e.path),
      );
    }
    final snapshots = <String>[];
    for (final root in roots) {
      if (_pubSnapshot(root)) snapshots.add(root);
      _raw(root, inventory);
    }
    if (snapshots.length > 1) _fail('来源含多个 Pub 源码快照，请选中确切一个快照或只含缓存的目录。');
    if (snapshots.length == 1)
      pubPlan = _restorePlan(project, snapshots.single);
    if (inventory.files.isEmpty && pubPlan == null)
      _fail('未按内容识别到 Gradle、Pub 缓存或本工具的 Pub 源码快照。');
    inventory.warnings.add('原始缓存无来源清单，无法区分私库／公库；导入所选目录中允许的全部缓存制品，可能包含其它工程依赖。');
    inventory.warnings.add(
      'Git 缓存仅保留源码及 objects/refs/HEAD/index 等解析必需数据；不导入含认证或未知键的 Git config、hooks/alternates/旧 worktree 指针及凭据、Gradle daemon/init.d/全局配置、transforms 或构建锁；缺失 Git 对象时仍需原仓权限或 Pub 源码快照。',
    );
  }
  inventory.files.sort(
    (a, b) => '${a.kind}/${a.relative}'.compareTo('${b.kind}/${b.relative}'),
  );
  final plan = MigrationPlan(
    project,
    source,
    inventory.files,
    inventory.warnings,
    pubPlan,
    stamps,
  );
  final destinations = <String>{};
  final conflicts = <String>[];
  for (final item in plan.files) {
    final root = _target(project, item.kind);
    if (_inside(root, source) || _inside(source, root)) _fail('导入源与目标缓存相互包含。');
    final target = _join(root, item.relative);
    if (!destinations.add(target.toLowerCase())) _fail('多个来源写入同一目标。');
    _validateParents(target);
    if (_type(root) != FileSystemEntityType.notFound && !_dir(root))
      _fail('目标缓存不是普通目录。');
    final type = _type(target);
    if (type == FileSystemEntityType.notFound) {
      plan.writes.add(item);
    } else if (type == FileSystemEntityType.file &&
        File(target).lengthSync() == item.size &&
        _hash(target) == item.sha256) {
      plan.reused++;
    } else {
      conflicts.add('${item.kind}/${item.relative}');
    }
  }
  if (conflicts.isNotEmpty)
    _fail(
      '发现 ${conflicts.length} 个同名不同内容或类型冲突，整个导入未写入；请先处理冲突：\n${conflicts.take(20).join('\n')}',
    );
  return plan;
}

void _validateSourceFile(
  String root,
  String relative,
  int size,
  String digest,
) {
  var current = root;
  for (final part in relative.split('/')) {
    current = _join(current, part);
    if (_type(current) == FileSystemEntityType.link)
      _fail('来源路径包含链接：$relative');
  }
  if (!_file(current) ||
      File(current).lengthSync() != size ||
      _hash(current) != digest)
    _fail('来源文件缺失或 SHA-256 不符：$relative');
}

Set<String> _gitRootRelatives(List<MigrationFile> files) {
  final roots = <String>{};
  for (final file in files.where((file) => file.kind == 'pub-cache')) {
    final parts = file.relative.split('/');
    if (parts.length > 3 && parts[0] == 'git' && parts[1] == 'cache')
      roots.add(parts.take(3).join('/'));
    final git = parts.indexOf('.git');
    if (parts.first == 'git' && git >= 0)
      roots.add(parts.take(git + 1).join('/'));
  }
  return roots;
}

void executeMigrationImport(MigrationPlan plan, {bool revalidate = true}) {
  // 写入前重新生成完整计划，防止确认期间环境和来源发生变化。
  final fresh = revalidate
      ? planMigrationImport(plan.project, plan.source)
      : plan;
  String signature(MigrationPlan p) =>
      jsonEncode(p.files.map((f) => f.toJson()).toList());
  if (signature(fresh) != signature(plan) ||
      jsonEncode(fresh.stamps) != jsonEncode(plan.stamps))
    _fail('确认期间来源发生变化，请重新预检。');
  final copied = <MigrationFile>[];
  try {
    for (final item in fresh.writes) {
      _validateSourceFile(
        Directory(item.source).parent.path,
        _name(item.source),
        item.size,
        item.sha256,
      );
      final target = _join(_target(plan.project, item.kind), item.relative);
      _validateParents(target);
      File(target).parent.createSync(recursive: true);
      final destination = File(target)..createSync(exclusive: true);
      copied.add(item);
      final input = File(item.source).openSync();
      final output = destination.openSync(mode: FileMode.writeOnly);
      try {
        while (true) {
          final bytes = input.readSync(1024 * 1024);
          if (bytes.isEmpty) break;
          output.writeFromSync(bytes);
        }
        output.flushSync();
      } finally {
        input.closeSync();
        output.closeSync();
      }
      if (item.executable && !Platform.isWindows) {
        final mode = Process.runSync('/bin/chmod', ['700', target]);
        if (mode.exitCode != 0) _fail('无法恢复执行权限：${item.kind}/${item.relative}');
      }
      if (_hash(target) != item.sha256 || _hash(item.source) != item.sha256)
        _fail('复制期间来源变化：${item.kind}/${item.relative}');
    }
    // Packed refs repositories still require these empty directories to be recognized by Git.
    for (final gitRoot in _gitRootRelatives(fresh.files)) {
      for (final part in ['objects', 'refs']) {
        final path = _join(_cache('pub-cache'), '$gitRoot/$part');
        _validateParents(_join(path, 'placeholder'));
        if (_type(path) != FileSystemEntityType.notFound && !_dir(path))
          _fail('Git 元数据目录类型冲突。');
        Directory(path).createSync(recursive: true);
      }
    }
    if (fresh.pubPlan != null) restoring.execute(fresh.pubPlan!);
  } catch (_) {
    // 只撤回本进程新增且内容仍未被其它程序修改的缓存文件。
    for (final item in copied.reversed) {
      final target = _join(_target(plan.project, item.kind), item.relative);
      if (_file(target) && _hash(target) == item.sha256)
        File(target).deleteSync();
    }
    rethrow;
  }
  stdout.writeln(
    '✔ 一键导入完成：新增 ${fresh.writes.length} 个缓存／平台文件，复用 ${fresh.reused} 个文件${fresh.pubPlan == null ? '' : '；Pub 源码已按清单配置本地覆盖'}。',
  );
  stdout.writeln('未安装或切换 SDK/JDK，未联网；请用项目对应工具验证依赖解析与构建。');
}

void main(List<String> arguments) {
  try {
    if (arguments.isEmpty || !{'export', 'import'}.contains(arguments.first))
      _fail(
        '用法：FlutterDependencyMigration.dart export --project P --destination D [--all] | import --project P --source S [--apply --expected-plan SHA256]',
      );
    final operation = arguments.first;
    final values = <String, String>{};
    final flags = <String>{};
    for (var index = 1; index < arguments.length; index++) {
      final arg = arguments[index];
      if ({'--all', '--apply'}.contains(arg)) {
        if (!flags.add(arg)) _fail('参数重复。');
      } else if ({
            '--project',
            '--destination',
            '--source',
            '--expected-plan',
          }.contains(arg) &&
          index + 1 < arguments.length &&
          !values.containsKey(arg)) {
        values[arg] = arguments[++index];
      } else {
        _fail('未知、重复或缺值参数：$arg');
      }
    }
    final project = values['--project'];
    if (project == null) _fail('缺少 --project。');
    if (operation == 'export') {
      if (values['--destination'] == null ||
          values.containsKey('--source') ||
          flags.contains('--apply') ||
          values.containsKey('--expected-plan'))
        _fail('提取参数不合法。');
      exportMigration(
        project,
        values['--destination']!,
        all: flags.contains('--all'),
      );
    } else {
      if (values['--source'] == null ||
          values.containsKey('--destination') ||
          flags.contains('--all'))
        _fail('导入参数不合法。');
      final plan = planMigrationImport(project, values['--source']!);
      final digest = migrationPlanDigest(plan);
      if (flags.contains('--apply')) {
        if (values['--expected-plan'] != digest)
          _fail('导入计划与确认前不一致或缺少 --expected-plan；请重新预检确认。');
        executeMigrationImport(plan, revalidate: false);
      } else {
        plan.show();
        stdout.writeln('JOBS_MIGRATION_PLAN=$digest');
      }
    }
  } catch (error) {
    stderr.writeln('✖ 一键迁移失败：$error');
    exitCode = 1;
  }
}

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
