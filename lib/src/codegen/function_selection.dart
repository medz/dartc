import 'package:dartc/abi.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';

import 'binary_encoding.dart';
import 'double_bits.dart';
import 'function_emitter.dart';
import 'function_liveness.dart';
import 'selected_function.dart';
import 'native_invocation.dart';
import 'reference_equality.dart';
import 'storage_access.dart';
import 'type_values.dart';

/// Selects encodings and fixed call locations before allocating a function.
final class FunctionSelection<R>(
  final SelectedFunction body,
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
        ({
          CallLayout<R> layout,
          FunctionTarget? target,
          List<Value> arguments,
          List<ValueType>? parameterTypes,
          Map<RegisterBank, R> stackScratch,
          R? addressRegister,
          R? parkRegister,
          Jump? onThrow,
        })
      >{};
  final constantTests = <TypeTest, bool>{};
  final cells = <NewCell>{};
  late final CallLayout<R> entry;
  late final FunctionLiveness liveness;

  /// Live managed values at each selected call, before assigning their homes.
  late final Map<Value, Set<Value>> liveReferences;
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
    // Internal booleans use integer locations; exported booleans remain rejected.
    entry = emitter.convention.classify(
      NativeSignature.types(
        layouts.callType(layouts.returnType(body.target)),
        layouts.entryTypes(body.target).map(layouts.callType),
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
            _call(
              instruction,
              target,
              body.inputsOf(instruction).toList(),
              block,
            );
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
          case NativeInvocation(:final signature):
            _selectCall(
              instruction,
              emitter.convention.classify(signature),
              body.inputsOf(instruction).skip(1).toList(),
              block,
            );
          case KeepAlive():
          case NativeSymbolAddress():
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
          case LoadField(:final field) || StorageRead(:final field):
            _storage(field, body.inputsOf(instruction).first);
            layouts.checkTransfer(field.type, body.typeOf(instruction));
          case StoreField(:final field, :final value) ||
              StorageWrite(:final field, :final value):
            _storage(field, body.inputsOf(instruction).first);
            layouts.checkTransfer(
              body.typeOf(body.inputsOf(instruction).last),
              field.type,
              constant: value is ScalarConstant,
            );
          case TypeView(:final operand, :final type) ||
              UncheckedCast(:final operand, :final type):
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
          case LoadObjectData() ||
              StoreObjectData() ||
              LoadObjectReference() ||
              StoreObjectReference():
            if (_generalTemporaries < 1) _generalTemporaries = 1;
            if (instruction case StoreObjectData(nativeType: final native)
                when native.isSinglePrecision && _floatingTemporaries == 0) {
              _floatingTemporaries = 1;
            }
          case TypeReference() ||
              ReferenceAddress() ||
              ReferenceFromAddress() ||
              LoadNative():
            break;
          case StoreNative(:final nativeType):
            if (nativeType.isSinglePrecision && _floatingTemporaries == 0) {
              _floatingTemporaries = 1;
            }
          case NumericNegate(:final type):
            if (emitter.negationNeedsTemporary) _generalTemporaries = 1;
            if (type != .floating) {
              throw UnsupportedError('Native numeric negation: $type');
            }
          case FloatBitCast(:final type, :final width):
            if (type == .integer && width == 32 && _floatingTemporaries == 0) {
              _floatingTemporaries = 1;
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
                'Native arithmetic requires known numeric representations in '
                '${body.target.library}::${body.target.name}: '
                '${left.type.dartName} $operator ${right.type.dartName}',
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
              'Native operation: ${instruction.runtimeType} in '
              '${body.target.owner?.dartName ?? body.target.library}.'
              '${body.target.name}',
            );
        }
      }
    }
    liveness = FunctionLiveness(
      body,
      inputsOf,
      calls.keys.toSet(),
      extraInputs: (_) => [?body.stackContext],
    );
    calls.removeWhere(
      (instruction, _) => liveness.omitted.contains(instruction),
    );
    liveReferences = Map.unmodifiable({
      for (final instruction in calls.keys)
        instruction: Set<Value>.unmodifiable(
          liveness.acrossCalls[instruction]!.where(
            (value) => layouts.isReference(body.typeOf(value)),
          ),
        ),
    });
    for (final block in body.blocks) {
      if (body.ends[block] case Return(value: final value?)) {
        layouts.checkTransfer(
          body.typeOf(value),
          layouts.returnType(body.target),
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
            body.typeOf(stored),
            body.typeOf(body.parametersOf(edge.target)[i]),
            constant: stored is ScalarConstant,
          );
        }
      }
    }
  }

  void _call(
    Instruction operation,
    FunctionTarget target,
    List<Value> inputs,
    Block block,
  ) {
    final parameters = layouts.entryTypes(target);
    if (inputs.length != parameters.length) {
      throw StateError('Selected call arity does not match ${target.name}.');
    }
    if (operation.type != .never && target.returnType != .never) {
      layouts.checkTransfer(layouts.returnType(target), body.typeOf(operation));
    }
    for (final (i, input) in inputs.indexed) {
      layouts.checkTransfer(
        body.typeOf(input),
        parameters[i],
        constant: input is ScalarConstant,
      );
    }
    _selectCall(
      operation,
      emitter.convention.classify(
        NativeSignature.types(
          layouts.callType(layouts.returnType(target)),
          parameters.map(layouts.callType),
        ),
      ),
      inputs,
      block,
      target: target,
      parameterTypes: parameters,
    );
  }

  void _selectCall(
    Value operation,
    CallLayout<R> layout,
    List<Value> arguments,
    Block block, {
    FunctionTarget? target,
    List<ValueType>? parameterTypes,
  }) {
    final clobbered = layout.clobberedRegisters;
    final stackScratch = <RegisterBank, R>{};
    for (final (i, location) in layout.parameters.indexed) {
      if (location is! StackArgument) continue;
      final kind = bank(parameterTypes?[i] ?? body.typeOf(arguments[i]));
      stackScratch.putIfAbsent(
        kind,
        () => emitter.allocatableRegisters.firstWhere(
          (register) =>
              emitter.bank(register) == kind && clobbered.contains(register),
        ),
      );
    }
    calls[operation] = (
      layout: layout,
      target: target,
      arguments: List.unmodifiable(arguments),
      parameterTypes: parameterTypes == null
          ? null
          : List.unmodifiable(parameterTypes),
      stackScratch: Map.unmodifiable(stackScratch),
      addressRegister: target != null
          ? null
          : emitter.allocatableRegisters.lastWhere(
              (register) =>
                  emitter.bank(register) == .general &&
                  clobbered.contains(register) &&
                  !layout.registerInputs.containsKey(register) &&
                  !layout.parameters.any(
                    (location) => location.registers.contains(register),
                  ),
            ),
      parkRegister: target != null
          ? null
          : emitter.allocatableRegisters.firstWhere(
              (register) =>
                  emitter.bank(register) == .general &&
                  register != emitter.failureRegister &&
                  clobbered.contains(register),
            ),
      onThrow: switch (body.ends[block]) {
        Invoke(operation: final invoked, :final onThrow)
            when target != null && invoked == operation =>
          onThrow,
        _ => null,
      },
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
    final inputs = body.inputsOf(instruction).toList();
    left = inputs.first;
    if (inputs.length > 1) right = inputs[1];
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
    final inputs = body.inputsOf(instruction).toList();
    left = inputs.first;
    right = inputs.last;
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
