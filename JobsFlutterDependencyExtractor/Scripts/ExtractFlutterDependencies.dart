// Created by Jobs on 2026年10月19日，星期一。
// 从 Pub 已解析的本地路径提取源码；不运行 pub get，不连接网络，不修改项目。
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

const ignoredDirectories = {
  '.git',
  '.dart_tool',
  'node_modules',
  'Pods',
  '.fvm',
  'build',
  'DerivedData',
  '.gradle',
  '.idea',
  '.symlinks',
  '.plugin_symlinks',
};
const generatedDirectorySuffixes = {
  'linux/flutter/ephemeral',
  'windows/flutter/ephemeral',
  'macos/Flutter/ephemeral',
};
final packageNamePattern = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');

Never fail(String message) => throw FormatException(message);

// 只解释 Pub 锁文件及依赖声明使用的映射；未知 YAML 语法明确拒绝。
class YamlEntry {
  YamlEntry(this.indent, this.key, this.value);
  final int indent;
  final String key;
  final String value;
}

List<String> splitYaml(String text, String separator) {
  final result = <String>[];
  var quote = '';
  var depth = 0;
  var start = 0;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (quote.isNotEmpty) {
      if (char == r'\' && quote == '"') {
        i++;
      } else if (char == quote) {
        if (quote == "'" && i + 1 < text.length && text[i + 1] == "'") {
          i++;
        } else {
          quote = '';
        }
      }
    } else if (char == '"' || char == "'") {
      quote = char;
    } else if (char == '{' || char == '[') {
      depth++;
    } else if (char == '}' || char == ']') {
      depth--;
    } else if (char == separator && depth == 0) {
      result.add(text.substring(start, i));
      start = i + 1;
    } else if (char == '#' && (i == 0 || text[i - 1].trim().isEmpty)) {
      text = text.substring(0, i);
      break;
    }
  }
  if (quote.isNotEmpty || depth != 0)
    fail('不支持跨行 flow / 引号 YAML，请使用标准 Pub 块映射。');
  result.add(text.substring(start));
  return result;
}

String scalar(String value) {
  value = splitYaml(value.trim(), '\u0000').single.trim();
  if (value.startsWith('"')) {
    final decoded = jsonDecode(value);
    if (decoded is! String) fail('无效 YAML 字符串。');
    return decoded;
  }
  if (value.startsWith("'") && value.endsWith("'")) {
    return value.substring(1, value.length - 1).replaceAll("''", "'");
  }
  if (value.startsWith('&') || value.startsWith('*') || value.startsWith('!')) {
    fail('依赖映射不支持 YAML anchor / tag；请展开后重试。');
  }
  return value;
}

Map<String, String> flowMapping(String value) {
  value = value.trim();
  if (!value.startsWith('{') || !value.endsWith('}')) fail('需要 YAML 映射。');
  final output = <String, String>{};
  for (final item in splitYaml(value.substring(1, value.length - 1), ',')) {
    if (item.trim().isEmpty) continue;
    final parts = splitYaml(item, ':');
    if (parts.length < 2) fail('无效 flow 映射。');
    final key = scalar(parts.first);
    if (output.containsKey(key)) fail('重复 YAML 键：$key');
    output[key] = parts.skip(1).join(':').trim();
  }
  return output;
}

List<YamlEntry> yamlEntries(String text) {
  final entries = <YamlEntry>[];
  for (var line in const LineSplitter().convert(
    text.replaceFirst('\uFEFF', ''),
  )) {
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    final indent = line.length - line.trimLeft().length;
    if (line.substring(0, indent).contains('\t')) fail('YAML 缩进不能包含 Tab。');
    line = line.substring(indent);
    // 块字符串和序列正文不是映射；依赖区若使用它们，会在 section 中拒绝。
    final match = RegExp(
      r'''^("[^"]*"|'[^']*'|[A-Za-z0-9_.$-]+):(?:\s+(.*)|$)''',
    ).firstMatch(line);
    entries.add(
      match == null
          ? YamlEntry(indent, '', line)
          : YamlEntry(indent, scalar(match[1]!), (match[2] ?? '').trim()),
    );
  }
  return entries;
}

String topScalar(String text, String key) {
  final matches = yamlEntries(text)
      .where((e) => e.indent == 0 && e.key == key)
      .toList();
  if (matches.length > 1) fail('重复顶层键：$key');
  return matches.isEmpty ? '' : scalar(matches.single.value);
}

