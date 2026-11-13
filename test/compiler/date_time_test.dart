@Tags(['assets', 'native'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test(
    'Duration preserves signed units, rounding, formatting and errors',
    () async {
      final native = await Process.run(
        NativeAssets(Target.host())
            .file('compiler/entry_date_time')
            .absolute
            .path,
        ['duration'],
        includeParentEnvironment: false,
        environment: {'PATH': ''},
      );
      expect(native.exitCode, 0, reason: '${native.stdout}\n${native.stderr}');
      expect(native.stderr, isEmpty);
      final sdk = await Process.run(Platform.resolvedExecutable, [
        'test/compiler/fixtures/date_time.dart',
        'duration',
      ]);
      expect(sdk.exitCode, 0, reason: '${sdk.stdout}\n${sdk.stderr}');
      expect(native.stdout, sdk.stdout);
      expect(native.stdout, endsWith('duration:ok\n'));
    },
  );
  for (final zone in [
    'UTC',
    'America/New_York',
    'Asia/Shanghai',
    'Australia/Lord_Howe',
  ]) {
    test('DateTime matches calendar, clock and zone rules for $zone', () async {
      final before = DateTime.now().microsecondsSinceEpoch;
      final native = await Process.run(
        NativeAssets(Target.host())
            .file('compiler/entry_date_time')
            .absolute
            .path,
        [],
        includeParentEnvironment: false,
        environment: {'TZ': zone, 'PATH': ''},
      );
      final after = DateTime.now().microsecondsSinceEpoch;
      expect(native.exitCode, 0, reason: '${native.stdout}\n${native.stderr}');
      expect(native.stderr, isEmpty);
      final lines = const LineSplitter().convert(native.stdout as String);
      for (final instant in lines.take(2)) {
        expect(int.parse(instant), inInclusiveRange(before, after));
      }
      final sdk = await Process.run(
        Platform.resolvedExecutable,
        ['test/compiler/fixtures/date_time.dart'],
        environment: {'TZ': zone},
      );
      expect(sdk.exitCode, 0, reason: '${sdk.stdout}\n${sdk.stderr}');
      expect(
        lines.skip(2),
        const LineSplitter().convert(sdk.stdout as String).skip(2),
      );
    });
  }
}
