// Created by Jobs on 2026年10月28日，星期三。
// 识别本工具导出的源码快照，原样复制到项目并注入本地 path overrides。
import 'dart:convert';
import 'dart:io';

import 'ExtractFlutterDependencies.dart' as extraction;

Never fail(String message) => throw FormatException(message);

String join(String parent, String child) => extraction.join(parent, child);

FileSystemEntityType type(String path) =>
    FileSystemEntity.typeSync(path, followLinks: false);

// 导入不跟随任何快照内部链接，避免从未通过识别的外部路径读取。
void requireDirectory(String path) {
  if (type(path) != FileSystemEntityType.directory) {
    fail('需要存在的普通文件夹，不能是链接：$path');
  }
}

extraction.Snapshot readMetadata(String path) {
  if (type(path) != FileSystemEntityType.file) {
    fail('缺少普通元数据文件，或文件是链接：$path');
  }
  if (File(path).lengthSync() > 16 * 1024 * 1024) {
    fail('元数据文件超过 16 MiB：$path');
  }
  return extraction.Snapshot(File(path));
}

// Dart 解码器会移除 BOM；配置合并时显式恢复以保留原文件形态。
String preservedText(extraction.Snapshot? snapshot) {
  if (snapshot == null) return '';
  final bytes = snapshot.bytes;
  final bom =
      bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf;
  return '${bom ? '\uFEFF' : ''}${snapshot.text}';
}

class SourceFile {
  SourceFile(this.path, this.relative, this.stat);
  String? digest;
  final String path, relative;
  final FileStat stat;

  void verify() {
    if (type(path) != FileSystemEntityType.file) {
      fail('导入期间源文件类型变化：$path');
    }
    if (digest != null && extraction.fileDigest(File(path)) != digest) fail('源码 hash 不符：$relative');
    final current = File(path).statSync();
    if (current.size != stat.size || current.modified != stat.modified) {
      fail('导入期间源文件变化：$path');
    }
  }
}

class ImportPackage {
  ImportPackage(this.name, this.version, this.source, this.root, this.files);
  final String name, version, source, root;
  final List<SourceFile> files;
}

// 只读盘点全部文件；额外包、设备、链接和未完成副本均拒绝。
List<SourceFile> inventory(String root) {
  final result = <SourceFile>[];
  void visit(String directory, String relative) {
    requireDirectory(directory);
    for (final entity in Directory(directory).listSync(followLinks: false)) {
      final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
      if (name.contains('\\') || name.contains(':') || name == '..') {
        fail('快照含不兼容跨平台的文件名：${entity.path}');
      }
      final child = relative.isEmpty ? name : '$relative/$name';
      final kind = type(entity.path);
      if (kind == FileSystemEntityType.directory) {
        visit(entity.path, child);
      } else if (kind == FileSystemEntityType.file) {
        result.add(SourceFile(entity.path, child, entity.statSync()));
      } else {
        fail('快照含链接或非常规文件：${entity.path}');
      }
    }
  }

  visit(root, '');
  return result;
}

void requireFlutter(String text, String description) {
  requireSingleYamlDocument(text);
  final deps = extraction.section(text, 'dependencies');
  final flutter = deps['flutter'];
  if (flutter == null ||
      !extraction.sdkDependency(flutter) ||
      extraction.scalar(extraction.flowMapping(flutter)['sdk']!) != 'flutter') {
    fail('$description 不是 Flutter 项目：缺少 dependencies.flutter.sdk: flutter。');
  }
  if (!extraction.packageNamePattern.hasMatch(
    extraction.topScalar(text, 'name'),
  )) {
    fail('$description 缺少合法的项目名称。');
  }
}

// Pub 只接受一个 YAML 文档，不能把新覆盖写到文档结束标记之后。
void requireSingleYamlDocument(String text) {
  var started = false;
  var hasContent = false;
  var ended = false;
  for (final raw in const LineSplitter().convert(
    text.replaceFirst('\uFEFF', ''),
  )) {
    if (raw.trim().isEmpty || raw.trimLeft().startsWith('#')) continue;
    final marker = RegExp(r'^(---|\.\.\.)(?:[ \t]+#.*)?[ \t]*$')
        .firstMatch(raw);
    if (marker?.group(1) == '---') {
      if (started || hasContent || ended) fail('不支持多个 YAML 文档，未写入。');
      started = true;
    } else if (marker?.group(1) == '...') {
      if (ended) fail('重复 YAML 文档结束标记，未写入。');
      ended = true;
    } else {
      if (ended) fail('YAML 文档结束标记之后含正文，未写入。');
      hasContent = true;
    }
  }
}