Map<String, String> section(String text, String key) {
  final entries = yamlEntries(text);
  final positions = <int>[];
  for (var i = 0; i < entries.length; i++) {
    if (entries[i].indent == 0 && entries[i].key == key) positions.add(i);
  }
  if (positions.isEmpty) return {};
  if (positions.length != 1) fail('重复 YAML 区域：$key');
  final start = positions.single;
  final inline = splitYaml(entries[start].value, '\u0000').single.trim();
  if (inline == 'null' || inline == '~') return {};
  if (inline.isNotEmpty) return flowMapping(inline);
  var end = start + 1;
  while (end < entries.length && entries[end].indent > 0) {
    end++;
  }
  if (end == start + 1) return {};
  final childIndent = entries
      .sublist(start + 1, end)
      .map((e) => e.indent)
      .reduce((a, b) => a < b ? a : b);
  final output = <String, String>{};
  for (var i = start + 1; i < end; i++) {
    final entry = entries[i];
    if (entry.indent != childIndent) continue;
    if (entry.key.isEmpty || entry.key == '<<' || output.containsKey(entry.key))
      fail('无效或重复依赖映射：$key');
    if (entry.value.isNotEmpty) {
      output[entry.key] = splitYaml(entry.value, '\u0000').single.trim();
    } else {
      final fields = <String>[];
      var j = i + 1;
      final fieldStart = j;
      while (j < end && entries[j].indent > childIndent) {
        j++;
      }
      if (j > fieldStart) {
        final fieldIndent = entries
            .sublist(fieldStart, j)
            .map((field) => field.indent)
            .reduce((a, b) => a < b ? a : b);
        for (final field in entries.sublist(fieldStart, j)) {
          if (field.indent == fieldIndent && field.key.isNotEmpty)
            fields.add('${field.key}: ${field.value}');
        }
      }
      output[entry.key] = '{${fields.join(', ')}}';
    }
  }
  return output;
}

bool sdkDependency(String value) =>
    value.trim().startsWith('{') && flowMapping(value).containsKey('sdk');

bool hasTopKey(String text, String key) =>
    yamlEntries(text).any((entry) => entry.indent == 0 && entry.key == key);

// 只解释标准成员路径列表，避免将复杂 YAML 猜测为成员身份。
List<String> workspacePatterns(String text) {
  final lines = const LineSplitter().convert(text);
  final positions = <int>[];
  for (var i = 0; i < lines.length; i++) {
    if (RegExp(r'''^(workspace|"workspace"|'workspace')\s*:''')
        .hasMatch(lines[i]))
      positions.add(i);
  }
  if (positions.isEmpty) return [];
  if (positions.length != 1) fail('重复 workspace 声明。');
  final index = positions.single;
  final inline = splitYaml(
    lines[index].substring(lines[index].indexOf(':') + 1),
    '\u0000',
  ).single.trim();
  if (inline.isNotEmpty) {
    if (!inline.startsWith('[') || !inline.endsWith(']'))
      fail('workspace 需要路径列表。');
    return splitYaml(
      inline.substring(1, inline.length - 1),
      ',',
    ).where((item) => item.trim().isNotEmpty).map(scalar).toList();
  }
  final paths = <String>[];
  for (var i = index + 1; i < lines.length; i++) {
    final line = lines[i];
    if (line.trim().isEmpty || line.trimLeft().startsWith('#')) continue;
    if (!line.startsWith(' ')) break;
    final match = RegExp(r'^\s+-\s+(.+)$').firstMatch(line);
    if (match == null) fail('不支持的 workspace 列表语法。');
    paths.add(scalar(match[1]!));
  }
  return paths;
}

RegExp workspaceGlob(String pattern) {
  if (pattern.isEmpty ||
      pattern.startsWith('/') ||
      pattern.contains('\\') ||
      pattern.split('/').any((part) => part == '..' || part == '.') ||
      RegExp(r'[\[\]{}:]').hasMatch(pattern)) {
    fail('不支持的 workspace 路径模式：$pattern；请使用相对路径及 * / ** / ?。');
  }
  final output = StringBuffer('^');
  for (var i = 0; i < pattern.length; i++) {
    if (pattern[i] == '*' && i + 1 < pattern.length && pattern[i + 1] == '*') {
      i++;
      if (i + 1 < pattern.length && pattern[i + 1] == '/') {
        i++;
        output.write('(?:.*/)?');
      } else {
        output.write('.*');
      }
    } else if (pattern[i] == '*') {
      output.write('[^/]*');
    } else if (pattern[i] == '?') {
      output.write('[^/]');
    } else {
      output.write(RegExp.escape(pattern[i]));
    }
  }
  output.write(r'$');
  return RegExp(output.toString(), caseSensitive: !Platform.isWindows);
}

