// Self-contained Flutter project diagnostics and maintenance, shared by macOS / Windows.
// Uses the selected project's FVM SDK; no packages, global SDK installation or shell edits.
import 'dart:convert';
import 'dart:io';

String join(String a, String b) => '$a${Platform.pathSeparator}$b';
String get home => Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'] ?? '';
Never fail(String message) => throw StateError(message);
bool file(String path) => File(path).existsSync();
bool dir(String path) => Directory(path).existsSync();
String read(String path) {
  if (!file(path) || File(path).lengthSync() > 8 * 1024 * 1024) fail('文件缺失或超过 8 MiB：$path');
  return File(path).readAsStringSync();
}
Map<String, dynamic> object(String path) {
  final value = jsonDecode(read(path));
  if (value is! Map<String, dynamic>) fail('需要 JSON 对象：$path');
  return value;
}
bool confirm(String message, {String word = ''}) {
  stdout.writeln(message);
  if (!stdin.hasTerminal) fail('请在交互终端执行；预览可用 --dry-run。');
  final answer = stdin.readLineSync();
  return answer != null && answer == word;
}
Future<ProcessResult> run(String command, List<String> args, String project,
    {Map<String, String>? environment, int seconds = 120}) async {
  // Process.start on Windows cannot directly execute .bat; command tokens are individually escaped.
  var executable = command;
  var arguments = args;
  if (Platform.isWindows && RegExp(r'\.(bat|cmd)$', caseSensitive: false).hasMatch(command)) {
    String quote(String s) {
      if (RegExp(r'["%\r\n\x00]').hasMatch(s)) fail('批处理参数含不支持的字符：$s');
      return '"$s"';
    }
    executable = join(Platform.environment['SystemRoot'] ?? r'C:\Windows', 'System32/cmd.exe');
    arguments = ['/d', '/v:off', '/s', '/c', '"${[command, ...args].map(quote).join(' ')}"'];
  }
  final process = await Process.start(executable, arguments, workingDirectory: project, environment: environment);
  final output = process.stdout.transform(utf8.decoder).join();
  final error = process.stderr.transform(utf8.decoder).join();
  int code;
  try { code = await process.exitCode.timeout(Duration(seconds: seconds)); }
  catch (_) {
    if (Platform.isWindows) {
      await Process.run(join(Platform.environment['SystemRoot'] ?? r'C:\Windows', 'System32/taskkill.exe'), ['/PID', '${process.pid}', '/T', '/F']);
    } else { process.kill(ProcessSignal.sigkill); }
    fail('命令超时（$seconds 秒）：$command ${args.join(' ')}');
  }
  return ProcessResult(process.pid, code, await output, await error);
}
String cleanOutput(ProcessResult result) => '${result.stdout}\n${result.stderr}'.replaceAll(RegExp(r'\x1b\[[0-?]*[ -/]*[@-~]'), '').trim();

class Project {
  final String root;
  late String sdk, flutter, dart, pin;
  Project(String path) : root = Directory(path).resolveSymbolicLinksSync() {
    if (!dir(root) || !file(join(root, 'pubspec.yaml')) || !dir(join(root, 'lib'))) fail('请选择 Flutter 工程根目录。');
    final yaml = read(join(root, 'pubspec.yaml'));
    if (!RegExp(r'\bsdk\s*:\s*["\x27]?flutter\b').hasMatch(yaml)) fail('pubspec.yaml 未声明 Flutter SDK。');
    final modern = join(root, '.fvmrc'), legacy = join(root, '.fvm/fvm_config.json');
    final config = object(file(modern) ? modern : legacy);
    final selected = config['flutter'] ?? config['flutterSdkVersion'];
    if (selected is! String || selected.isEmpty || RegExp(r'[\x00-\x1f]').hasMatch(selected)) fail('FVM 版本声明无效。');
    pin = selected;
    final link = join(root, '.fvm/flutter_sdk');
    if (!dir(link)) fail('FVM SDK 缺失；请先通过“安装/切换Flutter SDK版本”补齐。');
    sdk = Directory(link).resolveSymbolicLinksSync();
    flutter = join(sdk, Platform.isWindows ? 'bin/flutter.bat' : 'bin/flutter');
    dart = join(sdk, Platform.isWindows ? 'bin/cache/dart-sdk/bin/dart.exe' : 'bin/cache/dart-sdk/bin/dart');
    if (!file(flutter) || !file(dart)) fail('FVM SDK 缺少 Flutter 或同源 Dart；不会回退全局 SDK。');
  }
  Future<ProcessResult> flutterRun(List<String> args, {int seconds = 600, Map<String, String>? environment}) => run(flutter, args, root, seconds: seconds, environment: environment);
}

