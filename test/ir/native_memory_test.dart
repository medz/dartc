import 'dart:ffi' as ffi;

import 'package:dartc/ir.dart';
import 'package:dartc/interop.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  const address = Constant.integer(-1);
  final pointer = PointerFromAddress(address, FfiTypes.int64Pointer);

  test('reference recovery preserves traced types without allocating', () {
    final object = Block([.object.nullable]).parameters.single;
    final location = ReferenceAddress(object);
    final recovered = ReferenceFromAddress(location, .object.nullable);
    expect(location.type, ValueType.integer);
    expect(recovered.type, ValueType.object.nullable);
    expect(recovered.effects, {Effect.readsStorage});
    expect(() => ReferenceAddress(address), throwsArgumentError);
    for (final type in [
      ValueType.integer,
      ValueType.floating,
      ValueType.boolean,
      ValueType.voidType,
    ]) {
      expect(() => ReferenceFromAddress(address, type), throwsArgumentError);
    }
    expect(() => ReferenceFromAddress(object, .object), throwsArgumentError);
  });

  test('function pointers preserve native signatures without acquiring storage operations', () {
    final signature = NativeSignature(ffi.Int64, [ffi.Int8]);
    final descriptor = NativePointerType(NativeFunctionType(signature));
    final type = FfiTypes.resolve(descriptor);
    expect(FfiTypes.describe(type), descriptor);
    expect(FfiTypes.valueType(descriptor), type);
    expect(
      type,
      isNot(
        FfiTypes.resolve(
          NativePointerType(
            NativeFunctionType(NativeSignature(ffi.Int64, [ffi.Uint8])),
          ),
        ),
      ),
    );
    final function = PointerFromAddress(address, type);
    expect(PointerAddress(function).type, ValueType.integer);
    expect(() => LoadNative(function, .new(ffi.Int64)), throwsArgumentError);
    expect(
      () => StoreNative(function, .new(ffi.Int64), address),
      throwsArgumentError,
    );
    expect(() => PointerOffset(function, address), throwsArgumentError);
    expect(FfiTypes.isPointer(type.nullable), isFalse);
    final block = Block([.integer]);
    final created = block.emit(
      PointerFromAddress(block.parameters.single, type),
    );
    block.finish(Return(block.emit(PointerAddress(created))));
    final functionBody = IrFunction(
      FunctionTarget(
        Uri.parse('memory:function-pointer'),
        'address',
        .integer,
        [.integer],
      ),
      [block],
    );
    final runner = IrInterpreter(IrProgram([], [functionBody]), {});
    for (final value in [0, -1, 0x7fffffffffffffff]) {
      expect(runner.run(functionBody, [value]), value);
    }
    expect(
      () => PointerFromAddress(
        address,
        FfiTypes.nativeFunction.instantiate([
          FunctionType(.integer, [.integer]),
        ]),
      ),
      throwsArgumentError,
    );
  });

  test('native reads and writes use their explicit storage type', () {
    for (final type in [ffi.Float, ffi.Double]) {
      final native = NativeScalarType(type);
      expect(LoadNative(address, native).type, ValueType.floating);
      expect(
        StoreNative(address, native, const Constant.floating(1.5)).effects,
        {Effect.writesStorage},
      );
      expect(() => StoreNative(address, native, address), throwsArgumentError);
    }
    expect(
      () => StoreNative(address, .new(ffi.Int64), const Constant.floating(1.5)),
      throwsArgumentError,
    );
  });

  test(
    'pointer slots are sized independently of the pointed-to native type',
    () {
      final parameter = TypeParameterType('T')
        ..initializeBound(FfiTypes.nativeType)
        ..initializeDefaultType(FfiTypes.nativeType);
      for (final element in [
        FfiTypes.voidType,
        FfiTypes.nativeFunction.instantiate([FunctionType(.integer, [])]),
        parameter,
      ]) {
        final pointer = FfiTypes.pointer.instantiate([element]);
        expect(FfiTypes.pointerElementSize(pointer), isNull);
        final slots = FfiTypes.pointer.instantiate([pointer]);
        expect(FfiTypes.pointerElementSize(slots), 8);
        final value = PointerFromAddress(address, slots);
        expect(PointerOffset(value, address).type, slots);
      }
    },
  );

  test('native memory operations retain types and observable effects', () {
    expect(pointer.type, FfiTypes.int64Pointer);
    expect(pointer.type, isNot(ValueType.integer));
    expect(pointer.effects, {Effect.allocates});
    expect(PointerAddress(pointer).effects, isEmpty);
    expect(PointerOffset(pointer, address).effects, {Effect.allocates});
    expect(PointerOffset(pointer, address).type, pointer.type);
    expect(LoadNative(address, .new(ffi.Int64)).effects, {Effect.readsStorage});
    expect(StoreNative(address, .new(ffi.Int64), address).effects, {
      Effect.writesStorage,
    });
    expect(
      StoreNative(address, .new(ffi.Int64), address).type,
      ValueType.voidType,
    );
    final impostor = Block([ClassType(Uri.parse('dart:ffi'), 'Pointer')])
        .parameters
        .single;
    for (final value in [address, impostor, const Constant.nullValue()]) {
      expect(() => PointerAddress(value), throwsArgumentError);
      expect(() => PointerOffset(value, address), throwsArgumentError);
    }
    expect(
      () => PointerFromAddress(pointer, FfiTypes.int64Pointer),
      throwsArgumentError,
    );
    for (final value in [pointer, impostor, const Constant.nullValue()]) {
      expect(() => LoadNative(value, .new(ffi.Int64)), throwsArgumentError);
      expect(
        () => StoreNative(value, .new(ffi.Int64), address),
        throwsArgumentError,
      );
    }
    expect(() => LoadNative(address, .new(ffi.Void)), throwsArgumentError);
    expect(
      () => StoreNative(address, .new(ffi.Void), address),
      throwsArgumentError,
    );
    expect(
      () => StoreNative(address, .new(ffi.Int64), pointer),
      throwsArgumentError,
    );
    expect(() => PointerOffset(pointer, pointer), throwsArgumentError);
    expect(
      FfiTypes.valueType(NativeTypeRef.of(ffi.Pointer<ffi.Int64>)),
      pointer.type,
    );
    expect(
      FfiTypes.valueType(NativeTypeRef.of(ffi.Pointer<ffi.Void>)),
      FfiTypes.pointerTypes[ffi.Pointer<ffi.Void>],
    );
  });

  test(
    'offsets retain scalar element types and wrap without reading storage',
    () {
      final library = Uri.parse('memory:pointer');
      for (final (native, size) in [
        (ffi.Pointer<ffi.Int8>, 1),
        (ffi.Pointer<ffi.Uint8>, 1),
        (ffi.Pointer<ffi.Int16>, 2),
        (ffi.Pointer<ffi.Uint16>, 2),
        (ffi.Pointer<ffi.Int32>, 4),
        (ffi.Pointer<ffi.Uint32>, 4),
        (ffi.Pointer<ffi.Int64>, 8),
        (ffi.Pointer<ffi.Uint64>, 8),
        (ffi.Pointer<ffi.Float>, 4),
        (ffi.Pointer<ffi.Double>, 8),
      ]) {
        final type = FfiTypes.pointerTypes[native]!;
        final block = Block([.integer, .integer]);
        final pointer = block.emit(
          PointerFromAddress(block.parameters[0], type),
        );
        final offset = block.emit(PointerOffset(pointer, block.parameters[1]));
        block.finish(Return(block.emit(PointerAddress(offset))));
        final function = IrFunction(
          FunctionTarget(library, 'offset', .integer, [.integer, .integer]),
          [block],
        );
        final interpreter = IrInterpreter(IrProgram([], [function]), {});
        for (final address in [0, -1, 0x7fffffffffffffff]) {
          for (final index in [0, -1, 3, -0x8000000000000000]) {
            expect(
              interpreter.run(function, [address, index]),
              address + index * size,
            );
          }
        }
      }
    },
  );

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
