@Tags(['assets', 'native'])
library;

import 'dart:ffi';
import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';
import 'fixtures/finalizers.dart' as sdk;
import 'fixtures/finalizers_ffi.dart';

void main() {
  test('finalizers run as events after microtasks and can allocate', () {
    final native = Finalizers();
    addTearDown(native.close);
    native.create(3.25, 0);
    expect(native.collect(0), 0);
    expect(native.read(), 3.25);
    expect(native.count(), 1);
    expect(native.order(), 1234);
    native.collect(0);
    expect(native.count(), 1);
    native.create(7.5, 1);
    expect(native.collect(0), 0);
    expect(native.count(), 0);
    native.release();
    expect(native.collect(0), 0);
    expect(native.read(), 7.5);
    expect(native.count(), 1);
  });

  test('detach in a microtask cancels an already queued finalizer', () {
    final native = Finalizers();
    addTearDown(native.close);
    native.create(9.5, 0);
    expect(native.collect(1), 0);
    expect(native.count(), 0);
    expect(native.order(), 12);
  });

  test('creation zone binds nullable tokens and handles callback errors', () {
    final native = Finalizers();
    addTearDown(native.close);
    native.createInZone();
    expect(native.collect(0), 0);
    expect(native.read(), 12.5);
    expect(native.count(), 1);
    expect(native.order(), 7);
    native.create(1, 0);
    native.discardOwner();
    native.collect(0);
    expect(native.count(), 0);
  });

  test('native reentry cannot run pending Dart events inside another call', () {
    final native = Finalizers();
    addTearDown(native.close);
    native.create(2.5, 0);
    var nested = -1;
    final callback = NativeCallable<Void Function()>.isolateLocal(() {
      nested = native.collect(0);
    });
    addTearDown(callback.close);
    expect(native.reenter(callback.nativeFunction), 0);
    expect(nested, 0);
    expect(native.read(), 2.5);
    expect(native.order(), 1234);
  });

  test('invalid targets and detach keys are rejected before registration', () {
    final native = Finalizers();
    addTearDown(native.close);
    for (var kind = 0; kind < 5; kind++) {
      for (final detach in [0, 1]) {
        expect(native.rejects(kind, detach), sdk.rejects(kind, detach));
        expect(native.rejects(kind, detach), 1);
      }
    }
  });

  test('process entry drains events before releasing the heap', () async {
    final result = await Process.run(
      NativeAssets(Target.host())
          .file('compiler/entry_finalizers')
          .absolute
          .path,
      [],
      includeParentEnvironment: false,
      environment: {'PATH': ''},
    );
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect(result.stdout, 'finalized 中文🙂\ufffd\n');
    expect(result.stderr, isEmpty);
    final failure = await Process.run(
      NativeAssets(Target.host())
          .file('compiler/entry_finalizers_error')
          .absolute
          .path,
      [],
      includeParentEnvironment: false,
      environment: {'PATH': ''},
    );
    expect(failure.exitCode, 255);
    expect(failure.stdout, isEmpty);
    expect(failure.stderr, 'Unhandled Dart exception at native boundary.\n');
  });

  test('timer events share microtask priority and cancellation lifecycle', () {
    final native = Finalizers();
    addTearDown(native.close);
    native.timers();
    expect(native.order(), 1234);
    native.periodic();
    expect(native.count(), 3);
    expect(native.zoneMaps(), sdk.zoneMaps());
    expect(native.zoneMaps(), 1);
  });

  test(
    'multiple attachments retain distinct tokens across callback collections',
    () {
      final native = Finalizers();
      addTearDown(native.close);
      native.multiple();
      native.collect(0);
      expect(native.count(), 3);
      expect(native.read(), 13.75);
      native.collect(0);
      expect(native.count(), 3);
    },
  );
}
