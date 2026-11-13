@Tags(['assets', 'native'])
library;

import 'dart:io';
import 'dart:ffi';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';
import 'fixtures/varargs_types.dart';

void main() {
  test('unmanaged scalar exports still use the variadic entry convention', () {
    final library = DynamicLibrary.open(
      NativeAssets(Target.host()).library('compiler/varargs_scalar').path,
    );
    addTearDown(library.close);
    final sum = library
        .lookupFunction<
          Double Function(Double, VarArgs<(Double,)>),
          double Function(double, double)
        >('variadic_sum');
    expect(sum(1.25, 2.5), 3.75);
    expect(sum(-0.25, 0.5), 0.25);
  });

  test('SDK and dartc exchange variadic aggregates in both directions', () {
    final library = DynamicLibrary.open(
      NativeAssets(Target.host()).library('compiler/varargs').path,
    );
    addTearDown(library.close);
    final incoming = library
        .lookupFunction<AggregateCallback, DartAggregateCallback>(
          'variadic_aggregates',
        );
    final outgoing = library
        .lookupFunction<
          Double Function(
            Pointer<NativeFunction<AggregateCallback>>,
            Pair,
            Triple,
          ),
          double Function(
            Pointer<NativeFunction<AggregateCallback>>,
            Pair,
            Triple,
          )
        >('call_variadic_aggregates');
    final pair = Struct.create<Pair>()
      ..x = 1.25
      ..y = -2.5;
    final triple = Struct.create<Triple>()
      ..a = 10
      ..b = 20
      ..c = -3;
    expect(incoming(7, pair, triple), 32.75);
    final callback = NativeCallable<AggregateCallback>.isolateLocal((
      int bias,
      Pair p,
      Triple t,
    ) {
      expect(bias, 7);
      expect((p.x, p.y), (1.25, -2.5));
      expect((t.a, t.b, t.c), (10, 20, -3));
      p.x = 1000;
      t.a = 1000;
      return 42.25;
    }, exceptionalReturn: -1.0);
    addTearDown(callback.close);
    expect(outgoing(callback.nativeFunction, pair, triple), 42.25);
    expect(
      (pair.x, triple.a),
      (1.25, 10),
      reason: 'arguments are passed by value',
    );
  });

  test('variadic FFI executes the platform calling convention', () async {
    final native = await Process.run(
      NativeAssets(Target.host()).file('compiler/entry_varargs').path,
      [],
    );
    expect(native.exitCode, 0, reason: '${native.stdout}\n${native.stderr}');
    final sdk = await Process.run(Platform.resolvedExecutable, [
      'test/compiler/fixtures/varargs_sdk.dart',
    ]);
    expect(sdk.exitCode, 0, reason: '${sdk.stdout}\n${sdk.stderr}');
    expect(native.stdout, sdk.stdout);
  });
}
