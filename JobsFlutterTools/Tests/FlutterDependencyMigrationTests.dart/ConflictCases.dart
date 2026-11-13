// Created by Jobs on 2026年11月7日，星期六。
// 用普通临时缓存验证冲突选择、备份、确认指纹与覆盖失败撤回。
import 'dart:convert';
import 'dart:io';

Future<int> runConflictCases(String tool, Directory root) async {
  var assertions = 0;
  void expect(bool value, String message) {
    assertions++;
    if (!value) throw StateError(message);
  }

  void write(String path, String text) {
    File(path).parent.createSync(recursive: true);
    File(path).writeAsStringSync(text);
  }

  final base = '${root.path}/content conflicts';
  final donor = '$base/source cache';
  final relativeIndexes = [
    for (var i = 1; i <= 3; i++)
      'git/pkg-${i.toString().padLeft(40, '0')}/.git/index',
  ];
  for (var i = 0; i < relativeIndexes.length; i++) {
    final package = relativeIndexes[i].split('/')[1];
    write(
      '$donor/git/$package/pubspec.yaml',
      'name: fixture_$i\nversion: 1.0.0\n',
    );
    write('$donor/git/$package/lib/new.dart', '// new source $i');
    write('$donor/${relativeIndexes[i]}', 'source-index-$i\u0000binary');
  }

  var sequence = 0;
  Map<String, String> fixture() {
    final run = '$base/target ${sequence++}';
    write(
      '$run/project/pubspec.yaml',
      'name: conflict_fixture\ndependencies:\n  flutter:\n    sdk: flutter\n',
    );
    for (var i = 0; i < relativeIndexes.length; i++) {
      final package = relativeIndexes[i].split('/')[1];
      write(
        '$run/pub/git/$package/pubspec.yaml',
        'name: fixture_$i\nversion: 1.0.0\n',
      );
      write('$run/pub/${relativeIndexes[i]}', 'existing-index-$i\u0000binary');
    }
    Directory('$run/home').createSync();
    return {
      'HOME': '$run/home',
      'USERPROFILE': '$run/home',
      'LOCALAPPDATA': '$run/home',
      'PUB_CACHE': '$run/pub',
      'GRADLE_USER_HOME': '$run/gradle',
      'MAVEN_REPO_LOCAL': '$run/maven',
      'PROJECT': '$run/project',
    };
  }

  List<String> args(
    Map<String, String> env, [
    List<String> options = const [],
  ]) => ['import', '--project', env['PROJECT']!, '--source', donor, ...options];
  Future<ProcessResult> raw(Map<String, String> env, List<String> arguments) =>
      Process.run(Platform.resolvedExecutable, [
        tool,
        ...arguments,
      ], environment: env);
  String token(ProcessResult preview) => '${preview.stdout}'
      .split('\n')
      .singleWhere((line) => line.startsWith('JOBS_MIGRATION_PLAN='))
      .substring('JOBS_MIGRATION_PLAN='.length);
  Future<ProcessResult> apply(
    Map<String, String> env,
    List<String> options,
  ) async {
    final preview = await raw(env, args(env, options));
    if (preview.exitCode != 0) return preview;
    return raw(
      env,
      args(env, [...options, '--apply', '--expected-plan', token(preview)]),
    );
  }

  bool originals(Map<String, String> env) => [
    for (var i = 0; i < relativeIndexes.length; i++)
      File('${env['PUB_CACHE']}/${relativeIndexes[i]}').readAsStringSync() ==
          'existing-index-$i\u0000binary',
  ].every((value) => value);
  bool incoming(Map<String, String> env) => [
    for (var i = 0; i < relativeIndexes.length; i++)
      File('${env['PUB_CACHE']}/${relativeIndexes[i]}').readAsStringSync() ==
          'source-index-$i\u0000binary',
  ].every((value) => value);
  bool newFiles(Map<String, String> env) => [
    for (final path in relativeIndexes)
      File('${env['PUB_CACHE']}/git/${path.split('/')[1]}/lib/new.dart')
          .existsSync(),
  ].every((value) => value);
  bool noNewFiles(Map<String, String> env) => relativeIndexes.every(
    (path) =>
        !File('${env['PUB_CACHE']}/git/${path.split('/')[1]}/lib/new.dart')
            .existsSync(),
  );

  final rejected = fixture();
  final preview = await raw(rejected, args(rejected));
  expect(
    preview.exitCode == 0 &&
        '${preview.stdout}'
                .split('\n')
                .where((line) => line == 'JOBS_MIGRATION_CONFLICTS=3')
                .length ==
            1,
    'three Git indexes must be reviewable with exactly one conflict marker',
  );
  expect(originals(rejected) && noNewFiles(rejected), 'preview changed cache');
  final defaultApply = await raw(
    rejected,
    args(rejected, ['--apply', '--expected-plan', token(preview)]),
  );
  expect(
    defaultApply.exitCode != 0 && originals(rejected) && noNewFiles(rejected),
    'default reject must not apply any nonconflicting files',
  );

  final kept = fixture();
  final existing = await apply(kept, ['--conflict-policy', 'existing']);
  expect(
    existing.exitCode == 0 && originals(kept) && newFiles(kept),
    'existing policy must retain all Git indexes and import missing files: ${existing.stderr}',
  );
  final sourceEnv = fixture();
  final noBackup = await apply(sourceEnv, [
    '--conflict-policy',
    'source',
    '--no-backup',
  ]);
  expect(
    noBackup.exitCode == 0 && incoming(sourceEnv) && newFiles(sourceEnv),
    'source/no-backup did not replace indexes: ${noBackup.stderr}',
  );
  expect(
    !'${noBackup.stdout}'.contains('JOBS_MIGRATION_BACKUP='),
    'no-backup created persistent backup',
  );
  final zero = await raw(sourceEnv, args(sourceEnv));
  expect(
    zero.exitCode == 0 &&
        '${zero.stdout}'
                .split('\n')
                .where((line) => line == 'JOBS_MIGRATION_CONFLICTS=0')
                .length ==
            1,
    'zero conflicts marker must also be unique',
  );

  final backed = fixture();
  // 桌面容器可能也是源和工程的祖先，真正生成的本轮目录必须是兄弟目录。
  final backupRun = await apply(backed, [
    '--conflict-policy',
    'source',
    '--backup-directory',
    base,
  ]);
  expect(
    backupRun.exitCode == 0 && incoming(backed),
    'source backup failed: ${backupRun.stderr}',
  );
  final backup = '${backupRun.stdout}'
      .split('\n')
      .singleWhere((line) => line.startsWith('JOBS_MIGRATION_BACKUP='))
      .substring('JOBS_MIGRATION_BACKUP='.length);
  final manifest =
      jsonDecode(File('$backup/recovery.json').readAsStringSync()) as Map;
  expect(
    manifest['status'] == 'complete' && (manifest['files'] as List).length == 3,
    'verified backups need a complete recovery mapping',
  );
  for (var i = 0; i < relativeIndexes.length; i++) {
    final stored = File('$backup/payload/pub-cache/${relativeIndexes[i]}');
    expect(
      stored.readAsStringSync() == 'existing-index-$i\u0000binary',
      'backup index bytes differ',
    );
    stored.copySync('${backed['PUB_CACHE']}/${relativeIndexes[i]}');
  }
  expect(originals(backed), 'backup cannot restore original index bytes');

  for (final badOptions in [
    ['--conflict-policy', 'source'],
    ['--conflict-policy', 'source', '--no-backup', '--backup-directory', base],
    ['--conflict-policy', 'existing', '--no-backup'],
    ['--conflict-policy', 'source', '--backup-directory', donor],
    [
      '--conflict-policy',
      'source',
      '--backup-directory',
      '$base/not-yet/../source cache',
    ],
    [
      '--conflict-policy',
      'source',
      '--backup-directory',
      rejected['PUB_CACHE']!,
    ],
    ['--conflict-policy', 'source', '--backup-directory', rejected['PROJECT']!],
    ['--conflict-policy', 'source', '--backup-directory', 'relative-backup'],
  ]) {
    final invalid = await raw(rejected, args(rejected, badOptions));
    expect(
      invalid.exitCode != 0 && originals(rejected),
      'unsafe conflict/backup parameters accepted: $badOptions',
    );
  }

  final stale = fixture();
  final options = ['--conflict-policy', 'source', '--no-backup'];
  final stalePreview = await raw(stale, args(stale, options));
  write(
    '${stale['PUB_CACHE']}/${relativeIndexes.first}',
    'concurrent local edit',
  );
  final staleApply = await raw(
    stale,
    args(stale, [
      ...options,
      '--apply',
      '--expected-plan',
      token(stalePreview),
    ]),
  );
  expect(
    staleApply.exitCode != 0 &&
        noNewFiles(stale) &&
        File('${stale['PUB_CACHE']}/${relativeIndexes.first}')
                .readAsStringSync() ==
            'concurrent local edit',
    'target change after confirmation was overwritten',
  );
  final choice = fixture();
  final choicePreview = await raw(choice, args(choice, options));
  final changedChoice = await raw(
    choice,
    args(choice, [
      '--conflict-policy',
      'existing',
      '--apply',
      '--expected-plan',
      token(choicePreview),
    ]),
  );
  expect(
    changedChoice.exitCode != 0 && originals(choice) && noNewFiles(choice),
    'confirmed source policy token accepted existing policy',
  );
  final changedBackup = await raw(
    choice,
    args(choice, [
      '--conflict-policy',
      'source',
      '--backup-directory',
      base,
      '--apply',
      '--expected-plan',
      token(choicePreview),
    ]),
  );
  expect(
    changedBackup.exitCode != 0 && originals(choice),
    'confirmed backup choice changed',
  );

  final typed = fixture();
  File('${typed['PUB_CACHE']}/${relativeIndexes.first}').deleteSync();
  Directory('${typed['PUB_CACHE']}/${relativeIndexes.first}').createSync();
  final typedResult = await raw(typed, args(typed, options));
  expect(
    typedResult.exitCode != 0 && noNewFiles(typed),
    'file/directory conflict became selectable',
  );
  if (!Platform.isWindows) {
    final linked = fixture();
    final external = '$base/external original';
    write(external, 'external untouched');
    File('${linked['PUB_CACHE']}/${relativeIndexes.first}').deleteSync();
    Link('${linked['PUB_CACHE']}/${relativeIndexes.first}')
        .createSync(external);
    final linkedResult = await raw(linked, args(linked, options));
    expect(
      linkedResult.exitCode != 0 &&
          File(external).readAsStringSync() == 'external untouched',
      'source policy followed a target symlink',
    );
    final alias = '$base/backup alias';
    Link(alias).createSync(base);
    final aliasResult = await raw(
      rejected,
      args(rejected, [
        '--conflict-policy',
        'source',
        '--backup-directory',
        alias,
      ]),
    );
    expect(
      aliasResult.exitCode != 0 && originals(rejected),
      'backup symlink accepted',
    );

    final unwritable = '$base/backup not writable';
    Directory(unwritable).createSync();
    Process.runSync('/bin/chmod', ['500', unwritable]);
    try {
      final failure = await apply(rejected, [
        '--conflict-policy',
        'source',
        '--backup-directory',
        unwritable,
      ]);
      expect(
        failure.exitCode != 0 && originals(rejected) && noNewFiles(rejected),
        'failed backup allowed cache replacement',
      );
    } finally {
      Process.runSync('/bin/chmod', ['700', unwritable]);
    }
    final rollback = fixture();
    final blocked =
        '${rollback['PUB_CACHE']}/git/${relativeIndexes.first.split('/')[1]}/lib';
    Directory(blocked).createSync();
    Process.runSync('/bin/chmod', ['500', blocked]);
    try {
      final failure = await apply(rollback, options);
      expect(
        failure.exitCode != 0 && originals(rollback) && noNewFiles(rollback),
        'late write failure did not restore overwritten index bytes: ${failure.stderr}',
      );
    } finally {
      Process.runSync('/bin/chmod', ['700', blocked]);
    }
  }
  return assertions;
}
