import 'dart:ffi' as ffi;

import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:test/test.dart';

void main() {
  final signature = NativeSignature(ffi.Int8, [ffi.Int64, ffi.Float]);
  final type = FfiTypes.resolve(
    NativePointerType(NativeFunctionType(signature)),
  );
  final pointer = Block([type]).parameters.single;
  const integer = Constant.integer(129), floating = Constant.floating(1.25);

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
