@Tags(['assets', 'native'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';

void main() {
  for (final group in ['basic', 'generic', 'interfaces']) {
    test(
      'native extension types preserve $group contracts after erasure',
      () async {
        final reference = await Process.run(Platform.resolvedExecutable, [
          'test/compiler/fixtures/extension_types.dart',
          group,
        ]);
        final native = await Process.run(
          NativeAssets(Target.host())
              .file('compiler/entry_extension_types')
              .absolute
              .path,
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
          _ => [
            ['privateLibrary', null, true, null, []],
            ['mostSpecific', null, true, null, []],
            ['covariantInterface', 2.5, null, 'type', []],
          ],
        };
        for (final observation in expected) {
          expect(native.stdout, contains(jsonEncode(observation)));
        }
      },
    );
  }
}
