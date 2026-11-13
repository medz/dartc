@Tags(['assets', 'native'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  final assets = NativeAssets(Target.host());
  const source = 'test/compiler/fixtures/platform_environment.dart';
  const launcher = 'test/compiler/fixtures/raw_process_client.dart';
  final executable = assets
      .file('compiler/entry_platform_environment')
      .absolute
      .path;
  void check(ProcessResult result, List<Object?> values) {
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect(result.stderr, isEmpty);
    expect(
      result.stdout,
      [
        '${Platform.operatingSystem}:/:${Platform.isLinux}:${Platform.isMacOS}:false',
        jsonEncode([...values, false, false]),
        'true:true:3:799980000',
        '',
      ].join('\n'),
    );
  }

  test('platform environment preserves UTF-8, empty values, snapshots and read-only views', () async {
    final unicode = '中文🙂' * 1000;
    for (final environment in [
      <String, String>{},
      {
        'DARTC_VALUE': 'initial',
        'DARTC_EMPTY': '',
        'DARTC_EQUALS': 'a=b=c',
        'DARTC_UNICODE': unicode,
        '\ufeffDARTC_BOM': 'kept',
        'DARTC_DUP': 'last',
      },
    ]) {
      final expected = environment.isEmpty
          ? List<Object?>.filled(7, null)
          : ['initial', '', 'a=b=c', unicode, 'kept', null, 'last'];
      for (final command in [
        [executable],
        [Platform.resolvedExecutable, source],
      ]) {
        check(
          await Process.run(
            command.first,
            command.skip(1).toList(),
            includeParentEnvironment: false,
            environment: environment,
          ),
          expected,
        );
      }
    }
  });

  test('raw environment entries retain duplicate order and discard malformed names and UTF-8', () async {
    for (final command in [
      [executable],
      [Platform.resolvedExecutable, File(source).absolute.path],
    ]) {
      final result = await Process.run(
        Platform.resolvedExecutable,
        [launcher, 'environment', ...command],
        includeParentEnvironment: false,
        environment: {},
      );
      check(result, ['raw', '', 'a=b=c', '中文🙂', 'kept', null, 'last']);
    }
  });

  test(
    'native libraries read the host process environment across collections',
    () async {
      final result = await Process.run(
        Platform.resolvedExecutable,
        [
          'test/compiler/fixtures/platform_environment_client.dart',
          assets.library('compiler/platform_environment').absolute.path,
        ],
        includeParentEnvironment: false,
        environment: {'DARTC_VALUE': '中文🙂'},
      );
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stderr, isEmpty);
      expect(result.stdout, '4:4\n');
    },
  );
}