// 用声明本身对账，不猜测任意 YAML 或版本范围的兼容性。
String declarationKey(String value) {
  if (value.trim().startsWith('{')) {
    final mapping = extraction.flowMapping(value);
    final keys = mapping.keys.toList()..sort();
    return jsonEncode({
      for (final key in keys) key: extraction.scalar(mapping[key]!),
    });
  }
  return extraction.scalar(value);
}

// 同源覆盖按完整原文区域核对，不能用扁平映射丢掉 Git 的 url/ref/path 后判等。
String? rawOverrideEvidence(String yaml) {
  final lines = yaml.split('\n');
  final header = RegExp(
    r'''^(?:dependency_overrides|"dependency_overrides"|'dependency_overrides')[ \t]*:''',
  );
  int? start;
  var offset = 0;
  for (var index = 0; index < lines.length; index++) {
    final line = index == 0
        ? lines[index].replaceFirst('\uFEFF', '')
        : lines[index];
    if (start == null) {
      if (header.hasMatch(line)) start = offset;
    } else if (line.trim().isNotEmpty &&
        !line.startsWith(' ') &&
        !line.startsWith('\t') &&
        !line.startsWith('#') &&
        !line.startsWith('\r')) {
      return yaml.substring(start, offset);
    }
    offset += lines[index].length + (index < lines.length - 1 ? 1 : 0);
  }
  return start == null ? null : yaml.substring(start);
}

Map<String, String> directDependencies(String text) {
  final main = extraction.section(text, 'dependencies');
  final dev = extraction.section(text, 'dev_dependencies');
  if (main.keys.any(dev.containsKey)) {
    fail('dependencies 与 dev_dependencies 存在重名声明。');
  }
  return {...main, ...dev};
}

class ImportPlan {
  ImportPlan(
    this.project,
    this.source,
    this.packages,
    this.snapshots,
    this.projectManifest,
    this.originalOverrides,
    this.existingOverrides,
    this.restoredPubspecOverrides,
    this.replacedOverrides,
  );
  final String project, source;
  final List<ImportPackage> packages;
  final List<extraction.Snapshot> snapshots;
  final extraction.Snapshot projectManifest;
  final extraction.Snapshot? originalOverrides;
  final Map<String, String> existingOverrides;
  final List<String> restoredPubspecOverrides;
  final Set<String> replacedOverrides;

  void verify() {
    for (final item in snapshots) {
      if (type(item.file.path) != FileSystemEntityType.file) {
        fail('校验后元数据类型变化：${item.file.path}');
      }
      item.verify();
    }
    if (originalOverrides == null &&
        type(join(project, 'pubspec_overrides.yaml')) !=
            FileSystemEntityType.notFound) {
      fail('校验后出现 pubspec_overrides.yaml，请重新开始。');
    }
    for (final package in packages) {
      for (final file in package.files) {
        file.verify();
      }
    }
  }
}