class Snapshot {
  Snapshot(this.file) : bytes = file.readAsBytesSync();
  final File file;
  final List<int> bytes;
  String get text => utf8.decode(bytes);
  void verify() {
    if (!file.existsSync() ||
        base64Encode(bytes) != base64Encode(file.readAsBytesSync())) {
      fail('提取期间元数据发生变化，请停止依赖安装 / 编辑后重试：${file.path}');
    }
  }
}

Snapshot readSnapshot(String path) {
  if (FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.file)
    fail('缺少普通元数据文件：$path\n请先在项目中执行 flutter pub get。');
  if (File(path).lengthSync() > 16 * 1024 * 1024) fail('元数据文件过大：$path');
  return Snapshot(File(path));
}

String join(String parent, String child) =>
    '${parent.replaceFirst(RegExp(r'[/\\]+$'), '')}${Platform.pathSeparator}$child';
String canonical(String path) => Directory(path).resolveSymbolicLinksSync();
String pathKey(String path) => Platform.isWindows ? path.toLowerCase() : path;
bool inside(String child, String parent) =>
    pathKey(child) == pathKey(parent) ||
    pathKey(child).startsWith('${pathKey(parent)}${Platform.pathSeparator}');

class Package {
  Package(
    this.name,
    this.source,
    this.version,
    this.dependency,
    this.root,
    this.manifest,
  );
  final String name, source, version, dependency, root;
  final Snapshot manifest;
  final files = <CopyItem>[];
  final warnings = <String>[];
}

class CopyItem {
  CopyItem(this.source, this.relative, this.stat);
  final String source, relative;
  final FileStat stat;
}

bool generatedDirectory(String relative) {
  final parts = relative.split(Platform.pathSeparator);
  if (parts.length < 3) return false;
  return generatedDirectorySuffixes.contains(
    parts.sublist(parts.length - 3).join('/'),
  );
}

void skipEntry(Package package, String relative, String reason) {
  final warning = '${package.name}/$relative：$reason，已跳过';
  package.warnings.add(warning);
  stdout.writeln('⚠ $warning');
}

// 检查真实路径，避免链接指向生成目录的父层后，经别名带入构建缓存。
bool excludedSourcePath(String source, String root) {
  if (source == root) return false;
  final parts = source.substring(root.length + 1).split(Platform.pathSeparator);
  for (var i = 0; i < parts.length; i++) {
    if (ignoredDirectories.contains(parts[i]) ||
        generatedDirectory(parts.take(i + 1).join(Platform.pathSeparator))) {
      return true;
    }
  }
  return false;
}

// 包内有效链接物化；无法解析、包外或循环链接只告警，不中断其它源码提取。
void inventory(
  Package package,
  String directory,
  String relative,
  Set<String> ancestors,
) {
  final resolved = canonical(directory);
  if (!inside(resolved, package.root))
    fail('${package.name} 含包外符号链接：$relative');
  if (ancestors.contains(pathKey(resolved)))
    fail('${package.name} 含循环符号链接：$relative');
  final next = {...ancestors, pathKey(resolved)};
  for (final entity in Directory(directory).listSync(followLinks: false)) {
    final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
    final targetRelative = relative.isEmpty ? name : join(relative, name);
    var type = FileSystemEntity.typeSync(entity.path, followLinks: false);
    if (ignoredDirectories.contains(name) ||
        generatedDirectory(targetRelative)) {
      if (name == '.plugin_symlinks' || generatedDirectory(targetRelative)) {
        skipEntry(package, targetRelative, 'Flutter 生成目录');
      }
      continue;
    }
    var source = entity.path;
    if (type == FileSystemEntityType.link) {
      try {
        source = entity.resolveSymbolicLinksSync();
      } on FileSystemException {
        skipEntry(package, targetRelative, '无法解析的符号链接（目标缺失、循环或不可访问）');
        continue;
      }
      if (!inside(source, package.root)) {
        skipEntry(package, targetRelative, '指向包外的符号链接');
        continue;
      }
      if (next.contains(pathKey(source))) {
        skipEntry(package, targetRelative, '循环符号链接');
        continue;
      }
      type = FileSystemEntity.typeSync(source);
    }
    if (excludedSourcePath(source, package.root)) {
      skipEntry(package, targetRelative, '真实路径位于缓存或构建目录');
      continue;
    }
    if (type == FileSystemEntityType.directory) {
      inventory(package, source, targetRelative, next);
    } else if (type == FileSystemEntityType.file) {
      package.files.add(
        CopyItem(source, targetRelative, File(source).statSync()),
      );
    } else {
      fail('${package.name} 含不支持的特殊文件：$targetRelative');
    }
  }
}

