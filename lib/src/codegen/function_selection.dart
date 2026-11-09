import 'package:dartc/abi.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';

import 'binary_encoding.dart';
import 'function_emitter.dart';

/// Selects encodings and fixed call locations before allocating a function.
final class FunctionSelection<R>(
  IrFunction function,
  FunctionEmitter<R> emitter,
) {
  final binaries =
      <Instruction, ({BinaryEncoding<R> encoding, Value left, Value right})>{};
  final calls = <DirectCall, CallLayout<R>>{};
  late final CallLayout<R> entry;

  this {
    if (function.bodyKind != .synchronous ||
        function.target.kind.hasReceiver ||
        function.target.kind == .closure ||
        function.target.typeParameters.isNotEmpty ||
        function.target.signature.optionalSlots.isNotEmpty ||
        function.target.signature.namedParameters.isNotEmpty ||
        !_word(function.target.returnType) ||
        function.target.parameterTypes.any((type) => !_word(type))) {
      throw UnsupportedError(
        'Native scalar signature: ${function.target.name}',
      );
    }
    // Internal int/bool values use word locations; exports still require Int64.
    entry = emitter.convention.classify(
      NativeSignature.int64(function.entry.parameters.length),
    );
    for (final block in function.blocks) {
      for (final instruction in block.instructions) {
        switch (instruction) {
          case DirectCall(:final inputs, :final type, :final typeArguments):
            if (!_word(type) ||
                typeArguments.isNotEmpty ||
                inputs.any((v) => !_word(v.type))) {
              throw UnsupportedError(
                'Native call requires integer or boolean arguments.',
              );
            }
            calls[instruction] = emitter.convention.classify(
              NativeSignature.int64(inputs.length),
            );
          case IntBinary(:final operator, :final left, :final right):
            final encoding = switch (operator) {
              .add => emitter.add,
              .subtract => emitter.subtract,
              .multiply => emitter.multiply,
              .bitAnd => emitter.bitAnd,
              .bitOr => emitter.bitOr,
              .bitXor => emitter.bitXor,
              .lessThan => emitter.comparison(.lessThan),
              .lessOrEqual => emitter.comparison(.lessOrEqual),
              .greaterThan => emitter.comparison(.greaterThan),
              .greaterOrEqual => emitter.comparison(.greaterOrEqual),
              _ => throw UnsupportedError(
                'Native integer operation: $operator',
              ),
            };
            binaries[instruction] = (
              encoding: encoding,
              left: left,
              right: right,
            );
          case Equals(:final left, :final right, :final negated):
            if (!_word(left.type) || !_word(right.type)) {
              throw UnsupportedError(
                'Native equality requires integer or boolean operands.',
              );
            }
            final BinaryEncoding<R> encoding = left.type == right.type
                ? emitter.comparison(negated ? .notEqual : .equal)
                : BinaryEncoding(
                    (destination, _, _) =>
                        emitter.loadImmediate(destination, negated ? 1 : 0),
                  );
            binaries[instruction] = (
              encoding: encoding,
              left: left,
              right: right,
            );
          default:
            throw UnsupportedError(
              'Native operation: ${instruction.runtimeType}',
            );
        }
      }
    }
  }

  bool _word(ValueType type) => type == .integer || type == .boolean;
}
