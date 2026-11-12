import 'dart:ffi' show Uint8;

import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';

import 'program_layout.dart';
import 'checked_casts.dart';
import 'type_values.dart';
import 'member_calls.dart';
import 'heap_plan.dart';
import 'cell_initialization.dart';
import 'storage_access.dart';
import 'double_bits.dart';
import 'reference_equality.dart';
import 'selected_graph.dart';
import 'value_operations.dart';
import 'native_invocation.dart';
import 'non_null_values.dart';

/// Places allocating representation changes before register and root analysis.
final class FunctionRepresentation(
  final IrFunction function,
  final ProgramLayout layouts,
  CheckedCasts casts,
  MemberCalls members,
  HeapPlan heap, {
  FunctionTarget? captureTrace,
}) extends SelectedGraph {
  final _operands = <Instruction, List<Value>>{};
  final _arguments = <Jump, List<Value>>{};
  final boxes = <Instruction, Value>{};
  final introduced = <Instruction>{};
  final tests = <TypeTest, TypeTestKind>{};
  final invocations = <Instruction, FunctionTarget>{};
  final aliases = <Instruction>{};
  final _resultTypes = <Value, ValueType>{};
  final stackCells = <NewCell>{};
  final _prologue = <Value>[];
  bool get _factoryEnvironment =>
      function.target.kind == .factory &&
      function.target.owner!.typeParameters.isNotEmpty;
  late final entryParameters =
      layouts.entryTypes(function.target).length ==
          function.entry.parameters.length
      ? function.entry.parameters
      : [
          ...function.entry.parameters,
          ...Block(
            layouts
                .entryTypes(function.target)
                .skip(function.entry.parameters.length),
          ).parameters,
        ];

  late final _classArguments = _ownerArguments(
    _factoryEnvironment
        ? entryParameters[function.entry.parameters.length]
        : layouts.types.runtimeTypeOf(
            function.entry.parameters.first,
            _prologue,
          ),
    function.target.owner!,
    _prologue,
  );

  List<Value> _ownerArguments(Value actual, ClassType owner, List<Value> into) {
    final view = DirectCall(layouts.relations.viewOf(owner), [actual]);
    final checked = NullCheck(view);
    var parts = LoadField(TypeValues.parts, checked);
    into.addAll([view, checked, parts]);
    final arguments = <Value>[];
    for (final _ in owner.typeParameters) {
      final node = NullCheck(parts);
      final head = LoadField(TypeValues.head, node);
      final tail = LoadField(TypeValues.tail, node);
      into.addAll([node, head, tail]);
      arguments.add(head);
      parts = tail;
    }
    return arguments;
  }

  List<BlockParameter> parametersOf(Block block) =>
      block == function.entry ? entryParameters : block.parameters;

  Value _reify(ValueType type, List<Value> into) {
    if (type is TypeParameterType) {
      final index = function.target.typeParameters.indexOf(type);
      if (index >= 0) {
        return entryParameters[function.entry.parameters.length +
            (_factoryEnvironment ? 1 : 0) +
            index];
      }
      final owner = function.target.owner;
      if (owner != null &&
          (function.target.kind.hasReceiver || _factoryEnvironment)) {
        final index = owner.typeParameters.indexOf(type);
        if (index >= 0) return _classArguments[index];
      }
      if (function.target.kind == .closure) {
        final shape = layouts.closures.closures[function.target]!;
        final index = shape.parameters.indexOf(type);
        if (index >= 0) {
          return _load(shape.environment[index], entryParameters.first, into);
        }
      }
      throw UnsupportedError('Native type needs a lexical environment: $type');
    }
    if (type.freeTypeParameters.isEmpty) return layouts.types.constant(type);
    final (:target, :parameters) = layouts.types.instantiate(type);
    final call = DirectCall(target, [
      for (final parameter in parameters) _reify(parameter, into),
    ]);
    into.add(call);
    return call;
  }

  Iterable<Value> inputsOf(Value operation) => switch (operation) {
    StorageAccess(:final inputs) => inputs,
    DoubleBits(:final operand) => [operand],
    TypeReference(:final operand) => [operand],
    ReferenceEquality(:final left, :final right) => [left, right],
    NativeInvocation(:final inputs) => inputs,
    Instruction() => _operands[operation] ?? operation.inputs,
    _ => throw ArgumentError('Expected a selected operation.'),
  };

  /// The stored type before a selected call result is boxed for its caller.
  ValueType typeOf(Value value) =>
      _resultTypes[value] ??
      (stackCells.contains(value)
          ? (value.type as CellType).content
          : value.type);

  StorageRead _load(InstanceField field, Value receiver, List<Value> into) {
    final load = StorageRead(field, receiver);
    into.add(load);
    return load;
  }

  List<Value> argumentsOf(Jump edge) => _arguments[edge] ?? edge.arguments;

  Iterable<Jump> successors(Block block) => switch (ends[block]!) {
    final Jump jump => [jump],
    Branch(:final ifTrue, :final ifFalse) => [ifTrue, ifFalse],
    Invoke(:final onReturn, :final onThrow) => [?onReturn, onThrow],
    Throw(:final onThrow) ||
    ExhaustivenessFailure(:final onThrow) => [?onThrow],
    Return() || Unreachable() => const [],
    _ => block.successors,
  };

  this {
    final nonNull = NonNullValues(function);
    final valueOperations = ValueOperations(this, layouts, heap.invalid);
    checkCellInitialization(function);
    final operations = [
      for (final block in function.blocks) ...[
        ...block.instructions,
        if (block.end case Invoke(:final operation)) operation,
      ],
    ];
    // An address-only temporary has no observable object identity.
    final addressOnly = <Value>{
      for (final (i, parameter) in function.entry.parameters.indexed)
        if (layouts.pointerParameters.contains(function.target, i)) parameter,
      for (final operation in operations)
        if (operation is PointerFromAddress || operation is PointerOffset)
          operation,
    };
    stackCells.addAll(
      operations.whereType<NewCell>().where(
        (cell) => !(cell.type as CellType).isLate,
      ),
    );
    for (final operation in operations) {
      for (final (i, input) in operation.inputs.indexed) {
        if (!layouts.pointerParameters.accepts(operation, i)) {
          addressOnly.remove(input);
        }
        if (!(operation is ReadCell && operation.cell == input ||
            operation is WriteCell && operation.cell == input)) {
          stackCells.remove(input);
        }
      }
    }
    for (final block in function.blocks) {
      if (block.end case Return(value: final value?)) stackCells.remove(value);
      switch (block.end) {
        case Return(value: final value?) ||
            Throw(exception: final value) ||
            Yield(:final value) ||
            Await(operand: final value):
          addressOnly.remove(value);
        default:
          break;
      }
      for (final edge in block.successors) {
        stackCells.removeAll(edge.arguments);
        addressOnly.removeAll(edge.arguments);
      }
    }
    for (final parameter in function.entry.parameters) {
      if (addressOnly.contains(parameter)) _resultTypes[parameter] = .integer;
    }
    Value pointerAddress(Value pointer, List<Value> into) {
      if (!addressOnly.contains(pointer)) {
        return _load(layouts.pointers.address, pointer, into);
      }
      final address = PointerAddress(pointer);
      aliases.add(address);
      _operands[address] = [pointer];
      into.add(address);
      return address;
    }

    bool needsBox(Value value, ValueType type) {
      if (value is TestedValue) value = value.test.operand;
      return value is! Constant &&
          value.type is! CellType &&
          (typeOf(value) == .integer || typeOf(value) == .floating) &&
          layouts.representation(type) == .reference;
    }

    Value convert(Value value, ValueType type, List<Value> into) {
      if (type == .integer && FfiTypes.isPointer(value.type)) {
        return pointerAddress(value, into);
      }
      if (!needsBox(value, type)) return value;
      final box = TypeView(
        value,
        type.accepts(value.type) ? type : ValueType.object,
      );
      boxes[box] = value;
      introduced.add(box);
      into.add(box);
      return box;
    }

    Value? traceFor(Value? trace, List<Value> into) {
      if (trace != null || captureTrace == null) return trace;
      final capture = DirectCall(captureTrace, []);
      into.add(capture);
      return capture;
    }

    Value checkResult(Value value, ValueType type, List<Value> into) {
      final raw = TypeView(value, .object.nullable);
      final check = TypeCast(raw, type);
      into.add(raw);
      final signature = casts.targetFor(check, layouts);
      _operands[check] = [
        raw,
        for (final parameter in signature.parameters) _reify(parameter, into),
      ];
      into.add(check);
      return check;
    }

    void runtimeType(ObjectRuntimeType instruction, List<Value> into) {
      final source = instruction.operand.type;
      if (source == .nullType || layouts.representation(source) != .reference) {
        _operands[instruction] = [_reify(source, into)];
      }
    }

    void typeTest(TypeTest instruction, List<Value> into) {
      final kind = tests[instruction] = layouts.typeTest(
        instruction.operand.type,
        instruction.testedType,
      );
      if (kind == .subtype) {
        final actual = ObjectRuntimeType(instruction.operand, direct: true);
        runtimeType(actual, into);
        into.add(actual);
        if ([
          ValueType.integer,
          ValueType.floating,
          ValueType.boolean,
        ].contains(instruction.testedType)) {
          final comparison = ReferenceEquality(
            actual,
            layouts.types.constant(instruction.testedType),
            negated: instruction.negated,
          );
          aliases.add(instruction);
          _operands[instruction] = [comparison];
          into.addAll([comparison, instruction]);
          return;
        }
        _operands[instruction] = [actual, _reify(instruction.testedType, into)];
      }
      into.add(instruction);
    }

    Jump edge(Jump jump) {
      if (!jump.arguments.indexed.any(
        (item) => needsBox(item.$2, jump.target.parameters[item.$1].type),
      )) {
        return jump;
      }
      final inputs = [
        for (final (i, value) in jump.arguments.indexed)
          value is TestedValue &&
                  needsBox(value, jump.target.parameters[i].type)
              ? value.test.operand
              : value,
      ];
      final block = Block(inputs.map((v) => v.type));
      blocks.add(block);
      final body = instructions[block] = <Value>[];
      final arguments = [
        for (final (i, value) in block.parameters.indexed)
          convert(value, jump.target.parameters[i].type, body),
      ];
      // Retain the verified edge's type proof while assigning its physical operands.
      final transfer = Jump(jump.target, jump.arguments);
      _arguments[transfer] = arguments;
      ends[block] = transfer;
      block.finish(transfer);
      return Jump(block, inputs);
    }

    Block appendTo(Block block, Value operation, Jump? handler) {
      instructions[block]!.add(operation);
      if (handler == null || operation is! Instruction || !operation.mayThrow) {
        return block;
      }
      final next = Block();
      blocks.add(next);
      instructions[next] = [];
      ends[block] = Invoke(
        operation,
        onReturn: Jump(next),
        onThrow: edge(handler),
      );
      return next;
    }

    blocks.addAll(function.blocks);
    sourceBlocks:
    for (final sourceBlock in function.blocks) {
      var block = sourceBlock;
      var body = instructions[block] = <Value>[];
      final source = switch (sourceBlock.end) {
        Invoke(:final operation) => sourceBlock.instructions.followedBy([
          operation,
        ]),
        _ => sourceBlock.instructions,
      };
      for (final instruction in source) {
        final handler = switch (sourceBlock.end) {
          Invoke(:final operation, :final onThrow)
              when operation == instruction =>
            onThrow,
          _ => null,
        };
        if (instruction case ObjectClassName(:final operand)) {
          final type = layouts.types.runtimeTypeOf(operand, body);
          final name = _load(TypeValues.className, type, body);
          aliases.add(instruction);
          _operands[instruction] = [name];
          body.add(instruction);
          continue;
        }
        if (instruction case Identical(:final left, :final right)) {
          block = valueOperations.identical(left, right, block, typeTest);
          body = instructions[block]!;
          body.add(instruction);
          aliases.add(instruction);
          _operands[instruction] = block.parameters;
          continue;
        }
        if (instruction case ObjectHashCode(:final operand, direct: true)) {
          block = valueOperations.identityHash(operand, block, typeTest);
          body = instructions[block]!;
          body.add(instruction);
          aliases.add(instruction);
          _operands[instruction] = block.parameters;
          continue;
        }
        if (instruction case NewCollection(:final collectionType)
            when collectionType.declaration == CoreTypes.map ||
                collectionType.declaration == CoreTypes.set) {
          final target = layouts
              .collectionFactory(collectionType)
              .implementation;
          invocations[instruction] = target;
          _operands[instruction] = [
            ...target.signature.bind<Value>(
              [],
              {},
              (index) =>
                  members.program.implementationOf(target)!.defaults[index]!,
            ),
            _reify(
              target.owner!.instantiate(collectionType.typeArguments),
              body,
            ),
          ];
          body.add(instruction);
          continue;
        }
        if (layouts.lists.callFor(instruction) case final target?) {
          final element = instruction is CollectionSpread
              ? CoreTypes.view(
                  instruction.collection.type,
                  CoreTypes.list,
                )!.typeArguments.single
              : (instruction.type as ClassType).typeArguments.single;
          final inputs = instruction is NewCollection
              ? [instruction.growable ?? const Constant.boolean(true)]
              : instruction.inputs.toList();
          invocations[instruction] = target;
          _operands[instruction] = [
            for (final (i, input) in inputs.indexed)
              convert(input, target.parameterTypes[i], body),
            _reify(
              instruction is CollectionSpread
                  ? element
                  : CoreTypes.listOf(element),
              body,
            ),
          ];
          body.add(instruction);
          continue;
        }
        if (instruction case NewPayload(
          type: final ClassType type,
          :final bytes,
        )) {
          invocations[instruction] = heap.allocatePayload(type);
          _operands[instruction] = [bytes];
          body.add(instruction);
          continue;
        }
        if (instruction
            case LoadNative(:final address, nativeType: final native)
            when native.isBoolean) {
          final byte = LoadNative(address, NativeScalarType(Uint8));
          final boolean = IntBinary(
            .greaterThan,
            byte,
            const Constant.integer(0),
          );
          body.addAll([byte, boolean]);
          _operands[instruction] = [boolean];
          aliases.add(instruction);
          body.add(instruction);
          continue;
        }
        if (instruction case NativeView(
          type: final ClassType type,
          :final address,
          :final owner,
          :final copy,
        )) {
          invocations[instruction] = address == null || copy
              ? layouts.native!.owned(
                  type,
                  heap.allocatePayload(layouts.native!.buffer),
                  copy: copy,
                )
              : heap.constructorFor(
                  layouts.native!.view(type).initializer,
                  layouts,
                );
          _operands[instruction] = [
            address ?? const Constant.integer(0),
            owner,
            if (address != null && !copy) layouts.types.constant(type),
          ];
          body.add(instruction);
          continue;
        }
        if (instruction case NativeAddress(:final view)) {
          _operands[instruction] = [
            _load(
              layouts.native!.view(view.type as ClassType).address,
              view,
              body,
            ),
          ];
          aliases.add(instruction);
          body.add(instruction);
          continue;
        }
        if (instruction is NativeSize || instruction is NativeFieldOffset) {
          final value = instruction is NativeSize
              ? layouts.native!.layout.of(instruction.nativeType).size
              : layouts.native!.layout
                    .of((instruction as NativeFieldOffset).owner)
                    .offsets[instruction.index];
          _operands[instruction] = [Constant.integer(value)];
          aliases.add(instruction);
          body.add(instruction);
          continue;
        }
        if (instruction case CopyNative(
          :final destination,
          :final source,
          :final nativeType,
        )) {
          invocations[instruction] = heap.runtime!.copyBytes;
          _operands[instruction] = [
            destination,
            source,
            Constant.integer(layouts.native!.layout.of(nativeType).size),
          ];
          body.add(instruction);
          continue;
        }
        if (instruction
            case PointerAddress(pointer: final receiver) ||
                StringLength(string: final receiver)) {
          _operands[instruction] = [
            if (instruction is PointerAddress && addressOnly.contains(receiver))
              receiver
            else
              _load(
                instruction is PointerAddress
                    ? layouts.pointers.address
                    : layouts.strings.length,
                receiver,
                body,
              ),
          ];
          aliases.add(instruction);
          body.add(instruction);
          continue;
        }
        if (instruction is PointerFromAddress || instruction is PointerOffset) {
          final Value address;
          if (instruction case PointerFromAddress(address: final value)) {
            address = value;
          } else {
            final offset = instruction as PointerOffset;
            final base = pointerAddress(offset.pointer, body);
            final bytes = IntBinary(
              .multiply,
              offset.index,
              Constant.integer(
                FfiTypes.pointerElementSize(offset.pointer.type)!,
              ),
            );
            address = IntBinary(.add, base, bytes);
            body.addAll([bytes, address]);
          }
          if (addressOnly.contains(instruction)) {
            _resultTypes[instruction] = .integer;
            _operands[instruction] = [address];
            aliases.add(instruction);
            body.add(instruction);
            continue;
          }
          invocations[instruction] = heap.constructorFor(
            layouts.pointers.initializer,
            layouts,
          );
          _operands[instruction] = [
            address,
            layouts.types.constant(FfiTypes.pointerRuntimeType),
          ];
          body.add(instruction);
          continue;
        }
        if (instruction case NativeCall(
          :final pointer,
          :final arguments,
          :final signature,
          :final isLeaf,
        )) {
          if (signature.result is NativeCompoundType ||
              signature.parameters.any((type) => type is NativeCompoundType)) {
            DirectCall? result;
            if (signature.result is NativeCompoundType) {
              final type = instruction.type as ClassType;
              final create = layouts.native!.owned(
                type,
                heap.allocatePayload(layouts.native!.buffer),
                copy: false,
              );
              result = DirectCall(create, [
                const Constant.integer(0),
                const Constant.nullValue(),
              ]);
              invocations[result] = create;
              body.add(result);
            }
            final target = layouts.nativeCalls.target(signature);
            final call = DirectCall(target, [
              _load(layouts.pointers.address, pointer, body),
              if (result != null)
                _load(
                  layouts.native!.view(result.type as ClassType).address,
                  result,
                  body,
                ),
              for (final value in arguments)
                if (FfiTypes.isPointer(value.type))
                  _load(layouts.pointers.address, value, body)
                else if (value.type case ClassType(:final nativeType?)
                    when nativeType is NativeCompoundType)
                  _load(
                    layouts.native!.view(value.type as ClassType).address,
                    value,
                    body,
                  )
                else
                  value,
            ]);
            invocations[call] = target;
            body.add(call);
            for (final value in [pointer, ...arguments]) {
              body.add(KeepAlive(value));
            }
            if (FfiTypes.isPointer(instruction.type)) {
              invocations[instruction] = heap.constructorFor(
                layouts.pointers.initializer,
                layouts,
              );
              _operands[instruction] = [
                call,
                layouts.types.constant(FfiTypes.pointerRuntimeType),
              ];
            } else {
              aliases.add(instruction);
              _operands[instruction] = [result ?? call];
            }
            body.add(instruction);
            continue;
          }
          final raw = NativeInvocation(
            _load(layouts.pointers.address, pointer, body),
            [
              for (final value in arguments)
                if (FfiTypes.isPointer(value.type))
                  _load(layouts.pointers.address, value, body)
                else
                  value,
            ],
            signature,
            isLeaf: isLeaf,
          );
          body.add(raw);
          if (FfiTypes.isPointer(instruction.type)) {
            invocations[instruction] = heap.constructorFor(
              layouts.pointers.initializer,
              layouts,
            );
            _operands[instruction] = [
              raw,
              layouts.types.constant(FfiTypes.pointerRuntimeType),
            ];
          } else {
            aliases.add(instruction);
            _operands[instruction] = [raw];
          }
          body.add(instruction);
          continue;
        }
        if (instruction case MakeClosure(:final target, :final inputs)) {
          final shape = layouts.closures.closures[target]!;
          final arguments = <Value>[Constant.integer(shape.tag)];
          for (final (i, value) in inputs.indexed) {
            arguments.add(convert(value, shape.captures[i].type, body));
          }
          for (final parameter in shape.parameters) {
            arguments.add(_reify(parameter, body));
          }
          arguments.add(_reify(target.signature, body));
          invocations[instruction] = heap.constructorFor(
            shape.initializer!,
            layouts,
          );
          _operands[instruction] = arguments;
          body.add(instruction);
          continue;
        }
        if (instruction.type is CellType &&
                instruction is NewCell &&
                !stackCells.contains(instruction) ||
            instruction is CopyCell) {
          final type = instruction.type as CellType;
          final shape = layouts.closures.cell(type);
          Value initial;
          if (instruction is CopyCell) {
            initial = _load(shape.value, instruction.cell, body);
          } else if ((instruction as NewCell).initial case final value?) {
            initial = convert(value, shape.value.type, body);
          } else {
            initial = switch (shape.value.type) {
              ValueType.integer => const Constant.integer(0),
              ValueType.floating => const Constant.floating(0),
              ValueType.boolean => const Constant.boolean(false),
              _ => const Constant.nullValue(),
            };
            if (initial is Instruction) body.add(initial);
          }
          invocations[instruction] = heap.constructorFor(
            shape.initializer,
            layouts,
          );
          _operands[instruction] = [
            initial,
            if (shape.lazy case final lazy?) ...[
              instruction is CopyCell
                  ? _load(lazy.bound, instruction.cell, body)
                  : Constant.boolean((instruction as NewCell).initial != null),
              instruction is CopyCell
                  ? _load(lazy.thunk, instruction.cell, body)
                  : (instruction as NewCell).initializer ??
                        const Constant.nullValue(),
            ],
            layouts.types.constant(shape.type),
          ];
          body.add(instruction);
          continue;
        }
        if (instruction case ReadCell(:final cell) || WriteCell(:final cell)
            when !stackCells.contains(cell) &&
                !(cell.type as CellType).isLate) {
          final shape = layouts.closures.cell(cell.type as CellType);
          if (instruction is ReadCell) {
            final read = _load(shape.value, cell, body);
            aliases.add(instruction);
            _operands[instruction] = [read];
          } else {
            final value = convert(
              (instruction as WriteCell).value,
              shape.value.type,
              body,
            );
            body.add(StorageWrite(shape.value, cell, value));
            aliases.add(instruction);
            _operands[instruction] = [];
          }
          body.add(instruction);
          continue;
        }
        if (instruction case Equals(:final left)
            when left.type != .nullType &&
                ValueType.function.nullable.accepts(left.type)) {
          block = valueOperations.equalFunction(instruction, block);
          body = instructions[block]!;
          body.add(instruction);
          aliases.add(instruction);
          _operands[instruction] = block.parameters;
          continue;
        }
        if (instruction case ObjectHashCode(:final operand, direct: false)
            when operand.type == .nullType ||
                layouts.isBoxable(operand.type) ||
                FfiTypes.isPointer(operand.type)) {
          block = valueOperations.hashScalar(
            FfiTypes.isPointer(operand.type)
                ? _load(layouts.pointers.address, operand, body)
                : operand,
            block,
          );
          body = instructions[block]!;
          body.add(instruction);
          aliases.add(instruction);
          _operands[instruction] = block.parameters;
          continue;
        }
        if (instruction case Equals(:final left, :final right, :final negated)
            when FfiTypes.isPointer(left.type) &&
                FfiTypes.isPointer(right.type)) {
          final equal = Equals(
            _load(layouts.pointers.address, left, body),
            _load(layouts.pointers.address, right, body),
            negated: negated,
          );
          body.addAll([equal, instruction]);
          aliases.add(instruction);
          _operands[instruction] = [equal];
          continue;
        }
        if (instruction case Equals(:final left, :final right)
            when (layouts.isBoxable(left.type) ||
                    FfiTypes.isPointer(left.type)) &&
                right.type != .nullType &&
                layouts.representation(right.type) == .reference) {
          invocations[instruction] = members.builtin(left.type, hash: false);
          body.add(instruction);
          continue;
        }
        final invocation = switch (instruction) {
          InstantiateFunction(:final function, :final typeArguments) => (
            null,
            function,
            typeArguments,
          ),
          BindMethod(:final method, :final receiver) => (
            method,
            receiver,
            const <ValueType>[],
          ),
          FunctionCall(:final function, :final typeArguments) => (
            null,
            function,
            typeArguments,
          ),
          InstanceCall(:final member, :final receiver, :final typeArguments) =>
            (member, receiver, typeArguments),
          DirectCall(:final target, :final inputs, :final typeArguments)
              when target.kind.isVirtual &&
                  target.owner!.typeParameters.isNotEmpty =>
            (target, inputs.first, typeArguments),
          ObjectRuntimeType(:final operand, direct: false) ||
          ObjectHashCode(:final operand, direct: false)
              when operand.type != .nullType &&
                  layouts.representation(operand.type) == .reference =>
            (null, operand, const <ValueType>[]),
          Equals(:final left, :final right)
              when left is! TypeConstant &&
                  left is! ReifyType &&
                  !(left is ObjectRuntimeType && left.direct) &&
                  left.type != .nullType &&
                  right.type != .nullType &&
                  layouts.representation(left.type) == .reference =>
            (null, left, const <ValueType>[]),
          _ when instruction.implicitMember != null => (
            null,
            instruction.inputs.first,
            const <ValueType>[],
          ),
          _ => null,
        };
        if (invocation != null) {
          final (member, receiver, typeArguments) = invocation;
          final functionValue =
              instruction is FunctionCall || instruction is InstantiateFunction;
          final binding = instruction is BindMethod;
          final builtin =
              instruction is Equals ||
              instruction is ObjectRuntimeType ||
              instruction is ObjectHashCode;
          final virtual =
              instruction is! DirectCall &&
              !(instruction is BindMethod && instruction.direct);
          final targets = functionValue
              ? {
                  for (final closure in layouts.closures.targetsFor(
                    receiver.type as FunctionType,
                  ))
                    closure.type: (target: closure.target, closure: closure),
                }
              : {
                  for (final entry
                      in (virtual
                              ? members.targetsFor(
                                  receiver.unviewedType,
                                  member?.selector ??
                                      switch (instruction) {
                                        Equals() => (
                                          kind: .method,
                                          name: '==',
                                          privateScope: null,
                                        ),
                                        _ =>
                                          instruction.implicitMember!.selector,
                                      },
                                  hasBuiltin: builtin,
                                )
                              : {member!.owner!: member})
                          .entries)
                    if (!virtual ||
                        layouts.typeTest(receiver.type, entry.key) !=
                            .constantFalse)
                      entry.key: (target: entry.value, closure: null),
                };
          final plainObject =
              receiver.type.nonNullable is ClassType &&
              ![
                ValueType.integer,
                ValueType.floating,
                ValueType.boolean,
                ValueType.string,
                ValueType.typeType,
                TypeValues.type,
                ValueType.function,
                FfiTypes.pointerRuntimeType,
              ].any(receiver.type.accepts);
          if (targets.isEmpty &&
              plainObject &&
              (instruction is Equals || instruction is ObjectHashCode)) {
            final Value result = switch (instruction) {
              Equals(:final left, :final right, :final negated) =>
                layouts.representation(right.type) == .reference
                    ? ReferenceEquality(left, right, negated: negated)
                    : Constant.boolean(negated),
              ObjectHashCode(:final operand) => ObjectHashCode(
                operand,
                direct: true,
              ),
              _ => throw StateError('Expected object equality or hashing.'),
            };
            if (result is! Constant) body.add(result);
            aliases.add(instruction);
            _operands[instruction] = [result];
            body.add(instruction);
            continue;
          }
          if (instruction is Equals) {
            targets[TypeValues.type] = (
              target: layouts.types.equality,
              closure: null,
            );
          } else if (instruction is ObjectHashCode) {
            targets[TypeValues.type] = (
              target: layouts.types.hash,
              closure: null,
            );
          } else if (instruction is ObjectRuntimeType && targets.isEmpty) {
            runtimeType(instruction, body);
            body.add(instruction);
            continue;
          }
          if (instruction is Equals || instruction is ObjectHashCode) {
            if (!ValueType.function.accepts(receiver.type) &&
                layouts.typeTest(receiver.type, ValueType.string) !=
                    .constantFalse) {
              targets[ValueType.string] = (
                target: instruction is Equals
                    ? layouts.strings.equality
                    : layouts.strings.hash,
                closure: null,
              );
            }
            for (final type in [
              ValueType.integer,
              ValueType.floating,
              ValueType.boolean,
              FfiTypes.pointerRuntimeType,
            ]) {
              targets[type] = (
                target: members.builtin(
                  type,
                  hash: instruction is ObjectHashCode,
                ),
                closure: null,
              );
            }
          }
          final actual = layouts.types.runtimeTypeOf(receiver, body);
          final shape = targets.isEmpty
              ? null
              : functionValue
              ? _load(layouts.closures.tag, receiver, body)
              : virtual
              ? LoadField(TypeValues.shape, actual)
              : null;
          if (shape != null && !functionValue) body.add(shape);
          final types = [for (final type in typeArguments) _reify(type, body)];
          final result = instruction.type;
          final join = result == .never ? null : Block([result]);
          final missing = Block();
          blocks.add(missing);
          switch (instruction) {
            case ObjectRuntimeType():
              instructions[missing] = [];
              ends[missing] = Jump(join!, [actual]);
            case Equals(:final left, :final right, :final negated):
              final identity = layouts.representation(right.type) == .reference
                  ? ReferenceEquality(left, right, negated: negated)
                  : Constant.boolean(negated);
              instructions[missing] = [
                if (identity is ReferenceEquality) identity,
              ];
              ends[missing] = Jump(join!, [identity]);
            case ObjectHashCode(:final operand):
              final hash = ObjectHashCode(operand, direct: true);
              instructions[missing] = [hash];
              ends[missing] = Jump(join!, [hash]);
            default:
              final invalid = DirectCall(heap.invalid, []);
              instructions[missing] = [invalid];
              ends[missing] = Unreachable(invalid);
          }
          var builtinEntry = missing;
          if (instruction is Equals || instruction is ObjectHashCode) {
            builtinEntry = addBlock();
            final selected = addBlock();
            final kind = LoadField(TypeValues.kind, actual);
            final test = Equals(
              kind,
              Constant.integer(TypeKind.function.index),
            );
            instructions[builtinEntry]!.addAll([kind, test]);
            ends[builtinEntry] = Branch(test, Jump(selected), Jump(missing));
            final result = instruction is Equals
                ? valueOperations.equalFunction(instruction, selected)
                : valueOperations.hashFunction(receiver, selected);
            ends[result] = Jump(join!, result.parameters);
          }
          var next = block;
          if (builtin) {
            final nominal = Block();
            blocks.add(nominal);
            instructions[nominal] = [];
            final kind = LoadField(TypeValues.kind, actual);
            final test = Equals(kind, Constant.integer(TypeKind.nominal.index));
            body.addAll([kind, test]);
            ends[next] = Branch(test, Jump(nominal), Jump(builtinEntry));
            next = nominal;
            if (instruction case Equals(:final right)
                when right.type.accepts(.nullType)) {
              final nonNull = Block();
              blocks.add(nonNull);
              instructions[nonNull] = [];
              final test = Equals(right, const Constant.nullValue());
              instructions[next]!.add(test);
              ends[next] = Branch(test, Jump(missing), Jump(nonNull));
              next = nonNull;
            }
          }
          candidates:
          for (final MapEntry(key: type, value: (:target, :closure))
              in targets.entries) {
            var current = next;
            if (shape != null) {
              final selected = Block(), otherwise = Block();
              blocks.addAll([selected, otherwise]);
              final test = Equals(
                shape,
                Constant.integer(
                  closure != null
                      ? closure.tag
                      : layouts.types.id(type.declaration),
                ),
              );
              instructions[next]!.add(test);
              ends[next] = Branch(test, Jump(selected), Jump(otherwise));
              instructions[otherwise] = [];
              instructions[selected] = [];
              next = otherwise;
              current = selected;
            }
            void append(Value operation) {
              current = appendTo(current, operation, handler);
            }

            final setup = <Value>[];
            final specialization = closure?.instantiation;
            final storage = specialization?.generic ?? closure;
            final carrier = specialization == null
                ? receiver
                : _load(specialization.origin, receiver, setup);
            var functionTypes = types;
            if (specialization != null) {
              Value arguments = _load(
                specialization.arguments,
                receiver,
                setup,
              );
              functionTypes = [];
              for (final _ in storage!.signature.typeParameters) {
                final node = NullCheck(arguments);
                final value = LoadField(TypeValues.head, node);
                final next = LoadField(TypeValues.tail, node);
                setup.addAll([node, value, next]);
                arguments = next;
                functionTypes.add(value);
              }
            }
            final parameters =
                storage?.parameters ??
                target.owner?.typeParameters ??
                const <TypeParameterType>[];
            final classTypes = closure != null
                ? [
                    for (final field in storage!.environment)
                      _load(field, carrier, setup),
                  ]
                : parameters.isEmpty
                ? <Value>[]
                : _ownerArguments(actual, target.owner!, setup);
            setup.forEach(append);
            final environment = {
              for (final (i, parameter) in parameters.indexed)
                parameter: classTypes[i],
              if (!binding)
                for (final (i, parameter)
                    in (storage?.signature.typeParameters ??
                            target.typeParameters)
                        .indexed)
                  parameter: functionTypes[i],
            };
            Value reify(ValueType type) {
              if (type.freeTypeParameters.isEmpty) {
                return layouts.types.constant(type);
              }
              if (type is TypeParameterType) return environment[type]!;
              final template = layouts.types.instantiate(type);
              final call = DirectCall(template.target, [
                for (final parameter in template.parameters)
                  environment[parameter]!,
              ]);
              append(call);
              return call;
            }

            if (instruction case BindMethod(
              :final method,
              :final direct,
              :final ownerType,
            )) {
              final shape = layouts.closures.methods[target]!;
              final actualType = reify(shape.signature);
              final bound = BindMethod(
                method,
                receiver,
                direct: direct,
                ownerType: ownerType,
              );
              invocations[bound] = heap.constructorFor(
                shape.initializer!,
                layouts,
              );
              final captures = <Value>[];
              final captured = convert(
                receiver,
                shape.captures.single.type,
                captures,
              );
              captures.forEach(append);
              _operands[bound] = [
                Constant.integer(shape.tag),
                captured,
                ...classTypes,
                actualType,
              ];
              append(bound);
              final widened = TypeView(bound, .object);
              append(widened);
              final check = TypeCast(widened, instruction.type);
              final checkTypes = <Value>[];
              _operands[check] = [
                widened,
                for (final parameter
                    in casts.targetFor(check, layouts).parameters)
                  _reify(parameter, checkTypes),
              ];
              checkTypes.forEach(append);
              append(check);
              ends[current] = Jump(join!, [check]);
              continue;
            }

            final invocationTypes = closure == null
                ? types
                : [for (final type in closure.typeArguments) reify(type)];
            for (final (i, parameter) in target.typeParameters.indexed) {
              environment[parameter] = invocationTypes[i];
            }
            final bounds =
                storage?.signature.typeParameters ?? target.typeParameters;
            if (specialization == null) {
              for (final (i, parameter) in bounds.indexed) {
                append(
                  DirectCall(casts.bounds(layouts), [
                    storage == null ? invocationTypes[i] : functionTypes[i],
                    reify(parameter.bound),
                  ]),
                );
              }
            }
            if (instruction is InstantiateFunction) {
              final shape = layouts.closures.specializations[closure]!;
              final actualType = reify(shape.signature);
              Value arguments = const Constant.nullValue();
              for (final type in types.reversed) {
                final node = layouts.types.cons(type, arguments);
                invocations[node] = heap.constructorFor(
                  node.initializer,
                  layouts,
                );
                _operands[node] = [
                  ...node.inputs,
                  layouts.types.constant(TypeValues.list),
                ];
                append(node);
                arguments = node;
              }
              final applied = InstantiateFunction(receiver, typeArguments);
              invocations[applied] = heap.constructorFor(
                shape.initializer!,
                layouts,
              );
              _operands[applied] = [
                Constant.integer(shape.tag),
                receiver,
                arguments,
                actualType,
              ];
              append(applied);
              ends[current] = Jump(join!, [applied]);
              continue;
            }
            final inputs = switch (instruction) {
              InstanceCall(:final positional, :final named) ||
              FunctionCall(
                :final positional,
                :final named,
              ) => target.signature.bind<Value>(
                positional,
                named,
                (i) =>
                    (closure?.defaults ??
                    members.program.implementationOf(target)!.defaults)[i]!,
              ),
              DirectCall(:final inputs) => inputs.skip(1),
              ObjectRuntimeType() || ObjectHashCode() => const <Value>[],
              Equals(:final right) => [right],
              _ when instruction.implicitMember != null =>
                target.signature.bind<Value>(
                  instruction.inputs.skip(1).toList(),
                  const {},
                  (i) => members.program.implementationOf(target)!.defaults[i]!,
                ),
              _ => throw StateError('Expected a member call.'),
            };
            final arguments = <Value>[
              if (!functionValue || target.kind == .closure) carrier,
            ];
            if (closure != null) {
              final captures = <Value>[];
              for (final field in storage!.captures) {
                arguments.add(_load(field, carrier, captures));
              }
              captures.forEach(append);
            }
            for (final (i, value) in inputs.indexed) {
              final destination =
                  target.signature.parameters[i +
                      (target.kind.hasReceiver || functionValue ? 0 : 1)];
              final pending = <Value>[];
              if (destination.freeTypeParameters.isEmpty &&
                  destination.accepts(value.type)) {
                arguments.add(convert(value, destination, pending));
                pending.forEach(append);
                continue;
              }
              final widened = layouts.representation(value.type) == .address
                  ? value
                  : TypeView(
                      convert(value, .object.nullable, pending),
                      .object.nullable,
                    );
              pending.forEach(append);
              if (widened is TypeView) append(widened);
              final check = TypeCast(widened, destination);
              final signature = casts.targetFor(check, layouts);
              _operands[check] = [
                widened,
                for (final parameter in signature.parameters)
                  environment[parameter]!,
              ];
              if (destination == .never) {
                instructions[current]!.add(check);
                ends[current] = handler == null
                    ? Unreachable(check)
                    : Invoke(check, onReturn: null, onThrow: edge(handler));
                continue candidates;
              }
              append(check);
              arguments.add(check);
            }
            final call = switch (instruction) {
              FunctionCall(:final function, :final positional, :final named) =>
                FunctionCall(function, positional, named, typeArguments),
              InstanceCall(:final positional, :final named, :final ownerType) =>
                InstanceCall(
                  member!,
                  receiver,
                  positional,
                  named,
                  ownerType,
                  typeArguments,
                ),
              DirectCall(:final inputs, :final ownerType) => DirectCall(
                member!,
                inputs,
                ownerType: ownerType,
                typeArguments: typeArguments,
              ),
              ObjectRuntimeType(:final operand) => ObjectRuntimeType(operand),
              ObjectHashCode(:final operand) => ObjectHashCode(operand),
              Equals(:final left, :final right, :final negated) => Equals(
                left,
                right,
                negated: negated,
              ),
              CollectionLength(:final collection) => CollectionLength(
                collection,
              ),
              GetIterator(:final iterable) => GetIterator(iterable),
              IteratorMoveNext(:final iterator) => IteratorMoveNext(iterator),
              IteratorCurrent(:final iterator) => IteratorCurrent(iterator),
              CollectionGet(:final collection, :final key) => CollectionGet(
                collection,
                key,
              ),
              CollectionAdd(:final collection, :final value) => CollectionAdd(
                collection,
                value,
              ),
              CollectionSpread(
                :final collection,
                :final source,
                :final isMethodCall,
              ) =>
                CollectionSpread(
                  collection,
                  source,
                  isMethodCall: isMethodCall,
                ),
              ListSet(:final collection, :final key, :final value) => ListSet(
                collection,
                key,
                value,
              ),
              MapPut(:final map, :final key, :final value) => MapPut(
                map,
                key,
                value,
              ),
              MapContainsKey(:final map, :final key) => MapContainsKey(
                map,
                key,
              ),
              MapEntries(:final map) => MapEntries(map),
              ListSublist(:final list, :final start, :final end) => ListSublist(
                list,
                start,
                end,
              ),
              _ => throw StateError('Expected a member call.'),
            };
            invocations[call] = target;
            final entryTypes = layouts.entryTypes(target);
            final converted = <Value>[];
            _operands[call] = [
              for (final (i, value) in arguments.indexed)
                convert(value, entryTypes[i], converted),
              ...invocationTypes,
            ];
            converted.forEach(append);
            if (join == null || target.returnType == .never) {
              instructions[current]!.add(call);
              final returned = join == null ? null : Jump(missing);
              ends[current] = handler == null
                  ? returned ?? Unreachable(call)
                  : Invoke(call, onReturn: returned, onThrow: edge(handler));
              continue;
            }
            if (layouts.representation(result) == .reference &&
                layouts.isBoxable(target.returnType)) {
              _resultTypes[call] = target.returnType;
            }
            append(call);
            final conversions = <Value>[];
            var value = convert(call, result, conversions);
            if (member?.requiresResultCheck ?? target.requiresResultCheck) {
              value = checkResult(value, result, conversions);
            }
            conversions.forEach(append);
            ends[current] = Jump(join, [value]);
          }
          if (virtual) ends[next] = Jump(missing);
          if (join == null) continue sourceBlocks;
          blocks.add(join);
          block = join;
          body = instructions[block] = [instruction];
          aliases.add(instruction);
          _operands[instruction] = join.parameters;
          continue;
        }
        final lateCell = switch (instruction) {
          ReadCell(:final cell) ||
          WriteCell(:final cell) when (cell.type as CellType).isLate => cell,
          _ => null,
        };
        final lateField = switch (instruction) {
          LoadField(:final field) ||
          StoreField(:final field) when field.isLate => field,
          _ => null,
        };
        if (lateField != null || lateCell != null) {
          final shape = lateCell == null
              ? null
              : layouts.closures.cell(lateCell.type as CellType);
          final field = lateField ?? shape!.value;
          final receiver = switch (instruction) {
            LoadField(:final receiver) ||
            StoreField(:final receiver) => receiver,
            _ => lateCell!,
          };
          final (valueField, boundField) = shape == null
              ? layouts.instances.slots(field)
              : (shape.value, shape.lazy!.bound);
          final isFinal = lateCell == null
              ? field.isFinal
              : (lateCell.type as CellType).isFinal;
          final isRead = instruction is LoadField || instruction is ReadCell;
          Block fresh() {
            final next = Block();
            blocks.add(next);
            instructions[next] = [];
            return next;
          }

          void enter(Block next) {
            block = next;
            body = instructions[next]!;
          }

          void append(Value operation) =>
              enter(appendTo(block, operation, handler));

          void fail(Block failed, String message) {
            final call = DirectCall(layouts.instances.failure!.target, [
              Constant.string(message),
            ]);
            instructions[failed]!.add(call);
            ends[failed] = handler == null
                ? Unreachable(call)
                : Invoke(call, onReturn: null, onThrow: edge(handler));
          }

          void requireUnbound(String message) {
            final commit = fresh(), failed = fresh();
            final flag = StorageRead(boundField, receiver);
            append(flag);
            ends[block] = Branch(flag, Jump(failed), Jump(commit));
            fail(failed, message);
            enter(commit);
          }

          void bind(Value value) {
            append(StorageWrite(valueField, receiver, value));
            append(
              StorageWrite(boundField, receiver, const Constant.boolean(true)),
            );
            if (shape != null) {
              append(
                StorageWrite(
                  shape.lazy!.thunk,
                  receiver,
                  const Constant.nullValue(),
                ),
              );
            }
          }

          final join = Block(
            isRead
                ? [
                    field.requiresReadCheck
                        ? .object.nullable
                        : shape?.value.type ?? instruction.type,
                  ]
                : [],
          );
          blocks.add(join);
          if (instruction
              case StoreField(:final value) || WriteCell(:final value)) {
            final conversions = <Value>[];
            var stored = convert(value, field.type, conversions);
            conversions.forEach(append);
            if (field.type.freeTypeParameters.isNotEmpty) {
              final widened = TypeView(stored, .object.nullable);
              append(widened);
              final pending = <Value>[];
              final arguments = _ownerArguments(
                layouts.types.runtimeTypeOf(receiver, pending),
                field.owner,
                pending,
              );
              pending.forEach(append);
              final check = TypeCast(widened, field.type);
              final signature = casts.targetFor(check, layouts);
              _operands[check] = [
                widened,
                for (final parameter in signature.parameters)
                  arguments[field.owner.typeParameters.indexOf(parameter)],
              ];
              append(check);
              stored = check;
            }
            if (isFinal) {
              requireUnbound(
                "Field '${field.name}' has already been initialized.",
              );
            }
            bind(stored);
            ends[block] = Jump(join);
          } else {
            final bound = fresh(), initialize = fresh();
            final flag = StorageRead(boundField, receiver);
            append(flag);
            ends[block] = Branch(flag, Jump(bound), Jump(initialize));
            final read = shape == null
                ? LoadField(valueField, receiver)
                : StorageRead(valueField, receiver);
            instructions[bound]!.add(read);
            ends[bound] = Jump(join, [read]);
            enter(initialize);
            if (shape?.lazy?.initialize ?? field.initializer
                case final initializer?) {
              final value = shape == null
                  ? DirectCall(initializer, [
                      receiver,
                    ], ownerType: CoreTypes.view(receiver.type, field.owner))
                  : DirectCall(initializer, [
                      _load(shape.lazy!.thunk, receiver, body),
                    ]);
              append(value);
              if (isFinal) {
                requireUnbound(
                  "Field '${field.name}' has been assigned during initialization.",
                );
              }
              final conversions = <Value>[];
              final stored = convert(value, field.type, conversions);
              conversions.forEach(append);
              bind(stored);
              ends[block] = Jump(join, [value]);
            } else {
              fail(block, "Field '${field.name}' has not been initialized.");
            }
          }
          block = join;
          body = instructions[block] = [];
          final pending = <Value>[];
          final values = isRead && field.requiresReadCheck
              ? [checkResult(join.parameters.single, instruction.type, pending)]
              : join.parameters;
          pending.forEach(append);
          body.add(instruction);
          aliases.add(instruction);
          _operands[instruction] = values;
          continue;
        }
        if (instruction
            case StoreField(:final field, :final receiver, :final value)
            when !field.isLate && field.type.freeTypeParameters.isNotEmpty) {
          final widened = TypeView(
            convert(value, .object.nullable, body),
            .object.nullable,
          );
          body.add(widened);
          final arguments = _ownerArguments(
            layouts.types.runtimeTypeOf(receiver, body),
            field.owner,
            body,
          );
          final check = TypeCast(widened, field.type);
          final signature = casts.targetFor(check, layouts);
          _operands[check] = [
            widened,
            for (final parameter in signature.parameters)
              arguments[field.owner.typeParameters.indexOf(parameter)],
          ];
          _operands[instruction] = [receiver, check];
          body.add(check);
          if (sourceBlock.end
              case Invoke(:final operation, :final onReturn, :final onThrow)
              when operation == instruction) {
            final stored = Block();
            blocks.add(stored);
            instructions[stored] = [instruction];
            ends[stored] = edge(onReturn!);
            ends[block] = Invoke(
              check,
              onReturn: Jump(stored),
              onThrow: edge(onThrow),
            );
          } else {
            body.add(instruction);
          }
          continue;
        }
        if (instruction case LoadField(:final field, :final receiver)
            when field.requiresReadCheck) {
          final pending = <Value>[];
          final value = checkResult(
            _load(field, receiver, pending),
            instruction.type,
            pending,
          );
          for (final operation in pending) {
            block = appendTo(block, operation, handler);
          }
          body = instructions[block]!;
          body.add(instruction);
          aliases.add(instruction);
          _operands[instruction] = [value];
          continue;
        }
        if (instruction case ReifyType(:final template)) {
          _operands[instruction] = [_reify(template, body)];
        }
        if (instruction is ObjectRuntimeType) runtimeType(instruction, body);
        if (instruction is TypeTest) {
          typeTest(instruction, body);
          continue;
        }
        if (instruction
            case TypeCast(:final operand) || NullCheck(:final operand)) {
          if (nonNull.contains(operand) &&
              instruction.type.accepts(operand.type.nonNullable)) {
            aliases.add(instruction);
            _operands[instruction] = [operand];
            body.add(instruction);
            continue;
          }
          final check = casts.targetFor(instruction, layouts);
          _operands[instruction] = [
            operand,
            for (final parameter in check.parameters) _reify(parameter, body),
          ];
        }
        if (instruction case TypeView(:final operand, :final type)
            when needsBox(operand, type)) {
          boxes[instruction] = operand;
        }
        final destinations = switch (instruction) {
          DirectCall(:final target) => layouts.entryTypes(target),
          Construct(:final initializer) => [
            ...initializer.signature.parameters,
            TypeValues.type,
          ],
          NewCell(:final initial, type: final CellType type)
              when initial != null =>
            [type.content],
          WriteCell(:final cell) => [
            cell.type,
            (cell.type as CellType).content,
          ],
          StoreGlobal(:final global) => [global.type],
          StoreObjectReference(:final object) => <ValueType>[
            object.type,
            .integer,
            .object.nullable,
          ],
          StoreField(:final receiver, :final field) => [
            receiver.type,
            field.type,
          ],
          _ => null,
        };
        if (destinations != null) {
          final inputs = [
            ...instruction.inputs,
            if (instruction case DirectCall(:final target, :final ownerType)
                when target.kind == .factory &&
                    target.owner!.typeParameters.isNotEmpty)
              _reify(ownerType ?? target.owner!, body),
            if (instruction case DirectCall(:final typeArguments))
              for (final type in typeArguments) _reify(type, body),
            if (instruction case Construct(:final instantiatedType))
              _reify(instantiatedType, body),
          ];
          var changed = inputs.length != instruction.inputs.length;
          for (final (i, input) in inputs.indexed) {
            final value = convert(input, destinations[i], body);
            changed |= value != input;
            inputs[i] = value;
          }
          if (changed) _operands[instruction] = inputs;
        }
        body.add(instruction);
      }
      ends[block] ??= switch (sourceBlock.end) {
        Return(:final value) => Return(
          convert(
            value ?? const Constant.nullValue(),
            function.target.returnType,
            body,
          ),
        ),
        final Jump jump => edge(jump),
        Branch(:final condition, :final ifTrue, :final ifFalse) => Branch(
          condition,
          edge(ifTrue),
          edge(ifFalse),
        ),
        Invoke(:final operation, :final onReturn)
            when aliases.contains(operation) =>
          edge(onReturn!),
        Invoke(:final operation, :final onReturn, :final onThrow) => Invoke(
          operation,
          onReturn: onReturn == null ? null : edge(onReturn),
          onThrow: edge(onThrow),
        ),
        Throw(:final exception, :final stackTrace, :final onThrow) => Throw(
          convert(exception, .object, body),
          stackTrace: traceFor(stackTrace, body),
          onThrow: onThrow == null ? null : edge(onThrow),
        ),
        ExhaustivenessFailure(:final onThrow) => ExhaustivenessFailure(
          onThrow == null ? null : edge(onThrow),
        ),
        final end => end,
      };
      if (block != sourceBlock) block.finish(sourceBlock.end);
    }
    instructions[function.entry]!.insertAll(0, _prologue);
  }
}