Map<String, Map<String, String>> lockPackages(String text) {
  final entries = yamlEntries(text);
  final result = <String, Map<String, String>>{};
  var inPackages = false;
  String? current;
  for (final entry in entries) {
    if (entry.indent == 0) {
      inPackages = entry.key == 'packages';
      current = null;
      if (inPackages && entry.value.isNotEmpty && entry.value != '{}')
        fail('锁文件 packages 必须为 Pub 标准块映射。');
    } else if (inPackages && entry.indent == 2) {
      current = entry.key;
      if (!packageNamePattern.hasMatch(current) || result.containsKey(current))
        fail('锁文件含非法或重复包名。');
      result[current] = {};
    } else if (inPackages && entry.indent == 4 && current != null) {
      if (result[current]!.containsKey(entry.key)) fail('锁文件含重复字段。');
      result[current]![entry.key] = scalar(entry.value);
    } else if (inPackages && entry.indent == 6 && current != null) {
      result[current]!['description.${entry.key}'] = scalar(entry.value);
    }
  }
  if (!entries.any((e) => e.indent == 0 && e.key == 'packages'))
    fail('锁文件缺少 packages。');
  return result;
}

// Pub 的公开仓库及常见镜像；其余 hosted 源按私库迁移，Git / path 一律保留。
const publicPubHosts = {'pub.dev', 'pub.dartlang.org', 'pub.flutter-io.cn', 'pub-web.flutter-io.cn'};
Set<String> privatePackageNames(String lockText) {
  final locked = lockPackages(lockText);
  return locked.entries.where((entry) {
    final record = entry.value;
    if (record['source'] == 'git' || record['source'] == 'path') return true;
    if (record['source'] != 'hosted') return false;
    final url = record['description.url'];
    // 旧 Pub 锁文件的 hosted description 只有包名，默认公共源。
    return url != null && !publicPubHosts.contains(Uri.parse(url).host.toLowerCase());
  }).map((entry) => entry.key).toSet();
}

// 保留 url/ref/path 等嵌套字段；不能用扁平 section() 对账 Git 声明。
String? dependencyEvidence(String text, String group, String name) {
  final entries = yamlEntries(text);
  var inGroup = false;
  int? childIndent;
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    if (entry.indent == 0) {
      inGroup = entry.key == group;
      childIndent = null;
      if (inGroup && entry.value.startsWith('{')) return section(text, group)[name];
      continue;
    }
    if (!inGroup) continue;
    childIndent ??= entry.indent;
    if (entry.indent != childIndent || entry.key != name) continue;
    final evidence = <Object>[entry.value];
    for (var j = i + 1; j < entries.length && entries[j].indent > entry.indent; j++) {
      final child = entries[j];
      evidence.add([child.indent - entry.indent, child.key, splitYaml(child.value, '\u0000').single.trim()]);
    }
    return jsonEncode(evidence);
  }
  return null;
}

