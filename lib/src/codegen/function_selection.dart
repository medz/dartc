import 'package:dartc/abi.dart';
import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';

import 'scalar_binary.dart';
import 'double_bits.dart';
import 'function_emitter.dart';
import 'function_liveness.dart';
import 'selected_function.dart';
import 'native_invocation.dart';
import 'indirect_invocation.dart';
import 'callable_table_address.dart';
import 'reference_equality.dart';
import 'storage_access.dart';
import 'type_values.dart';

/// Selects operand constraints and fixed call locations before allocation.
final class FunctionSelection<R>(
  final SelectedFunction body,
  FunctionEmitter<R> emitter,
) {
  final layouts = body.layouts;
  final convention = emitter.convention;
  final registers = List<R>.unmodifiable(emitter.allocatableRegisters);
  final registerBanks = Map<R, RegisterBank>.unmodifiable({
    for (final register in emitter.allocatableRegisters)
      register: emitter.bank(register),
  });
  final exceptionRegister = emitter.exceptionRegister;
  final traceRegister = emitter.traceRegister;
  final failureRegister = emitter.failureRegister;
  late final R contextRegister;
  bool bindsContext = false;
  final negationNeedsTemporary = emitter.negationNeedsTemporary;
  final binaries =
      <
        Value,
        ({
          bool reuseLeft,
          ({R left, R right, R result, Set<R> clobbered})? fixed,
          Comparison? comparison,
          bool? constant,
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
          List<ExecutionShape>? parameterShapes,
          Map<RegisterBank, R> stackScratch,
          R? addressRegister,
          Jump? onThrow,
        })
      >{};
  final constantTests = <TypeTest, bool>{};
  final nativeStorage = <NativeLocalStorage, NativeStorage>{};
  late final CallLayout<R> entry;
  late final FunctionLiveness liveness;

  /// Live managed values at each selected call, before assigning their homes.
  late final Map<Value, Set<Value>> liveReferences;

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
    entry = convention.classify(
      NativeSignature.types(
        layouts.shapeCallType(layouts.resultShape(body.target)),
        layouts.entryShapes(body.target).map(layouts.shapeCallType),
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
        if (instruction is ReferenceAddress ||
            instruction is ReferenceFromAddress ||
            instruction is AllocatedObject) {
          final value = instruction is ReferenceAddress
              ? instruction.object
              : instruction;
          if (!body.shapeOf(value).isReference) {
            throw UnsupportedError(
              'Memory access requires a reference representation.',
            );
          }
        }
        final memoryObject = switch (instruction) {
          LoadObjectData(:final object) ||
          StoreObjectData(:final object) ||
          LoadObjectReference(:final object) ||
          StoreObjectReference(:final object) => object,
          _ => null,
        };
        if (memoryObject != null && !body.shapeOf(memoryObject).isReference) {
          throw StateError(
            'Managed memory requires a proven reference carrier.',
          );
        }
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
          case NewCell() || CopyCell() || ReadCell() || WriteCell():
            throw StateError('Cell storage must be lowered before selection.');
          case NativeInvocation(:final signature):
            _selectCall(
              instruction,
              convention.classify(signature),
              body.inputsOf(instruction).skip(1).toList(),
              block,
            );
          case IndirectInvocation(
            :final signature,
            :final execution,
            :final arguments,
          ):
            for (final (index, argument) in arguments.indexed) {
              layouts.checkShapeTransfer(
                body.shapeOf(argument),
                execution.parameters[index],
              );
            }
            if (instruction.type != .never && signature.result != .never) {
              layouts.checkShapeTransfer(
                execution.result,
                body.shapeOf(instruction),
              );
            }
            _selectCall(
              instruction,
              convention.classify(
                NativeSignature.types(
                  layouts.shapeCallType(execution.result),
                  execution.parameters.map(layouts.shapeCallType),
                ),
              ),
              arguments,
              block,
              parameterShapes: execution.parameters,
            );
          case BindNativeContext():
            if (!bindsContext) contextRegister = emitter.heapRegister;
            bindsContext = true;
          case ReadNativeContext():
            break;
          case NativeLocalStorage(:final storage):
            final layout = layouts.nativeLayout.of(storage);
            if (layout.size == 0) {
              throw ArgumentError(
                'Native local storage must have positive size.',
              );
            }
            nativeStorage[instruction] = layout;
          case KeepAlive():
          case ObjectDescriptorAddress():
          case StackMapAddress():
          case ModuleRootsAddress():
          case NativeSymbolAddress():
          case NativeDataAddress():
          case CallableTableAddress():
          case ModuleObjectReference():
          case FrameValue():
          case ReifyType():
          case DoubleBits():
            break;
          case ObjectRuntimeType():
            break;
          case ObjectHashCode(:final operand, direct: true):
            if (!body.shapeOf(operand).isReference) {
              throw UnsupportedError(
                'Native identity hash requires a managed reference.',
              );
            }
          case LoadField(:final field) || StorageRead(:final field):
            _storage(field, body.inputsOf(instruction).first);
            layouts.checkShapeTransfer(
              layouts.slotShape(field),
              body.shapeOf(instruction),
            );
          case StoreField(:final field) || StorageWrite(:final field):
            _storage(field, body.inputsOf(instruction).first);
            layouts.checkShapeTransfer(
              body.shapeOf(body.inputsOf(instruction).last),
              layouts.slotShape(field),
            );
          case TypeView(:final operand) || UncheckedCast(:final operand):
            layouts.checkShapeTransfer(
              body.shapeOf(operand),
              body.shapeOf(instruction),
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
                emitter,
                operand,
                const Constant.nullValue(),
                comparison: equal ? .equal : .notEqual,
              );
            } else {
              throw StateError('Unresolved type test.');
            }
          case LoadObjectData() ||
              StoreObjectData() ||
              LoadObjectReference() ||
              StoreObjectReference() ||
              TypeReference() ||
              LoadNative() ||
              StoreNative() ||
              FloatBitCast():
            break;
          case ReferenceAddress() ||
              ReferenceFromAddress() ||
              AllocatedObject():
            break;
          case NumericNegate(:final type):
            if (body.typeOf(instruction) != .floating) {
              throw UnsupportedError('Native numeric negation: $type');
            }
          case NumericToDouble(:final operand) ||
              NumericToInt(:final operand) ||
              NumericRoundToDouble(:final operand) ||
              NumericSquareRoot(:final operand):
            if (!_number(body.typeOf(operand))) {
              throw UnsupportedError(
                'Native numeric operand requires a known representation.',
              );
            }
          case NumericBinary(:final operator, :final left, :final right):
            if (!_number(body.typeOf(left)) || !_number(body.typeOf(right))) {
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
            if (comparison != null && body.typeOf(left) != body.typeOf(right)) {
              _mixed(instruction, comparison, left, right);
              break;
            }
            final floating =
                body.typeOf(instruction) == .floating ||
                body.typeOf(left) == .floating;
            _binary(
              instruction,
              emitter,
              left,
              right,
              floatingInputs: floating,
              comparison: comparison,
            );
          case IntBinary(:final operator, :final left, :final right):
            _binary(
              instruction,
              emitter,
              left,
              right,
              floatingInputs: operator == .divide,
            );
          case ReferenceEquality(:final left, :final right, :final negated):
            if (!body.shapeOf(left).isReference ||
                !body.shapeOf(right).isReference) {
              throw ArgumentError('Reference equality requires references.');
            }
            _binary(
              instruction,
              emitter,
              left,
              right,
              comparison: negated ? .notEqual : .equal,
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
                (!_scalar(body.typeOf(left)) || !_scalar(body.typeOf(right)))) {
              throw UnsupportedError(
                'Native equality requires supported scalar operands.',
              );
            }
            if (_number(body.typeOf(left)) &&
                _number(body.typeOf(right)) &&
                body.typeOf(left) != body.typeOf(right)) {
              _mixed(instruction, negated ? .notEqual : .equal, left, right);
              break;
            }
            final comparable =
                body.typeOf(left) == body.typeOf(right) ||
                (nullComparison || typeLiteral) &&
                    layouts.representation(left.type) == .reference &&
                    layouts.representation(right.type) == .reference;
            _binary(
              instruction,
              emitter,
              left,
              right,
              floatingInputs: comparable && body.typeOf(left) == .floating,
              comparison: comparable ? (negated ? .notEqual : .equal) : null,
              constant: comparable ? null : negated,
            );
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
            (value) => body.shapeOf(value).hasReferences,
          ),
        ),
    });
    for (final block in body.blocks) {
      if (body.ends[block] case Return(value: final value?)) {
        layouts.checkShapeTransfer(
          body.shapeOf(value),
          layouts.resultShape(body.target),
        );
      }
      for (final edge in body.successors(block)) {
        for (final i in liveness.liveParameters[edge.target]!) {
          final argument = body.argumentsOf(edge)[i];
          final stored = argument is TestedValue
              ? argument.test.operand
              : argument;
          layouts.checkShapeTransfer(
            body.shapeOf(stored),
            body.shapeOf(body.parametersOf(edge.target)[i]),
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
    final parameters = layouts.entryShapes(target);
    if (inputs.length != parameters.length) {
      throw StateError('Selected call arity does not match ${target.name}.');
    }
    if (operation is ManagedStorageAllocation) {
      // A successful allocator call yields the raw word in the return register;
      // its consumer owns a managed reference from this point (including GC).
      if (target != operation.allocator || layouts.resultShape(target) != ExecutionShape.word ||
          !body.shapeOf(operation).isReference) {
        throw StateError('Invalid managed allocator ABI transfer.');
      }
    } else if (operation.type != .never && target.returnType != .never) {
      layouts.checkShapeTransfer(
        layouts.resultShape(target),
        body.shapeOf(operation),
      );
    }
    for (final (i, input) in inputs.indexed) {
      layouts.checkShapeTransfer(body.shapeOf(input), parameters[i]);
    }
    _selectCall(
      operation,
      convention.classify(
        NativeSignature.types(
          layouts.shapeCallType(layouts.resultShape(target)),
          parameters.map(layouts.shapeCallType),
        ),
      ),
      inputs,
      block,
      target: target,
      parameterShapes: parameters,
    );
  }

  void _selectCall(
    Value operation,
    CallLayout<R> layout,
    List<Value> arguments,
    Block block, {
    FunctionTarget? target,
    List<ExecutionShape>? parameterShapes,
  }) {
    final clobbered = layout.clobberedRegisters;
    final stackScratch = <RegisterBank, R>{};
    for (final (i, location) in layout.parameters.indexed) {
      if (location is! StackArgument) continue;
      final kind = shapeBank(parameterShapes?[i] ?? body.shapeOf(arguments[i]));
      stackScratch.putIfAbsent(
        kind,
        () => registers.firstWhere(
          (register) =>
              registerBanks[register] == kind && clobbered.contains(register),
        ),
      );
    }
    calls[operation] = (
      layout: layout,
      target: target,
      arguments: List.unmodifiable(arguments),
      parameterShapes: parameterShapes == null
          ? null
          : List.unmodifiable(parameterShapes),
      stackScratch: Map.unmodifiable(stackScratch),
      addressRegister: target != null
          ? null
          : registers.lastWhere(
              (register) =>
                  registerBanks[register] == .general &&
                  clobbered.contains(register) &&
                  !layout.registerInputs.containsKey(register) &&
                  !layout.parameters.any(
                    (location) => location.registers.contains(register),
                  ),
            ),
      onThrow: switch (body.ends[block]) {
        Invoke(operation: final invoked, :final onThrow)
            when target != null && invoked == operation ||
                operation is IndirectInvocation &&
                    invoked == operation.origin =>
          onThrow,
        _ => null,
      },
    );
  }

  void _storage(InstanceField field, Value receiver) {
    if (field.isLate || !body.shapeOf(receiver).isReference) {
      throw StateError('Expected a checked field and a storage reference.');
    }
    layouts.fieldOffset(field);
  }

  void _binary(
    Value instruction,
    FunctionEmitter<R> emitter,
    Value left,
    Value right, {
    bool floatingInputs = false,
    Comparison? comparison,
    bool? constant,
  }) {
    final inputs = body.inputsOf(instruction).toList();
    left = inputs.first;
    if (inputs.length > 1) right = inputs[1];
    final encoding = scalarBinaryEncoding(
      emitter,
      instruction,
      floating: floatingInputs,
      comparison: comparison,
      constant: constant,
    );
    final fixed = encoding.fixed;
    binaries[instruction] = (
      reuseLeft: encoding.reuseLeft,
      fixed: fixed == null
          ? null
          : (
              left: fixed.left,
              right: fixed.right,
              result: fixed.result,
              clobbered: Set<R>.unmodifiable(fixed.clobbered),
            ),
      comparison: comparison,
      constant: constant,
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
    if (body.typeOf(left) == .floating) {
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
  }

  bool _number(ValueType type) => type == .integer || type == .floating;

  /// Selects the physical bank for an already supported value representation.
  RegisterBank valueBank(Value value) => shapeBank(body.shapeOf(value));

  RegisterBank shapeBank(ExecutionShape shape) =>
      layouts.shapeRepresentation(shape) == .floating ? .floating : .general;

  RegisterBank bank(ValueType type) =>
      layouts.representation(type) == .floating ? .floating : .general;

  bool _scalar(ValueType type) =>
      type == .integer || type == .boolean || type == .floating;
}