class Checks {
  int failed = 0;
  Future<void> check(String title, Future<void> Function() operation) async {
    try { await operation(); stdout.writeln('✔ $title'); }
    catch (e) { failed++; stdout.writeln('✖ $title：$e'); }
  }
}

String? findExecutable(String name, List<String> candidates) {
  for (final path in [...candidates, ...?Platform.environment['PATH']?.split(Platform.isWindows ? ';' : ':').map((d) => join(d, name))]) {
    if (file(path)) return path;
  }
  return null;
}

Future<void> diagnose(Project p, bool harmony) async {
  stdout.writeln('${harmony ? '鸿蒙Flutter环境体检' : '原生Flutter项目体检'}\n项目：${p.root}\nFVM：${p.pin}\nSDK：${p.sdk}');
  stdout.writeln('检查可能访问工具配置的网络并初始化 SDK 缓存；不安装、切换或升级 SDK。');
  final checks = Checks();
  final environment = <String, String>{};
  String? toolRoot, sdkRoot;
  if (harmony) {
    await checks.check('DevEco / CLT 与 SDK 定位', () async {
      final configured = Platform.environment['DEVECO_STUDIO_HOME'] ?? Platform.environment['TOOL_HOME'];
      final candidates = <String>[];
      if (configured != null && configured.isNotEmpty) {
        candidates.add(configured.endsWith('.app') ? join(configured, 'Contents') : configured);
      } else {
        final base = Platform.isWindows ? join(Platform.environment['LOCALAPPDATA'] ?? home, 'Jobs/HarmonySimulator/tools') : join(home, 'Library/Application Support/JobsHarmonySimulator');
        if (dir(base)) candidates.addAll(Directory(base).listSync().whereType<Directory>().where((d) => d.path.split(Platform.pathSeparator).last.startsWith('clt-')).map((d) => d.path));
        if (!Platform.isWindows && dir('/Applications')) candidates.addAll(Directory('/Applications').listSync().whereType<Directory>().where((d) => d.path.contains('DevEco') && d.path.endsWith('.app')).map((d) => join(d.path, 'Contents')));
      }
      final usable = candidates.where((r) => dir(join(r, 'sdk/default/openharmony'))).toSet().toList();
      if (usable.length != 1) fail('找到 ${usable.length} 套工具；请通过 TOOL_HOME 指定本次使用的 CLT 根目录或 DEVECO_STUDIO_HOME 指定 Studio。');
      toolRoot = usable.single;
      sdkRoot = join(toolRoot!, 'sdk');
      environment['TOOL_HOME'] = toolRoot!;
      environment['DEVECO_SDK_HOME'] = sdkRoot!;
      environment['OHOS_SDK_HOME'] = join(sdkRoot!, 'default/openharmony');
      final paths = [join(toolRoot!, 'node/bin'), join(toolRoot!, 'node'), join(toolRoot!, 'tools/node/bin'), join(toolRoot!, 'tools/node'), join(toolRoot!, 'ohpm/bin'), join(toolRoot!, 'hvigor/bin'), join(toolRoot!, 'tools/ohpm/bin'), join(toolRoot!, 'tools/hvigor/bin'), join(sdkRoot!, 'default/openharmony/toolchains')];
      environment['PATH'] = [...paths, Platform.environment['PATH'] ?? ''].join(Platform.isWindows ? ';' : ':');
    });
  }
  await checks.check('FVM 工具', () async {
    final fvm = findExecutable(Platform.isWindows ? 'fvm.bat' : 'fvm', [
      if (Platform.isWindows) ...[join(Platform.environment['LOCALAPPDATA'] ?? home, 'Pub/Cache/bin/fvm.bat'), join(home, 'fvm/bin/fvm.exe'), ...?Platform.environment['PATH']?.split(';').map((d) => join(d, 'fvm.exe'))],
      join(home, '.pub-cache/bin/fvm'), join(home, 'fvm/bin/fvm')]);
    if (fvm == null) fail('找不到 FVM；本体检不会全局安装 Flutter。');
    final result = await run(fvm, ['--version'], p.root, seconds: 30);
    if (result.exitCode != 0 || cleanOutput(result).isEmpty) fail(cleanOutput(result));
    stdout.writeln(cleanOutput(result));
  });
  await checks.check('基础 Flutter 与 FVM 版本声明', () async {
    final result = await p.flutterRun(['--version', '--machine'], environment: environment);
    if (result.exitCode != 0) fail(cleanOutput(result));
    final data = jsonDecode('${result.stdout}');
    if (data is! Map || data['frameworkVersion'] is! String || data['dartSdkVersion'] is! String) fail('版本 JSON 不完整。');
    final base = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(p.pin)?.group(1);
    if (base != null && !(data['frameworkVersion'] as String).startsWith(base)) fail('FVM 声明 ${p.pin}，实际 ${data['frameworkVersion']}；请修复绑定。');
    stdout.writeln('Flutter ${data['frameworkVersion']}；Dart ${data['dartSdkVersion']}');
  });
  await checks.check('同源 Dart', () async {
    final result = await run(p.dart, ['--version'], p.root, seconds: 30);
    if (result.exitCode != 0 || !cleanOutput(result).contains('Dart SDK version:')) fail(cleanOutput(result));
  });
  await checks.check('Flutter 基础环境 doctor', () async {
    final result = await p.flutterRun(['doctor', '-v'], environment: environment);
    final output = cleanOutput(result);
    stdout.writeln(output);
    if (result.exitCode != 0 || RegExp(r'^\s*\[(?:!|✗|x)\]|Doctor found issues', multiLine: true, caseSensitive: false).hasMatch(output) || !RegExp(r'No issues found', caseSensitive: false).hasMatch(output)) fail('基础环境存在问题或无法确认健康结论。');
  });
  if (harmony) {
    await checks.check('当前 FVM SDK 的 Harmony 构建能力', () async {
      final result = await p.flutterRun(['build', '-h'], environment: environment);
      if (result.exitCode != 0 || !RegExp(r'^\s*hap\s', multiLine: true).hasMatch(cleanOutput(result))) fail('当前 FVM SDK 未提供 hap 构建命令；需在 FVM 中绑定 Harmony 适配分支。');
    });
    for (final entry in {'Node': ['node', '--version'], 'OHPM': ['ohpm', '--version'], 'Hvigor': ['hvigorw', '--version'], 'HDC': ['hdc', '-v'], 'Java': ['java', '-version']}.entries) {
      await checks.check(entry.key, () async {
        if (toolRoot == null) fail('DevEco 路径未就绪。');
        final name = entry.value.first;
        final suffix = Platform.isWindows ? (['ohpm', 'hvigorw'].contains(name) ? '.bat' : '.exe') : '';
        final javaHome = Platform.environment['JAVA_HOME'];
        final candidates = <String>[if (name == 'java' && javaHome != null) join(javaHome, 'bin/java$suffix')];
        for (final d in ['', 'bin', 'node', 'node/bin', 'ohpm/bin', 'hvigor/bin', 'tools/node', 'tools/node/bin', 'tools/ohpm/bin', 'tools/hvigor/bin', 'jbr/bin', 'jbr/Contents/Home/bin', 'sdk/default/openharmony/toolchains']) { candidates.add(join(join(toolRoot!, d), '$name$suffix')); }
        final executable = findExecutable('$name$suffix', candidates);
        if (executable == null) fail('缺少 $name；请准备配套工具。');
        final result = await run(executable, [entry.value.last], p.root, environment: environment, seconds: 60);
        if (result.exitCode != 0 || cleanOutput(result).isEmpty) fail(cleanOutput(result));
        stdout.writeln(cleanOutput(result));
      });
    }
    await checks.check('Harmony SDK 编译组件', () async {
      if (sdkRoot == null) fail('SDK 未定位。');
      for (final part in ['ets', 'native', 'toolchains']) { if (!dir(join(sdkRoot!, 'default/openharmony/$part'))) fail('SDK 缺少 $part'); }
    });
    await checks.check('项目 ohos 平台结构', () async {
      for (final name in ['ohos/build-profile.json5', 'ohos/oh-package.json5', 'ohos/AppScope/app.json5']) { if (!file(join(p.root, name))) fail('缺少 $name'); }
      if (!file(join(p.root, 'ohos/hvigorfile.ts')) && !file(join(p.root, 'ohos/hvigorfile.js'))) fail('缺少 ohos/hvigorfile');
    });
    await checks.check('第三方原生插件 Harmony 适配', () async {
      final packages = projectPackages(p);
      final unsupported = <String>[];
      for (final entry in packages.entries) {
        final spec = join(entry.value, 'pubspec.yaml');
        if (!file(spec)) continue;
        final yaml = read(spec);
        if (RegExp(r'^\s+plugin\s*:', multiLine: true).hasMatch(yaml) && !RegExp(r'^\s+ohos\s*:', multiLine: true).hasMatch(yaml)) unsupported.add(entry.key);
      }
      if (unsupported.isNotEmpty) fail('以下原生插件未声明 ohos 支持，请逐项核对替代/联邦实现：${unsupported.join(', ')}');
    });
  }
  if (checks.failed != 0) fail('${checks.failed} 项未通过；环境不健康。');
  stdout.writeln('✔ ${harmony ? '基础 Flutter 与 Harmony 所有检查均通过' : '原生 Flutter 环境体检通过'}。项目能否完成编译仍以实际构建为准。');
}

