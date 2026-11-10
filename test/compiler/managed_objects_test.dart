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
    'generic constructor arguments survive allocation and nested collection',
    () {
      final native = ManagedObjects();
      addTearDown(native.close);
      for (final count in [0, 10000]) {
        for (final (integer, floating) in [
          (-0x8000000000000000, -0.0),
          (0x7fffffffffffffff, 1.25),
        ]) {
          sdk.constructNumbers(
            integer,
            floating,
            count,
            native.output,
            native.floatingOutput,
          );
          final expected = native.output.value;
          final floatingBits = native.floatingOutput.cast<Int64>().value;
          native.output.value = 0;
          native.floatingOutput.value = 0;
          native.constructNumbers(
            integer,
            floating,
            count,
            native.output,
            native.floatingOutput,
          );
          expect(native.output.value, expected);
          expect(native.floatingOutput.cast<Int64>().value, floatingBits);
        }
      }
    },
  );

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
