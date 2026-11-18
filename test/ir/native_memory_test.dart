import 'dart:ffi' as ffi;

import 'package:dartc/ir.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/optimizer.dart';
import 'package:test/test.dart';

import '../support/ir_interpreter.dart';

void main() {
  test(
    'native local blocks retain identity and physical lifetime without GC',
    () {
      final type = NativeArrayType(.of(ffi.Uint8), 77);
      for (final zero in [false, true]) {
        final entry = Block();
        final first = entry.emit(
          NativeLocalStorage(type, zeroInitialize: zero),
        );
        final second = entry.emit(
          NativeLocalStorage(type, zeroInitialize: zero),
        );
        entry.finish(Return(entry.emit(IntBinary(.subtract, first, second))));
        final target = FunctionTarget(null, 'localBlocks', .integer, []);
        final body = IrFunction(target, [entry]);
        expect(first.type, ValueType.integer);
        expect(first.inputs, isEmpty);
        expect(first.effects, zero ? {Effect.writesStorage} : isEmpty);
        expect(first.mayThrow, isFalse);
        expect(body.observesCallerFrame, isTrue);
        final clone = first.mapInputs(
          (_) => throw StateError('No operands'),
        ) as NativeLocalStorage;
        expect(clone, isNot(same(first)));
        expect(clone.declaration, same(first));
        expect(second.declaration, isNot(same(first.declaration)));
        expect(clone.storage, type);
        expect(clone.zeroInitialize, zero);
        final normalized = const ProgramSimplification().bind().normalize(
          IrProgram([], [body]),
        );
        expect(
          normalized.functions.single.blocks.single.instructions
              .whereType<NativeLocalStorage>(),
          hasLength(2),
        );
        final text = StringBuffer();
        body.writeTo(text);
        expect(text.toString(), contains('nativeLocalStorage'));
      }
      for (final type in [
        NativeTypeRef.of(ffi.Void),
        NativeFunctionType(NativeSignature(ffi.Void, [])),
      ]) {
        expect(() => NativeLocalStorage(type), throwsArgumentError);
      }
      final suspended = Block()..emit(NativeLocalStorage(.of(ffi.Int64)));
      suspended.finish(const Return());
      expect(
        () => IrFunction(
          FunctionTarget(null, 'asyncBlock', CoreTypes.futureOf(.nullType), []),
          [suspended],
          bodyKind: .asynchronous,
          completionType: ValueType.nullType,
        ),
        throwsStateError,
      );
    },
  );

  test(
    'native allocation contracts require integer size and address slots',
    () {
      final mapping = FunctionTarget(null, 'mapping', .integer, [.integer]);
      expect(
        () => IrExternal(mapping, memory: const .zeroed(0)),
        returnsNormally,
      );
      for (final (target, index) in [
        (mapping, -1),
        (mapping, 1),
        (FunctionTarget(null, 'wrongSize', .integer, [.object]), 0),
        (FunctionTarget(null, 'wrongResult', .object, [.integer]), 0),
      ]) {
        expect(
          () => IrExternal(target, memory: .zeroed(index)),
          throwsArgumentError,
        );
      }
    },
  );

  test(
    'native write contracts require address and length slots and write effects',
    () {
      final target = FunctionTarget(null, 'mutate', .voidType, [
        .integer,
        .integer,
      ]);
      for (final memory in [
        const WrittenMemory(0, 1),
        const ReleasedMemory(0, 1),
      ]) {
        expect(() => IrExternal(target, memory: memory), returnsNormally);
        expect(
          () => IrExternal(target, memory: memory, effects: const {}),
          throwsArgumentError,
        );
      }
      for (final memory in [
        const WrittenMemory(-1, 1),
        const ReleasedMemory(0, 2),
      ]) {
        expect(() => IrExternal(target, memory: memory), throwsArgumentError);
      }
    },
  );

  test(
    'call-frame operands are confined to the direct call that binds them',
    () {
      final callee = FunctionTarget(null, 'scan', .integer, [
        .integer,
        .integer,
      ]);
      final target = FunctionTarget(null, 'caller', .integer, []);
      final valid = Block();
      valid.finish(
        Return(
          valid.emit(
            DirectCall(callee, [
              CallFrameValue.stackPointer,
              CallFrameValue.returnAddress,
            ]),
          ),
        ),
      );
      IrFunction(target, [valid]);
      expect(
        () => DirectCall(FunctionTarget(null, 'boxed', .voidType, [.object]), [
          CallFrameValue.stackPointer,
        ]),
        throwsArgumentError,
      );
      for (final value in [
        CallFrameValue.stackPointer,
        CallFrameValue.returnAddress,
      ]) {
        expect(
          () => IrFunction(target, [Block()..finish(Return(value))]),
          throwsStateError,
        );
        final block = Block();
        block.finish(
          Return(block.emit(IntBinary(.add, value, const Constant.integer(1)))),
        );
        expect(() => IrFunction(target, [block]), throwsStateError);
      }
    },
  );

  test(
    'layout descriptors share declaration identity across instantiations',
    () {
      final t = TypeParameterType('T')
        ..initializeBound(ValueType.object.nullable);
      final generic = ClassType(null, 'Box', typeParameters: [t]);
      expect(ObjectDescriptorAddress(generic).declaration, same(generic));
      final closed = generic.instantiate([ValueType.integer]);
      final descriptor = ObjectDescriptorAddress(closed);
      expect(descriptor.declaration, same(generic));
      final function = FunctionTarget(null, 'descriptor', .integer, []);
      final block = Block()..finish(Return(descriptor));
      expect(() => IrFunction(function, [block]), throwsStateError);
      final entry = Block();
      entry.finish(Return(entry.emit(descriptor)));
      final body = IrFunction(function, [entry]);
      expect(body.referencedClasses, contains(generic));
    },
  );

  const address = Constant.integer(-1);
  final pointer = PointerFromAddress(address, FfiTypes.int64Pointer);

  test(
    'callback contracts reject missing exceptions and incompatible signatures',
    () {
      final type = FunctionType(FfiTypes.scalarTypes[ffi.Int64]!, [
        FfiTypes.scalarTypes[ffi.Int64]!,
      ]);
      final function = FunctionTarget(null, 'callback', .integer, [.integer]);
      expect(
        () => NativeCallbackAddress(StaticCallbackTarget(function, type)),
        throwsArgumentError,
      );
      expect(
        () => NativeCallbackAddress(
          StaticCallbackTarget(
            function,
            type,
            exceptionalReturn: const Constant.floating(1),
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => NativeCallbackAddress(
          StaticCallbackTarget(
            function,
            FunctionType(FfiTypes.scalarTypes[ffi.Double]!, type.parameters),
            exceptionalReturn: const Constant.floating(0),
          ),
        ),
        throwsArgumentError,
      );
      final voidType = FunctionType(FfiTypes.voidType, type.parameters);
      expect(
        () => NativeCallbackAddress(
          StaticCallbackTarget(
            function,
            voidType,
            exceptionalReturn: const Constant.integer(0),
          ),
        ),
        throwsArgumentError,
      );
      final callback = NativeCallbackAddress(
        StaticCallbackTarget(
          function,
          type,
          exceptionalReturn: const Constant.integer(-1),
        ),
      );
      final block = Block();
      block.finish(Return(block.emit(callback)));
      final factory = IrFunction(FunctionTarget(null, 'create', .integer, []), [
        block,
      ]);
      expect(factory.callees, contains(function));
      expect(
        NativeCallbackAddress(StaticCallbackTarget(function, voidType))
            .target
            .dartSignature
            .result,
        ValueType.voidType,
      );
    },
  );

  test('closure callback entries retain a typed lookup and reject mismatched entries', () {
    final lookup = FunctionTarget(null, 'lookup', .function, [.integer]);
    final native = FunctionType(FfiTypes.scalarTypes[ffi.Int64]!, [
      FfiTypes.scalarTypes[ffi.Int64]!,
    ]);
    final callback = NativeCallbackAddress(
      ClosureCallbackTarget(
        lookup,
        FunctionType(.integer, [.integer]),
        native,
        exceptionalReturn: const Constant.integer(-1),
      ),
    );
    final block = Block();
    block.finish(Return(block.emit(callback)));
    final factory = IrFunction(FunctionTarget(null, 'entry', .integer, []), [
      block,
    ]);
    expect(factory.callees, contains(lookup));
    expect(
      () => NativeCallbackAddress(
        ClosureCallbackTarget(
          FunctionTarget(null, 'invalid', .integer, [.integer]),
          callback.target.dartSignature,
          native,
          exceptionalReturn: const Constant.integer(-1),
        ),
      ),
      throwsArgumentError,
    );
    expect(
      () => NativeCallbackAddress(
        ClosureCallbackTarget(
          lookup,
          FunctionType(.integer, [.floating]),
          native,
          exceptionalReturn: const Constant.integer(-1),
        ),
      ),
      throwsArgumentError,
    );
  });

  test(
    'abstract compound views expose addresses without becoming allocatable',
    () {
      for (final type in [FfiTypes.struct, FfiTypes.union]) {
        final view = Block([type]).parameters.single;
        expect(NativeAddress(view).inputs, [view]);
        expect(() => NativeView(type), throwsArgumentError);
        expect(() => FfiTypes.describe(type), throwsUnsupportedError);
      }
      for (final type in <ValueType>[
        .object,
        FfiTypes.struct.nullable,
        FfiTypes.compound,
        ClassType(Uri.parse('dart:ffi'), 'Struct'),
      ]) {
        expect(
          () => NativeAddress(Block([type]).parameters.single),
          throwsArgumentError,
        );
      }
    },
  );

  test('copying native views require an explicit source address', () {
    final type = ClassType(
      null,
      'CopySource',
      nativeType: NativeCompoundType('CopySource', [
        NativeField('value', .of(ffi.Int64)),
      ]),
    );
    expect(() => NativeView(type, copy: true), throwsArgumentError);
    expect(NativeView(type).address, isNull);
    const address = Constant.integer(128);
    expect(
      NativeView(type, address: address, copy: true).address,
      same(address),
    );
  });

  test('allocated references keep their identity and storage extent', () {
    final type = ClassType(null, 'Storage');
    final entry = Block([.integer, .integer]);
    final object = AllocatedObject(
      entry.parameters.first,
      type,
      entry.parameters.last,
    );
    final replacement = Block([.integer, .integer]);
    final copied = object.mapInputs(
      (input) =>
          replacement.parameters[entry.parameters.indexOf(
            input as BlockParameter,
          )],
    ) as AllocatedObject;
    expect(copied.address, same(replacement.parameters.first));
    expect(copied.payloadBytes, same(replacement.parameters.last));
    expect(copied.type, same(type));
    expect(copied.mayThrow, isFalse);
    expect(
      () => AllocatedObject(const Constant.nullValue(), type, address),
      throwsArgumentError,
    );
    expect(
      () => AllocatedObject(address, type, const Constant.boolean(false)),
      throwsArgumentError,
    );
    expect(
      () => AllocatedObject(
        address,
        ClassType(null, 'Abstract', isAbstract: true),
        address,
      ),
      throwsArgumentError,
    );
  });

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
    ]) {
      final backing = ReferenceFromAddress(address, type);
      expect(backing.type, type);
      expect(ExecutionShapes().shapeOf(null, backing), ExecutionShape.reference);
      expect(backing.effects, {Effect.readsStorage});
    }
    for (final type in [ValueType.voidType, ValueType.never, CellType(.integer)]) {
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
    expect(() => LoadNative(function, .of(ffi.Int64)), throwsArgumentError);
    expect(
      () => StoreNative(function, .of(ffi.Int64), address),
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
      () => StoreNative(address, .of(ffi.Int64), const Constant.floating(1.5)),
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
        expect(FfiTypes.pointerElement(pointer), isNull);
        final slots = FfiTypes.pointer.instantiate([pointer]);
        expect(FfiTypes.pointerElement(slots)!.nativeSize, 8);
        final value = PointerFromAddress(address, slots);
        expect(PointerOffset(value, address).type, slots);
      }
    },
  );

  test('native memory operations retain types and observable effects', () {
    expect(pointer.type, FfiTypes.int64Pointer);
    expect(pointer.type, isNot(ValueType.integer));
    expect(pointer.effects, {Effect.allocates});
    expect(pointer.mayThrow, isTrue);
    expect(PointerAddress(pointer).effects, isEmpty);
    expect(PointerOffset(pointer, address).effects, {Effect.allocates});
    expect(PointerOffset(pointer, address).type, pointer.type);
    expect(LoadNative(address, .of(ffi.Int64)).effects, {Effect.readsStorage});
    expect(StoreNative(address, .of(ffi.Int64), address).effects, {
      Effect.writesStorage,
    });
    expect(
      StoreNative(address, .of(ffi.Int64), address).type,
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
      expect(() => LoadNative(value, .of(ffi.Int64)), throwsArgumentError);
      expect(
        () => StoreNative(value, .of(ffi.Int64), address),
        throwsArgumentError,
      );
    }
    expect(() => LoadNative(address, .of(ffi.Void)), throwsArgumentError);
    expect(
      () => StoreNative(address, .of(ffi.Void), address),
      throwsArgumentError,
    );
    expect(
      () => StoreNative(address, .of(ffi.Int64), pointer),
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