ImportPlan validate(String projectInput, String sourceInput, {bool privateOnly = false}) {
  requireDirectory(projectInput);
  requireDirectory(sourceInput);
  final project = Directory(projectInput).resolveSymbolicLinksSync();
  final source = Directory(sourceInput).resolveSymbolicLinksSync();
  if (extraction.inside(source, project) ||
      extraction.inside(project, source)) {
    fail('导出目录与目标项目不能重叠；请把快照放到项目之外。');
  }
  final sourceName = Directory(source).uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .last;
  if ((sourceName.startsWith('.FlutterDependencies-') || sourceName.startsWith('.FlutterPrivateDependencies-')) &&
      sourceName.contains('-incomplete-')) {
    fail('所选目录是提取未完成的半成品。');
  }
  final snapshots = <extraction.Snapshot>[];
  extraction.Snapshot take(String path) {
    final snapshot = readMetadata(path);
    snapshots.add(snapshot);
    return snapshot;
  }

  final projectManifest = take(join(project, 'pubspec.yaml'));
  requireFlutter(projectManifest.text, '目标项目');
  final targetOverridesPath = join(project, 'pubspec_overrides.yaml');
  final overrideType = type(targetOverridesPath);
  final originalOverrides = overrideType == FileSystemEntityType.notFound
      ? null
      : take(targetOverridesPath);
  final targetText = projectManifest.text;
  final overrideText = originalOverrides?.text ?? '';
  requireSingleYamlDocument(overrideText);
  for (final text in [targetText, overrideText]) {
    if (extraction.topScalar(text, 'resolution') == 'workspace' ||
        extraction.hasTopKey(text, 'workspace')) {
      fail('目标使用 Pub workspace；当前仅支持独立 Flutter 项目，未写入任何内容。');
    }
  }
  final snapshotManifest = take(join(source, 'manifest.json'));
  final decoded = jsonDecode(snapshotManifest.text);
  if (decoded is! Map ||
      decoded['formatVersion'] != 1 ||
      decoded['status'] != 'complete' ||
      decoded['packages'] is! List) {
    fail('不是本工具 formatVersion 1 的完整依赖快照。');
  }
  if ((decoded['snapshotKind'] == 'flutter-private-dependencies') != privateOnly) {
    fail('快照类型与入口不匹配；私库快照须使用“导入Flutter项目工程私库依赖”。');
  }
  if (decoded['snapshotKind'] != null && decoded['snapshotKind'] != 'flutter-private-dependencies') fail('未知快照类型。');
  final hashes = decoded['fileHashes'];
  if (privateOnly && (hashes is! Map || hashes.values.any((v) => v is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(v)))) fail('私库快照缺少有效的文件 hash 清单。');
  final verifiedFiles = <String>{};
  void verifyHash(String relative, File file) {
    if (!privateOnly) return;
    if (hashes[relative] != extraction.fileDigest(file)) fail('私库快照文件损坏：$relative');
    verifiedFiles.add(relative);
  }
  if (decoded['warnings'] != null &&
      (decoded['warnings'] is! List ||
          (decoded['warnings'] as List).any((warning) => warning is! String))) {
    fail('快照 warnings 必须是字符串列表。');
  }
  final sourceManifest = take(join(source, 'pubspec.yaml'));
  final sourceLock = take(join(source, 'pubspec.lock'));
  requireSingleYamlDocument(sourceLock.text);
  requireFlutter(sourceManifest.text, '快照项目');
  if (decoded['projectName'] !=
      extraction.topScalar(sourceManifest.text, 'name')) {
    fail('manifest.json 与快照 pubspec.yaml 的项目名称不符。');
  }
  final locked = extraction.lockPackages(sourceLock.text);
  final privateNames = privateOnly ? extraction.privatePackageNames(sourceLock.text) : <String>{};
  verifyHash('pubspec.yaml', sourceManifest.file);
  verifyHash('pubspec.lock', sourceLock.file);
  final sourceOverridesPath = join(source, 'pubspec_overrides.yaml');
  final sourceOverrides = privateOnly && type(sourceOverridesPath) != FileSystemEntityType.notFound ? take(sourceOverridesPath) : null;
  if (sourceOverrides != null) verifyHash('pubspec_overrides.yaml', sourceOverrides.file);
  requireDirectory(join(source, 'packages'));
  // 根层也复核链接，防止看似正常的元数据旁藏有外部引用。
  for (final entity in Directory(source).listSync(followLinks: false)) {
    if (![
      FileSystemEntityType.file,
      FileSystemEntityType.directory,
    ].contains(type(entity.path))) {
      fail('快照根目录含链接或非常规文件：${entity.path}');
    }
  }
  final byName = <String, ImportPackage>{};
  final caseNames = <String>{};
  for (final record in decoded['packages'] as List) {
    if (record is! Map ||
        record['name'] is! String ||
        !extraction.packageNamePattern.hasMatch(record['name'] as String) ||
        record['version'] is! String ||
        !['hosted', 'git', 'path', 'workspace'].contains(record['source']) ||
        record['fileCount'] is! int ||
        (record['fileCount'] as int) < 1) {
      fail('快照包记录不完整或不合法。');
    }
    final name = record['name'] as String;
    if (!caseNames.add(name.toLowerCase()) ||
        name == extraction.topScalar(targetText, 'name') ||
        [
          'flutter',
          'flutter_test',
          'flutter_driver',
          'sky_engine',
        ].contains(name)) {
      fail('重复包名、SDK 包或项目自身不能导入：$name');
    }
    if (record['copiedPath'] != 'packages/$name') {
      fail('快照复制路径不合法：$name');
    }
    final root = join(source, 'packages/$name');
    requireDirectory(root);
    final manifest = take(join(root, 'pubspec.yaml'));
    requireSingleYamlDocument(manifest.text);
    final version = extraction.topScalar(manifest.text, 'version');
    if (extraction.topScalar(manifest.text, 'name') != name ||
        (version.isEmpty ? '0.0.0' : version) !=
            (record['version'] == '' ? '0.0.0' : record['version'])) {
      fail('包名或版本与快照清单不符：$name');
    }
    final lock = locked[name];
    if (record['source'] == 'workspace' && lock != null) {
      fail('workspace 包不应伪装已锁定的外部依赖：$name');
    }
    if (record['source'] != 'workspace' &&
        (lock == null ||
            lock['source'] != record['source'] ||
            lock['version'] != record['version'])) {
      fail('包名、来源或版本与快照锁文件不符：$name');
    }
    final files = inventory(root);
    if (files.length != record['fileCount']) {
      fail('快照文件数量不符，可能不完整：$name');
    }
    for (final file in files) {
      final relative = 'packages/$name/${file.relative}';
      verifyHash(relative, File(file.path));
      if (privateOnly) file.digest = hashes[relative] as String;
    }
    byName[name] = ImportPackage(
      name,
      record['version'] as String,
      record['source'] as String,
      root,
      files,
    );
  }
  final diskNames = Directory(join(source, 'packages'))
      .listSync(followLinks: false)
      .map((entity) => entity.uri.pathSegments.where((p) => p.isNotEmpty).last)
      .toSet();
  if (diskNames.length != byName.length ||
      diskNames.any((name) => !byName.containsKey(name))) {
    fail('packages/ 与 manifest.json 清单不一致，含多余或缺失的包。');
  }
  if (privateOnly && (byName.length != privateNames.length || privateNames.any((name) => !byName.containsKey(name)))) {
    fail('私库清单与锁文件不符，含公共包或缺失的私库。');
  }
  if (privateOnly && verifiedFiles.length != (hashes as Map).length) fail('私库 hash 清单含多余或缺失的文件。');
  bool needsSnapshot(String name) => !privateOnly || privateNames.contains(name) || locked[name] == null;
  for (final package in byName.values) {
    final manifest = snapshots.singleWhere(
      (snapshot) => snapshot.file.path == join(package.root, 'pubspec.yaml'),
    );
    for (final entry
        in extraction.section(manifest.text, 'dependencies').entries) {
      if (!extraction.sdkDependency(entry.value) && needsSnapshot(entry.key) &&
          !byName.containsKey(entry.key)) {
        fail('快照缺少传递依赖：${package.name} → ${entry.key}');
      }
    }
  }
  final sourceDirect = directDependencies(sourceManifest.text);
  for (final entry in sourceDirect.entries) {
    if (!extraction.sdkDependency(entry.value) && needsSnapshot(entry.key) &&
        !byName.containsKey(entry.key)) {
      fail('快照缺少原项目的直接依赖：${entry.key}');
    }
  }
  final targetDirect = directDependencies(targetText);
  var matched = 0;
  for (final entry in targetDirect.entries) {
    if (extraction.sdkDependency(entry.value)) continue;
    if (privateOnly && !privateNames.contains(entry.key)) {
      if (entry.value.startsWith('{') && extraction.flowMapping(entry.value).keys.any((k) => ['git', 'path', 'hosted'].contains(k))) {
        if (sourceDirect[entry.key] != entry.value) fail('目标存在快照未覆盖的自定义依赖：${entry.key}');
      }
      continue;
    }
    if (!byName.containsKey(entry.key) || sourceDirect[entry.key] == null) {
      fail('快照不能覆盖目标项目直接依赖：${entry.key}');
    }
    if (declarationKey(entry.value) !=
        declarationKey(sourceDirect[entry.key]!)) {
      fail('目标依赖声明与快照来源不一致：${entry.key}；请使用同一依赖声明的快照。');
    }
    if (privateOnly) {
      for (final group in ['dependencies', 'dev_dependencies']) {
        if (extraction.dependencyEvidence(targetText, group, entry.key) != extraction.dependencyEvidence(sourceManifest.text, group, entry.key)) fail('私库 Git url/ref/path 或路径声明不一致：${entry.key}');
      }
    }
    matched++;
  }
  if (privateOnly && matched == 0 && byName.isNotEmpty) {
    if (jsonEncode(targetDirect) != jsonEncode(sourceDirect)) fail('仅含间接私库时，目标直接依赖须与来源一致。');
    matched = 1;
  }
  if (matched == 0 || byName.isEmpty) {
    fail('目标项目没有与此快照匹配的第三方直接依赖，无需导入。');
  }
  final existing = extraction.section(overrideText, 'dependency_overrides');
  final declaredOverrides = extraction.section(
    targetText,
    'dependency_overrides',
  );
  final sourceDeclaredOverrides = extraction.section(
    sourceManifest.text,
    'dependency_overrides',
  );
  final sourceOverrideEvidence = rawOverrideEvidence(sourceManifest.text);
  final targetOverrideEvidence = rawOverrideEvidence(targetText);
  final restoredPubspecOverrides = <String>[];
  final replacedOverrides = <String>{};
  for (final name in byName.keys) {
    if (existing.containsKey(name)) {
      if (!privateOnly || sourceOverrides == null ||
          extraction.dependencyEvidence(overrideText, 'dependency_overrides', name) != extraction.dependencyEvidence(sourceOverrides.text, 'dependency_overrides', name)) {
        fail('目标已为 $name 配置不同的 dependency_overrides，未覆盖；请先人工解决冲突。');
      }
      replacedOverrides.add(name);
    }
    if (declaredOverrides.containsKey(name)) {
      if (!sourceDeclaredOverrides.containsKey(name) ||
          sourceOverrideEvidence == null ||
          (privateOnly
              ? extraction.dependencyEvidence(targetText, 'dependency_overrides', name) != extraction.dependencyEvidence(sourceManifest.text, 'dependency_overrides', name)
              : sourceOverrideEvidence != targetOverrideEvidence)) {
        fail('目标 pubspec.yaml 的 $name 覆盖与快照原始覆盖区不一致，未替换；请先人工解决冲突。');
      }
      restoredPubspecOverrides.add(name);
    }
  }
  for (final name in replacedOverrides) { existing.remove(name); }
  for (final relative in ['vendor', 'vendor/flutter_dependencies']) {
    final path = join(project, relative);
    if (type(path) != FileSystemEntityType.notFound) requireDirectory(path);
  }
  final plan = ImportPlan(
    project,
    source,
    byName.values.toList(),
    snapshots,
    projectManifest,
    originalOverrides,
    existing,
    restoredPubspecOverrides,
    replacedOverrides,
  );
  // 在预检阶段检查合并结果，避免确认后才发现配置格式不可合并。
  checkedOverrides(plan, {
    for (final package in plan.packages)
      package.name:
          'vendor/flutter_dependencies/validation/packages/${package.name}',
  });
  plan.verify();
  return plan;
}

