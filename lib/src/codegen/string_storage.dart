import 'dart:ffi' show Uint16;

import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';

/// Owns UTF-16 string storage and checked code-unit access.
final class StringStorage({final IrCallable? indexError}) {
  final length = InstanceField(
    ValueType.string,
    'length',
    .integer,
    isFinal: true,
  );

  // shortcut: payloads are immutable module data; own buffers when adding constructed strings.
  final data = InstanceField(ValueType.string, 'data', .integer, isFinal: true);
  late final declaration = IrClass(ValueType.string, [length, data]);
  IrFunction? _read;

  Iterable<IrFunction> get functions => [?_read];

  FunctionTarget? callFor(Instruction operation) =>
      operation is StringCodeUnitAt ? (_read ??= _codeUnitAt()).target : null;

  IrFunction _codeUnitAt() {
    final error = indexError;
    if (error == null) {
      throw UnsupportedError('String indexing requires IndexError.withLength.');
    }
    final target = FunctionTarget(
      Uri.parse('dartc:strings'),
      'codeUnitAt',
      .integer,
      [.string, .integer],
    );
    final entry = Block(target.parameterTypes),
        upper = Block(),
        read = Block(),
        failed = Block();
    final [string, index] = entry.parameters;
    final count = entry.emit(LoadField(length, string));
    entry.finish(
      Branch(
        entry.emit(IntBinary(.lessThan, index, const Constant.integer(0))),
        Jump(failed),
        Jump(upper),
      ),
    );
    upper.finish(
      Branch(
        upper.emit(IntBinary(.lessThan, index, count)),
        Jump(read),
        Jump(failed),
      ),
    );
    final address = read.emit(
      IntBinary(
        .add,
        read.emit(LoadField(data, string)),
        read.emit(IntBinary(.multiply, index, const Constant.integer(2))),
      ),
    );
    read.finish(
      Return(read.emit(LoadNative(address, NativeScalarType(Uint16)))),
    );
    failed.finish(
      Throw(
        failed.emit(
          Construct(
            error.target,
            error.target.signature.bind<Value>(
              [index, count],
              {'indexable': string, 'name': const Constant.string('index')},
              (i) => error.defaults[i]!,
            ),
          ),
        ),
      ),
    );
    return IrFunction(target, [entry, upper, read, failed]);
  }
}
