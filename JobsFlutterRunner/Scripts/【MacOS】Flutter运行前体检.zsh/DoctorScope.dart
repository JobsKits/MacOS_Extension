// Created by Jobs on 2026年11月10日，星期二.
// 复用当前 SDK 的本地官方验证器，不执行公网资源、设备扫描或版本远端查询。
import 'dart:convert';
import 'dart:io' as io;

import 'package:flutter_tools/src/base/logger.dart';
import 'package:flutter_tools/src/cache.dart';
import 'package:flutter_tools/src/context_runner.dart';
import 'package:flutter_tools/src/doctor.dart';

bool localValidator(String title, String scope) {
  final android = title.startsWith('Android toolchain');
  final xcode = title.startsWith('Xcode');
  final web = title.startsWith('Chrome');
  final windows = title.startsWith('Windows Version') || title.startsWith('Visual Studio');
  final harmony = RegExp(r'^(?:OpenHarmony|Harmony|OHOS)', caseSensitive: false).hasMatch(title);
  if (scope == 'all') return android || xcode || web || windows || harmony;
  return switch (scope) {
    'ios' || 'macos' => xcode,
    'android' => android,
    'web' => web,
    'windows' => windows,
    'ohos' => harmony,
    _ => throw ArgumentError('Unknown validation scope: $scope'),
  };
}

Future<void> main(List<String> args) async {
  try {
    final scope = args.isEmpty ? 'all' : args.single;
    final root = io.Platform.environment['FLUTTER_ROOT'];
    if (root == null || root.isEmpty) throw StateError('FLUTTER_ROOT is required.');
    final metadata = jsonDecode(io.File('$root/bin/cache/flutter.version.json').readAsStringSync());
    final framework = metadata['frameworkVersion'] ?? metadata['flutterVersion'];
    final dart = metadata['dartSdkVersion'];
    if (framework is! String || framework.isEmpty || dart is! String || dart.isEmpty ||
        io.Platform.version.split(' ').first != dart.split(' ').first) {
      throw StateError('The prepared SDK version metadata and Dart runtime do not match.');
    }
    Cache.flutterRoot = root;
    final results = await runInContext(() async {
      final validators = DoctorValidatorsProvider.defaultInstance.validators
          .where((validator) => localValidator(validator.title, scope)).toList();
      return Future.wait(validators.map((validator) async {
        try {
          final result = await validator.validate();
          return <String, Object?>{
            'title': validator.title,
            'type': result.type.toString().split('.').last,
            'statusInfo': result.statusInfo,
            'messages': result.messages.map((message) => <String, String>{
              'type': message.type.toString().split('.').last,
              'message': message.message,
            }).toList(),
          };
        } catch (error) {
          return <String, Object?>{'title': validator.title, 'type': 'crash',
            'statusInfo': null, 'messages': [<String, String>{'type': 'error', 'message': '$error'}]};
        }
      }));
    }, overrides: {Logger: () => BufferLogger.test()});
    // 仅在所选验证器全部结束后输出一个完整 JSON；中断或超时没有可复用的半成品。
    io.stdout.writeln(jsonEncode({'schemaVersion': 1, 'complete': true, 'scope': scope,
      'base': {'frameworkVersion': framework, 'dartSdkVersion': dart}, 'validators': results}));
    io.exit(results.every((result) => result['type'] == 'success') ? 0 : 1);
  } catch (error) {
    io.stderr.writeln('Local Flutter validation failed: $error');
    io.exit(2);
  }
}