Map<String, String> projectPackages(Project p) {
  final configPath = join(p.root, '.dart_tool/package_config.json');
  final data = object(configPath);
  if (data['configVersion'] != 2 || data['packages'] is! List) fail('请先拉取 Flutter 第三方依赖，生成有效 package_config.json。');
  final result = <String, String>{};
  for (final entry in data['packages'] as List) {
    if (entry is! Map || entry['name'] is! String || entry['rootUri'] is! String) fail('依赖解析记录无效。');
    final uri = File(configPath).uri.resolve(entry['rootUri'] as String);
    if (uri.scheme != 'file' || !dir(uri.toFilePath())) fail('依赖路径不可用：${entry['name']}');
    final name = entry['name'] as String;
    if (result.containsKey(name)) fail('依赖解析记录重复：$name');
    result[name] = Directory.fromUri(uri).resolveSymbolicLinksSync();
  }
  final expectedFlutter = join(p.sdk, 'packages/flutter');
  if (!dir(expectedFlutter) || result['flutter'] != Directory(expectedFlutter).resolveSymbolicLinksSync()) fail('依赖清单没有指向当前 FVM SDK 的 Flutter；请先用此版本重新拉取第三方依赖。');
  return result;
}

class Edit {
  final String path, before, after;
  Edit(this.path, this.before, this.after);
}

