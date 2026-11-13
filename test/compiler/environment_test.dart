@Tags(['assets', 'native'])
library;

import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';
import 'fixtures/environment_config.dart';

void main() {
  for (final (name, definitions) in [
    ('default', const <String, String>{}),
    ('configured', environmentDefinitions),
  ]) {
    test(
      '$name declarations agree across constants, calls and imports',
      () async {
        final native = await Process.run(
          NativeAssets(Target.host())
              .file('compiler/entry_environment_$name')
              .path,
          [],
          environment: {'text': 'OS variable', 'empty': 'OS variable'},
        );
        expect(
          native.exitCode,
          0,
          reason: '${native.stdout}\n${native.stderr}',
        );
        final sdk = await Process.run(Platform.resolvedExecutable, [
          for (final MapEntry(:key, :value) in definitions.entries)
            '-D$key=$value',
          'test/compiler/fixtures/environment.dart',
        ]);
        expect(sdk.exitCode, 0, reason: '${sdk.stdout}\n${sdk.stderr}');
        final actual = native.stdout as String;
        final expected = sdk.stdout as String;
        expect(actual.split('\n').first, definitions['flavor'] ?? 'default');
        // SDK tools restrict configurable URIs to dart.library.* declarations.
        expect(
          actual.substring(actual.indexOf('\n')),
          expected.substring(expected.indexOf('\n')),
        );
      },
    );
  }
}
