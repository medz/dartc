import 'dart:ffi' show Int64, Uint8;

import 'package:dartc/interop.dart';
import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart' show ProgramFlowFacts;
import 'package:dartc/runtime/contracts.dart' show TypeKind;

import 'program_layout.dart';
import 'checked_casts.dart';
import 'member_calls.dart';
import 'heap_plan.dart';
import 'storage_access.dart';
import 'reference_equality.dart';
import 'selected_function.dart';
import 'value_operations.dart';
import 'native_invocation.dart';
import 'indirect_invocation.dart';
import 'non_null_values.dart';
import 'record_storage.dart';
import 'value_carrier.dart';

/// Places allocating representation changes before register and root analysis.
final class FunctionRepresentation(
  final IrFunction function,
  ProgramLayout layouts,
  CheckedCasts casts,
  MemberCalls members,
  HeapPlan heap,
) extends SelectedFunction {
  final _prologue = <Value>[];
  bool get _factoryEnvironment =>
      function.target.kind == .factory &&
      function.target.owner!.typeParameters.isNotEmpty;

  final _classArguments = <int, Value>{};
  final _typeArguments = <TypeParameterType, Value>{};
  Value? _ownerType;

  Value _typeInput() {
    final value = Block([TypeMetadata.type]).parameters.single;
    entryParameters.add(value);
    return value;
  }

  Value _ownerArgument(
    Value actual,
    ClassType owner,
    int index,
    List<Value> into,
  ) {
    final argument = DirectCall(layouts.relations.argumentOf(owner, index), [
      actual,
    ]);
    final checked = NullCheck(argument);
    into.addAll([argument, checked]);
    return checked;
  }

  Value _reify(ValueType type, List<Value> into) {
    type = type.reify();
    if (_factoryEnvironment && type == function.target.owner) {
      layouts.typeEnvironment.requireOwner(function.target);
      return _ownerType ??= _typeInput();
    }
    if (type is TypeParameterType) {
      for (final binding in function.typeBindings) {
        if (binding.parameter == type) return binding.value;
      }
      final index = function.target.typeParameters.indexOf(type);
      if (index >= 0) {
        layouts.typeEnvironment.requireParameter(function.target, index);
        return _typeArguments.putIfAbsent(type, _typeInput);
      }
      final owner = function.target.owner;
      if (owner != null &&
          (function.target.kind.hasReceiver || _factoryEnvironment)) {
        final index = owner.typeParameters.indexOf(type);
        if (index >= 0) {
          return _classArguments.putIfAbsent(
            index,
            () => _ownerArgument(
              _factoryEnvironment
                  ? () {
                      layouts.typeEnvironment.requireOwner(function.target);
                      return _ownerType ??= _typeInput();
                    }()
                  : layouts.types.runtimeTypeOf(
                      function.entry.parameters.first,
                      _prologue,
                    ),
              owner,
              index,
              _prologue,
            ),
          );
        }
      }
      if (function.target.kind == .closure &&
          function.target.capturedTypeParameters.contains(type)) {
        layouts.typeEnvironment.requireLexicalParameter(function.target, type);
        return _typeArguments.putIfAbsent(type, _typeInput);
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

  StorageRead _load(InstanceField field, Value receiver, List<Value> into) {
    final load = StorageRead(field, receiver);
    into.add(load);
    return load;
  }

  this
    : super(
        function.target,
        layouts,
        function.entry,
        sourceFunction: function,
        parameters: [
          ...function.entry.parameters,
          ...Block(
            layouts
                .entryTypes(function.target)
                .skip(function.entry.parameters.length),
          ).parameters,
        ],
      ) {
    var typeIndex = function.entry.parameters.length;
    if (layouts.typeEnvironment.ownerOf(function.target)) {
      _ownerType = entryParameters[typeIndex++];
    }
    for (final index in layouts.typeEnvironment.parametersOf(function.target)) {
      _typeArguments[function.target.typeParameters[index]] =
          entryParameters[typeIndex++];
    }
    for (final parameter in layouts.typeEnvironment.lexicalParametersOf(
      function.target,
    )) {
      _typeArguments[parameter] = entryParameters[typeIndex++];
    }
    if (function.bodyKind != .synchronous) {
      throw ArgumentError(
        'Suspensions must be normalized before representation.',
      );
    }
    final nonNull = NonNullValues(function);
    final valueOperations = ValueOperations(this, layouts, heap.invalid);
    members.cellInitialization.check(function);
    final operations = {
      for (final block in function.blocks) ...[
        ...block.instructions,
        if (block.end case Invoke(:final operation)) operation,
      ],
    };
    final addressOnly = layouts.pointerRepresentation.addressesIn(function);
    for (final block in function.blocks) {
      for (final parameter in block.parameters) {
        if (addressOnly.contains(parameter)) resultShapes[parameter] = ExecutionShape.word;
      }
    }
    for (final operation in operations) {
      if (addressOnly.contains(operation)) resultShapes[operation] = ExecutionShape.word;
    }
    Value pointerAddress(Value pointer, List<Value> into) {
      if (typeOf(pointer) != .integer) {
        return _load(layouts.pointers.address, pointer, into);
      }
      final address = PointerAddress(pointer);
      aliases.add(address);
      operands[address] = [pointer];
      into.add(address);
      return address;
    }

    Value transfer(Value value, ExecutionShape destination, List<Value> into) {
      if (destination == ExecutionShape.word && FfiTypes.isPointer(value.type)) {
        return pointerAddress(value, into);
      }
      if (shapeOf(value) != destination &&
          value is! Constant && value.type is! CellType) {
        throw StateError('Representation conversion must be lowered in IR: '
            '${value.runtimeType} ${value.type.dartName}.');
      }
      return value;
    }

    Value convert(Value value, ValueType type, List<Value> into) =>
        transfer(value, ExecutionShapes.forType(type), into);

    Value checkResult(Value value, ValueType type, List<Value> into) {
      final raw = TypeView(
        value,
        layouts.isBoxable(value.type)
            ? valueCarrier(value.type)
            : ValueType.object.nullable,
      );
      final check = TypeCast(raw, type);
      into.add(raw);
      final signature = casts.targetFor(check);
      operands[check] = [
        raw,
        for (final parameter in signature.parameters) _reify(parameter, into),
      ];
      into.add(check);
      return check;
    }

    TypeCast checkField(
      InstanceField field,
      Value receiver,
      Value value,
      List<Value> into,
    ) {
      final scalar = layouts.isBoxable(value.type);
      final source = TypeView(
        scalar ? value : convert(value, .object.nullable, into),
        scalar ? valueCarrier(value.type) : ValueType.object.nullable,
      );
      into.add(source);
      final check = TypeCast(source, field.type);
      final signature = casts.targetFor(check);
      final actual = signature.parameters.isEmpty
          ? null
          : layouts.types.runtimeTypeOf(receiver, into);
      operands[check] = [
        source,
        for (final parameter in signature.parameters)
          _ownerArgument(
            actual!,
            field.owner,
            field.owner.typeParameters.indexOf(parameter),
            into,
          ),
      ];
      into.add(check);
      return check;
    }

    void runtimeType(ObjectRuntimeType instruction, List<Value> into) {
      final source = valueCarrier(instruction.operand.type);
      if (source == .nullType || layouts.representation(source) != .reference) {
        operands[instruction] = [_reify(source, into)];
      }
    }

    Block typeTest(TypeTest instruction, Block block) {
      final kind = tests[instruction] = layouts.typeTest(
        instruction.operand.type,
        instruction.testedType,
      );
      if (kind == .subtype) {
        final tested = instruction.testedType.runtimeCheckType;
        if ((tested.nullableBase ?? tested)
            case FutureOrType(:final argument, :final futureType)
            when tested != tested.reify()) {
          final done = addBlock([.boolean]);
          Jump result(bool matches) =>
              Jump(done, [Constant.boolean(matches != instruction.negated)]);
          for (final alternative in [
            if (tested.nullableBase != null) ValueType.nullType,
            argument,
            futureType,
          ]) {
            final test = TypeTest(instruction.operand, alternative);
            block = typeTest(test, block);
            final next = addBlock();
            ends[block] = Branch(test, result(true), Jump(next));
            block = next;
          }
          ends[block] = result(false);
          aliases.add(instruction);
          operands[instruction] = done.parameters;
          instructions[done]!.add(instruction);
          return done;
        }
        final constraints = switch (tested.nullableBase ?? tested) {
          NonNullableTypeParameterType(:final parameter) => [
            parameter,
            ValueType.object,
          ],
          PromotedType(
            :final lexicalType,
            :final bound,
            :final isNonNullable,
          ) =>
            [lexicalType, bound, if (isNonNullable) ValueType.object],
          _ => null,
        };
        if (constraints != null) {
          // Promotion constrains a value; it does not introduce a runtime Type.
          final done = addBlock([.boolean]);
          Jump result(bool matches) =>
              Jump(done, [Constant.boolean(matches != instruction.negated)]);
          if (tested.nullableBase != null) {
            final test = TypeTest(instruction.operand, .nullType);
            block = typeTest(test, block);
            final next = addBlock();
            ends[block] = Branch(test, result(true), Jump(next));
            block = next;
          }
          for (final constraint in constraints) {
            final test = TypeTest(instruction.operand, constraint);
            block = typeTest(test, block);
            final next = addBlock();
            ends[block] = Branch(test, Jump(next), result(false));
            block = next;
          }
          ends[block] = result(true);
          aliases.add(instruction);
          operands[instruction] = done.parameters;
          instructions[done]!.add(instruction);
          return done;
        }
      }
      final into = instructions[block]!;
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
          operands[instruction] = [comparison];
          into.addAll([comparison, instruction]);
          return block;
        }
        operands[instruction] = [actual, _reify(instruction.testedType, into)];
      }
      into.add(instruction);
      return block;
    }

    final unwindConversions = <Value>{};
    final unwindEdges = <Jump>{
      for (final block in function.blocks)
        ...switch (block.end) {
          Invoke(:final onThrow) => [onThrow],
          Throw(:final onThrow) ||
          ExhaustivenessFailure(:final onThrow) => [?onThrow],
          _ => const <Jump>[],
        },
    };
    bool needsConversion(Value value, ValueType type) =>
        type == .integer &&
            FfiTypes.isPointer(value.type) &&
            typeOf(value) != .integer ||
        shapeOf(value) != ExecutionShapes.forType(type);

    Jump edge(Jump jump) {
      if (!jump.arguments.indexed.any(
        (item) =>
            needsConversion(item.$2, typeOf(jump.target.parameters[item.$1])),
      )) {
        return jump;
      }
      final inputs = [
        for (final (i, value) in jump.arguments.indexed)
          value is TestedValue &&
                  shapeOf(value) != shapeOf(jump.target.parameters[i])
              ? value.test.operand
              : value,
      ];
      final block = Block(inputs.map((v) => v.type));
      for (final (i, parameter) in block.parameters.indexed) {
        resultShapes[parameter] = shapeOf(inputs[i]);
      }
      blocks.add(block);
      final body = instructions[block] = <Value>[];
      final arguments = [
        for (final (i, value) in block.parameters.indexed)
          convert(value, typeOf(jump.target.parameters[i]), body),
      ];
      if (unwindEdges.contains(jump)) {
        unwindConversions.addAll(body);
      }
      // Retain the verified edge's type proof while assigning its physical operands.
      final transfer = Jump(jump.target, jump.arguments);
      edgeArguments[transfer] = arguments;
      ends[block] = transfer;
      block.finish(transfer);
      return Jump(block, inputs);
    }

    Block appendTo(Block block, Value operation, Jump? handler) {
      instructions[block]!.add(operation);
      final semantic = switch (operation) {
        final Instruction instruction => instruction,
        IndirectInvocation(:final origin) => origin,
        _ => null,
      };
      if (handler == null || semantic == null || !semantic.mayThrow) {
        return block;
      }
      final next = Block();
      blocks.add(next);
      instructions[next] = [];
      ends[block] = Invoke(
        semantic,
        onReturn: Jump(next),
        onThrow: edge(handler),
      );
      return next;
    }

    final handlers = <Value, Jump>{};
    (Block, int, int, Jump?, SourceLocation?)? operationOrigin;
    void finishOperation() {
      if (operationOrigin case (
        final origin,
        final start,
        final added,
        final handler,
        final location,
      )) {
        void record(Value value) {
          if (location != null) sourceLocations[value] = location;
          if (handler != null &&
              !operations.contains(value) &&
              !unwindConversions.contains(value)) {
            handlers[value] = handler;
          }
        }

        instructions[origin]!.skip(start).forEach(record);
        for (final next in blocks.skip(added)) {
          instructions[next]!.forEach(record);
        }
      }
      operationOrigin = null;
    }

    blocks.addAll(function.blocks);
    sourceBlocks:
    for (final sourceBlock in function.blocks) {
      finishOperation();
      var block = sourceBlock;
      var body = instructions[block] = <Value>[];
      final source = switch (sourceBlock.end) {
        Invoke(:final operation) => sourceBlock.instructions.followedBy([
          operation,
        ]),
        _ => sourceBlock.instructions,
      };
      for (final instruction in source) {
        finishOperation();
        if (instruction.requiredStorageView != null || instruction is ManagedStorageAllocation) {
          final facts = members.callTypes;
          if (facts is! ProgramFlowFacts || !facts.provesStorageView(instruction)) {
            throw StateError('Cannot select a storage access without actual allocation proof.');
          }
        }
        final handler = switch (sourceBlock.end) {
          Invoke(:final operation, :final onThrow)
              when operation == instruction =>
            onThrow,
          _ => null,
        };
        final location = function.sourceLocations[instruction];
        if (handler != null || location != null) {
          operationOrigin = (
            block,
            body.length,
            blocks.length,
            handler,
            location,
          );
        }
        if (instruction case ManagedStorageAllocation(:final allocator)) {
          if (allocator != heap.runtime?.allocate) {
            throw StateError('Managed storage requires the actual runtime allocator.');
          }
          invocations[instruction] = allocator;
          body.add(instruction);
          continue;
        }
        if (instruction is PatternMatchFailure) {
          invocations[instruction] =
              heap.runtime?.patternMatchFailure ??
              (throw UnsupportedError('Pattern match runtime unavailable'));
        }
        if (instruction case AssertionFailure(:final message)) {
          invocations[instruction] =
              heap.runtime?.assertionFailure ??
              (throw UnsupportedError('Assertion runtime unavailable'));
          operands[instruction] = [
            convert(
              message ?? const Constant.nullValue(),
              .object.nullable,
              body,
            ),
          ];
        }
        if (instruction case ObjectClassName(:final operand)) {
          final type = layouts.types.runtimeTypeOf(operand, body);
          final name = _load(TypeMetadata.className, type, body);
          aliases.add(instruction);
          operands[instruction] = [name];
          body.add(instruction);
          continue;
        }
        if (instruction case Identical(:final left, :final right)) {
          block = valueOperations.identical(left, right, block, typeTest);
          body = instructions[block]!;
          body.add(instruction);
          aliases.add(instruction);
          operands[instruction] = block.parameters;
          continue;
        }
        if (instruction case ObjectHashCode(:final operand, direct: true)) {
          block = valueOperations.identityHash(operand, block, typeTest);
          body = instructions[block]!;
          body.add(instruction);
          aliases.add(instruction);
          operands[instruction] = block.parameters;
          continue;
        }
        if (instruction is NewCollection ||
            instruction is ListFilled ||
            instruction is ListFrom ||
            instruction is CollectionSpread &&
                !instruction.isMethodCall &&
                CoreTypes.view(instruction.collection.type, CoreTypes.list) !=
                    null) {
          throw StateError(
            'Normalize collection construction before representation.',
          );
        }
        if (instruction case MakeRecord(
          type: final RecordType type,
          inputs: final fields,
        )) {
          invocations[instruction] = layouts.records.create(
            type,
            layouts.types,
          );
          operands[instruction] = [
            for (final field in fields) convert(field, .object.nullable, body),
          ];
          body.add(instruction);
          continue;
        }
        if (instruction case RecordGet(:final record, :final slot)) {
          final object = TypeView(record, .object);
          final value = LoadObjectReference(
            object,
            Constant.integer(RecordStorage.offset(slot)),
          );
          body.addAll([object, value, instruction]);
          aliases.add(instruction);
          operands[instruction] = [value];
          continue;
        }
        if (instruction case NewPayload(
          type: final ClassType type,
          :final bytes,
        )) {
          invocations[instruction] = heap.allocatePayload(type);
          operands[instruction] = [bytes];
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
          operands[instruction] = [boolean];
          aliases.add(instruction);
          body.add(instruction);
          continue;
        }
        if (instruction is NativeView ||
            instruction is NativeAddress ||
            instruction is CopyNative) {
          throw StateError(
            'Native view storage implementations must enter ordinary IR before selection.',
          );
        }
        if (instruction is NativeSize || instruction is NativeFieldOffset) {
          final value = instruction is NativeSize
              ? layouts.native.layout.of(instruction.nativeType).size
              : layouts.native.layout
                    .of((instruction as NativeFieldOffset).owner)
                    .offsets[instruction.index];
          operands[instruction] = [Constant.integer(value)];
          aliases.add(instruction);
          body.add(instruction);
          continue;
        }
        if (instruction
            case PointerAddress(pointer: final receiver) ||
                StringLength(string: final receiver)) {
          operands[instruction] = [
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
                layouts.native.layout
                    .of(FfiTypes.pointerElement(offset.pointer.type)!)
                    .size,
              ),
            );
            address = IntBinary(.add, base, bytes);
            body.addAll([bytes, address]);
          }
          if (addressOnly.contains(instruction)) {
            resultShapes[instruction] = ExecutionShape.word;
            operands[instruction] = [address];
            aliases.add(instruction);
            body.add(instruction);
            continue;
          }
          invocations[instruction] = heap.constructorFor(
            layouts.pointers.initializer,
          );
          operands[instruction] = [
            address,
            layouts.types.constant(FfiTypes.pointerRuntimeType),
          ];
          body.add(instruction);
          continue;
        }
        if (instruction is NativeCall) {
          throw StateError(
            'Native value conversions must enter ordinary IR before selection.',
          );
        }
        if (instruction case RawNativeCall(
          :final address,
          :final arguments,
          :final resultStorage,
          :final signature,
          :final isLeaf,
        )) {
          final Value raw;
          if (signature.result is NativeCompoundType ||
              signature.parameters.any((type) => type is NativeCompoundType)) {
            final target = layouts.nativeCalls.target(
              signature,
              isLeaf: isLeaf,
            );
            final call = DirectCall(target, [
              address,
              ?resultStorage,
              ...arguments,
            ]);
            invocations[call] = target;
            callOrigins[call] = instruction;
            raw = call;
          } else {
            raw = NativeInvocation(
              address,
              arguments,
              signature,
              isLeaf: isLeaf,
            );
          }
          body.add(raw);
          aliases.add(instruction);
          operands[instruction] = [raw];
          body.add(instruction);
          continue;
        }
        if (instruction case final ReadFunctionTypeArgument read) {
          final facts = members.callTypes;
          if (facts is! ProgramFlowFacts ||
              !facts.provesFunctionEnvironment(read)) {
            throw StateError(
              'Callable type environment requires its actual origin proof.',
            );
          }
          final own = read.source.typeParameters.indexOf(read.parameter);
          final Value value;
          if (own >= 0) {
            Value arguments = _load(
              layouts.closures.identityArguments,
              read.function,
              body,
            );
            for (var i = 0; i < own; i++) {
              arguments = _load(TypeMetadata.tail, arguments, body);
            }
            value = _load(TypeMetadata.head, arguments, body);
          } else {
            final shape = read.source.kind == .closure
                ? layouts.closures.closures[read.source]!
                : layouts.closures.methods[read.source]!;
            final original = _load(
              layouts.closures.environment,
              read.function,
              body,
            );
            value = _load(
              shape.environment[shape.parameters.indexOf(read.parameter)],
              original,
              body,
            );
          }
          aliases.add(read);
          operands[read] = [value];
          body.add(read);
          continue;
        }
        if (instruction case final ReadFunctionEnvironment read) {
          final facts = members.callTypes;
          if (facts is! ProgramFlowFacts ||
              !facts.provesFunctionEnvironment(read)) {
            throw StateError(
              'Callable environment selection requires its actual origin proof.',
            );
          }
          final shape = read.source.kind == .closure
              ? layouts.closures.closures[read.source]!
              : layouts.closures.methods[read.source]!;
          final original = _load(
            layouts.closures.environment,
            read.function,
            body,
          );
          final value = read.capture != null
              ? _load(shape.captures[read.capture!], original, body)
              : read.source.kind == .closure
              ? original
              : _load(shape.captures.single, original, body);
          aliases.add(read);
          operands[read] = [value];
          body.add(read);
          continue;
        }
        if (instruction case CellReference(cell: final cell) ||
            CellStorageReference(cell: final cell) ||
            CellStorageView(backing: final cell) ||
            CallableReference(function: final cell)) {
          aliases.add(instruction);
          operands[instruction] = [cell];
          body.add(instruction);
          continue;
        }
        if (instruction is MakeClosure || instruction is BindMethod && instruction.entryBinding == null ||
            instruction is InstantiateFunction || instruction is InstantiateFunctionFrom) {
          throw StateError('Lower callable creation into ordinary IR before representation.');
        }
        if (instruction is NewCell || instruction is CopyCell ||
            instruction is ReadCell || instruction is WriteCell) {
          throw StateError('Lower cell storage into ordinary IR before representation.');
        }
        if (instruction case Equals(:final left)
            when left.type != .nullType &&
                ValueType.function.nullable.accepts(left.type)) {
          block = valueOperations.equalFunction(instruction, block);
          body = instructions[block]!;
          body.add(instruction);
          aliases.add(instruction);
          operands[instruction] = block.parameters;
          continue;
        }
        if (instruction case ObjectHashCode(:final operand, direct: false)
            when operand.type == .nullType ||
                layouts.isBoxable(operand.type) ||
                FfiTypes.isPointer(operand.type)) {
          block = valueOperations.hashScalar(
            FfiTypes.isPointer(operand.type)
                ? pointerAddress(operand, body)
                : operand,
            block,
          );
          body = instructions[block]!;
          body.add(instruction);
          aliases.add(instruction);
          operands[instruction] = block.parameters;
          continue;
        }
        if (instruction case Equals(:final left, :final right, :final negated)
            when FfiTypes.isPointer(left.type) &&
                FfiTypes.isPointer(right.type)) {
          final equal = Equals(
            pointerAddress(left, body),
            pointerAddress(right, body),
            negated: negated,
          );
          body.addAll([equal, instruction]);
          aliases.add(instruction);
          operands[instruction] = [equal];
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
        if (instruction is MakeInvocation) {
          throw StateError('Normalize Invocation before representation.');
        }
        if (instruction case FunctionCall(entryBinding: final binding?)) {
          final shape = binding.shape;
          final table = _load(
            layouts.closures.entryTable,
            instruction.function,
            body,
          );
          final slot = shape.slot == 0
              ? table as Value
              : IntBinary(.add, table, Constant.integer(shape.slot * 8));
          if (!identical(slot, table)) body.add(slot);
          final address = LoadNative(slot, NativeScalarType(Int64));
          body.add(address);
          final arguments = <Value>[
            instruction.function,
            ...instruction.positional,
            for (final name in shape.named.keys) instruction.named[name]!,
            for (final type in instruction.typeArguments) _reify(type, body),
          ];
          final call = IndirectInvocation(
            instruction,
            address,
            arguments,
            shape.signature,
            shape.execution,
          );
          final facts = members.callTypes;
          if (facts == null) {
            throw StateError(
              'Indirect callable entries require actual execution facts.',
            );
          }
          final targets = facts.executionTargetsOf(instruction);
          if (!binding.entries.values.toSet().containsAll(targets)) {
            throw StateError(
              'Callable execution facts disagree with its entries.',
            );
          }
          indirectInvocations[call] = Set.unmodifiable(targets);
          body.add(call);
          aliases.add(instruction);
          operands[instruction] = [call];
          body.add(instruction);
          continue;
        }
        if (instruction is FunctionCall) {
          throw StateError('Function calls require their actual execution entry binding.');
        }
        final invocation = switch (instruction) {
          DynamicDispatch(:final receiver, :final typeArguments) => (
            null,
            receiver,
            typeArguments,
          ),
          InstanceCall(:final member, :final receiver, :final typeArguments) =>
            (member, receiver, typeArguments),
          BindMethod(:final method, :final receiver) => (method, receiver, const <ValueType>[]),
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
          final dynamicCall = instruction is DynamicDispatch
              ? instruction
              : null;
          final builtin =
              instruction is Equals ||
              instruction is ObjectRuntimeType ||
              instruction is ObjectHashCode;
          final virtual = instruction is! DirectCall && !(instruction is BindMethod && instruction.direct);
          final targets = dynamicCall != null
              ? {
                  for (final entry
                      in members
                          .dynamicTargets(dynamicCall, types: layouts.types)
                          .entries)
                    entry.key: (
                      target: entry.value,
                    ),
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
                                  receiverValue: receiver,
                                )
                              : {member!.owner!: member})
                          .entries)
                    if (!virtual ||
                        layouts.typeTest(receiver.type, entry.key) !=
                            .constantFalse)
                      entry.key: (target: entry.value,),
                };
          final plainObject =
              receiver.type.nonNullable is ClassType &&
              ![
                ValueType.integer,
                ValueType.floating,
                ValueType.boolean,
                ValueType.string,
                ValueType.typeType,
                TypeMetadata.type,
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
            operands[instruction] = [result];
            body.add(instruction);
            continue;
          }
          if (instruction is Equals) {
            targets[TypeMetadata.type] = (
              target: layouts.types.equality,
            );
          } else if (instruction is ObjectHashCode) {
            targets[TypeMetadata.type] = (
              target: layouts.types.hash,
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
                );
            }
          }
          // A typed dispatch with complete receiver evidence has no missing
          // case. Its final target uses the remaining receiver alternatives;
          // selection must not invent a runtime failure call for that proof.
          final dispatchSelector = instruction is InstanceCall
              ? instruction.member.selector
              : instruction is BindMethod ? instruction.method.selector
              : instruction.implicitMember?.selector;
          final exhaustive =
              dispatchSelector != null &&
              members.callTypes is ProgramFlowFacts &&
              () {
                final facts = members.callTypes as ProgramFlowFacts;
                if (!facts.reachesOperation(instruction) ||
                    facts.hasUnknownCall(instruction)) {
                  return false;
                }
                final receivers = facts.receiverClassesOf(receiver);
                return receivers.isNotEmpty &&
                    receivers.every((type) {
                      final selected = targets[type.declaration]?.target;
                      return selected != null &&
                          members.program
                                  .lookupMember(
                                    type,
                                    dispatchSelector,
                                  )
                                  .target
                                  ?.implementation ==
                              selected.implementation;
                    });
              }();
          late final actual = layouts.types.runtimeTypeOf(receiver, body);
          final dynamicKind = dynamicCall == null
              ? null
              : _load(TypeMetadata.kind, actual, body);
          final shape = dynamicCall != null
              ? null
              : targets.isEmpty
              ? null
              : virtual
              ? LoadField(TypeMetadata.shape, actual)
              : null;
          if (shape != null) body.add(shape);
          final types = instruction is InstanceCall && instruction.entryBinding != null
              ? instruction.executionTypes
              : [for (final type in typeArguments) _reify(type, body)];
          final result = instruction.type;
          final join = result == .never ? null : Block([result]);
          if (instruction case InstanceCall(entryBinding: final binding?) when join != null) {
            resultShapes[join.parameters.single] = binding.execution.result;
          }
          if (instruction case BindMethod(entryBinding: final binding?) when join != null) {
            resultShapes[join.parameters.single] = binding.execution.result;
          }
          final missing = Block();
          blocks.add(missing);
          switch (instruction) {
            case DynamicDispatch():
              final missingBody = <Value>[];
              instructions[missing] = missingBody;
              final target =
                  dynamicCall!.failure ??
                  (throw StateError(
                    'Normalize dynamic dispatch before representation.',
                  ));
              final failure = DirectCall(
                target,
                dynamicCall.inputs,
                typeArguments: dynamicCall.typeArguments,
              );
              operands[failure] = [
                for (final input in failure.inputs)
                  convert(input, .dynamicType, missingBody),
                ...types,
              ];
              final failed = appendTo(missing, failure, handler);
              ends[failed] = Jump(join!, [failure]);
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
            final kind = LoadField(TypeMetadata.kind, actual);
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
          if (dynamicCall != null && dynamicCall.selector.name == 'call' &&
              dynamicCall.selector.privateScope == null && dynamicCall.selector.kind != .setter) {
            final facts = members.callTypes;
            final possible = facts is! ProgramFlowFacts || facts.valueOf(receiver).runtimeTypes.any(
                (type) => type is FunctionType || type.accepts(ValueType.function));
            if (possible) {
              final selected = addBlock(), nominal = addBlock();
              final test = Equals(dynamicKind!, Constant.integer(TypeKind.function.index));
              body.add(test);
              ends[next] = Branch(test, Jump(selected), Jump(nominal));
              next = nominal;
              if (dynamicCall.selector.kind == .getter) {
                ends[selected] = Jump(join!, [receiver]);
              } else {
                final binding = dynamicCall.entryBinding ??
                    (throw StateError('Dynamic function calls need their actual checked entries.'));
                final into = instructions[selected]!;
                final table = _load(layouts.closures.entryTable, receiver, into);
                final slot = binding.shape.slot == 0 ? table as Value
                    : IntBinary(.add, table, Constant.integer(binding.shape.slot * 8));
                if (!identical(slot, table)) into.add(slot);
                final address = LoadNative(slot, NativeScalarType(Int64));
                into.add(address);
                final call = IndirectInvocation(instruction, address, [receiver,
                  ...dynamicCall.positional,
                  for (final name in binding.shape.named.keys) dynamicCall.named[name]!,
                  ...types,
                ], binding.shape.signature, binding.shape.execution);
                if (facts == null) throw StateError('Missing actual dynamic function facts.');
                final entries = binding.entries.values.toSet();
                indirectInvocations[call] = Set.unmodifiable(
                    facts.executionTargetsOf(instruction).where(entries.contains));
                final returned = appendTo(selected, call, handler);
                ends[returned] = Jump(join!, [call]);
              }
            }
          }
          if (builtin) {
            final nominal = Block();
            blocks.add(nominal);
            instructions[nominal] = [];
            final kind = LoadField(TypeMetadata.kind, actual);
            final test = Equals(kind, Constant.integer(TypeKind.nominal.index));
            body.addAll([kind, test]);
            var otherKind = builtinEntry;
            if (layouts.records.declaration case final carrier?
                when targets.containsKey(carrier.type)) {
              otherKind = addBlock();
              final record = Equals(
                kind,
                Constant.integer(TypeKind.record.index),
              );
              instructions[otherKind]!.add(record);
              ends[otherKind] = Branch(
                record,
                Jump(nominal),
                Jump(builtinEntry),
              );
            }
            ends[next] = Branch(test, Jump(nominal), Jump(otherKind));
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
          var remaining = targets.length;
          candidates:
          for (final MapEntry(key: type, value: (:target,))
              in targets.entries) {
            final finalCase = --remaining == 0 && exhaustive;
            var current = next;
            final binding = dynamicCall != null &&
                dynamicCall.selector.kind == .getter && target.kind == .method;
            if (dynamicCall != null) {
              final selected = addBlock(), otherwise = addBlock();
              final kind = type == ValueType.nullClass
                  ? TypeKind.nullType
                  : type == layouts.records.declaration?.type
                  ? TypeKind.record
                  : TypeKind.nominal;
              final kindTest = Equals(
                dynamicKind!,
                Constant.integer(kind.index),
              );
              instructions[next]!.add(kindTest);
              final checkShape =
                  kind == TypeKind.nullType || kind == TypeKind.record
                  ? selected
                  : addBlock();
              ends[next] = Branch(kindTest, Jump(checkShape), Jump(otherwise));
              if (kind != TypeKind.nullType && kind != TypeKind.record) {
                final shapeBody = instructions[checkShape]!;
                final key = _load(TypeMetadata.shape, actual, shapeBody);
                final test = Equals(
                  key,
                  Constant.integer(
                    layouts.types.id(type.declaration),
                  ),
                );
                shapeBody.add(test);
                ends[checkShape] = Branch(
                  test,
                  Jump(selected),
                  Jump(otherwise),
                );
              }
              next = otherwise;
              current = selected;
              if (kind == TypeKind.record) {
                final shapes = layouts.records
                    .fieldsFor(dynamicCall.selector)
                    .toList();
                if (shapes.isNotEmpty) {
                  final found = addBlock();
                  final actualShape = _load(
                    TypeMetadata.shape,
                    actual,
                    instructions[current]!,
                  );
                  for (final (i, shape) in shapes.indexed) {
                    final nextShape = i == shapes.length - 1
                        ? missing
                        : addBlock();
                    final test = Equals(
                      actualShape,
                      Constant.integer(
                        layouts.records.shapeId(shape, layouts.types),
                      ),
                    );
                    instructions[current]!.add(test);
                    ends[current] = Branch(test, Jump(found), Jump(nextShape));
                    current = nextShape;
                  }
                  current = found;
                }
              }
              if (dynamicCall.selector.kind == .method &&
                  target.kind == .getter) {
                final bridge =
                    dynamicCall.getterCalls[target] ??
                    (throw StateError(
                      'Normalize getter calls before representation.',
                    ));
                final call = DynamicDispatch(
                  receiver,
                  dynamicCall.selector,
                  dynamicCall.positional,
                  dynamicCall.named,
                  typeArguments,
                  dynamicCall.failure,
                  dynamicCall.getterCalls,
                );
                invocations[call] = bridge;
                operands[call] = [
                  for (final input in call.inputs)
                    convert(input, .dynamicType, instructions[current]!),
                  for (final index in layouts.typeEnvironment.parametersOf(
                    bridge,
                  ))
                    types[index],
                ];
                current = appendTo(current, call, handler);
                ends[current] = Jump(join!, [call]);
                continue;
              }
              final signature = target.signature;
              if (!binding &&
                  (!signature.acceptsShape(
                        dynamicCall.positional.length,
                        dynamicCall.named.keys,
                      ) ||
                      types.isNotEmpty &&
                          types.length != signature.typeParameters.length)) {
                ends[current] = Jump(missing);
                continue;
              }
            }
            if (shape != null && !finalCase) {
              final selected = Block(), otherwise = Block();
              blocks.addAll([selected, otherwise]);
              final record = type == layouts.records.declaration?.type;
              final key = record
                  ? _load(TypeMetadata.kind, actual, instructions[next]!)
                  : shape;
              final test = Equals(
                key,
                Constant.integer(
                  record
                      ? TypeKind.record.index
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

            if (instruction case BindMethod(entryBinding: final entryBinding?)) {
              final entry = entryBinding.entries[target] ?? (throw StateError('Missing actual method producer.'));
              final call = DirectCall(entry, instruction.inputs);
              invocations[call] = entry;
              callOrigins[call] = instruction;
              resultShapes[call] = entryBinding.execution.result;
              append(call);
              ends[current] = Jump(join!, [call]);
              continue;
            }
            if (instruction case InstanceCall(entryBinding: final entryBinding?)) {
              final entry = entryBinding.entries[target] ??
                  (throw StateError('Missing actual member execution entry.'));
              final call = DirectCall(entry, [receiver,
                ...instruction.positional,
                for (final name in entryBinding.names) instruction.named[name]!,
                ...instruction.executionTypes]);
              invocations[call] = entry;
              callOrigins[call] = instruction;
              resultShapes[call] = entryBinding.execution.result;
              if (join == null) {
                instructions[current]!.add(call);
                ends[current] = handler == null ? Unreachable(call)
                    : Invoke(call, onReturn: null, onThrow: edge(handler));
              } else {
                append(call);
                ends[current] = Jump(join, [call]);
              }
              continue;
            }

            if (binding) {
              final implementation = dynamicCall.methodBindings[target] ??
                  (throw StateError('Dynamic method extraction needs its actual producer.'));
              final call = DirectCall(implementation, [receiver]);
              callOrigins[call] = instruction;
              append(call);
              ends[current] = Jump(join!, [call]);
              continue;
            }
            final carrier = receiver;
            var functionTypes = types;
            final parameters = target.owner?.typeParameters ?? const <TypeParameterType>[];
            final environment = {
              if (!binding && functionTypes.isNotEmpty)
                for (final (i, parameter)
                    in target.typeParameters
                        .indexed)
                  parameter: functionTypes[i],
            };
            Value argument(TypeParameterType parameter) =>
                environment.putIfAbsent(parameter, () {
                  final index = parameters.indexOf(parameter);
                  final pending = <Value>[];
                  final value = _ownerArgument(actual, target.owner!, index, pending);
                  pending.forEach(append);
                  return value;
                });
            Value reify(ValueType type) {
              if (type.freeTypeParameters.isEmpty) {
                return layouts.types.constant(type);
              }
              if (type is TypeParameterType) return argument(type);
              final template = layouts.types.instantiate(type);
              final call = DirectCall(template.target, [
                for (final parameter in template.parameters)
                  argument(parameter),
              ]);
              append(call);
              return call;
            }

            if (dynamicCall != null &&
                !binding &&
                functionTypes.isEmpty) {
              final signature = target.signature;
              functionTypes = [
                for (final type in signature.defaultTypeArguments) reify(type),
              ];
              for (final (i, parameter) in signature.typeParameters.indexed) {
                environment[parameter] = functionTypes[i];
              }
            }
            final invocationTypes = dynamicCall == null ? types : functionTypes;
            for (final (i, parameter) in target.typeParameters.indexed) {
              environment[parameter] = invocationTypes[i];
            }
            for (final (i, parameter) in target.typeParameters.indexed) {
              append(DirectCall(casts.bounds(layouts), [invocationTypes[i], reify(parameter.bound)]));
            }
            final inputs = switch (instruction) {
              DynamicDispatch(:final positional, :final named) ||
              InstanceCall(:final positional, :final named) => target.signature.bind<Value>(
                positional,
                named,
                (i) =>
                    members.program.implementationOf(target)!.defaults[i]!,
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
            final arguments = <Value>[carrier];
            for (final (i, value) in inputs.indexed) {
              final destination =
                  target.signature.parameters[i +
                      (target.kind.hasReceiver ? 0 : 1)];
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
              final signature = casts.targetFor(check);
              operands[check] = [
                widened,
                for (final parameter in signature.parameters)
                  argument(parameter),
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
              DynamicDispatch(
                :final selector,
                :final positional,
                :final named,
                :final failure,
                :final getterCalls,
                :final entryBinding,
                :final methodBindings,
              ) =>
                DynamicDispatch(
                  receiver,
                  selector,
                  positional,
                  named,
                  typeArguments,
                  failure,
                  getterCalls,
                  entryBinding,
                  methodBindings,
                ),
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
            callOrigins[call] = instruction;
            final entryTypes = layouts.entryTypes(target);
            final converted = <Value>[];
            operands[call] = [
              for (final (i, value) in arguments.indexed)
                convert(value, entryTypes[i], converted),
              for (final index in layouts.typeEnvironment.parametersOf(target))
                invocationTypes[index],
              for (final parameter
                  in layouts.typeEnvironment.lexicalParametersOf(target))
                argument(parameter),
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
              resultShapes[call] = layouts.resultShape(target);
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
          if (virtual && !exhaustive) ends[next] = Jump(missing);
          if (join == null) continue sourceBlocks;
          blocks.add(join);
          block = join;
          body = instructions[block] = [instruction];
          aliases.add(instruction);
          operands[instruction] = join.parameters;
          continue;
        }
        final lateField = switch (instruction) {
          LoadField(:final field) ||
          StoreField(:final field) when field.isLate => field,
          _ => null,
        };
        if (lateField != null) {
          final field = lateField;
          final receiver = switch (instruction) {
            LoadField(:final receiver) ||
            StoreField(:final receiver) => receiver,
            _ => throw StateError('Expected a late field access.'),
          };
          final (valueField, boundField) = layouts.instances.slots(field);
          final isFinal = field.isFinal;
          final isRead = instruction is LoadField;
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
          }

          final join = Block(
            isRead
                ? [
                    field.requiresReadCheck
                        ? layouts.isBoxable(field.type)
                              ? valueCarrier(field.type)
                              : ValueType.object.nullable
                        : instruction.type,
                  ]
                : [],
          );
          blocks.add(join);
          if (instruction case StoreField(:final value)) {
            final conversions = <Value>[];
            final stored = field.type.freeTypeParameters.isEmpty
                ? convert(value, field.type, conversions)
                : checkField(field, receiver, value, conversions);
            conversions.forEach(append);
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
            final read = LoadField(valueField, receiver);
            instructions[bound]!.add(read);
            ends[bound] = Jump(join, [read]);
            enter(initialize);
            if (field.initializer case final initializer?) {
              final value = DirectCall(initializer, [
                receiver,
              ], ownerType: CoreTypes.view(receiver.type, field.owner));
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
          operands[instruction] = values;
          continue;
        }
        if (instruction case InitializeStorageField(:final field, :final destination, :final source)) {
          final loaded = _load(field, source, body);
          body.add(StorageWrite(field, destination, loaded));
          aliases.add(instruction);
          operands[instruction] = [];
          body.add(instruction);
          continue;
        }
        if (instruction
            case StoreField(:final field, :final receiver, :final value)
            when !field.isLate && field.type.freeTypeParameters.isNotEmpty) {
          final check = checkField(field, receiver, value, body);
          operands[instruction] = [receiver, check];
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
          operands[instruction] = [value];
          continue;
        }
        if (instruction case CheckedTypeArgument(:final implementation)) {
          if (implementation == null) {
            throw StateError('Lower checked type arguments before selection.');
          }
          invocations[instruction] = implementation;
          operands[instruction] = instruction.inputs.toList();
          body.add(instruction);
          continue;
        }
        if (instruction case ReifyType(:final template)) {
          operands[instruction] = [_reify(template, body)];
        }
        if (instruction is ObjectRuntimeType) runtimeType(instruction, body);
        if (instruction is TypeTest) {
          block = typeTest(instruction, block);
          body = instructions[block]!;
          continue;
        }
        if (instruction
            case TypeCast(:final operand) || NullCheck(:final operand)) {
          if (nonNull.contains(operand) &&
              instruction.type.accepts(operand.type.nonNullable)) {
            aliases.add(instruction);
            operands[instruction] = [operand];
            body.add(instruction);
            continue;
          }
          final check = casts.targetFor(instruction);
          operands[instruction] = [
            operand,
            for (final parameter in check.parameters) _reify(parameter, body),
          ];
        }
        if (instruction is TypeView && addressOnly.contains(instruction)) {
          operands[instruction] = [pointerAddress(instruction.operand, body)];
          aliases.add(instruction);
          body.add(instruction);
          continue;
        }
        if (instruction case MaterializedValue(:final backing)) {
          operands[instruction] = [backing];
          aliases.add(instruction);
          body.add(instruction);
          continue;
        }
        if (instruction case ConstantCarrier(:final value)) {
          operands[instruction] = [value];
          aliases.add(instruction);
          body.add(instruction);
          continue;
        }
        if (instruction is MaterializeValue || instruction is ProjectValue) {
          throw StateError('Lower actual representation operations before selection.');
        }
        final destinations = switch (instruction) {
          DirectCall(:final target) ||
          InitializeObject(initializer: final target) => layouts.entryShapes(target),
          Construct(typeDescriptor: null) => [
            ...layouts.executionShapes.inputShapesOf(function, instruction),
            ExecutionShape.reference,
          ],
          _ => layouts.executionShapes.inputShapesOf(function, instruction),
        };
        {
          final inputs = [
            ...instruction.inputs,
            if (instruction case DirectCall(:final target, :final ownerType)
                when layouts.typeEnvironment.ownerOf(target))
              _reify(ownerType ?? target.owner!, body),
            if (instruction case DirectCall(
              :final target,
              :final typeArguments,
            ))
              for (final index
                  in layouts.typeEnvironment.parametersOf(target).toList())
                _reify(typeArguments[index], body),
            if (instruction case DirectCall(
              :final target,
              :final lexicalEnvironment,
            ))
              for (final parameter
                  in layouts.typeEnvironment
                      .lexicalParametersOf(target)
                      .toList())
                _reify(lexicalEnvironment[parameter] ?? parameter, body),
            if (instruction case Construct(:final instantiatedType, typeDescriptor: null))
              _reify(instantiatedType, body),
          ];
          var changed = inputs.length != instruction.inputs.length;
          for (final (i, input) in inputs.indexed) {
            final value = transfer(input, destinations[i], body);
            changed |= value != input;
            inputs[i] = value;
          }
          if (changed) operands[instruction] = inputs;
        }
        body.add(instruction);
      }
      finishOperation();
      final handler = switch (sourceBlock.end) {
        Invoke(:final onThrow) => onThrow,
        Throw(:final onThrow) => onThrow,
        _ => null,
      };
      final location =
          function.sourceLocations[sourceBlock] ??
          switch (sourceBlock.end) {
            Invoke(:final operation) => function.sourceLocations[operation],
            _ => null,
          };
      if (handler != null || location != null) {
        operationOrigin = (
          block,
          body.length,
          blocks.length,
          handler,
          location,
        );
      }
      if (location != null) sourceLocations[block] = location;
      if (sourceBlock.end case ExhaustivenessFailure(:final onThrow)) {
        final target =
            heap.runtime?.exhaustivenessFailure ??
            (throw UnsupportedError('Exhaustive switch runtime unavailable'));
        final call = DirectCall(target, []);
        body.add(call);
        ends[block] = onThrow == null
            ? Unreachable(call)
            : Invoke(call, onReturn: null, onThrow: edge(onThrow));
      }
      if (sourceBlock.end case Throw(
        :final exception,
        :final stackTrace,
        :final onThrow,
        :final isRecorded,
      )) {
        if (!isRecorded) {
          throw StateError(
            'Exception state must be normalized before representation.',
          );
        }
        ends[block] = Throw.recorded(
          transfer(exception, ExecutionShape.reference, body),
          stackTrace,
          onThrow: onThrow == null ? null : edge(onThrow),
        );
      }
      ends[block] ??= switch (sourceBlock.end) {
        Return(:final value) => Return(
          transfer(
            value ?? const Constant.nullValue(),
            layouts.resultShape(function.target),
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
        final end => end,
      };
      if (block != sourceBlock) block.finish(sourceBlock.end);
    }
    finishOperation();
    instructions[function.entry]!.insertAll(0, _prologue);
    // Generated boxing and type preparation share their source handler.
    for (final block in blocks.toList()) {
      final values = instructions[block]!;
      if (!values.any(handlers.containsKey)) continue;
      var end = ends[block]!;
      if (end case Unreachable(cause: final Instruction cause)
          when cause.mayThrow && handlers.containsKey(cause)) {
        end = Invoke(cause, onReturn: null, onThrow: edge(handlers[cause]!));
      }
      instructions[block] = [];
      var current = block;
      for (final value in values) {
        current = appendTo(
          current,
          value,
          aliases.contains(value) || end is Invoke && end.operation == value
              ? null
              : handlers[value],
        );
      }
      ends[current] = end;
      if (sourceLocations[block] case final location?) {
        sourceLocations[current] = location;
      }
    }
  }
}
