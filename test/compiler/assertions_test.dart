@Tags(['assets', 'native'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  for (final enabled in [false, true]) {
    test(
      'native assertions preserve enabled=$enabled effects and messages',
      () async {
        final reference = await Process.run(Platform.resolvedExecutable, [
          if (enabled) '--enable-asserts',
          'test/compiler/fixtures/assertions.dart',
        ]);
        final native = await Process.run(
          NativeAssets(Target.host())
              .file('compiler/entry_assertions_$enabled')
              .absolute
              .path,
          [],
          includeParentEnvironment: false,
          environment: {'PATH': ''},
        );
        for (final result in [reference, native]) {
          expect(
            result.exitCode,
            0,
            reason: '${result.stdout}\n${result.stderr}',
          );
          expect(result.stderr, isEmpty);
        }
        expect(native.stdout, reference.stdout);
        final expected = enabled
            ? [
                [
                  'asserted',
                  0,
                  null,
                  ['assert', 20],
                  [0, 20],
                ],
                [
                  'withoutMessage',
                  false,
                  null,
                  ['assert', null],
                  [],
                ],
                [
                  'throwingMessage',
                  false,
                  null,
                  ['state', 'negative tick'],
                  [-2],
                ],
                [
                  'construct',
                  0,
                  null,
                  ['assert', 91],
                  [90, 0, 91],
                ],
              ]
            : [
                [
                  'asserted',
                  -1,
                  30,
                  null,
                  [30],
                ],
                [
                  'throwingMessage',
                  false,
                  50,
                  null,
                  [50],
                ],
                [
                  'construct',
                  0,
                  90,
                  null,
                  [90, 92],
                ],
              ];
        for (final observation in [
          ...expected,
          for (var mode = 0; mode < 6; mode++)
            ['retainedMessage', mode, true, null, []],
        ]) {
          expect(native.stdout, contains(jsonEncode(observation)));
        }
      },
    );
  }
}
