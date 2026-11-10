import 'dart:ffi';

import 'package:dartc/abi.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';

import 'binary_encoding.dart';
import 'function_emitter.dart';
import 'function_liveness.dart';
import 'function_representation.dart';
import 'heap_plan.dart';
import 'program_layout.dart';

/// Selects encodings and fixed call locations before allocating a function.
final class FunctionSelection<R>(
  IrFunction function,
  final FunctionEmitter<R> emitter,
  final ProgramLayout layouts,
  HeapPlan heap,
) {
  final body = FunctionRepresentation(function, layouts);
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
  final calls =
      <
        Instruction,
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
  Iterable<Value> inputsOf(Instruction instruction) {
    if (constantTests.containsKey(instruction)) return const [];
    if (binaries[instruction] case final binary?) {
      return [binary.left, binary.right];
    }
    return body.inputsOf(instruction);
  }

  this {
    if (function.bodyKind != .synchronous ||
        function.target.kind == .closure ||
        function.target.typeParameters.isNotEmpty) {
      throw UnsupportedError(
        'Native function signature: ${function.target.name}',
      );
    }
    // Internal booleans use integer locations; exported booleans remain rejected.
    entry = emitter.convention.classify(
      NativeSignature.types(
        layouts.callType(function.target.returnType),
        function.target.parameterTypes.map(layouts.callType),
      ),
    );
    for (final block in body.blocks) {
      switch (body.ends[block]!) {
        case Return() || Jump() || Branch():
          break;
        case final end:
          throw UnsupportedError('Native terminator: ${end.runtimeType}');
      }
      for (final instruction in body.instructions[block]!) {
        if (body.boxes[instruction] case final value?) {
          _call(instruction, heap.box(value.type), [value]);
          continue;
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
          case NativeCall(:final signature, :final arguments):
            calls[instruction] = (
              layout: emitter.convention.classify(signature),
              target: null,
              arguments: arguments,
            );
          case final Construct operation:
            final target = heap.constructors[operation]!;
            _call(instruction, target, body.inputsOf(operation).toList());
          case DirectCall(:final target, :final type, :final typeArguments):
            if (typeArguments.isNotEmpty) {
              throw UnsupportedError(
                'Native generic function calls are not implemented.',
              );
            }
            if (type != .voidType) {
              layouts.checkTransfer(target.returnType, type);
            }
            _call(instruction, target, body.inputsOf(instruction).toList());
          case LoadField(:final field, :final type):
            if (field.isLate) {
              throw UnsupportedError('Native late field: ${field.name}');
            }
            layouts.fieldOffset(field);
            layouts.checkTransfer(field.type, type);
          case StoreField(:final field, :final value):
            if (field.isLate || field.type.freeTypeParameters.isNotEmpty) {
              throw UnsupportedError(
                'Native checked field write: ${field.name}',
              );
            }
            layouts.fieldOffset(field);
            layouts.checkTransfer(
              body.inputsOf(instruction).last.type,
              field.type,
              constant: value is ScalarConstant,
            );
          case TypeView(:final operand, :final type):
            layouts.checkTransfer(
              operand.type,
              type,
              constant: operand is ScalarConstant,
            );
          case TypeTest(:final operand, :final testedType, :final negated):
            final source = operand.type;
            if (testedType.accepts(source)) {
              constantTests[instruction] = !negated;
            } else if (testedType == .never ||
                source == .nullType && !testedType.mayBeNull ||
                testedType == .nullType && !source.mayBeNull) {
              constantTests[instruction] = negated;
            } else if (testedType == .nullType ||
                testedType == .object ||
                !testedType.mayBeNull &&
                    testedType.accepts(source.nonNullable)) {
              if (layouts.representation(source) != .reference) {
                throw UnsupportedError(
                  'Native null test representation: ${source.dartName}',
                );
              }
              final equal = (testedType == .nullType) != negated;
              _binary(
                instruction,
                emitter.comparison(equal ? .equal : .notEqual),
                operand,
                const Constant.nullValue(),
              );
            } else {
              throw UnsupportedError(
                'Native type test requires runtime type metadata: ${testedType.dartName}',
              );
            }
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
          case NumericToDouble(:final operand) ||
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
            final nullComparison =
                left.type == .nullType || right.type == .nullType;
            if (!nullComparison &&
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
                    FfiTypes.isPointer(left.type) &&
                        FfiTypes.isPointer(right.type) ||
                    nullComparison &&
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
      if (body.ends[block] case Return(value: final value?)
          when function.target.returnType != .voidType) {
        layouts.checkTransfer(
          value.type,
          function.target.returnType,
          constant: value is ScalarConstant,
        );
      }
      for (final edge in body.successors(block)) {
        for (final i in liveness.liveParameters[edge.target]!) {
          final argument = edge.arguments[i];
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
    if (cells.isNotEmpty) _checkCells(function);
  }

  void _call(Instruction operation, FunctionTarget target, List<Value> inputs) {
    for (final (i, input) in inputs.indexed) {
      layouts.checkTransfer(
        input.type,
        target.parameterTypes[i],
        constant: input is ScalarConstant,
      );
    }
    calls[operation] = (
      layout: emitter.convention.classify(
        NativeSignature.types(
          layouts.callType(target.returnType),
          target.parameterTypes.map(layouts.callType),
        ),
      ),
      target: target,
      arguments: inputs,
    );
  }

  void _checkCells(IrFunction function) {
    final predecessors = {
      for (final block in function.blocks) block: <Block>[],
    };
    for (final block in function.blocks) {
      for (final instruction in block.instructions) {
        for (final value in instruction.inputs.where(cells.contains)) {
          if (!(instruction is ReadCell && instruction.cell == value ||
              instruction is WriteCell && instruction.cell == value)) {
            throw UnsupportedError('Native local storage cannot escape.');
          }
        }
      }
      if (block.end case Return(value: final value?)
          when cells.contains(value)) {
        throw UnsupportedError('Native local storage cannot escape.');
      }
      for (final edge in block.successors) {
        if (edge.arguments.any(cells.contains)) {
          throw UnsupportedError('Native local storage cannot be aliased.');
        }
        predecessors[edge.target]!.add(block);
      }
    }
    final initialized = {
      for (final block in function.blocks) block: cells.toSet(),
    };
    Set<NewCell> after(Block block, {bool checkReads = false}) {
      final ready = block == function.entry ? <NewCell>{} : cells.toSet();
      for (final previous in predecessors[block]!) {
        ready.removeWhere((cell) => !initialized[previous]!.contains(cell));
      }
      for (final instruction in block.instructions) {
        if (checkReads && calls.containsKey(instruction)) {
          for (final cell
              in liveness.acrossCalls[instruction]!.whereType<NewCell>()) {
            if (!ready.contains(cell)) {
              throw UnsupportedError('Live local is uninitialized at a call.');
            }
          }
        }
        switch (instruction) {
          case NewCell(:final initial):
            if (initial == null) {
              ready.remove(instruction);
            } else {
              ready.add(instruction);
            }
          case WriteCell(cell: final NewCell cell):
            ready.add(cell);
          case ReadCell(:final cell) when checkReads && !ready.contains(cell):
            throw UnsupportedError(
              'Native local may be read before initialization.',
            );
          default:
            break;
        }
      }
      return ready;
    }

    bool changed;
    do {
      changed = false;
      for (final block in function.blocks) {
        final next = after(block), previous = initialized[block]!;
        if (next.length != previous.length || !next.containsAll(previous)) {
          initialized[block] = next;
          changed = true;
        }
      }
    } while (changed);
    for (final block in function.blocks) {
      after(block, checkReads: true);
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
  RegisterBank bank(ValueType type) =>
      layouts.representation(type) == .floating ? .floating : .general;

  bool _scalar(ValueType type) =>
      type == .integer ||
      type == .boolean ||
      type == .floating ||
      FfiTypes.isPointer(type);
}
