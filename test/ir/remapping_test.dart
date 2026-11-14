import 'dart:ffi' as ffi;

import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:test/test.dart';

void main() {
  test(
    'native remapping retains leaf calls, nominal signatures and owners',
    () {
      final native = NativeSignature(ffi.Int64, [
        ffi.Pointer<ffi.Void>,
        ffi.Int64,
      ]);
      final dart = FunctionType(.integer, [
        FfiTypes.pointerTypes[ffi.Pointer<ffi.Void>]!,
        .integer,
      ]);
      final pointer = NativeSymbolAddress(
        NativeReference(
          'test',
          'read',
          NativeFunctionType(native),
          isLeaf: true,
        ),
      );
      final before = Block([ValueType.object, ValueType.integer]);
      final after = Block([ValueType.object, ValueType.integer]);
      final call = NativeCall.symbol(
        pointer,
        dart,
        [before.parameters[1], const Constant.integer(2)],
        borrowedOwners: {0: before.parameters[0]},
      );
      final copy = call.mapInputs(
        (value) => switch (value) {
          final BlockParameter parameter =>
            after.parameters[before.parameters.indexOf(parameter)],
          final NativeSymbolAddress address => address.mapInputs((v) => v),
          _ => value,
        },
      ) as NativeCall;
      expect(copy.signature, native);
      expect(copy.dartSignature, same(dart));
      expect(copy.isLeaf, isTrue);
      expect(copy.arguments.first, same(after.parameters[1]));
      expect(copy.borrowedOwners, {0: after.parameters[0]});
      expect(
        (copy.pointer as NativeSymbolAddress).reference,
        same(pointer.reference),
      );
      expect(copy.pointer, isNot(same(pointer)));
      expect(call.borrowedOwners, {0: before.parameters[0]});
      final narrowed = NativeSymbolAddress(
        NativeReference(
          'test',
          'narrow',
          NativeFunctionType(
            NativeSignature(ffi.Int32, [ffi.Pointer<ffi.Void>, ffi.Int64]),
          ),
          isLeaf: true,
        ),
      );
      expect(narrowed.type, pointer.type);
      expect(
        () => call.mapInputs(
          (value) => identical(value, pointer) ? narrowed : value,
        ),
        throwsArgumentError,
      );
      expect(
        () => call.mapInputs(
          (value) => identical(value, before.parameters[0])
              ? const Constant.string('wrong type')
              : value,
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'callbacks retain declared native types and get distinct instructions',
    () {
      final target = FunctionTarget(
        Uri.parse('memory:remap'),
        'callback',
        .integer,
        [.integer],
      );
      final native = FunctionType(FfiTypes.int64, [FfiTypes.int64]);
      final callback = NativeCallbackAddress(
        target,
        native,
        exceptionalReturn: const Constant.integer(-1),
      );
      final copy =
          callback.mapInputs((value) => value) as NativeCallbackAddress;
      expect(copy, isNot(same(callback)));
      expect(copy.function, same(target));
      expect(copy.nativeType, same(native));
      expect(copy.signature, callback.signature);
      expect(copy.exceptionalReturn, callback.exceptionalReturn);
    },
  );

  test('named order, type arguments and storage flags survive remapping', () {
    final before = Block([ValueType.object, ValueType.integer]);
    final after = Block([ValueType.object, ValueType.integer]);
    final selector = (
      kind: FunctionKind.method,
      name: 'invoke',
      privateScope: null,
    );
    final call = DynamicDispatch(
      before.parameters[0],
      selector,
      [before.parameters[1]],
      {'second': before.parameters[1], 'first': const Constant.integer(1)},
      [ValueType.string],
    );
    Value remap(Value value) => value is BlockParameter
        ? after.parameters[before.parameters.indexOf(value)]
        : value;
    final copy = call.mapInputs(remap) as DynamicDispatch;
    expect(copy.selector, selector);
    expect(copy.named.keys, ['second', 'first']);
    expect(copy.named['second'], same(after.parameters[1]));
    expect(copy.typeArguments, [ValueType.string]);
    final late = CellType(ValueType.integer, isLate: true, isFinal: true);
    final cell = NewCell(late, before.parameters[1]);
    final copiedCell = cell.mapInputs(remap) as NewCell;
    expect(copiedCell.type, late);
    expect(copiedCell.initial, same(after.parameters[1]));
  });
}
