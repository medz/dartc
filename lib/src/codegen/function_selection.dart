import 'dart:ffi';

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
        !(function.target.returnType == .voidType ||
            _scalar(function.target.returnType)) ||
        function.target.parameterTypes.any((type) => !_scalar(type))) {
      throw UnsupportedError(
        'Native scalar signature: ${function.target.name}',
      );
    }
    // Internal booleans use integer locations; exported booleans remain rejected.
    entry = emitter.convention.classify(
      NativeSignature(
        _nativeType(function.target.returnType),
        function.target.parameterTypes.map(_nativeType),
      ),
    );
    for (final block in function.blocks) {
      for (final instruction in block.instructions) {
        switch (instruction) {
          case DirectCall(:final inputs, :final type, :final typeArguments):
            if (!(type == .voidType || _scalar(type)) ||
                typeArguments.isNotEmpty ||
                inputs.any((v) => !_scalar(v.type))) {
              throw UnsupportedError(
                'Native call requires supported scalar arguments.',
              );
            }
            calls[instruction] = emitter.convention.classify(
              NativeSignature(
                _nativeType(type),
                inputs.map((v) => _nativeType(v.type)),
              ),
            );
          case PointerFromAddress() ||
              PointerAddress() ||
              LoadNativeInt64() ||
              StoreNativeInt64():
            break;
          case NumericNegate(:final type):
            if (type != .floating) {
              throw UnsupportedError('Native numeric negation: $type');
            }
          case NumericBinary(:final operator, :final left, :final right):
            if (left.type != .floating || right.type != .floating) {
              throw UnsupportedError(
                'Native arithmetic requires known double operands.',
              );
            }
            final encoding = switch (operator) {
              .add => emitter.addDouble,
              .subtract => emitter.subtractDouble,
              .multiply => emitter.multiplyDouble,
              .divide => emitter.divideDouble,
              .lessThan => emitter.comparison(.lessThan, floating: true),
              .lessOrEqual => emitter.comparison(.lessOrEqual, floating: true),
              .greaterThan => emitter.comparison(.greaterThan, floating: true),
              .greaterOrEqual => emitter.comparison(
                .greaterOrEqual,
                floating: true,
              ),
              _ => throw UnsupportedError('Native double operation: $operator'),
            };
            binaries[instruction] = (
              encoding: encoding,
              left: left,
              right: right,
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
            if (!_scalar(left.type) ||
                !_scalar(right.type) ||
                (left.type == .integer && right.type == .floating) ||
                (left.type == .floating && right.type == .integer)) {
              throw UnsupportedError(
                'Native equality requires supported scalar operands.',
              );
            }
            final BinaryEncoding<R> encoding = left.type == right.type
                ? emitter.comparison(
                    negated ? .notEqual : .equal,
                    floating: left.type == .floating,
                  )
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

  /// Selects the physical bank for an already supported value representation.
  RegisterBank bank(ValueType type) => type == .floating ? .floating : .general;

  bool _scalar(ValueType type) =>
      type == .integer ||
      type == .boolean ||
      type == .floating ||
      type == FfiTypes.int64Pointer;

  Type _nativeType(ValueType type) => type == .voidType
      ? Void
      : type == .floating
      ? Double
      : type == FfiTypes.int64Pointer
      ? Pointer<Int64>
      : Int64;
}
