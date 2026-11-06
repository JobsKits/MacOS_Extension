// Created by Jobs on 2026年11月4日，星期三。
// 只用临时 HOME 与真实 CLI 验证私库过滤、缓存识别、完整校验和冲突零写入。
import 'dart:convert';
import 'dart:io';

void write(String path, String text) {
  final file = File(path)..parent.createSync(recursive: true);
  file.writeAsStringSync(text);
}

Future<void> main() async {
  final root = Directory(
    Directory.systemTemp
        .createTempSync('JobsMigration 测试 ')
        .resolveSymbolicLinksSync(),
  );
  final toolsDirectory = Platform.environment['JOBS_TEST_TOOLS_DIR'];
  final tool = toolsDirectory == null
      ? File.fromUri(Platform.script).parent.parent.parent.uri
            .resolve('Scripts/Tools/FlutterDependencyMigration.dart')
            .toFilePath()
      : Directory(toolsDirectory).absolute.uri
            .resolve('FlutterDependencyMigration.dart')
            .toFilePath();
  final project = '${root.path}/source';
  final target = '${root.path}/target';
  final destination = '${root.path}/output';
  final home = '${root.path}/home';
  final donor = '${root.path}/donor';
  final gradle = '$donor/renamed android';
  final cache = '$donor/renamed dart';
  final targetGradle = '$home/gradle';
  final targetPub = '$home/pub';
  var assertions = 0;
  void expect(bool value, String message) {
    assertions++;
    if (!value) throw StateError(message);
  }

  final environment = {
    'HOME': home,
    'USERPROFILE': home,
    'LOCALAPPDATA': home,
    'GRADLE_USER_HOME': targetGradle,
    'PUB_CACHE': targetPub,
    'MAVEN_REPO_LOCAL': '$home/maven',
  };
  Future<ProcessResult> run(
    List<String> args, [
    Map<String, String> extra = const {},
  ]) async {
    final env = {...environment, ...extra};
    if (args.contains('--apply')) {
      final previewArgs = args.where((arg) => arg != '--apply').toList();
      final preview = await Process.run(Platform.resolvedExecutable, [
        tool,
        ...previewArgs,
      ], environment: env);
      if (preview.exitCode != 0) return preview;
      final line = '${preview.stdout}'
          .split('\n')
          .singleWhere((line) => line.startsWith('JOBS_MIGRATION_PLAN='));
      args = [
        ...args,
        '--expected-plan',
        line.substring('JOBS_MIGRATION_PLAN='.length),
      ];
    }
    return Process.run(Platform.resolvedExecutable, [
      tool,
      ...args,
    ], environment: env);
  }

  const spec = '''name: migration_fixture
dependencies:
  flutter:
    sdk: flutter
  alpha:
    git: https://private.invalid/alpha.git
  beta: ^1.0.0
''';
  try {
    Directory(home).createSync();
    Directory(destination).createSync();
    write('$project/pubspec.yaml', spec);
    write('$target/pubspec.yaml', spec);
    write(
      '$gradle/caches/modules-2/files-2.1/private.group/a/1/hash/a.jar',
      'private jar',
    );
    write(
      '$gradle/caches/modules-2/files-2.1/public.group/b/1/hash/b.jar',
      'public jar',
    );
    write(
      '$gradle/caches/modules-2/metadata-2.100/module-artifact.bin',
      'mutable index',
    );
    write(
      '$gradle/caches/modules-2/metadata-2.100/descriptors/private.group/a/1/repo/descriptor.bin',
      'private descriptor',
    );
    write(
      '$gradle/wrapper/dists/gradle-8.0-all/hash/gradle.zip',
      'distribution',
    );
    write('$gradle/gradle.properties', 'do not copy credentials');
    write('$gradle/init.d/evil.gradle', 'do not execute');
    write(
      '$cache/hosted/pub.dev/beta-1.0.0/pubspec.yaml',
      'name: beta\nversion: 1.0.0\n',
    );
    write('$cache/hosted/pub.dev/beta-1.0.0/lib/beta.dart', '// beta');
    write('$cache/hosted/pub.dev/.cache/beta-versions.json', 'mutable index');
    write('$cache/credentials.json', 'never copy');
    final alpha = '${root.path}/resolved/alpha';
    final beta = '$cache/hosted/pub.dev/beta-1.0.0';
    final flutter = '${root.path}/resolved/flutter';
    write('$alpha/pubspec.yaml', 'name: alpha\nversion: 1.0.0\n');
    write('$alpha/lib/alpha.dart', '// alpha');
    write('$flutter/pubspec.yaml', 'name: flutter\nversion: 0.0.0\n');
    write('$project/pubspec.lock', '''packages:
  alpha:
    source: git
    version: "1.0.0"
  beta:
    description:
      name: beta
      url: "https://pub.dev"
    source: hosted
    version: "1.0.0"
  flutter:
    source: sdk
    version: "0.0.0"
''');
    write('$project/android/build.gradle.kts', '''repositories {
  maven {
    url = uri("https://private.invalid/maven")
    content { includeGroup("private.group") }
  }
}
''');
    write('$project/ios/Podfile.lock', '''SPEC REPOS:
  trunk:
    - PublicPod
  https://private.invalid/specs:
    - PrivatePod
''');
    write('$project/ios/Pods/PrivatePod/src.m', '// private');
    write('$project/ios/Pods/PrivatePod/Cargo.lock', 'functional lock');
    write('$project/ios/Pods/PublicPod/src.m', '// public');
    write(
      '$project/ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved',
      '{"version":2,"pins":[{"identity":"private-spm","location":"https://private.invalid/spm.git"}]}',
    );
    write(
      '$project/.jobs/dependencies/spm/checkouts/private-spm/Package.swift',
      '// swift package',
    );
    write('$project/node_modules/private-web/index.js', '// private web');
    write('$project/node_modules/public-web/index.js', '// public web');
    write('$project/package-lock.json', '''{
// generated lock comment
"packages": {
  "node_modules/private-web": {"resolved":"https://private.invalid/pkg.tgz"},
  "node_modules/public-web": {"resolved":"https://registry.npmjs.org/public.tgz"},
},
}''');
    write(
      '$project/ohos/oh_modules/.store/private/index.ets',
      '// private ohpm',
    );
    Link('$project/ohos/oh_modules/@company/sdk').parent
        .createSync(recursive: true);
    Link('$project/ohos/oh_modules/@company/sdk')
        .createSync('../.store/private');
    write(
      '$project/ohos/oh-package-lock.json5',
      '{"packages":{"@company/sdk@1.0.0":{"name":"@company/sdk","resolved":"https://private.invalid/sdk.har"}}}',
    );
    write(
      '$project/.dart_tool/package_config.json',
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {
            'name': 'migration_fixture',
            'rootUri': Directory(project).uri.toString(),
          },
          {'name': 'alpha', 'rootUri': Directory(alpha).uri.toString()},
          {'name': 'beta', 'rootUri': Directory(beta).uri.toString()},
          {'name': 'flutter', 'rootUri': Directory(flutter).uri.toString()},
        ],
      }),
    );
    final preview = await run([
      'import',
      '--project',
      target,
      '--source',
      donor,
    ]);
    expect(
      preview.exitCode == 0,
      'renamed parent content preview failed: ${preview.stderr}',
    );
    expect(
      !Directory(targetGradle).existsSync() &&
          !Directory(targetPub).existsSync(),
      'preview mutated cache',
    );
    final imported = await run([
      'import',
      '--project',
      target,
      '--source',
      donor,
      '--apply',
    ]);
    expect(
      imported.exitCode == 0,
      'raw cache merge failed: ${imported.stderr}',
    );
    expect(
      File('$targetGradle/caches/modules-2/files-2.1/private.group/a/1/hash/a.jar')
              .readAsStringSync() ==
          'private jar',
      'Gradle artifact not merged',
    );
    expect(
      File('$targetPub/hosted/pub.dev/beta-1.0.0/lib/beta.dart').existsSync(),
      'Pub renamed cache not merged',
    );
    expect(
      !File('$targetGradle/gradle.properties').existsSync() &&
          !Directory('$targetGradle/init.d').existsSync() &&
          !File('$targetPub/credentials.json').existsSync(),
      'credentials or executable config imported',
    );
    expect(
      !File('$targetGradle/caches/modules-2/metadata-2.100/module-artifact.bin')
              .existsSync() &&
          !Directory('$targetPub/hosted/pub.dev/.cache').existsSync(),
      'mutable shared index imported',
    );
    final repeated = await run([
      'import',
      '--project',
      target,
      '--source',
      donor,
      '--apply',
    ]);
    expect(
      repeated.exitCode == 0 && '${repeated.stdout}'.contains('新增 0'),
      'cache merge not idempotent',
    );
    write(
      '$gradle/caches/modules-2/files-2.1/new.group/c/1/hash/c.jar',
      'must not write on conflict',
    );
    write(
      '$targetGradle/caches/modules-2/files-2.1/private.group/a/1/hash/a.jar',
      'existing independent value',
    );
    final conflict = await run([
      'import',
      '--project',
      target,
      '--source',
      donor,
      '--apply',
    ]);
    expect(conflict.exitCode != 0, 'conflict accepted');
    expect(
      !File('$targetGradle/caches/modules-2/files-2.1/new.group/c/1/hash/c.jar')
          .existsSync(),
      'conflict partially wrote another artifact',
    );
    expect(
      File('$targetGradle/caches/modules-2/files-2.1/private.group/a/1/hash/a.jar')
              .readAsStringSync() ==
          'existing independent value',
      'conflict overwritten',
    );
    final result = await run(
      ['export', '--project', project, '--destination', destination],
      {'GRADLE_USER_HOME': gradle, 'PUB_CACHE': cache},
    );
    expect(
      result.exitCode == 0,
      'private export failed: ${result.stdout}\n${result.stderr}',
    );
    final outputLine = '${result.stdout}'
        .split('\n')
        .singleWhere((v) => v.startsWith('JOBS_MIGRATION_OUTPUT='));
    final bundle = outputLine.substring('JOBS_MIGRATION_OUTPUT='.length);
    final manifest =
        jsonDecode(File('$bundle/migration.json').readAsStringSync()) as Map;
    final files = manifest['files'] as List;
    bool has(String kind, String path) =>
        files.any((row) => row['kind'] == kind && row['path'] == path);
    expect(
      has('gradle', 'caches/modules-2/files-2.1/private.group/a/1/hash/a.jar'),
      'private Maven group missing',
    );
    expect(
      !files.any((row) => '${row['path']}'.contains('public.group')),
      'private export included public Maven group',
    );
    expect(
      has(
        'gradle',
        'caches/modules-2/metadata-2.100/descriptors/private.group/a/1/repo/descriptor.bin',
      ),
      'private Maven descriptor missing',
    );
    expect(
      has('pods-ios', 'PrivatePod/src.m') &&
          has('pods-ios', 'PrivatePod/Cargo.lock') &&
          !has('pods-ios', 'PublicPod/src.m'),
      'Pod private selection or functional lock failed',
    );
    expect(
      has('spm-project', 'checkouts/private-spm/Package.swift'),
      'managed SPM root missing',
    );
    expect(
      has('web-root', 'private-web/index.js') &&
          !has('web-root', 'public-web/index.js'),
      'npm private lock selection failed',
    );
    expect(
      has('ohos', '@company/sdk/index.ets'),
      'OHPM in-root symlink not materialized',
    );
    final snapshot = manifest['pubSnapshot'] as String;
    expect(
      Directory('$bundle/$snapshot/packages/alpha').existsSync() &&
          !Directory('$bundle/$snapshot/packages/beta').existsSync(),
      'Pub private selection failed',
    );
    final cleanTarget = '${root.path}/clean target';
    write('$cleanTarget/pubspec.yaml', spec);
    for (final path in (manifest['projectFiles'] as Map).keys) {
      if (File('$project/$path').existsSync()) {
        File('$cleanTarget/$path').parent.createSync(recursive: true);
        File('$project/$path').copySync('$cleanTarget/$path');
      }
    }
    final nativeImport = await run(
      ['import', '--project', cleanTarget, '--source', bundle, '--apply'],
      {'GRADLE_USER_HOME': '$home/fresh-gradle'},
    );
    expect(
      nativeImport.exitCode == 0,
      'private bundle import failed: ${nativeImport.stdout}\n${nativeImport.stderr}',
    );
    expect(
      File('$cleanTarget/pubspec_overrides.yaml').existsSync() &&
          File('$cleanTarget/ios/Pods/PrivatePod/src.m').existsSync(),
      'bundle Pub/platform restore missing',
    );
    final freshTarget = '${root.path}/tampered target';
    write('$freshTarget/pubspec.yaml', spec);
    for (final path in (manifest['projectFiles'] as Map).keys) {
      if (File('$project/$path').existsSync()) {
        File('$freshTarget/$path').parent.createSync(recursive: true);
        File('$project/$path').copySync('$freshTarget/$path');
      }
    }
    write('$freshTarget/ios/Podfile.lock', 'different native lock');
    final nativeMismatch = await run(
      ['import', '--project', freshTarget, '--source', bundle, '--apply'],
      {'GRADLE_USER_HOME': '$home/native-mismatch'},
    );
    expect(
      nativeMismatch.exitCode != 0 &&
          !Directory('$home/native-mismatch').existsSync(),
      'native lock mismatch accepted',
    );
    File('$project/ios/Podfile.lock').copySync('$freshTarget/ios/Podfile.lock');
    write('$bundle/payload/pods-ios/PrivatePod/src.m', 'tampered');
    final tampered = await run(
      ['import', '--project', freshTarget, '--source', bundle, '--apply'],
      {'GRADLE_USER_HOME': '$home/tamper-gradle'},
    );
    expect(
      tampered.exitCode != 0 &&
          !File('$freshTarget/pubspec_overrides.yaml').existsSync() &&
          !Directory('$home/tamper-gradle').existsSync(),
      'tampered hash accepted or wrote',
    );
    final all = await run(
      ['export', '--project', project, '--destination', destination, '--all'],
      {'GRADLE_USER_HOME': gradle, 'PUB_CACHE': cache},
    );
    expect(all.exitCode == 0, 'all export failed: ${all.stderr}');
    final allBundle = '${all.stdout}'
        .split('\n')
        .singleWhere((v) => v.startsWith('JOBS_MIGRATION_OUTPUT='))
        .substring('JOBS_MIGRATION_OUTPUT='.length);
    final allManifest = jsonDecode(
      File('$allBundle/migration.json').readAsStringSync(),
    );
    expect(
      (allManifest['files'] as List).any(
        (row) => '${row['path']}'.contains('public.group'),
      ),
      'all export missing public cache',
    );
    expect(
      Directory('$allBundle/${allManifest['pubSnapshot']}/packages/beta')
          .existsSync(),
      'all export missing public Pub package',
    );
    // 真实导入记录来自旧版本；一键导入只补缺失包，已有生效版本不被快照替换。
    final retainedSource = '${root.path}/保留版本 来源';
    final retainedTarget = '${root.path}/保留版本 目标';
    final retainedPackages = '${root.path}/保留版本 包';
    final retainedDonor = '${root.path}/保留版本 依赖';
    final retainedGradle = '$home/retained-gradle';
    final retainedPub = '$home/retained-pub';
    final retainedEnvironment = {
      'GRADLE_USER_HOME': retainedGradle,
      'PUB_CACHE': retainedPub,
    };
    write('$retainedSource/pubspec.yaml', spec);
    write('$retainedTarget/pubspec.yaml', spec);
    write('$retainedPackages/alpha/lib/alpha.dart', '// current alpha');
    write('$retainedPackages/beta/lib/beta.dart', '// missing beta');
    write('$retainedPackages/flutter/pubspec.yaml', 'name: flutter\n');
    void resolveRetained(String alphaVersion) {
      write(
        '$retainedPackages/alpha/pubspec.yaml',
        'name: alpha\nversion: $alphaVersion\n',
      );
      write(
        '$retainedPackages/beta/pubspec.yaml',
        'name: beta\nversion: 1.0.0\n',
      );
      write('$retainedSource/pubspec.lock', '''packages:
  alpha:
    source: git
    version: "$alphaVersion"
  beta:
    source: hosted
    version: "1.0.0"
  flutter:
    source: sdk
    version: "0.0.0"
''');
      write(
        '$retainedSource/.dart_tool/package_config.json',
        jsonEncode({
          'configVersion': 2,
          'packages': [
            {
              'name': 'migration_fixture',
              'rootUri': Directory(retainedSource).uri.toString(),
            },
            for (final name in ['alpha', 'beta', 'flutter'])
              {
                'name': name,
                'rootUri': Directory('$retainedPackages/$name').uri.toString(),
              },
          ],
        }),
      );
    }

    Future<String> exportRetained(String output) async {
      final result = await Process.run(Platform.resolvedExecutable, [
        File(tool).parent.uri
            .resolve('ExtractFlutterDependencies.dart')
            .toFilePath(),
        '--project',
        retainedSource,
        '--destination',
        output,
      ], environment: environment);
      expect(result.exitCode == 0, 'retained fixture export: ${result.stderr}');
      return Directory(output).listSync().whereType<Directory>().single.path;
    }

    Map<String, String> retainedState(String path) => {
      for (final file in Directory(
        path,
      ).listSync(recursive: true, followLinks: false).whereType<File>())
        file.path: base64Encode(file.readAsBytesSync()),
    };
    resolveRetained('0.9.0');
    final oldRetainedSnapshot = await exportRetained('${root.path}/保留版本 旧快照');
    final seeded = await run([
      'import',
      '--project',
      retainedTarget,
      '--source',
      oldRetainedSnapshot,
      '--apply',
    ], retainedEnvironment);
    expect(seeded.exitCode == 0, 'seed managed version: ${seeded.stderr}');
    final oldRun = Directory('$retainedTarget/vendor/flutter_dependencies')
        .listSync()
        .whereType<Directory>()
        .single;
    final oldReceipt = jsonDecode(
      File('${oldRun.path}/import.json').readAsStringSync(),
    ) as Map;
    final retainedAlpha = (oldReceipt['packages'] as Map)['alpha'] as String;
    final retainedOverride =
        '# 保留工程现有版本\ndependency_overrides:\n  alpha:\n    path: ${jsonEncode(retainedAlpha)}\n  untouched: ^7.0.0\n';
    write('$retainedTarget/pubspec_overrides.yaml', retainedOverride);
    resolveRetained('2.0.0');
    write('$retainedPackages/alpha/lib/alpha.dart', '// incoming alpha');
    await exportRetained(retainedDonor);
    const retainedJar = 'caches/modules-2/files-2.1/company/a/1/hash/a.jar';
    write('$retainedDonor/改名 Gradle/$retainedJar', 'missing cache artifact');
    final retainedArgs = [
      'import',
      '--project',
      retainedTarget,
      '--source',
      retainedDonor,
    ];
    final beforeRetained = retainedState(retainedTarget);
    final retainedPreview = await run(retainedArgs, retainedEnvironment);
    expect(
      retainedPreview.exitCode == 0 &&
          '${retainedPreview.stdout}'.contains('0.9.0') &&
          '${retainedPreview.stdout}'.contains('2.0.0'),
      'preview must show retained and snapshot versions: ${retainedPreview.stdout}\n${retainedPreview.stderr}',
    );
    expect(
      jsonEncode(beforeRetained) == jsonEncode(retainedState(retainedTarget)) &&
          !Directory(retainedGradle).existsSync() &&
          !Directory(retainedPub).existsSync(),
      'retained-version preview wrote project or caches',
    );
    final retainedImport = await run([
      ...retainedArgs,
      '--apply',
    ], retainedEnvironment);
    expect(
      retainedImport.exitCode == 0,
      'retained-version import failed: ${retainedImport.stdout}\n${retainedImport.stderr}',
    );
    final retainedText = File('$retainedTarget/pubspec_overrides.yaml')
        .readAsStringSync();
    expect(
      retainedText.contains('path: ${jsonEncode(retainedAlpha)}') &&
          File('$retainedTarget/$retainedAlpha/pubspec.yaml')
              .readAsStringSync()
              .contains('version: 0.9.0') &&
          File('$retainedTarget/$retainedAlpha/lib/alpha.dart')
                  .readAsStringSync() ==
              '// current alpha' &&
          retainedText.contains('# 保留工程现有版本') &&
          retainedText.contains('untouched: ^7.0.0'),
      'existing effective version, path or unrelated configuration changed',
    );
    final retainedRuns = Directory(
      '$retainedTarget/vendor/flutter_dependencies',
    ).listSync().whereType<Directory>().toList();
    expect(
      retainedRuns.length == 2,
      'missing package must have independent run',
    );
    final newRetainedRun = retainedRuns.singleWhere(
      (d) => d.path != oldRun.path,
    );
    expect(
      Directory('${newRetainedRun.path}/packages/beta').existsSync() &&
          !Directory('${newRetainedRun.path}/packages/alpha').existsSync() &&
          File('${newRetainedRun.path}/pubspec_overrides.yaml.before-import')
                  .readAsStringSync() ==
              retainedOverride &&
          File('$retainedGradle/$retainedJar').readAsStringSync() ==
              'missing cache artifact',
      'must import only missing beta/cache and back up exact configuration',
    );
    final completedRetained = retainedState(retainedTarget);
    final repeatedRetained = await run([
      ...retainedArgs,
      '--apply',
    ], retainedEnvironment);
    expect(
      repeatedRetained.exitCode == 0 &&
          jsonEncode(completedRetained) ==
              jsonEncode(retainedState(retainedTarget)) &&
          Directory('$retainedTarget/vendor/flutter_dependencies')
                  .listSync()
                  .whereType<Directory>()
                  .length ==
              2,
      'repeat import must reuse effective dependencies without new vendor runs: ${repeatedRetained.stderr}',
    );
    final unknownTarget = '${root.path}/未知自定义 目标';
    write('$unknownTarget/pubspec.yaml', spec);
    write(
      '$unknownTarget/pubspec_overrides.yaml',
      'dependency_overrides:\n  alpha:\n    path: custom-alpha\n',
    );
    write(
      '$unknownTarget/custom-alpha/pubspec.yaml',
      'name: alpha\nversion: 0.9.0\n',
    );
    final unknownBefore = retainedState(unknownTarget);
    final unknownImport = await run(
      [
        'import',
        '--project',
        unknownTarget,
        '--source',
        retainedDonor,
        '--apply',
      ],
      {
        'GRADLE_USER_HOME': '$home/unknown-gradle',
        'PUB_CACHE': '$home/unknown-pub',
      },
    );
    expect(
      unknownImport.exitCode != 0 &&
          jsonEncode(unknownBefore) ==
              jsonEncode(retainedState(unknownTarget)) &&
          !Directory('$home/unknown-gradle').existsSync() &&
          !Directory('$home/unknown-pub').existsSync(),
      'unknown custom overrides must reject without any dependency/cache writes',
    );
    final consentEnv = {
      ...environment,
      'GRADLE_USER_HOME': '$home/consent-gradle',
      'PUB_CACHE': '$home/consent-pub',
    };
    final consentArgs = ['import', '--project', target, '--source', donor];
    final consentPreview = await Process.run(Platform.resolvedExecutable, [
      tool,
      ...consentArgs,
    ], environment: consentEnv);
    expect(consentPreview.exitCode == 0, 'consent preview failed');
    final token = '${consentPreview.stdout}'
        .split('\n')
        .singleWhere((line) => line.startsWith('JOBS_MIGRATION_PLAN='))
        .substring('JOBS_MIGRATION_PLAN='.length);
    write(
      '$gradle/caches/modules-2/files-2.1/added.after.preview/a/1/hash/a.jar',
      'unseen addition',
    );
    final changed = await Process.run(Platform.resolvedExecutable, [
      tool,
      ...consentArgs,
      '--apply',
      '--expected-plan',
      token,
    ], environment: consentEnv);
    expect(
      changed.exitCode != 0 &&
          !Directory('$home/consent-gradle').existsSync() &&
          !Directory('$home/consent-pub').existsSync(),
      'changed confirmation plan imported unseen file',
    );
    // 真实本地 Git → 原始 Pub 缓存 → 改名导入 → pub get --offline，原仓移走确保不靠回源。
    final seed = '${root.path}/git-seed';
    write(
      '$seed/pubspec.yaml',
      'name: git_dep\nversion: 1.0.0\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\n',
    );
    write('$seed/lib/git_dep.dart', '// actual Git dependency');
    for (final args in [
      ['init', seed],
      ['-C', seed, 'add', '.'],
      [
        '-C',
        seed,
        '-c',
        'user.name=Fixture',
        '-c',
        'user.email=fixture@example.invalid',
        'commit',
        '-m',
        'fixture',
      ],
    ]) {
      final git = await Process.run('git', args, environment: environment);
      expect(git.exitCode == 0, 'local Git fixture failed: ${git.stderr}');
    }
    final prepare = '${root.path}/git-prepare';
    final gitSourceCache = '${root.path}/renamed git pub cache';
    final gitSpec =
        'name: git_fixture\nenvironment:\n  sdk: ">=3.0.0 <4.0.0"\ndependencies:\n  git_dep:\n    git: ${Directory(seed).uri}\n';
    write('$prepare/pubspec.yaml', gitSpec);
    final prepared = await Process.run(
      Platform.resolvedExecutable,
      ['pub', 'get'],
      workingDirectory: prepare,
      environment: {
        ...environment,
        'PUB_CACHE': gitSourceCache,
        'DART_SUPPRESS_ANALYTICS': 'true',
      },
    );
    expect(
      prepared.exitCode == 0,
      'local-only Git pub preparation failed: ${prepared.stdout}\n${prepared.stderr}',
    );
    Directory(seed).renameSync('${root.path}/moved-git-seed');
    final gitTarget = '${root.path}/git-target';
    write(
      '$gitTarget/pubspec.yaml',
      gitSpec.replaceFirst(
        'dependencies:\n',
        'dependencies:\n  flutter:\n    sdk: flutter\n',
      ),
    );
    final offlineCache = '$home/offline-pub';
    final rawGit = await run(
      ['import', '--project', gitTarget, '--source', gitSourceCache, '--apply'],
      {'PUB_CACHE': offlineCache},
    );
    expect(
      rawGit.exitCode == 0,
      'raw Git Pub cache merge failed: ${rawGit.stdout}\n${rawGit.stderr}',
    );
    File('$prepare/pubspec.lock').copySync('$gitTarget/pubspec.lock');
    write('$gitTarget/pubspec.yaml', gitSpec);
    final offline = await Process.run(
      Platform.resolvedExecutable,
      ['pub', 'get', '--offline'],
      workingDirectory: gitTarget,
      environment: {
        ...environment,
        'PUB_CACHE': offlineCache,
        'DART_SUPPRESS_ANALYTICS': 'true',
      },
    );
    expect(
      offline.exitCode == 0,
      'imported raw Git cache did not resolve offline: ${offline.stdout}\n${offline.stderr}',
    );
    stdout.writeln(
      'PASS $assertions assertions; isolated temporary HOME, no downloads or real environment writes.',
    );
  } finally {
    if (Platform.environment['JOBS_KEEP_FIXTURE'] == '1') {
      stdout.writeln('FIXTURE=${root.path}');
    } else {
      root.deleteSync(recursive: true);
    }
  }
}
