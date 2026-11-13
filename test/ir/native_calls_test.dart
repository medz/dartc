import 'dart:ffi' as ffi;

import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:test/test.dart';

void main() {
  test(
    'VarArgs flatten to Dart arguments without losing the native boundary',
    () {
      final native = NativeSignature(ffi.Int32, [
        ffi.Int32,
        ffi.Double,
      ], variadicStart: 1);
      final type = FfiTypes.resolve(NativeFunctionType(native));
      expect(FfiTypes.describe(type), NativeFunctionType(native));
      final declaration = type.typeArguments.single as FunctionType;
      expect(
        FfiTypes.dartSignature(declaration),
        FunctionType(.integer, [.integer, .floating]),
      );
      final pointer = Block([
        FfiTypes.pointer.instantiate([type]),
      ]).parameters.single;
      final call = NativeCall(pointer, [
        const Constant.integer(7),
        const Constant.floating(1.5),
      ]);
      expect(call.signature, native);
      expect(call.type, ValueType.integer);
      expect(
        () => NativeCall(pointer, [const Constant.integer(7)]),
        throwsArgumentError,
      );
      for (final record in [
        RecordType([], {'named': FfiTypes.int64}),
        ValueType.record,
      ]) {
        final malformed = FunctionType(FfiTypes.int64, [
          FfiTypes.varArgs.instantiate([record]),
        ]);
        expect(() => FfiTypes.signature(malformed), throwsUnsupportedError);
      }
      final empty = NativeSignature(ffi.Void, [], variadicStart: 0);
      expect(
        FfiTypes.describe(FfiTypes.resolve(NativeFunctionType(empty))),
        NativeFunctionType(empty),
      );
    },
  );

  final signature = NativeSignature(ffi.Int8, [ffi.Int64, ffi.Float]);
  final type = FfiTypes.resolve(
    NativePointerType(NativeFunctionType(signature)),
  );
  final pointer = Block([type]).parameters.single;
  const integer = Constant.integer(129), floating = Constant.floating(1.25);

  test(
    'borrowed addresses keep owners and reject invalid native boundaries',
    () {
      final native = NativeSignature(ffi.Int64, [
        ffi.Pointer<ffi.Void>,
        ffi.Int64,
      ]);
      final dart = FunctionType(.integer, [
        FfiTypes.pointerTypes[ffi.Pointer<ffi.Void>]!,
        .integer,
      ]);
      NativeSymbolAddress symbol({bool leaf = true}) => NativeSymbolAddress(
        NativeReference(
          'test',
          'read',
          NativeFunctionType(native),
          isLeaf: leaf,
        ),
      );
      final owner = Block([ValueType.object]).parameters.single;
      final owners = <int, Value>{0: owner};
      final pointer = symbol();
      final call = NativeCall.symbol(pointer, dart, [
        integer,
        integer,
      ], borrowedOwners: owners);
      owners.clear();
      expect(call.inputs, [pointer, integer, integer, owner]);
      expect(() => call.borrowedOwners.clear(), throwsUnsupportedError);
      for (final invalid in <Map<int, Value>>[
        {-1: owner},
        {2: owner},
        {1: owner},
        {0: integer},
      ]) {
        expect(
          () => NativeCall.symbol(pointer, dart, [
            integer,
            integer,
          ], borrowedOwners: invalid),
          throwsArgumentError,
        );
      }
      expect(
        () => NativeCall.symbol(
          symbol(leaf: false),
          dart,
          [integer, integer],
          borrowedOwners: {0: owner},
        ),
        throwsArgumentError,
      );
      expect(
        () => NativeCall.symbol(
          pointer,
          dart,
          [floating, integer],
          borrowedOwners: {0: owner},
        ),
        throwsArgumentError,
      );
      expect(
        () => NativeCall.symbol(
          pointer,
          FunctionType(.floating, dart.parameters),
          [integer, integer],
          borrowedOwners: {0: owner},
        ),
        throwsArgumentError,
      );
      final block = Block()
        ..emit(pointer)
        ..emit(call)
        ..finish(Return(integer));
      expect(
        () => IrFunction(
          FunctionTarget(Uri.parse('memory:borrow'), 'read', .integer, []),
          [block],
        ),
        throwsStateError,
      );
    },
  );

  test('native Dart signatures retain scalar types and pointer variance', () {
    final pointer = FfiTypes.int64Pointer;
    final wider = FfiTypes.pointer.instantiate([FfiTypes.nativeType]);
    final native = NativeSignature(ffi.Pointer<ffi.Int64>, [
      ffi.Pointer<ffi.Int64>,
    ]);
    expect(FfiTypes.canCall(native, FunctionType(wider, [pointer])), isTrue);
    expect(FfiTypes.canExport(native, FunctionType(wider, [pointer])), isFalse);
    expect(
      FfiTypes.canExport(native, FunctionType(pointer, [pointer])),
      isTrue,
    );
    for (final type in [
      FunctionType(pointer, [wider]),
      FunctionType(pointer.nullable, [pointer]),
      FunctionType(pointer, [pointer], optionalPositional: 1),
      FunctionType(pointer, [pointer], namedParameters: {'value': true}),
      FunctionType(pointer, []),
    ]) {
      expect(FfiTypes.canCall(native, type), isFalse);
    }
    expect(
      FfiTypes.canCall(
        NativeSignature(ffi.Int64, [ffi.Int64]),
        FunctionType(.object, [.integer]),
      ),
      isFalse,
    );
  });

  test('native compound calls preserve nominal types and owner contracts', () {
    final description = NativeCompoundType('Pair', [
      NativeField('value', NativeScalarType(ffi.Double)),
    ]);
    final pair = ClassType(
      Uri.parse('package:example/types.dart'),
      'Pair',
      nativeType: description,
    );
    final native = FfiTypes.nativeFunction.instantiate([
      FunctionType(pair, [pair]),
    ]);
    final pointer = Block([
      FfiTypes.pointer.instantiate([native]),
    ]).parameters.single;
    final value = NativeView(pair);
    final call = NativeCall(pointer, [value]);
    expect(call.type, same(pair));
    expect(call.signature.result, same(description));
    final symbol = NativeSymbolAddress(
      NativeReference(
        'test',
        'pair',
        NativeFunctionType(NativeSignature.types(description, [description])),
      ),
    );
    expect(
      NativeCall.symbol(symbol, FunctionType(pair, [pair]), [value]).type,
      same(pair),
    );
    expect(
      () => NativeCall(pointer, [const Constant.integer(1)]),
      throwsArgumentError,
    );
    expect(
      () => NativeView(pair, owner: const Constant.integer(1)),
      throwsArgumentError,
    );
    expect(
      CopyNative(
        const Constant.integer(0),
        const Constant.integer(8),
        description,
      ).effects,
      {Effect.readsStorage, Effect.writesStorage},
    );
  });

  test(
    'native calls derive signatures and retain evaluated operands and effects',
    () {
      final arguments = <Value>[integer, floating];
      final call = NativeCall(pointer, arguments);
      arguments.clear();
      expect(call.signature, signature);
      expect(call.inputs, [pointer, integer, floating]);
      expect(call.type, ValueType.integer);
      expect(call.isLeaf, isFalse);
      expect(call.effects, Effect.values.toSet());
      expect(() => call.arguments.clear(), throwsUnsupportedError);
      final leaf = NativeCall(pointer, [integer, floating], isLeaf: true);
      expect(leaf.isLeaf, isTrue);
      expect(
        leaf.effects,
        containsAll([Effect.readsStorage, Effect.writesStorage]),
      );
    },
  );

  test(
    'native calls reject nonfunction pointers and incorrect Dart arguments',
    () {
      for (final value in [
        integer,
        Block([FfiTypes.int64Pointer]).parameters.single,
        Block([type.nullable]).parameters.single,
        Block([ClassType(Uri.parse('dart:ffi'), 'Pointer')]).parameters.single,
      ]) {
        expect(
          () => NativeCall(value, [integer, floating]),
          throwsArgumentError,
        );
      }
      for (final arguments in <List<Value>>[
        [],
        [integer],
        [floating, integer],
        [integer, floating, integer],
      ]) {
        expect(() => NativeCall(pointer, arguments), throwsArgumentError);
      }
    },
  );

  test(
    'native pointer parameters keep complete signatures and SSA ownership',
    () {
      final accepting = FfiTypes.resolve(
        NativePointerType(
          NativeFunctionType(
            NativeSignature.types(NativeScalarType(ffi.Void), [
              FfiTypes.describe(type),
            ]),
          ),
        ),
      );
      final block = Block([accepting, type]);
      final call = block.emit(
        NativeCall(block.parameters[0], [block.parameters[1]]),
      );
      expect(call.type, ValueType.voidType);
      final other = FfiTypes.resolve(
        NativePointerType(
          NativeFunctionType(
            NativeSignature(ffi.Uint8, [ffi.Int64, ffi.Float]),
          ),
        ),
      );
      expect(
        () => NativeCall(block.parameters[0], [
          Block([other]).parameters.single,
        ]),
        throwsArgumentError,
      );
      block.finish(Return());
      final target = FunctionTarget(
        Uri.parse('memory:native-call'),
        'invoke',
        .voidType,
        [accepting, type],
      );
      final function = IrFunction(target, [block]);
      final output = StringBuffer();
      function.writeTo(output);
      expect(output.toString(), contains('callNative'));
      expect(
        () => IrFunction(target, [
          Block([accepting, type])
            ..emit(NativeCall(block.parameters[0], [block.parameters[1]]))
            ..finish(Return()),
        ]),
        throwsStateError,
      );
    },
  );
}