String decodeChinese(String value) {
  // Decode only valid UTF-8 percent sequences containing non-ASCII letters, preserving URI delimiters.
  return value.replaceAllMapped(RegExp(r'(?:%[0-9a-fA-F]{2})+'), (m) {
    try {
      final decoded = Uri.decodeComponent(m[0]!);
      if (!decoded.runes.any((c) => c > 127) || RegExp(r'''[\x00-\x20/\\'"#$?]''').hasMatch(decoded)) return m[0]!;
      return decoded;
    } catch (_) { return m[0]!; }
  });
}

// Mask comments and quoted strings while preserving offsets; used to locate real Dart/Gradle statements.
String codeMask(String text) {
  final out = text.split('');
  var i = 0;
  void mask(int a, int b) { for (var j = a; j < b; j++) { if (out[j] != '\n' && out[j] != '\r') out[j] = ' '; } }
  while (i < text.length) {
    if (text.startsWith('//', i)) { final end = text.indexOf('\n', i); final b = end < 0 ? text.length : end; mask(i, b); i = b; }
    else if (text.startsWith('/*', i)) {
      final start = i; var depth = 1; i += 2;
      while (i < text.length && depth > 0) {
        if (text.startsWith('/*', i)) { depth++; i += 2; }
        else if (text.startsWith('*/', i)) { depth--; i += 2; }
        else { i++; }
      }
      mask(start, i);
    }
    else if (text[i] == '"' || text[i] == "'") {
      final start = i, quote = text[i];
      final triple = text.startsWith(quote * 3, i), delimiter = triple ? quote * 3 : quote;
      i += delimiter.length;
      while (i < text.length) { if (text[i] == '\\') { i += 2; continue; } if (text.startsWith(delimiter, i)) { i += delimiter.length; break; } i++; }
      if (i > text.length) i = text.length;
      mask(start, i);
    } else { i++; }
  }
  return out.join();
}

