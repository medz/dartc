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
      <
        Instruction,
        ({
          BinaryEncoding<R> encoding,
          Value left,
          Value right,
          bool floatingInputs,
        })
      >{};
  final mixedComparisons =
      <Instruction, ({Comparison comparison, Value integer, Value floating})>{};
  final calls = <Instruction, CallLayout<R>>{};
  late final CallLayout<R> entry;
  int _generalTemporaries = 0, _floatingTemporaries = 0;

  /// The maximum additional scratch demand of a selected operation.
  int temporaries(RegisterBank bank) =>
      bank == .general ? _generalTemporaries : _floatingTemporaries;

  this {
    if (function.bodyKind != .synchronous ||
        function.target.kind.hasReceiver ||
        function.target.kind == .closure ||
        function.target.typeParameters.isNotEmpty ||
        !(function.target.returnType == .voidType ||
            _scalar(function.target.returnType)) ||
        function.target.parameterTypes.any((type) => !_scalar(type))) {
      throw UnsupportedError(
        'Native scalar signature: ${function.target.name}',
      );
    }
    // Internal booleans use integer locations; exported booleans remain rejected.
    entry = emitter.convention.classify(
      NativeSignature.types(
        _callType(function.target.returnType),
        function.target.parameterTypes.map(_callType),
      ),
    );
    for (final block in function.blocks) {
      for (final instruction in block.instructions) {
        switch (instruction) {
          case NativeCall(:final signature):
            calls[instruction] = emitter.convention.classify(signature);
          case DirectCall(:final inputs, :final type, :final typeArguments):
            if (!(type == .voidType || _scalar(type)) ||
                typeArguments.isNotEmpty ||
                inputs.any((v) => !_scalar(v.type))) {
              throw UnsupportedError(
                'Native call requires supported scalar arguments.',
              );
            }
            calls[instruction] = emitter.convention.classify(
              NativeSignature.types(
                _callType(type),
                inputs.map((v) => _callType(v.type)),
              ),
            );
          case PointerFromAddress() ||
              PointerAddress() ||
              PointerOffset() ||
              LoadNative():
            break;
          case StoreNative(:final pointer):
            if (FfiTypes.pointerElement(pointer.type) == Float &&
                _floatingTemporaries == 0) {
              _floatingTemporaries = 1;
            }
          case NumericNegate(:final type):
            if (type != .floating) {
              throw UnsupportedError('Native numeric negation: $type');
            }
          case NumericToDouble(:final operand):
            if (!_number(operand.type)) {
              throw UnsupportedError(
                'Native conversion requires a known numeric representation.',
              );
            }
          case NumericBinary(:final operator, :final left, :final right):
            if (!_number(left.type) || !_number(right.type)) {
              throw UnsupportedError(
                'Native arithmetic requires known numeric representations.',
              );
            }
            final Comparison? comparison = switch (operator) {
              .lessThan => .lessThan,
              .lessOrEqual => .lessOrEqual,
              .greaterThan => .greaterThan,
              .greaterOrEqual => .greaterOrEqual,
              _ => null,
            };
            if (comparison != null && left.type != right.type) {
              _mixed(instruction, comparison, left, right);
              break;
            }
            final floating =
                instruction.type == .floating || left.type == .floating;
            final encoding = switch (operator) {
              .add => floating ? emitter.addDouble : emitter.add,
              .subtract => floating ? emitter.subtractDouble : emitter.subtract,
              .multiply => floating ? emitter.multiplyDouble : emitter.multiply,
              .divide => emitter.divideDouble,
              _ when comparison != null => emitter.comparison(
                comparison,
                floating: floating,
              ),
              _ => throw UnsupportedError(
                'Native numeric operation: $operator',
              ),
            };
            _binary(
              instruction,
              encoding,
              left,
              right,
              floatingInputs: floating,
            );
          case IntBinary(:final operator, :final left, :final right):
            final encoding = switch (operator) {
              .add => emitter.add,
              .subtract => emitter.subtract,
              .multiply => emitter.multiply,
              .divide => emitter.divideDouble,
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
            _binary(
              instruction,
              encoding,
              left,
              right,
              floatingInputs: operator == .divide,
            );
          case Equals(:final left, :final right, :final negated):
            if (!_scalar(left.type) || !_scalar(right.type)) {
              throw UnsupportedError(
                'Native equality requires supported scalar operands.',
              );
            }
            if (_number(left.type) &&
                _number(right.type) &&
                left.type != right.type) {
              _mixed(instruction, negated ? .notEqual : .equal, left, right);
              break;
            }
            final BinaryEncoding<R> encoding =
                left.type == right.type ||
                    FfiTypes.isPointer(left.type) &&
                        FfiTypes.isPointer(right.type)
                ? emitter.comparison(
                    negated ? .notEqual : .equal,
                    floating: left.type == .floating,
                  )
                : BinaryEncoding(
                    (destination, _, _) =>
                        emitter.loadImmediate(destination, negated ? 1 : 0),
                  );
            _binary(instruction, encoding, left, right);
          default:
            throw UnsupportedError(
              'Native operation: ${instruction.runtimeType}',
            );
        }
      }
    }
  }

  void _binary(
    Instruction instruction,
    BinaryEncoding<R> encoding,
    Value left,
    Value right, {
    bool floatingInputs = false,
  }) {
    final count = floatingInputs
        ? [left, right].where((v) => v.type == .integer).length
        : 0;
    if (count > _floatingTemporaries) _floatingTemporaries = count;
    binaries[instruction] = (
      encoding: encoding,
      left: left,
      right: right,
      floatingInputs: floatingInputs,
    );
  }

  void _mixed(
    Instruction instruction,
    Comparison comparison,
    Value left,
    Value right,
  ) {
    if (left.type == .floating) {
      (left, right) = (right, left);
      comparison = switch (comparison) {
        .lessThan => .greaterThan,
        .lessOrEqual => .greaterOrEqual,
        .greaterThan => .lessThan,
        .greaterOrEqual => .lessOrEqual,
        _ => comparison,
      };
    }
    mixedComparisons[instruction] = (
      comparison: comparison,
      integer: left,
      floating: right,
    );
    _generalTemporaries = 1;
    if (_floatingTemporaries == 0) _floatingTemporaries = 1;
  }

  bool _number(ValueType type) => type == .integer || type == .floating;

  /// Selects the physical bank for an already supported value representation.
  RegisterBank bank(ValueType type) => type == .floating ? .floating : .general;

  bool _scalar(ValueType type) =>
      type == .integer ||
      type == .boolean ||
      type == .floating ||
      FfiTypes.isPointer(type);

  NativeTypeRef _callType(ValueType type) {
    if (type == .voidType) return NativeScalarType(Void);
    if (type == .floating) return NativeScalarType(Double);
    if (type == .integer || type == .boolean) return NativeScalarType(Int64);
    // Dart calls classify addresses without requiring a concrete pointee type.
    if (FfiTypes.isPointer(type)) {
      return NativePointerType(NativeScalarType(Void));
    }
    throw UnsupportedError('Native representation: $type');
  }
}
