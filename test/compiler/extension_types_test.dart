@Tags(['assets', 'native'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  for (final (group, enabled) in [
    ('basic', false),
    ('generic', false),
    ('interfaces', false),
    ('constructors', false),
    ('constructors', true),
  ]) {
    final setting = enabled ? 'enabled' : 'disabled';
    final asset = enabled
        ? 'entry_extension_types_assertions'
        : 'entry_extension_types';
    test(
      'native extension types preserve $group contracts ($setting assertions)',
      () async {
        final reference = await Process.run(Platform.resolvedExecutable, [
          if (enabled) '--enable-asserts',
          'test/compiler/fixtures/extension_types.dart',
          group,
        ]);
        final native = await Process.run(
          NativeAssets(Target.host()).file('compiler/$asset').absolute.path,
          [group],
          includeParentEnvironment: false,
          environment: {'PATH': ''},
        );
        for (final result in [reference, native]) {
          expect(
            result.exitCode,
            0,
            reason: result.stdout.toString() + result.stderr.toString(),
          );
          expect(result.stderr, isEmpty);
        }
        expect(native.stdout, reference.stdout);
        final expected = switch (group) {
          'basic' => [
            ['typeValues', null, true, null, []],
            ['identity', 3, true, null, []],
            ['checkedConstruction', 'bad', null, 'type', []],
            ['nullable', null, 0, null, []],
          ],
          'generic' => [
            ['erasedPhantomType', null, true, null, []],
            ['constIdentity', null, true, null, []],
            ['phantomConstructorIdentity', null, false, null, []],
            [
              'dynamicArgument',
              null,
              null,
              'type',
              [5],
            ],
            ['defaultBounded', null, null, 'type', []],
            ['redirects', null, '7:7:2:8:three:4:null:23:mapped', null, []],
          ],
          'interfaces' => [
            ['privateLibrary', null, true, null, []],
            ['mostSpecific', null, true, null, []],
            ['covariantInterface', 2.5, null, 'type', []],
          ],
          _ => [
            [
              'ordered',
              0,
              2,
              null,
              enabled ? [2, 1, 3, 4, 5] : [2, 4, 5],
            ],
            if (enabled) ...[
              [
                'primary',
                0,
                null,
                'assert:null',
                [0, 0],
              ],
              [
                'ordered',
                -1,
                null,
                'assert:70',
                [1, 0, 70],
              ],
              ['runtimeConst', 0, null, 'assert:null', []],
            ] else ...[
              [
                'primary',
                0,
                0,
                null,
                [0, 10, 20],
              ],
              [
                'ordered',
                -1,
                1,
                null,
                [1, 3, 4],
              ],
              ['runtimeConst', 0, 0, null, []],
            ],
            [
              'afterThrow',
              null,
              3,
              null,
              enabled ? [3, 2, 4, 5, 6] : [3, 5, 6],
            ],
            ['retainedRepresentation', null, 7, null, []],
          ],
        };
        for (final observation in expected) {
          expect(native.stdout, contains(jsonEncode(observation)));
        }
      },
    );
  }
}
