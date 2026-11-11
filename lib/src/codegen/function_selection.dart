import 'package:dartc/abi.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';

import 'binary_encoding.dart';
import 'function_emitter.dart';
import 'function_liveness.dart';
import 'function_representation.dart';
import 'storage_access.dart';
import 'double_bits.dart';
import 'reference_equality.dart';
import 'native_invocation.dart';

/// Selects encodings and fixed call locations before allocating a function.
final class FunctionSelection<R>(
  final FunctionRepresentation body,
  final FunctionEmitter<R> emitter,
) {
  final layouts = body.layouts;
  final binaries =
      <
        Value,
        ({
          BinaryEncoding<R> encoding,
          Value left,
          Value right,
          bool floatingInputs,
        })
      >{};
  final mixedComparisons =
      <Instruction, ({Comparison comparison, Value integer, Value floating})>{};
  final calls =
      <
        Value,
        ({CallLayout<R> layout, FunctionTarget? target, List<Value> arguments})
      >{};
  final constantTests = <TypeTest, bool>{};
  final cells = <NewCell>{};
  late final CallLayout<R> entry;
  late final FunctionLiveness liveness;
  int _generalTemporaries = 0, _floatingTemporaries = 0;

  /// The maximum additional scratch demand of a selected operation.
  int temporaries(RegisterBank bank) =>
      bank == .general ? _generalTemporaries : _floatingTemporaries;

  /// The operands read by the selected encoding, including generated constants.
  Iterable<Value> inputsOf(Value instruction) {
    if (constantTests.containsKey(instruction)) return const [];
    if (binaries[instruction] case final binary?) {
      return [binary.left, binary.right];
    }
    return body.inputsOf(instruction);
  }

  this {
    final function = body.function;
    if (function.bodyKind != .synchronous) {
      throw UnsupportedError(
        'Native function signature: ${function.target.name}',
      );
    }
    // Internal booleans use integer locations; exported booleans remain rejected.
    entry = emitter.convention.classify(
      NativeSignature.types(
        layouts.callType(function.target.returnType),
        layouts.entryTypes(function.target).map(layouts.callType),
      ),
    );
    for (final block in body.blocks) {
      switch (body.ends[block]!) {
        case Return() ||
            Jump() ||
            Branch() ||
            Invoke() ||
            Throw() ||
            Unreachable():
          break;
        case final end:
          throw UnsupportedError('Native terminator: ${end.runtimeType}');
      }
      for (final instruction in body.instructions[block]!) {
        if (body.aliases.contains(instruction)) continue;
        if (instruction is Instruction) {
          final target = body.invocations[instruction];
          if (target != null) {
            _call(instruction, target, body.inputsOf(instruction).toList());
            continue;
          }
        }
        switch (instruction) {
          case NewCell(
            type: final CellType type,
            :final initializer,
            :final initial,
          ):
            if (type.isLate || initializer != null) {
              throw UnsupportedError(
                'Native local storage requires a non-late value.',
              );
            }
            layouts.representation(type.content);
            if (initial != null) {
              layouts.checkTransfer(
                body.inputsOf(instruction).single.type,
                type.content,
                constant: initial is ScalarConstant,
              );
            }
            cells.add(instruction);
          case ReadCell(:final cell) || WriteCell(:final cell):
            if (cell is! NewCell) {
              throw UnsupportedError('Native local storage cannot be aliased.');
            }
            if (instruction case WriteCell(:final value)) {
              layouts.checkTransfer(
                body.inputsOf(instruction).last.type,
                (cell.type as CellType).content,
                constant: value is ScalarConstant,
              );
            }
          case NativeInvocation(:final signature, :final arguments):
            calls[instruction] = (
              layout: emitter.convention.classify(signature),
              target: null,
              arguments: arguments,
            );
          case ReifyType():
          case DoubleBits():
            break;
          case ObjectRuntimeType():
            if (_generalTemporaries < 1) _generalTemporaries = 1;
          case ObjectHashCode(:final operand, direct: true):
            if (layouts.representation(operand.type) != .reference) {
              throw UnsupportedError(
                'Native identity hash requires a managed reference.',
              );
            }
            if (_generalTemporaries < 1) _generalTemporaries = 1;
          case LoadField(:final field, :final type) ||
              StorageRead(:final field, :final type):
            _storage(field, body.inputsOf(instruction).first);
            layouts.checkTransfer(field.type, type);
          case StoreField(:final field, :final value) ||
              StorageWrite(:final field, :final value):
            _storage(field, body.inputsOf(instruction).first);
            layouts.checkTransfer(
              body.typeOf(body.inputsOf(instruction).last),
              field.type,
              constant: value is ScalarConstant,
            );
          case TypeView(:final operand, :final type):
            layouts.checkTransfer(
              operand.type,
              type,
              constant: operand is ScalarConstant,
            );
          case TypeTest(:final operand, :final negated):
            final kind = body.tests[instruction]!;
            if (kind == .constantTrue) {
              constantTests[instruction] = !negated;
            } else if (kind == .constantFalse) {
              constantTests[instruction] = negated;
            } else if (kind == .isNull || kind == .isNotNull) {
              final equal = (kind == .isNull) != negated;
              _binary(
                instruction,
                emitter.comparison(equal ? .equal : .notEqual),
                operand,
                const Constant.nullValue(),
              );
            } else {
              throw StateError('Unresolved type test.');
            }
          case LoadObjectData() || StoreObjectData():
            if (_generalTemporaries < 1) _generalTemporaries = 1;
            if (instruction case StoreObjectData(nativeType: final native)
                when native.isSinglePrecision && _floatingTemporaries == 0) {
              _floatingTemporaries = 1;
            }
          case LoadNative():
            break;
          case StoreNative(:final nativeType):
            if (nativeType.isSinglePrecision && _floatingTemporaries == 0) {
              _floatingTemporaries = 1;
            }
          case NumericNegate(:final type):
            if (type != .floating) {
              throw UnsupportedError('Native numeric negation: $type');
            }
          case NumericToDouble(:final operand) ||
              NumericToInt(:final operand) ||
              NumericRoundToDouble(:final operand) ||
              NumericSquareRoot(:final operand):
            if (!_number(operand.type)) {
              throw UnsupportedError(
                'Native numeric operand requires a known representation.',
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
              .truncateDivide => emitter.divideSigned,
              .shiftLeft => emitter.shiftLeft,
              .shiftRight => emitter.shiftRight,
              .unsignedShiftRight => emitter.unsignedShiftRight,
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
          case ReferenceEquality(:final left, :final right, :final negated):
            if (layouts.representation(left.type) != .reference ||
                layouts.representation(right.type) != .reference) {
              throw ArgumentError('Reference equality requires references.');
            }
            _binary(
              instruction,
              emitter.comparison(negated ? .notEqual : .equal),
              left,
              right,
            );
          case Equals(:final left, :final right, :final negated):
            final nullComparison =
                left.type == .nullType || right.type == .nullType;
            final typeLiteral =
                left is TypeConstant ||
                left is ReifyType ||
                left is ObjectRuntimeType && left.direct;
            if (typeLiteral &&
                layouts.representation(right.type) == .reference) {
              throw StateError('Unresolved Type equality.');
            }
            if (!nullComparison &&
                !typeLiteral &&
                (!_scalar(left.type) || !_scalar(right.type))) {
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
                    (nullComparison || typeLiteral) &&
                        layouts.representation(left.type) == .reference &&
                        layouts.representation(right.type) == .reference
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
    liveness = FunctionLiveness(body, inputsOf, calls.keys.toSet());
    calls.removeWhere(
      (instruction, _) => liveness.omitted.contains(instruction),
    );
    for (final block in body.blocks) {
      if (body.ends[block] case Return(value: final value?)) {
        layouts.checkTransfer(
          value.type,
          function.target.returnType,
          constant: value is ScalarConstant,
        );
      }
      for (final edge in body.successors(block)) {
        for (final i in liveness.liveParameters[edge.target]!) {
          final argument = body.argumentsOf(edge)[i];
          final stored = argument is TestedValue
              ? argument.test.operand
              : argument;
          layouts.checkTransfer(
            stored.type,
            edge.target.parameters[i].type,
            constant: stored is ScalarConstant,
          );
        }
      }
    }
  }

  void _call(Instruction operation, FunctionTarget target, List<Value> inputs) {
    final parameters = layouts.entryTypes(target);
    if (inputs.length != parameters.length) {
      throw StateError('Selected call arity does not match ${target.name}.');
    }
    if (operation.type != .never && target.returnType != .never) {
      layouts.checkTransfer(target.returnType, body.typeOf(operation));
    }
    for (final (i, input) in inputs.indexed) {
      layouts.checkTransfer(
        body.typeOf(input),
        parameters[i],
        constant: input is ScalarConstant,
      );
    }
    calls[operation] = (
      layout: emitter.convention.classify(
        NativeSignature.types(
          layouts.callType(target.returnType),
          parameters.map(layouts.callType),
        ),
      ),
      target: target,
      arguments: inputs,
    );
  }

  void _storage(InstanceField field, Value receiver) {
    if (field.isLate ||
        layouts.representation(body.typeOf(receiver)) != .reference) {
      throw StateError('Expected a checked field and a storage reference.');
    }
    layouts.fieldOffset(field);
  }

  void _binary(
    Value instruction,
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
  RegisterBank bank(ValueType type) =>
      layouts.representation(type) == .floating ? .floating : .general;

  bool _scalar(ValueType type) =>
      type == .integer || type == .boolean || type == .floating;
}
