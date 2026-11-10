@Tags(['assets', 'native'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dartc/target.dart';

import 'package:test/test.dart';

import '../support/native_assets.dart';
import 'fixtures/managed_globals_ffi.dart';

void main() {
  test('standalone entry retains managed globals across collections', () async {
    final result = await Process.run(
      NativeAssets(Target.host())
          .file('compiler/entry_managed_globals')
          .absolute
          .path,
      [],
      includeParentEnvironment: false,
      environment: {'PATH': ''},
    );
    expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    expect(result.stdout, isEmpty);
    expect(result.stderr, isEmpty);
  });

  late ManagedGlobals native;
  setUpAll(() {
    native = ManagedGlobals();
    addTearDown(native.close);
  });

  test('global aliases and cycles survive cross-entry collections', () {
    expect(native.graph(0), 1);
    expect(native.graph(1), 55);
    for (var i = 1; i <= 4; i++) {
      expect(native.collect(40000), 39999);
      expect(native.graph(2), 55 + 21 * i);
      expect(native.collect(40000), 39999);
      expect(native.graph(3), 55 + 21 * i);
    }
  });

  test('nullable and num globals preserve boxed values across collections', () {
    expect(native.nullableState(0), 7);
    for (final value in [9007199254740993, -9007199254740993]) {
      native.writeInteger(value);
      native.collect(40000);
      expect(native.readInteger(), value);
    }
    int bits(double value) => (ByteData(8)..setFloat64(0, value)).getUint64(0);
    for (final value in [-0.0, 1.25, double.infinity]) {
      native.writeDouble(value);
      native.collect(40000);
      expect(bits(native.readDouble()), bits(value));
    }
    expect(native.nullableState(1), 0);
    native.collect(40000);
    expect(native.nullableState(0), 0);
    expect(native.nullableState(2), 8);
    native.collect(40000);
    expect(native.nullableState(0), 8);
    expect(native.nullableState(3), 7);
    native.collect(40000);
    expect(native.nullableState(0), 7);
  });

  test('lazy references initialize once and late final null is bound', () {
    expect(native.binding(1), 0);
    expect(native.binding(0), 42);
    native.collect(40000);
    expect(native.binding(0), 42);
    expect(native.binding(1), 1);
    expect(native.binding(2), -1);
    expect(native.binding(3), 17);
    native.collect(40000);
    expect(native.binding(2), 17);
    expect(native.binding(4), -1);
    expect(native.binding(5), 5);
    native.collect(40000);
    expect(native.binding(4), 1);
    expect(native.binding(6), -1);
    expect(native.binding(4), 1);
  });

  test('failed and recursive initializers preserve committed references', () {
    expect(native.initialization(1), 0);
    expect(native.initialization(0), -2);
    expect(native.initialization(0), 72);
    native.collect(40000);
    expect(native.initialization(0), 72);
    expect(native.initialization(1), 2);
    expect(native.initialization(2), -2);
    native.collect(40000);
    expect(native.initialization(2), 91);
    expect(native.initialization(3), 1);
    // A recursive final read binds the inner object before the outer write.
    expect(native.initialization(4), -1);
    native.collect(40000);
    expect(native.initialization(4), 20);
    expect(native.initialization(5), 2);
  });
}