// 增量插入覆盖声明，现有正文、注释及换行保持原状。
String mergeOverrides(String original, Map<String, String> paths) {
  requireSingleYamlDocument(original);
  final newline = original.contains('\r\n') ? '\r\n' : '\n';
  String entries(int indent) => paths.entries
      .map(
        (e) =>
            '${' ' * indent}${e.key}:$newline${' ' * (indent + 2)}path: ${jsonEncode(e.value)}$newline',
      )
      .join();
  final lines = original.split('\n');
  var offset = 0;
  final header = RegExp(
    r'''^(?:dependency_overrides|"dependency_overrides"|'dependency_overrides')[ \t]*:[ \t]*''',
  );
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    final plain = index == 0 ? line.replaceFirst('\uFEFF', '') : line;
    final match = header.firstMatch(plain);
    if (match != null) {
      final bom = line.length - plain.length;
      final valueStart = offset + bom + match.end;
      final tail = extraction
          .splitYaml(plain.substring(match.end), '\u0000')
          .single
          .trim();
      if (tail.startsWith('{')) {
        // Flow 映射保留原有字节，只在闭括号前追加 path 记录。
        final existing = extraction.flowMapping(tail);
        final close = valueStart + tail.lastIndexOf('}');
        final content = paths.entries
            .map((e) => '${e.key}: {path: ${jsonEncode(e.value)}}')
            .join(', ');
        return original.replaceRange(
          close,
          close,
          '${existing.isEmpty ? '' : ', '}$content',
        );
      }
      if (tail.isNotEmpty && !['{}', '~', 'null'].contains(tail)) {
        fail('pubspec_overrides.yaml 的覆盖区格式不受支持，未写入。');
      }
      var output = original;
      var difference = 0;
      if (tail.isNotEmpty) {
        output = output.replaceRange(valueStart, valueStart + tail.length, '');
        difference = tail.length;
      }
      // 寻找下一个顶层区域，在它之前加入完整的块映射。
      var end = offset + line.length + (index < lines.length - 1 ? 1 : 0);
      var next = index + 1;
      int? childIndent;
      while (next < lines.length) {
        final current = lines[next];
        if (current.isNotEmpty &&
            !current.startsWith(' ') &&
            !current.startsWith('\r') &&
            !current.startsWith('#'))
          break;
        if (current.trim().isNotEmpty && !current.trimLeft().startsWith('#')) {
          final indentation = current.length - current.trimLeft().length;
          if (indentation > 0 &&
              (childIndent == null || indentation < childIndent)) {
            childIndent = indentation;
          }
        }
        end += current.length + (next < lines.length - 1 ? 1 : 0);
        next++;
      }
      end -= difference;
      final prefix = output.substring(0, end);
      return '${prefix.endsWith('\n') ? prefix : '$prefix$newline'}${entries(childIndent ?? 2)}${output.substring(end)}';
    }
    offset += line.length + (index < lines.length - 1 ? 1 : 0);
  }
  final endMarker = RegExp(
    r'^\.\.\.(?:[ \t]+#.*)?\r?$',
    multiLine: true,
  ).firstMatch(original);
  final position = endMarker?.start ?? original.length;
  final before = original.substring(0, position);
  final prefix = before.isEmpty || before.endsWith('\n')
      ? before
      : '$before$newline';
  return '${prefix}dependency_overrides:$newline${entries(2)}${original.substring(position)}';
}


