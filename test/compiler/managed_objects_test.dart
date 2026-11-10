@Tags(['assets', 'native'])
library;

import 'dart:ffi';
import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';
import 'fixtures/managed_objects.dart' as sdk;
import 'fixtures/managed_objects_ffi.dart';

void main() {
  test(
    'mapping failures escape allocation and constructor calls cleanly',
    () async {
      for (final name in ['managed_failure', 'managed_growth_failure']) {
        final result = await Process.run(
          NativeAssets(Target.host()).file('compiler/$name').absolute.path,
          [],
        );
        expect(result.exitCode, 255, reason: '$name: ${result.stderr}');
        expect(result.stdout, isEmpty);
        expect(result.stderr, 'Unhandled exception:\nOut of Memory\n');
      }
    },
    skip: !Platform.isLinux,
  );

  test('constructors preserve effects, references and floating results', () {
    final native = ManagedObjects();
    addTearDown(native.close);
    final output = native.output;
    for (final count in [0, 1, 10000]) {
      output.value = 0;
      final expected = sdk.allocateAndNotify(count, 1.25, output);
      final expectedSum = output.value;
      output.value = 0;
      expect(native.allocateAndNotify(count, 1.25, output), expected);
      expect(output.value, expectedSum);
      expect(output.value, count * (count - 1) ~/ 2);
    }
    expect(
      1 / native.allocateAndNotify(1, -0.0, .fromAddress(0)),
      double.negativeInfinity,
    );
  });

  test(
    'a standalone entry allocates and collects without an SDK process',
    () async {
      final result = await Process.run(
        NativeAssets(Target.host())
            .file('compiler/entry_managed')
            .absolute
            .path,
        [],
        includeParentEnvironment: false,
        environment: {'PATH': ''},
      );
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      expect(result.stdout, isEmpty);
      expect(result.stderr, isEmpty);
    },
  );
}
