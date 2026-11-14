@Tags(['assets', 'native'])
library;

import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  test(
    'list kinds retain SDK iterable interfaces and generic element types',
    () async {
      final commands = [
        [
          Platform.resolvedExecutable,
          'test/compiler/fixtures/iterable_chaining.dart',
        ],
        [
          NativeAssets(Target.host())
              .file('compiler/entry_iterable_chaining')
              .path,
        ],
      ];
      final expected = [
        for (var i = 0; i < 5; i++) ...['[1,2,3,4]', '4:1:4:3'],
        '[1,2.5]',
        '[1,2,3,4]',
        '[0,1,2,3]',
        'true',
        '[6,7,8]',
        'true',
        '',
      ].join('\n');
      for (final command in commands) {
        final result = await Process.run(
          command.first,
          command.skip(1).toList(),
        );
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        expect(result.stderr, isEmpty);
        expect(result.stdout, expected);
      }
    },
  );
}