// 仅移除已核对为同源的覆盖条目；其它覆盖、顶层设置和注释继续保留。
String removeOverrides(String original, Set<String> names) {
  if (names.isEmpty) return original;
  final lines = original.split('\n');
  final header = RegExp(r'''^(?:dependency_overrides|"dependency_overrides"|'dependency_overrides')\s*:\s*''');
  var active = false;
  int? childIndent;
  final result = <String>[];
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final match = header.firstMatch(line.replaceFirst('\uFEFF', ''));
    if (match != null) {
      active = true;
      final tail = extraction.splitYaml(line.replaceFirst('\uFEFF', '').substring(match.end), '\u0000').single.trim();
      if (tail.startsWith('{')) {
        final map = extraction.flowMapping(tail)..removeWhere((key, _) => names.contains(key));
        final start = line.indexOf('{'), end = line.lastIndexOf('}');
        result.add(line.replaceRange(start, end + 1, '{${map.entries.map((e) => '${e.key}: ${e.value}').join(', ')}}'));
        active = false;
      } else { result.add(line); }
      continue;
    }
    final entry = extraction.yamlEntries(line);
    if (active && entry.isNotEmpty) {
      final current = entry.single;
      if (current.indent == 0) { active = false; }
      else {
        childIndent ??= current.indent;
        if (current.indent == childIndent && names.contains(current.key)) {
          while (i + 1 < lines.length) {
            final next = lines[i + 1];
            if (next.trim().isEmpty) break;
            final indent = next.length - next.trimLeft().length;
            if (indent <= childIndent) break;
            i++;
          }
          continue;
        }
      }
    }
    result.add(line);
  }
  return result.join('\n');
}

