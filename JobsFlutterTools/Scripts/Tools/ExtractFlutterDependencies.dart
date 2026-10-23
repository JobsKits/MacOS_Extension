// Created by Jobs on 2026年10月19日，星期一。
// 从 Pub 已解析的本地路径提取源码；不运行 pub get，不连接网络，不修改项目。
import 'dart:convert';
import 'dart:io';

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
}

class CopyItem {
  CopyItem(this.source, this.relative, this.stat);
  final String source, relative;
  final FileStat stat;
}

// 链接只允许落在当前包内，物化为文件；缓存 / 构建目录不随源码导出。
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
    if (ignoredDirectories.contains(name)) continue;
    var source = entity.path;
    if (type == FileSystemEntityType.link) {
      source = entity.resolveSymbolicLinksSync();
      if (!inside(source, package.root))
        fail('${package.name} 含包外符号链接：$targetRelative');
      type = FileSystemEntity.typeSync(source);
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
    }
  }
  if (!entries.any((e) => e.indent == 0 && e.key == 'packages'))
    fail('锁文件缺少 packages。');
  return result;
}

void extract(String projectInput, String destinationInput) {
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
  final locked = lockPackages(lock.text);
  for (final entry in locked.entries) {
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
    if (!roots.containsKey(entry.key))
      fail('声明依赖尚未解析：${entry.key}；请执行 flutter pub get。');
  }
  final selected = <String>{};
  if (!workspace) selected.addAll(locked.keys);
  final queue = <String>[...mainDeps.keys, ...devDeps.keys];
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
  final work = Directory(destination)
      .createTempSync('.FlutterDependencies-$projectName-$stamp-incomplete-');
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
        File(item.source).copySync(output.path);
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
    final manifest = {
      'formatVersion': 1,
      'status': 'complete',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'projectName': projectName,
      'projectPath': project,
      'resolutionRoot': resolutionRoot,
      'scope': 'Resolved Pub source packages including dev and transitive; SDK excluded',
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
      'symlinks':
          'Internal links materialized; external or cyclic links rejected',
    };
    File(join(work.path, 'manifest.json')).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
    );
    File(join(work.path, 'README.md'))
        .writeAsStringSync('''# $projectName 的 Flutter 第三方依赖源码

已提取 ${packages.length} 个 Pub 包，包含直接、间接、开发依赖、插件包内平台源码、资源和原有许可证。

- 源码位于 `packages/`，逐包名称、版本、来源、本地原路径见 `manifest.json`。
- `pubspec.yaml` 与 `pubspec.lock` 是提取时的原始证据，可能含本地路径或私有仓库地址，分享前请检查。
- 排除 Flutter / Dart SDK，以及 ${ignoredDirectories.join('、')} 等缓存目录。
- 这是源码快照；未重写项目依赖，不保证直接离线构建。CocoaPods / Gradle / Maven 下载的独立原生依赖和外部二进制不在 Pub 包源码范围内。
- 内部符号链接已物化，未修改源项目和缓存；复制不改变各包原有许可条款。
''');
    final finalName =
        'FlutterDependencies-$projectName-$stamp-${work.path.split(Platform.pathSeparator).last.split('-').last}';
    final finalPath = join(destination, finalName);
    if (FileSystemEntity.typeSync(finalPath, followLinks: false) !=
        FileSystemEntityType.notFound)
      fail('目标已存在，未覆盖。');
    work.renameSync(finalPath);
    published = true;
    stdout.writeln(
      '✔ 提取完成：$finalPath\n✔ 包数量：${packages.length}；清单：manifest.json',
    );
  } finally {
    if (!published) stderr.writeln('提取未完成，半成品保留在隐藏目录：${work.path}');
  }
}

void main(List<String> arguments) {
  try {
    if (arguments.length != 4 ||
        arguments[0] != '--project' ||
        arguments[2] != '--destination') {
      fail(
        '用法：dart ExtractFlutterDependencies.dart --project <Flutter目录> --destination <输出父目录>',
      );
    }
    extract(arguments[1], arguments[3]);
  } catch (error) {
    stderr.writeln('✖ 提取失败：$error');
    exitCode = 1;
  }
}
