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
  test('stack locations, snapshots and first Error traces survive collection and overrides', () {
    final native = Exceptions();
    addTearDown(native.close);
    for (var mode = 0; mode < 8; mode++) {
      expect(sdk.stackTraceLifecycle(mode), isTrue, reason: 'SDK case $mode');
      expect(
        native.stackTraceLifecycle(mode),
        isTrue,
        reason: 'native case $mode',
      );
    }
  });

  test(
    'stack snapshots cross suspended native reentry without losing callers',
    () {
      final native = Exceptions();
      addTearDown(native.close);
      final depth = native.traceDepth();
      final callback = NativeCallable<Int32 Function()>.isolateLocal(
        native.traceDepth,
        exceptionalReturn: -1,
      );
      addTearDown(callback.close);
      expect(native.reenterTrace(callback.nativeFunction), greaterThan(depth));
    },
  );

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

  test('irrefutable pattern failures preserve locals, cleanup and errors across GC', () {
    final native = Exceptions();
    addTearDown(native.close);
    const expected = [12, 78, 78, 12];
    for (final count in [0, 40000]) {
      for (var mode = 0; mode < expected.length; mode++) {
        expect(sdk.patternFailure(mode, count), expected[mode]);
        expect(native.patternFailure(mode, count), expected[mode]);
      }
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