// 写入前再次解析全部覆盖，确认新路径准确且原有覆盖语义未被挤出。
String checkedOverrides(ImportPlan plan, Map<String, String> paths) {
  final text = mergeOverrides(removeOverrides(preservedText(plan.originalOverrides), plan.replacedOverrides), paths);
  final merged = extraction.section(text, 'dependency_overrides');
  if (merged.length != plan.existingOverrides.length + paths.length) {
    fail('合并后的 dependency_overrides 数量不正确，未写入。');
  }
  for (final entry in paths.entries) {
    final value = merged[entry.key];
    if (value == null ||
        extraction.scalar(extraction.flowMapping(value)['path'] ?? '') !=
            entry.value) {
      fail('合并后的本地覆盖路径不正确：${entry.key}，未写入。');
    }
  }
  for (final entry in plan.existingOverrides.entries) {
    if (merged[entry.key] == null ||
        declarationKey(merged[entry.key]!) != declarationKey(entry.value)) {
      fail('合并改变了已有覆盖：${entry.key}，未写入。');
    }
  }
  return text;
}

void showPlan(ImportPlan plan) {
  stdout.writeln('✔ 已识别完整 Flutter 依赖快照（formatVersion 1）');
  stdout.writeln('来源目录：${plan.source}\n目标项目：${plan.project}');
  final manifestPath = join(plan.source, 'manifest.json');
  final manifest = jsonDecode(
    plan.snapshots
        .singleWhere((snapshot) => snapshot.file.path == manifestPath)
        .text,
  ) as Map;
  final warningCount = (manifest['warnings'] as List?)?.length ?? 0;
  if (warningCount > 0) {
    stdout.writeln('⚠ 源快照包含 $warningCount 条提取告警；详情：$manifestPath');
    stdout.writeln('被跳过的源内容不会随本次导入补齐，请核对告警后继续。');
  }
  if (plan.restoredPubspecOverrides.isNotEmpty) {
    stdout.writeln(
      '✔ 将恢复 ${plan.restoredPubspecOverrides.length} 个与快照原文一致的 pubspec.yaml 既有覆盖。',
    );
    stdout.writeln('原 pubspec.yaml 保持不变；移除本次新增的 path 覆盖后，原声明重新生效。');
  }
  if (plan.replacedOverrides.isNotEmpty) stdout.writeln('将备份并替换与来源完全相同的 ${plan.replacedOverrides.length} 个覆盖声明。');
  if (manifest['snapshotKind'] == 'flutter-private-dependencies') stdout.writeln('🔐 私库模式：仅恢复 Git、path、自建 Pub 源；公共 Pub 包仍按原声明获取。');
  stdout.writeln('导入位置：vendor/flutter_dependencies/<独立运行目录>/packages/');
  for (final package in plan.packages) {
    stdout.writeln(
      '  ${package.name} ${package.version} [${package.source}]，${package.files.length} 个文件',
    );
  }
  stdout.writeln(
    plan.originalOverrides == null
        ? '配置：新建 pubspec_overrides.yaml；原 pubspec.yaml 与锁文件保持不变。'
        : '配置：增量更新 pubspec_overrides.yaml；原文件精确备份为本次目录/pubspec_overrides.yaml.before-import。',
  );
  stdout.writeln('不会执行 pub get、联网或运行包内代码；导入后请单独执行“拉取Flutter第三方依赖”。');
}

