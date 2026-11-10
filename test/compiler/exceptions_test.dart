@Tags(['assets', 'native'])
library;

import 'dart:ffi';
import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';
import 'fixtures/exceptions.dart' as sdk;
import 'fixtures/exceptions_ffi.dart';

void main() {
  test(
    'catch, rethrow and overriding finally completions match SDK effects',
    () {
      final native = Exceptions();
      addTearDown(native.close);
      for (final count in [0, 40000]) {
        for (var mode = 0; mode <= 5; mode++) {
          native.effects.value = 0;
          final expected = sdk.cleanup(mode, count, native.effects);
          final effects = native.effects.value;
          native.effects.value = 0;
          expect(
            native.cleanup(mode, count, native.effects),
            expected,
            reason: 'mode $mode, count $count',
          );
          expect(
            native.effects.value,
            effects,
            reason: 'mode $mode, count $count',
          );
        }
      }
    },
  );

  test('constructor failures propagate and caught calls return normally', () {
    final native = Exceptions();
    addTearDown(native.close);
    for (final value in [-100, 0, 123, 10000]) {
      native.effects.value = 0;
      expect(native.constructorFailure(value, native.effects), 1);
      expect(native.effects.value, 1);
      expect(native.recoveredCalls(value), sdk.recoveredCalls(value));
      expect(native.checkedCall(value), sdk.checkedCall(value));
      expect(
        native.checkedDouble(value.toDouble()),
        sdk.checkedDouble(value.toDouble()),
      );
    }
  });

  test('uncaught exceptions stop at the native boundary', () async {
    final result = await Process.run(
      NativeAssets(Target.host())
          .file('compiler/entry_exception')
          .absolute
          .path,
      [],
      includeParentEnvironment: false,
      environment: {'PATH': ''},
    );
    expect(result.exitCode, 255);
    expect(result.stdout, isEmpty);
    expect(result.stderr, 'Unhandled Dart exception at native boundary.\n');
  });
}
