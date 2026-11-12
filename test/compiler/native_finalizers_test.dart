@Tags(['assets', 'native'])
library;

import 'dart:ffi';
import 'dart:io';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';
import 'fixtures/native_finalizers_ffi.dart';

void main() {
  late NativeFinalizers native;
  setUp(() {
    native = NativeFinalizers();
    addTearDown(native.close);
  });

  test(
    'block, parameter, receiver and Never exits retain finalizable resources',
    () {
      for (final mode in [0, 1, 2, 4, 6, 7]) {
        native.state.value = 0;
        expect(
          native.lifetimes(native.state, mode),
          mode == 0 || mode == 7 ? 1 : 0,
          reason: 'case $mode',
        );
        expect(native.collect(native.state), 1, reason: 'case $mode');
        expect(native.collect(native.state), 1);
      }
    },
  );

  test(
    'captured and late resources survive until their closure is released',
    () {
      for (final mode in [3, 5]) {
        native.state.value = 0;
        expect(native.lifetimes(native.state, mode), 0);
        expect(native.collect(native.state), 0);
        expect(native.callClosure(), 0);
        native.releaseClosure();
        expect(native.collect(native.state), 1);
      }
    },
  );

  test('detach cancels delivery and multiple registrations each run once', () {
    native.attach(native.state, 1);
    expect(native.collect(native.state), 0);
    native.attach(native.state, 2);
    expect(native.collect(native.state), 2);
    expect(native.collect(native.state), 2);
  });

  test('unload finalizes reachable native resources exactly once', () {
    native.attach(native.state, 0);
    expect(native.collect(native.state), 0);
    expect(native.unload(), 1);
    expect(native.unload(), 1);
  });

  test('native registrations outlive the finalizer variable', () {
    native.attach(native.state, 3);
    expect(native.collect(native.state), 1);
  });

  test('process shutdown invokes still-reachable native finalizers', () async {
    final result = await Process.run(
      NativeAssets(Target.host())
          .file('compiler/entry_native_finalizers')
          .absolute
          .path,
      [],
      includeParentEnvironment: false,
      environment: {'PATH': ''},
    );
    expect(result.exitCode, 42, reason: '${result.stdout}${result.stderr}');
    expect(result.stdout, isEmpty);
    expect(result.stderr, isEmpty);
  });

  test(
    'shutdown retains every owner while draining many live registrations',
    () {
      native.attach(native.state, 4);
      expect(native.collect(native.state), 0);
      expect(native.unload(), 1000);
    },
  );

  test('invalid external sizes do not leave registrations behind', () {
    expect(native.invalidSize(native.state, -1), isTrue);
    expect(native.collect(native.state), 0);
  });

  test(
    'native typed-list aliases retain their buffer and finalization token',
    () {
      expect(native.pointerViews(native.state, 0), 0);
      expect(native.collect(native.state), 0);
      expect(native.pointerViews(native.state, 1), -123);
      expect(native.pointerViews(native.state, 2), 1);
      expect(native.collect(native.state), 1);
    },
  );

  test(
    'typed-list finalizers default to the pointer and accept null callbacks',
    () {
      expect(native.pointerViews(native.state, 3), 0);
      expect(native.pointerViews(native.state, 2), 1);
      expect(native.pointerViews(native.state, 4), 1);
      expect(native.pointerViews(native.state, 5), 1);
      expect(native.collect(native.state), 1);
    },
  );
}