List<Edit> importEdits(Project p) {
  final edits = <Edit>[];
  final excluded = {'.git', '.fvm', '.dart_tool', 'build', '.import_backup', '.jobs_flutter_backups', 'Pods', 'node_modules'};
  void visit(Directory directory) {
    for (final entry in directory.listSync(followLinks: false)) {
      final name = entry.path.split(Platform.pathSeparator).last;
      if (entry is Directory && !excluded.contains(name) && !name.startsWith('.')) visit(entry);
      if (entry is! File || !name.endsWith('.dart')) continue;
      final original = read(entry.path), mask = codeMask(original);
      final replacements = <(int, int, String)>[];
      for (final match in RegExp(r'\b(?:import|export|part)\s+').allMatches(mask)) {
        final start = match.start;
        final statement = original.substring(start);
        final directive = RegExp(r'''^(?:import|export|part)\s+(['"])([^\r\n]*?)\1''').firstMatch(statement);
        if (directive == null) continue;
        final value = directive[2]!, decoded = decodeChinese(value);
        if (value != decoded) { final offset = start + directive[0]!.indexOf(directive[1]!) + 1; replacements.add((offset, offset + value.length, decoded)); }
      }
      var updated = original;
      for (final item in replacements.reversed) updated = updated.replaceRange(item.$1, item.$2, item.$3);
      if (updated != original) edits.add(Edit(entry.path, original, updated));
    }
  }
  visit(Directory(p.root));
  return edits;
}

List<Edit> namespaceEdits(Project p) {
  final edits = <Edit>[];
  for (final entry in projectPackages(p).entries) {
    final pluginSpec = join(entry.value, 'pubspec.yaml');
    if (!file(pluginSpec) || !RegExp(r'^\s+plugin\s*:', multiLine: true).hasMatch(read(pluginSpec))) continue;
    for (final name in ['build.gradle', 'build.gradle.kts']) {
      final path = join(entry.value, 'android/$name');
      if (!file(path) || FileSystemEntity.isLinkSync(path)) continue;
      final original = read(path), mask = codeMask(original);
      if (RegExp(r'\bnamespace\b').hasMatch(mask)) continue;
      final blocks = RegExp(r'^\s*android\s*\{', multiLine: true).allMatches(mask).toList();
      if (blocks.length != 1) { stdout.writeln('跳过无法确定 android 块的插件：${entry.key}'); continue; }
      final manifest = join(entry.value, 'android/src/main/AndroidManifest.xml');
      if (!file(manifest)) continue;
      final xml = read(manifest).replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
      final package = RegExp(r'''<manifest\b[^>]*\bpackage\s*=\s*['"]([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+)['"]''').firstMatch(xml)?[1];
      if (package == null) { stdout.writeln('跳过缺少明确 manifest package 的插件：${entry.key}'); continue; }
      final position = blocks.single.end;
      final newline = original.contains('\r\n') ? '\r\n' : '\n';
      final declaration = name.endsWith('.kts') ? 'namespace = "$package"' : "namespace '$package'";
      edits.add(Edit(path, original, original.replaceRange(position, position, '$newline    $declaration$newline')));
    }
  }
  return edits;
}

