@Tags(['assets', 'native'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  for (final zone in [
    'UTC',
    'America/New_York',
    'Asia/Shanghai',
    'Australia/Lord_Howe',
  ]) {
    test('platform time matches clock and zone rules for $zone', () async {
      final before = DateTime.now().microsecondsSinceEpoch;
      final native = await Process.run(
        NativeAssets(Target.host())
            .file('compiler/entry_platform_time')
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
      expect(int.parse(lines.first), inInclusiveRange(before, after));
      final sdk = await Process.run(
        Platform.resolvedExecutable,
        ['test/compiler/fixtures/platform_time_sdk.dart'],
        environment: {'TZ': zone},
      );
      expect(sdk.exitCode, 0, reason: '${sdk.stdout}\n${sdk.stderr}');
      expect(lines.skip(1), const LineSplitter().convert(sdk.stdout as String));
    });
  }
}
