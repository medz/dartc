import 'dart:ffi' as ffi;

import 'package:dartc/ir.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  const address = Constant.integer(-1);
  final pointer = PointerFromAddress(address);

  test('native memory operations retain types and observable effects', () {
    expect(pointer.type, FfiTypes.int64Pointer);
    expect(pointer.type, isNot(ValueType.integer));
    expect(pointer.effects, {Effect.allocates});
    expect(PointerAddress(pointer).effects, isEmpty);
    expect(LoadNativeInt64(pointer).effects, {Effect.readsStorage});
    expect(StoreNativeInt64(pointer, address).effects, {Effect.writesStorage});
    expect(StoreNativeInt64(pointer, address).type, ValueType.voidType);
    final impostor = Block([ClassType(Uri.parse('dart:ffi'), 'Pointer')])
        .parameters
        .single;
    for (final value in [address, impostor, const Constant.nullValue()]) {
      expect(() => PointerAddress(value), throwsArgumentError);
      expect(() => LoadNativeInt64(value), throwsArgumentError);
      expect(() => StoreNativeInt64(value, address), throwsArgumentError);
    }
    expect(() => PointerFromAddress(pointer), throwsArgumentError);
    expect(() => StoreNativeInt64(pointer, pointer), throwsArgumentError);
    expect(FfiTypes.valueType(ffi.Pointer<ffi.Int64>), pointer.type);
    expect(
      () => FfiTypes.valueType(ffi.Pointer<ffi.Int8>),
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