void applyEdits(Project p, List<Edit> edits, bool preview, String label) {
  stdout.writeln('$label：计划修改 ${edits.length} 个文件。');
  for (final edit in edits) stdout.writeln('  ${edit.path}');
  if (edits.isEmpty || preview) return;
  if (label.contains('namespace')) stdout.writeln('这些插件可能位于多个项目共用的 Pub 缓存；只处理本项目解析到的依赖，备份会保存到当前项目。');
  if (!confirm('输入 REPAIR 确认上述修改；其它输入取消：', word: 'REPAIR')) return;
  for (final edit in edits) { if (read(edit.path) != edit.before || FileSystemEntity.isLinkSync(edit.path)) fail('文件在预览后变化，未开始修复：${edit.path}'); }
  final backupRoot = join(p.root, '.jobs_flutter_backups');
  if (FileSystemEntity.isLinkSync(backupRoot)) fail('备份目录是链接，未修改文件。');
  final backup = Directory(join(backupRoot, '${DateTime.now().microsecondsSinceEpoch}'))..createSync(recursive: true);
  final manifest = <Map<String, String>>[];
  for (var i = 0; i < edits.length; i++) {
    final edit = edits[i], copy = join(backup.path, '$i.original');
    File(edit.path).copySync(copy);
    if (read(copy) != edit.before) fail('备份时文件发生变化，未开始写入：${edit.path}');
    manifest.add({'path': edit.path, 'backup': '$i.original'});
  }
  File(join(backup.path, 'manifest.json')).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest), flush: true);
  stdout.writeln('已完成原始文件备份：${backup.path}');
  for (final edit in edits) {
    if (FileSystemEntity.isLinkSync(edit.path) || read(edit.path) != edit.before) fail('文件被并发修改，停止后续写入；请核对备份：${backup.path}');
    final bytes = File(edit.path).readAsBytesSync();
    final bom = bytes.length >= 3 && bytes[0] == 0xef && bytes[1] == 0xbb && bytes[2] == 0xbf;
    File(edit.path).writeAsBytesSync([if (bom) ...[0xef, 0xbb, 0xbf], ...utf8.encode(edit.after)], flush: true);
  }
  stdout.writeln('✔ 修复完成。备份与原路径映射：${backup.path}');
}

void validateCacheTargets(List<String> targets) {
  // Inspect all targets before deleting any. A linked ancestor can redirect a safe-looking cache path.
  for (final target in targets) {
    var current = Directory(target).absolute;
    while (current.parent.path != current.path) {
      if (FileSystemEntity.isLinkSync(current.path)) fail('缓存路径包含链接，停止：${current.path}');
      current = current.parent;
    }
  }
}