void execute(ImportPlan plan) {
  plan.verify();
  final parent = Directory(join(plan.project, 'vendor/flutter_dependencies'));
  parent.createSync(recursive: true);
  final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(
    RegExp(r'[^0-9]'),
    '',
  );
  final work = parent.createTempSync('import-$stamp-');
  final runName = work.uri.pathSegments.where((s) => s.isNotEmpty).last;
  final incomplete = File(join(work.path, '.incomplete'));
  incomplete.writeAsStringSync('尚未更新项目覆盖配置；此目录不是已完成导入。\n');
  String? temporaryConfig;
  try {
    if (plan.originalOverrides != null) {
      File(join(work.path, 'pubspec_overrides.yaml.before-import'))
          .writeAsBytesSync(plan.originalOverrides!.bytes, flush: true);
    }
    final paths = <String, String>{};
    for (final package in plan.packages) {
      paths[package.name] =
          'vendor/flutter_dependencies/$runName/packages/${package.name}';
      for (final item in package.files) {
        item.verify();
        final output = File(
          join(work.path, 'packages/${package.name}/${item.relative}'),
        );
        output.parent.createSync(recursive: true);
        File(item.path).copySync(output.path);
        item.verify();
        if (output.lengthSync() != item.stat.size || (item.digest != null && extraction.fileDigest(output) != item.digest)) {
          fail('复制长度不符：${item.path}');
        }
      }
    }
    File(join(work.path, 'source-manifest.json')).writeAsBytesSync(
      plan.snapshots
          .singleWhere((s) => s.file.path == join(plan.source, 'manifest.json'))
          .bytes,
      flush: true,
    );
    File(join(work.path, 'import.json')).writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert({'formatVersion': 1, 'source': plan.source, 'project': plan.project, 'createdAt': DateTime.now().toUtc().toIso8601String(), 'overridesExisted': plan.originalOverrides != null, 'restoredPubspecOverrides': plan.restoredPubspecOverrides, 'packages': paths})}\n',
      flush: true,
    );
    final text = checkedOverrides(plan, paths);
    // 独立临时目录保证临时文件不覆盖用户已有文件。
    final configDirectory = Directory(plan.project)
        .createTempSync('.flutter-dependency-import-');
    temporaryConfig = configDirectory.path;
    final configFile = File(
      join(configDirectory.path, 'pubspec_overrides.yaml'),
    );
    configFile.writeAsStringSync(text, flush: true);
    plan.verify();
    for (final relative in ['vendor', 'vendor/flutter_dependencies']) {
      requireDirectory(join(plan.project, relative));
    }
    requireDirectory(work.path);
    configFile.renameSync(join(plan.project, 'pubspec_overrides.yaml'));
    try {
      incomplete.deleteSync();
    } catch (error) {
      stderr.writeln('⚠ 配置已发布，导入已完成；仅未能清理标记 ${incomplete.path}：$error');
    }
    stdout.writeln(
      '✔ 导入完成：${work.path}\n✔ 已配置 ${paths.length} 个本地 path overrides。',
    );
    stdout.writeln(
      '恢复：先核对 pubspec_overrides.yaml 仍只有本次改动，再用本次备份还原；原文件不存在时只移除本次新增覆盖区。保留 vendor 中源码不会自动生效。',
    );
  } catch (_) {
    stderr.writeln('✖ 导入未完成，已复制文件保留：${work.path}');
    rethrow;
  } finally {
    if (temporaryConfig != null) {
      final directory = Directory(temporaryConfig);
      // 仅清理本进程新建的临时配置文件，不删除任何项目源码。
      final config = File(join(directory.path, 'pubspec_overrides.yaml'));
      try {
        if (config.existsSync()) config.deleteSync();
        if (directory.existsSync()) directory.deleteSync();
      } catch (error) {
        stderr.writeln('⚠ 未能清理本次临时配置目录：$temporaryConfig；$error');
      }
    }
  }
}

void main(List<String> arguments) {
  try {
    final privateOnly = arguments.contains('--private-only');
    arguments = arguments.where((arg) => arg != '--private-only').toList();
    if ((arguments.length != 4 && arguments.length != 5) ||
        arguments[0] != '--project' ||
        arguments[2] != '--source' ||
        (arguments.length == 5 && arguments[4] != '--validate-only')) {
      fail(
        '用法：dart ImportFlutterDependencies.dart --project <Flutter项目> --source <导出快照目录> [--validate-only]',
      );
    }
    final plan = validate(arguments[1], arguments[3], privateOnly: privateOnly);
    showPlan(plan);
    if (arguments.length == 4) execute(plan);
  } catch (error) {
    stderr.writeln('✖ 导入失败：$error');
    exitCode = 1;
  }
}
