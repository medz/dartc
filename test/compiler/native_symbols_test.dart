@Tags(['assets', 'native'])
library;

import 'dart:ffi';
import 'dart:typed_data';

import 'package:dartc/target.dart';
import 'package:test/test.dart';

import '../support/native_assets.dart';
import 'fixtures/native_symbols_ffi.dart';
import 'fixtures/native_symbols_types.dart';

void main() {
  for (final suffix in ['', '_dynamic']) {
    test(
      'native data and function addresses through ${suffix.isEmpty ? 'static' : 'dynamic'} linking',
      () {
        final native = NativeSymbols('native_symbols$suffix');
        addTearDown(native.close);
        final integer = native.integerAddress();
        integer.value = 0;
        expect(native.exchangeInteger(0x12345), 0);
        expect(integer.value, 0x2345);
        expect(native.exchangeInteger(-321), 0x2345);
        expect(integer.value, -321);
        expect(native.storeFloat(1.1), 1.1);
        expect(native.readFloat(), Float32List.fromList([1.1])[0]);
        final real = native.doubleAddress();
        real.value = -3.25;
        expect(real.value, -3.25);
        expect(native.storeBool(true), isTrue);
        expect(native.storeBool(false), isFalse);
        native.pointerAddress().value = nullptr;
        expect(native.exchangePointer(integer), nullptr);
        expect(native.pointerAddress().value, integer);
        final input = Struct.create<NativePair>()
          ..integer = 123
          ..real = -4.5;
        native.storePair(input);
        input.integer = 9;
        final result = native.readPair();
        expect((result.integer, result.real), (123, -4.5));
        native.pairAddress().ref.integer = 456;
        expect(native.readPair().integer, 456);
        expect(result.integer, 123);
        expect(native.readConstant(), 42);
        final function = native.functionAddress();
        expect(function.asFunction<int Function(int)>()(39), 42);
        expect(native.callAddress(17), 20);
        if (suffix.isNotEmpty) {
          final provider = NativeAssets(Target.host())
              .open('compiler/native_symbols_provider');
          addTearDown(provider.close);
          expect(integer, provider.lookup<Int16>('integer'));
          expect(
            function,
            provider.lookup<NativeFunction<Int64 Function(Int64)>>('add'),
          );
        }
      },
    );
  }
}
