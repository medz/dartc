import 'dart:ffi' as ffi;

import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  const address = Constant.integer(-1);
  final pointer = PointerFromAddress(address, FfiTypes.int64Pointer);

  test('native reads and writes use the element value type', () {
    for (final type in [ffi.Pointer<ffi.Float>, ffi.Pointer<ffi.Double>]) {
      final pointer = PointerFromAddress(address, FfiTypes.pointerTypes[type]!);
      expect(LoadNative(pointer).type, ValueType.floating);
      expect(StoreNative(pointer, const Constant.floating(1.5)).effects, {
        Effect.writesStorage,
      });
      expect(() => StoreNative(pointer, address), throwsArgumentError);
    }
    expect(
      () => StoreNative(pointer, const Constant.floating(1.5)),
      throwsArgumentError,
    );
  });

  test('native memory operations retain types and observable effects', () {
    expect(pointer.type, FfiTypes.int64Pointer);
    expect(pointer.type, isNot(ValueType.integer));
    expect(pointer.effects, {Effect.allocates});
    expect(PointerAddress(pointer).effects, isEmpty);
    expect(LoadNative(pointer).effects, {Effect.readsStorage});
    expect(StoreNative(pointer, address).effects, {Effect.writesStorage});
    expect(StoreNative(pointer, address).type, ValueType.voidType);
    final impostor = Block([ClassType(Uri.parse('dart:ffi'), 'Pointer')])
        .parameters
        .single;
    for (final value in [address, impostor, const Constant.nullValue()]) {
      expect(() => PointerAddress(value), throwsArgumentError);
      expect(() => LoadNative(value), throwsArgumentError);
      expect(() => StoreNative(value, address), throwsArgumentError);
    }
    expect(
      () => PointerFromAddress(pointer, FfiTypes.int64Pointer),
      throwsArgumentError,
    );
    expect(() => StoreNative(pointer, pointer), throwsArgumentError);
    expect(FfiTypes.valueType(ffi.Pointer<ffi.Int64>), pointer.type);
    expect(
      () => FfiTypes.valueType(ffi.Pointer<ffi.Void>),
      throwsUnsupportedError,
    );
  });

  test(
    'pointer construction preserves address bits without accessing memory',
    () {
      final block = Block()..emit(pointer);
      final result = block.emit(PointerAddress(pointer));
      block.finish(Return(result));
      final function = IrFunction(
        FunctionTarget(Uri.parse('memory:pointer'), 'address', .integer, []),
        [block],
      );
      expect(
        IrInterpreter(IrProgram([], [function]), {}).run(function, []),
        -1,
      );
    },
  );
}