Future<void> maintenance(Project p) async {
  stdout.writeln('Flutter清理维护工具\n项目：${p.root}\nFVM SDK：${p.sdk}');
  final options = ['刷新依赖（pub get）', '项目清理（clean 后 pub get，保留锁文件）', '升级项目依赖（pub upgrade --major-versions）', '修复 Pub 共享缓存', '清理 Pub 共享下载缓存（保留 FVM 可执行文件）', '清理 Gradle 共享 caches（保留配置与凭据）', '清理当前 FVM SDK 的 bin/cache（影响共用此版本的项目）', if (!Platform.isWindows) '清理本项目 iOS 生成缓存（保留 Podfile.lock / pubspec.lock / ios/Flutter 源文件）'];
  for (var i = 0; i < options.length; i++) stdout.writeln('${i + 1}、${options[i]}');
  if (!stdin.hasTerminal) fail('维护需在交互终端选择；没有执行清理。');
  stdout.write('输入编号，回车 / q 取消：');
  final choice = int.tryParse(stdin.readLineSync() ?? '');
  if (choice == null) return;
  if (choice < 1 || choice > options.length) fail('无效编号。');
  if (choice <= 4) {
    if (!confirm('将执行：${options[choice - 1]}。回车继续，其它输入取消：')) return;
    final commands = switch (choice) { 1 => [['pub', 'get']], 2 => [['clean'], ['pub', 'get']], 3 => [['pub', 'upgrade', '--major-versions']], _ => [['pub', 'cache', 'repair']] };
    for (final args in commands) { final result = await p.flutterRun(args, seconds: 1800); stdout.writeln(cleanOutput(result)); if (result.exitCode != 0) fail('维护失败（${result.exitCode}），已停止。'); }
    return;
  }
  final pubCache = Platform.environment['PUB_CACHE'] ?? (Platform.isWindows ? join(Platform.environment['LOCALAPPDATA'] ?? home, 'Pub/Cache') : join(home, '.pub-cache'));
  final gradle = Platform.environment['GRADLE_USER_HOME'] ?? join(home, '.gradle');
  for (final cacheRoot in [pubCache, gradle]) {
    final absolute = Directory(cacheRoot).absolute.path;
    if (!File(cacheRoot).isAbsolute || absolute == Directory(absolute).parent.path || absolute == home || absolute == p.root) fail('共享缓存根目录过于宽泛或不是绝对路径：$cacheRoot');
  }
  final targets = switch (choice) {
    5 => [join(pubCache, 'hosted'), join(pubCache, 'hosted-hashes'), join(pubCache, 'git')],
    6 => [join(gradle, 'caches')],
    7 => [join(p.sdk, 'bin/cache')],
    _ => ['ios/Pods', 'ios/.symlinks', 'ios/Flutter/ephemeral', 'build/ios'].map((x) => join(p.root, x)).toList()
  };
  validateCacheTargets(targets);
  stdout.writeln('将删除以下可再生成缓存；请先关闭相关构建进程：');
  for (final path in targets) stdout.writeln('  $path');
  if (!confirm('输入 CLEAN 确认；其它输入取消：', word: 'CLEAN')) return;
  validateCacheTargets(targets);
  for (final path in targets) {
    if (FileSystemEntity.isLinkSync(path)) fail('缓存路径是链接，停止：$path');
    if (dir(path)) Directory(path).deleteSync(recursive: true);
  }
  stdout.writeln('✔ 所选缓存清理完成；后续构建可能重新下载。');
}

Future<void> main(List<String> args) async {
  try {
    if (args.length < 2 || args.length > 3 || (args.length == 3 && args[2] != '--dry-run')) fail('用法：FlutterProjectTools.dart <动作> <项目目录> [--dry-run]');
    final p = Project(args[1]), preview = args.contains('--dry-run');
    switch (args[0]) {
      case 'native-doctor': case 'harmony-doctor':
        if (preview) { stdout.writeln('FVM ${p.pin}：${p.sdk}；尚未执行体检。'); break; }
        if (confirm('回车开始环境体检；其它输入取消：')) await diagnose(p, args[0] == 'harmony-doctor');
      case 'repair-imports': applyEdits(p, importEdits(p), preview, '修复 Flutter 项目中文路径（Dart URI）');
      case 'repair-namespace': applyEdits(p, namespaceEdits(p), preview, '修复 Flutter 插件 namespace');
      case 'maintenance': if (!preview) await maintenance(p); else stdout.writeln('清理仅在交互选择并确认后执行。');
      default: fail('未知动作：${args[0]}');
    }
  } catch (e) { stderr.writeln('✖ $e'); exitCode = 1; }
}