void extract(String projectInput, String destinationInput, {bool privateOnly = false}) {
  final project = canonical(projectInput);
  final snapshots = <Snapshot>[];
  Snapshot take(String path) {
    final s = readSnapshot(path);
    snapshots.add(s);
    return s;
  }

  final projectManifest = take(join(project, 'pubspec.yaml'));
  final mainDeps = section(projectManifest.text, 'dependencies');
  final devDeps = section(projectManifest.text, 'dev_dependencies');
  final flutter = mainDeps['flutter'];
  if (flutter == null ||
      !sdkDependency(flutter) ||
      scalar(flowMapping(flutter)['sdk']!) != 'flutter')
    fail('所选文件夹自身不是 Flutter 项目。');
  final projectName = topScalar(projectManifest.text, 'name');
  if (!packageNamePattern.hasMatch(projectName)) fail('pubspec.yaml 缺少合法项目名称。');
  var resolutionRoot = project;
  final projectOverridePath = join(project, 'pubspec_overrides.yaml');
  final projectOverride = File(projectOverridePath).existsSync()
      ? take(projectOverridePath)
      : null;
  final resolutionText =
      projectOverride != null && hasTopKey(projectOverride.text, 'resolution')
      ? projectOverride.text
      : projectManifest.text;
  final workspaceMember =
      topScalar(resolutionText, 'resolution') == 'workspace';
  final workspaceText =
      projectOverride != null && hasTopKey(projectOverride.text, 'workspace')
      ? projectOverride.text
      : projectManifest.text;
  final workspace = workspaceMember || hasTopKey(workspaceText, 'workspace');
  if (privateOnly && workspace) fail('私库迁移暂不支持 Pub workspace；请使用独立 Flutter 项目。');
  if (workspaceMember) {
    while (!File(join(resolutionRoot, '.dart_tool/package_config.json'))
            .existsSync() ||
        !File(join(resolutionRoot, 'pubspec.lock')).existsSync()) {
      final parent = Directory(resolutionRoot).parent.path;
      if (parent == resolutionRoot)
        fail('未找到 workspace 共享解析文件，请在 workspace 根执行 flutter pub get。');
      resolutionRoot = parent;
    }
  }
  final lock = take(join(resolutionRoot, 'pubspec.lock'));
  final config = take(join(resolutionRoot, '.dart_tool/package_config.json'));
  final rootManifest = resolutionRoot == project
      ? projectManifest
      : take(join(resolutionRoot, 'pubspec.yaml'));
  for (final root in {project, resolutionRoot}) {
    final override = join(root, 'pubspec_overrides.yaml');
    if (File(override).existsSync()) take(override);
  }
  final resolvedAt = config.file.lastModifiedSync();
  for (final snapshot in snapshots) {
    if (snapshot.file.path != config.file.path &&
        snapshot.file.lastModifiedSync().isAfter(resolvedAt)) {
      fail('项目声明或锁文件比解析配置更新，请先执行 flutter pub get：${snapshot.file.path}');
    }
  }
  final locked = lockPackages(lock.text);
  final privateNames = privateOnly ? privatePackageNames(lock.text) : <String>{};
  if (privateOnly && privateNames.isEmpty) fail('没有已解析的 Git、path 或自建 Pub 源依赖，无需迁移。');
  final decoded = jsonDecode(config.text);
  if (decoded is! Map ||
      decoded['configVersion'] != 2 ||
      decoded['packages'] is! List)
    fail('package_config.json 格式不受支持。');
  final roots = <String, String>{};
  for (final entry in decoded['packages'] as List) {
    if (entry is! Map ||
        entry['name'] is! String ||
        entry['rootUri'] is! String)
      fail('解析配置含无效包。');
    final name = entry['name'] as String;
    if (!packageNamePattern.hasMatch(name) || roots.containsKey(name))
      fail('解析配置含非法或重复包名。');
    final uri = config.file.absolute.uri.resolve(entry['rootUri'] as String);
    if (uri.scheme != 'file' || uri.hasQuery || uri.hasFragment)
      fail('$name 不是本地包路径。');
    // 私库迁移无需读取公共缓存或 SDK 包源码。
    if (privateOnly && name != projectName && !privateNames.contains(name)) continue;
    final path = uri.toFilePath();
    if (!Directory(path).existsSync())
      fail('本地依赖缺失：$name；请执行 flutter pub get。');
    roots[name] = canonical(path);
  }
  if (roots[projectName] != project) fail('解析配置不属于所选项目，请执行 flutter pub get。');
  final workspaceMembers = <String>{};
  if (workspace) {
    workspaceMembers.add(resolutionRoot);
    final pending = <Snapshot>[rootManifest];
    while (pending.isNotEmpty) {
      final parentManifest = pending.removeLast();
      final parentRoot = canonical(parentManifest.file.parent.path);
      final overridePath = join(parentRoot, 'pubspec_overrides.yaml');
      final override = File(overridePath).existsSync()
          ? take(overridePath)
          : null;
      if (override != null &&
          override.file.lastModifiedSync().isAfter(resolvedAt)) {
        fail('workspace 覆盖声明已更新，请执行 flutter pub get：$parentRoot');
      }
      final declarations =
          override != null && hasTopKey(override.text, 'workspace')
          ? override.text
          : parentManifest.text;
      for (final pattern in workspacePatterns(declarations)) {
        final glob = workspaceGlob(pattern.replaceFirst(RegExp(r'/+$'), ''));
        final matches = roots.values.where((candidate) {
          if (candidate == parentRoot || !inside(candidate, parentRoot))
            return false;
          final relative = candidate
              .substring(parentRoot.length + 1)
              .replaceAll(Platform.pathSeparator, '/');
          return glob.hasMatch(relative);
        }).toSet();
        if (matches.isEmpty &&
            !pattern.contains('*') &&
            !pattern.contains('?')) {
          fail('workspace 成员未解析：$pattern；请执行 flutter pub get。');
        }
        for (final member in matches) {
          if (!workspaceMembers.add(member)) continue;
          final memberManifest = take(join(member, 'pubspec.yaml'));
          final memberOverridePath = join(member, 'pubspec_overrides.yaml');
          final memberOverride = File(memberOverridePath).existsSync()
              ? take(memberOverridePath)
              : null;
          final memberResolution =
              memberOverride != null &&
                  hasTopKey(memberOverride.text, 'resolution')
              ? memberOverride.text
              : memberManifest.text;
          if (topScalar(memberResolution, 'resolution') != 'workspace') {
            fail('workspace 成员缺少 resolution: workspace：$member');
          }
          if (memberManifest.file.lastModifiedSync().isAfter(resolvedAt)) {
            fail('workspace 成员声明已更新，请执行 flutter pub get：$member');
          }
          pending.add(memberManifest);
        }
      }
    }
    if (!workspaceMembers.contains(project))
      fail('所选项目未被祖先 workspace 声明，请在正确的 workspace 执行 flutter pub get。');
  }
  for (final entry in locked.entries) {
    if (privateOnly && !privateNames.contains(entry.key)) continue;
    if (!roots.containsKey(entry.key))
      fail('锁文件与解析配置不一致，缺少 ${entry.key}；请执行 flutter pub get。');
    if (!['hosted', 'git', 'path', 'sdk'].contains(entry.value['source']))
      fail('${entry.key} 使用不支持的来源。');
  }
  if (!workspace &&
      roots.keys.any(
        (name) => name != projectName && !locked.containsKey(name),
      ))
    fail('解析配置含锁文件以外的包，请执行 flutter pub get。');
  // 新声明尚未解析时不能把旧缓存包装成完整结果。
  for (final entry in {...mainDeps, ...devDeps}.entries) {
    if (privateOnly && !privateNames.contains(entry.key)) continue;
    if (!roots.containsKey(entry.key))
      fail('声明依赖尚未解析：${entry.key}；请执行 flutter pub get。');
  }
  final selected = <String>{};
  if (!workspace) selected.addAll(privateOnly ? privateNames : locked.keys);
  final queue = privateOnly ? <String>[] : <String>[...mainDeps.keys, ...devDeps.keys];
  final visited = <String>{projectName};
  while (queue.isNotEmpty) {
    final name = queue.removeLast();
    if (!visited.add(name)) continue;
    final record = locked[name];
    if (record?['source'] == 'sdk') continue;
    final root = roots[name];
    if (root == null) fail('依赖图缺少 $name，请执行 flutter pub get。');
    if (record == null && !workspaceMembers.contains(root))
      fail('依赖 $name 没有锁定记录且不是已声明的 workspace 成员。');
    selected.add(name);
    final manifest = take(join(root, 'pubspec.yaml'));
    for (final dependency in section(manifest.text, 'dependencies').entries) {
      if (!sdkDependency(dependency.value)) queue.add(dependency.key);
    }
  }
  final packages = <Package>[];
  for (final name in selected.toList()..sort()) {
    final record = locked[name];
    if (record?['source'] == 'sdk') continue;
    final root = roots[name]!;
    if (root == project) fail('依赖根目录与项目相同：$name');
    final manifest = take(join(root, 'pubspec.yaml'));
    if (topScalar(manifest.text, 'name') != name) fail('包路径与名称不匹配：$name');
    final version = topScalar(manifest.text, 'version');
    if (record != null &&
        (record['version'] == null ||
            record['version'] != (version.isEmpty ? '0.0.0' : version)))
      fail('缓存与锁定版本不匹配：$name；请执行 flutter pub get。');
    final dependency = mainDeps.containsKey(name)
        ? 'direct main'
        : devDeps.containsKey(name)
        ? 'direct dev'
        : 'transitive';
    packages.add(
      Package(
        name,
        record?['source'] ?? 'workspace',
        record?['version'] ?? version,
        dependency,
        root,
        manifest,
      ),
    );
  }
  // 检查目标的真实现存祖先，拒绝项目和包内输出，避免递归复制自身。
  var ancestor = Directory(destinationInput).absolute;
  final suffix = <String>[];
  while (!ancestor.existsSync()) {
    if (FileSystemEntity.typeSync(ancestor.path, followLinks: false) !=
        FileSystemEntityType.notFound)
      fail('目标不是目录。');
    // URI 会先折叠 ..，Directory.parent 按原路径剥离；此处须使用原始路径片段。
    final separator = Platform.isWindows ? RegExp(r'[/\\]') : RegExp('/');
    suffix.insert(
      0,
      ancestor.path.split(separator).where((s) => s.isNotEmpty).last,
    );
    final parent = ancestor.parent;
    if (parent.path == ancestor.path) fail('无法解析目标目录。');
    ancestor = parent;
  }
  var destination = canonical(ancestor.path);
  for (final part in suffix) {
    if (part == '.') continue;
    destination = part == '..'
        ? Directory(destination).parent.path
        : join(destination, part);
  }
  // .. 折叠后可能落到另一个已有链接，必须重新解析真实祖先再做重叠检查。
  ancestor = Directory(destination);
  suffix.clear();
  while (!ancestor.existsSync()) {
    if (FileSystemEntity.typeSync(ancestor.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      fail('目标不是目录。');
    }
    final separator = Platform.isWindows ? RegExp(r'[/\\]') : RegExp('/');
    suffix.insert(
      0,
      ancestor.path.split(separator).where((s) => s.isNotEmpty).last,
    );
    ancestor = ancestor.parent;
  }
  destination = canonical(ancestor.path);
  for (final part in suffix) {
    destination = join(destination, part);
  }
  for (final source in [project, ...packages.map((p) => p.root)]) {
    if (inside(destination, source)) fail('目标目录不能位于项目或依赖包内：$destination');
  }
  for (final package in packages) {
    inventory(package, package.root, '', {});
    if (privateOnly && package.warnings.any((w) => w.contains('符号链接'))) {
      fail('私库源码存在无法迁移的链接：${package.name}；请先处理上方告警。');
    }
  }
  for (final snapshot in snapshots) {
    snapshot.verify();
  }
  Directory(destination).createSync(recursive: true);
  final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
    RegExp(r'[^0-9]'),
    '',
  );
  // 随机目录与最终目录同卷，完整完成后再原子改名。
  final prefix = privateOnly ? 'FlutterPrivateDependencies' : 'FlutterDependencies';
  final fileHashes = <String, String>{};
  final work = Directory(destination)
      .createTempSync('.$prefix-$projectName-$stamp-incomplete-');
  var published = false;
  try {
    stdout.writeln(
      '来源项目：$project\n本地解析：$resolutionRoot\n目标目录：${work.path}\n第三方包：${packages.length}',
    );
    for (final package in packages) {
      final target = join(work.path, 'packages/${package.name}');
      Directory(target).createSync(recursive: true);
      stdout.writeln(
        '提取 ${package.name} ${package.version} [${package.source}]\n  来源：${package.root}\n  目标：$target',
      );
      for (final item in package.files) {
        final before = File(item.source).statSync();
        if (before.size != item.stat.size ||
            before.modified != item.stat.modified)
          fail('源文件提取期间变化：${package.name}/${item.relative}');
        final output = File(join(target, item.relative));
        output.parent.createSync(recursive: true);
        final beforeHash = privateOnly ? fileDigest(File(item.source)) : null;
        File(item.source).copySync(output.path);
        if (privateOnly) {
          final digest = fileDigest(output);
          if (digest != beforeHash || fileDigest(File(item.source)) != digest) fail('源码复制期间变化：${package.name}/${item.relative}');
          fileHashes['packages/${package.name}/${item.relative.replaceAll(Platform.pathSeparator, '/')}'] = digest;
        }
        final after = File(item.source).statSync();
        if (after.size != before.size ||
            after.modified != before.modified ||
            output.lengthSync() != before.size)
          fail('源文件提取期间变化：${package.name}/${item.relative}');
      }
    }
    for (final snapshot in snapshots) {
      snapshot.verify();
    }
    // 保留解析证据；清单只输出来源类别和本地路径，不展开远端认证地址。
    File(join(work.path, 'pubspec.yaml'))
        .writeAsBytesSync(projectManifest.bytes);
    File(join(work.path, 'pubspec.lock')).writeAsBytesSync(lock.bytes);
    if (privateOnly && projectOverride != null) {
      File(join(work.path, 'pubspec_overrides.yaml')).writeAsBytesSync(projectOverride.bytes);
    }
    if (privateOnly) {
      for (final name in ['pubspec.yaml', 'pubspec.lock', if (projectOverride != null) 'pubspec_overrides.yaml']) {
        fileHashes[name] = fileDigest(File(join(work.path, name)));
      }
    }
    final manifest = {
      'formatVersion': 1,
      if (privateOnly) 'snapshotKind': 'flutter-private-dependencies',
      if (privateOnly) 'fileHashes': fileHashes,
      'status': 'complete',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'projectName': projectName,
      'projectPath': project,
      'resolutionRoot': resolutionRoot,
      'scope': privateOnly ? 'Git, path and custom hosted Pub packages including dev and transitive; public hosted and SDK excluded' : 'Resolved Pub source packages including dev and transitive; SDK excluded',
      'packages': [
        for (final p in packages)
          {
            'name': p.name,
            'source': p.source,
            'version': p.version,
            'dependency': p.dependency,
            'sourcePath': p.root,
            'copiedPath': 'packages/${p.name}',
            'fileCount': p.files.length,
          },
      ],
      'excludedDirectories': ignoredDirectories.toList()..sort(),
      'excludedGeneratedDirectorySuffixes': generatedDirectorySuffixes.toList()
        ..sort(),
      // 保留旧清单字段，兼容读取既有归档的消费者。
      'excludedRelativePaths': generatedDirectorySuffixes.toList()..sort(),
      'symlinks': 'Internal links materialized; unresolvable, external, cyclic or excluded-target links skipped with warnings',
      'warnings': [for (final p in packages) ...p.warnings],
    };
    File(join(work.path, 'manifest.json')).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
    );
    File(join(work.path, 'README.md'))
        .writeAsStringSync('''# $projectName 的 Flutter 第三方依赖源码

已提取 ${packages.length} 个${privateOnly ? '私库候选' : 'Pub'}包，包含直接、间接、开发依赖、插件包内平台源码、资源和原有许可证。
${privateOnly ? '仅包含 Git、path、自建 Pub 源；公共 hosted 包不复制。使用“导入Flutter项目工程私库依赖”导入，再执行 flutter pub get 获取公共依赖。' : ''}

- 源码位于 `packages/`，逐包名称、版本、来源、本地原路径见 `manifest.json`。
- `pubspec.yaml` 与 `pubspec.lock` 是提取时的原始证据，可能含本地路径或私有仓库地址，分享前请检查。
- 排除 Flutter / Dart SDK，以及 ${ignoredDirectories.join('、')} 等缓存目录。
- 排除嵌套的 ${generatedDirectorySuffixes.join('、')} 生成目录，保留各平台真实源码。
- 这是源码快照；未重写项目依赖，不保证直接离线构建。CocoaPods / Gradle / Maven 下载的独立原生依赖和外部二进制不在 Pub 包源码范围内。
- 包内有效符号链接已物化；无法解析、包外、循环或指向排除目录的链接已跳过，具体路径与原因见 `manifest.json` 的 `warnings`。
- 未修改源项目和缓存；复制不改变各包原有许可条款。
''');
    final finalName =
        '$prefix-$projectName-$stamp-${work.path.split(Platform.pathSeparator).last.split('-').last}';
    final finalPath = join(destination, finalName);
    if (FileSystemEntity.typeSync(finalPath, followLinks: false) !=
        FileSystemEntityType.notFound)
      fail('目标已存在，未覆盖。');
    work.renameSync(finalPath);
    published = true;
    stdout.writeln(
      '✔ 提取完成：$finalPath\n✔ 包数量：${packages.length}；清单：manifest.json\n'
      '跳过告警：${packages.fold<int>(0, (count, p) => count + p.warnings.length)}；详情见 manifest.json 的 warnings',
    );
  } finally {
    if (!published) stderr.writeln('提取未完成，半成品保留在隐藏目录：${work.path}');
  }
}

void main(List<String> arguments) {
  try {
    final privateOnly = arguments.contains('--private-only');
    arguments = arguments.where((arg) => arg != '--private-only').toList();
    if (arguments.length != 4 ||
        arguments[0] != '--project' ||
        arguments[2] != '--destination') {
      fail(
        '用法：dart ExtractFlutterDependencies.dart --project <Flutter目录> --destination <输出父目录>',
      );
    }
    extract(arguments[1], arguments[3], privateOnly: privateOnly);
  } catch (error) {
    stderr.writeln('✖ 提取失败：$error');
    exitCode = 1;
  }
}

String fileDigest(File file) {
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
