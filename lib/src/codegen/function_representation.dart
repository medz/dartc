import 'package:dartc/ir.dart';

import 'program_layout.dart';
import 'checked_casts.dart';
import 'type_values.dart';
import 'member_calls.dart';
import 'heap_plan.dart';
import 'cell_initialization.dart';

/// Places allocating representation changes before register and root analysis.
final class FunctionRepresentation(
  final IrFunction function,
  final ProgramLayout layouts,
  CheckedCasts casts,
  MemberCalls members,
  HeapPlan heap, {
  FunctionTarget? captureTrace,
}) {
  final blocks = <Block>[];
  final instructions = <Block, List<Instruction>>{};
  final ends = <Block, Terminator>{};
  final _operands = <Instruction, List<Value>>{};
  final _arguments = <Jump, List<Value>>{};
  final boxes = <Instruction, Value>{};
  final introduced = <Instruction>{};
  final tests = <TypeTest, TypeTestKind>{};
  final invocations = <Instruction, FunctionTarget>{};
  final identities = <Equals>{};
  final aliases = <Instruction>{};
  final _resultTypes = <Value, ValueType>{};
  final stackCells = <NewCell>{};
  final _prologue = <Instruction>[];
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
        : _receiverType(function.entry.parameters.first, _prologue),
    function.target.owner!,
    _prologue,
  );

  Value _receiverType(Value receiver, List<Instruction> into) {
    final actual = ObjectRuntimeType(receiver, direct: true);
    final concrete = TypeCast(actual, TypeValues.type);
    into.addAll([actual, concrete]);
    return concrete;
  }

  List<Value> _ownerArguments(
    Value actual,
    ClassType owner,
    List<Instruction> into,
  ) {
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

  Value _reify(ValueType type, List<Instruction> into) {
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

  Iterable<Value> inputsOf(Instruction instruction) =>
      _operands[instruction] ?? instruction.inputs;

  /// The stored type before a selected call result is boxed for its caller.
  ValueType typeOf(Value value) =>
      _resultTypes[value] ??
      (stackCells.contains(value)
          ? (value.type as CellType).content
          : value.type);

  LoadField _load(InstanceField field, Value receiver, List<Instruction> into) {
    // The selected carrier is physical storage, not the function's Dart type.
    final load = LoadField(field, Block([field.owner]).parameters.single);
    _operands[load] = [receiver];
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
    checkCellInitialization(function);
    final operations = [
      for (final block in function.blocks) ...[
        ...block.instructions,
        if (block.end case Invoke(:final operation)) operation,
      ],
    ];
    stackCells.addAll(operations.whereType<NewCell>());
    for (final operation in operations) {
      for (final input in operation.inputs) {
        if (!(operation is ReadCell && operation.cell == input ||
            operation is WriteCell && operation.cell == input)) {
          stackCells.remove(input);
        }
      }
    }
    for (final block in function.blocks) {
      if (block.end case Return(value: final value?)) stackCells.remove(value);
      for (final edge in block.successors) {
        stackCells.removeAll(edge.arguments);
      }
    }
    bool needsBox(Value value, ValueType type) {
      if (value is TestedValue) value = value.test.operand;
      return value is! Constant &&
          value.type is! CellType &&
          (typeOf(value) == .integer || typeOf(value) == .floating) &&
          layouts.representation(type) == .reference;
    }

    Value convert(Value value, ValueType type, List<Instruction> into) {
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

    Value? traceFor(Value? trace, List<Instruction> into) {
      if (trace != null || captureTrace == null) return trace;
      final capture = DirectCall(captureTrace, []);
      into.add(capture);
      return capture;
    }

    void runtimeType(ObjectRuntimeType instruction, List<Instruction> into) {
      final source = instruction.operand.type;
      if (source == .nullType || layouts.representation(source) != .reference) {
        _operands[instruction] = [
          _reify(
            FfiTypes.isPointer(source) ? FfiTypes.pointerRuntimeType : source,
            into,
          ),
        ];
      }
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
      final body = instructions[block] = <Instruction>[];
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

    Block appendTo(Block block, Instruction operation, Jump? handler) {
      instructions[block]!.add(operation);
      if (handler == null || !operation.mayThrow) return block;
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
      var body = instructions[block] = <Instruction>[];
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
            shape.initializer,
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
          if (type.isLate ||
              instruction is NewCell && instruction.initializer != null) {
            throw UnsupportedError(
              'Native captured late storage is not implemented.',
            );
          }
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
              final ClassType pointer when FfiTypes.isPointer(pointer) =>
                PointerFromAddress(const Constant.integer(0), pointer),
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
            layouts.types.constant(shape.type),
          ];
          body.add(instruction);
          continue;
        }
        if (instruction case ReadCell(:final cell) || WriteCell(:final cell)
            when !stackCells.contains(cell)) {
          final shape = layouts.closures.cell(cell.type as CellType);
          if ((cell.type as CellType).isLate) {
            throw UnsupportedError(
              'Native captured late storage is not implemented.',
            );
          }
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
            final placeholder = Block([shape.type, shape.value.type])
                .parameters;
            final write = StoreField(
              shape.value,
              placeholder[0],
              placeholder[1],
            );
            _operands[write] = [cell, value];
            body.add(write);
            aliases.add(instruction);
            _operands[instruction] = [];
          }
          body.add(instruction);
          continue;
        }
        final invocation = switch (instruction) {
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
          ObjectRuntimeType(:final operand, direct: false)
              when operand.type != .nullType &&
                  layouts.representation(operand.type) == .reference =>
            (null, operand, const <ValueType>[]),
          Equals(:final left, :final right)
              when left is! TypeConstant &&
                  left is! ReifyType &&
                  !(left is ObjectRuntimeType && left.direct) &&
                  left.type != .nullType &&
                  right.type != .nullType &&
                  ValueType.typeType.accepts(left.type.nonNullable) =>
            (null, left, const <ValueType>[]),
          _ => null,
        };
        if (invocation != null) {
          final (member, receiver, typeArguments) = invocation;
          final lexical = instruction is FunctionCall;
          final virtual = instruction is! DirectCall;
          final targets = lexical
              ? layouts.closures.targetsFor(instruction)
              : virtual
              ? members.targetsFor(
                  member?.owner ?? receiver.type,
                  member?.selector ?? instruction.objectMember!.selector,
                  hasBuiltin: member == null,
                )
              : {member!.owner!: member};
          if (instruction is Equals) {
            targets[TypeValues.type] = layouts.types.equality;
          } else if (instruction is ObjectRuntimeType && targets.isEmpty) {
            runtimeType(instruction, body);
            body.add(instruction);
            continue;
          }
          final actual = _receiverType(receiver, body);
          final shape = lexical
              ? _load(layouts.closures.tag, receiver, body)
              : virtual
              ? LoadField(TypeValues.shape, actual)
              : null;
          if (shape != null && !lexical) body.add(shape);
          final types = [for (final type in typeArguments) _reify(type, body)];
          final result = instruction.type;
          final join = result == .never
              ? null
              : Block(result == .voidType ? [] : [result]);
          final missing = Block();
          blocks.add(missing);
          switch (instruction) {
            case ObjectRuntimeType():
              instructions[missing] = [];
              ends[missing] = Jump(join!, [actual]);
            case Equals(:final left, :final right, :final negated):
              final identity = Equals(left, right, negated: negated);
              identities.add(identity);
              instructions[missing] = [identity];
              ends[missing] = Jump(join!, [identity]);
            default:
              final invalid = DirectCall(members.invalid, []);
              instructions[missing] = [invalid];
              ends[missing] = Unreachable(invalid);
          }
          var next = block;
          if (member == null && !lexical) {
            final nominal = Block();
            blocks.add(nominal);
            instructions[nominal] = [];
            final kind = LoadField(TypeValues.kind, actual);
            final test = Equals(kind, Constant.integer(TypeKind.nominal.index));
            body.addAll([kind, test]);
            ends[next] = Branch(test, Jump(nominal), Jump(missing));
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
          for (final MapEntry(key: type, value: target) in targets.entries) {
            var current = next;
            if (shape != null) {
              final selected = Block(), otherwise = Block();
              blocks.addAll([selected, otherwise]);
              final test = Equals(
                shape,
                Constant.integer(
                  lexical
                      ? layouts.closures.closures[target]!.tag
                      : layouts.types.id(type),
                ),
              );
              instructions[next]!.add(test);
              ends[next] = Branch(test, Jump(selected), Jump(otherwise));
              instructions[otherwise] = [];
              instructions[selected] = [];
              next = otherwise;
              current = selected;
            }
            void append(Instruction operation) {
              current = appendTo(current, operation, handler);
            }

            final setup = <Instruction>[];
            final closure = lexical ? layouts.closures.closures[target]! : null;
            final parameters =
                closure?.parameters ??
                target.owner?.typeParameters ??
                const <TypeParameterType>[];
            final classTypes = closure != null
                ? [
                    for (final field in closure.environment)
                      _load(field, receiver, setup),
                  ]
                : parameters.isEmpty
                ? <Value>[]
                : _ownerArguments(actual, target.owner!, setup);
            setup.forEach(append);
            final environment = {
              for (final (i, parameter) in parameters.indexed)
                parameter: classTypes[i],
              for (final (i, parameter) in target.typeParameters.indexed)
                parameter: types[i],
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

            for (final (i, parameter) in target.typeParameters.indexed) {
              append(
                DirectCall(casts.bounds(layouts), [
                  types[i],
                  reify(parameter.bound),
                ]),
              );
            }
            final inputs = switch (instruction) {
              InstanceCall(:final positional, :final named) ||
              FunctionCall(
                :final positional,
                :final named,
              ) => target.signature.bind<Value>(
                positional,
                named,
                (i) => members.program.implementationOf(target)!.defaults[i]!,
              ),
              DirectCall(:final inputs) => inputs.skip(1),
              ObjectRuntimeType() => const <Value>[],
              Equals(:final right) => [right],
              _ => throw StateError('Expected a member call.'),
            };
            final arguments = <Value>[receiver];
            if (closure != null) {
              final captures = <Instruction>[];
              for (final field in closure.captures) {
                arguments.add(_load(field, receiver, captures));
              }
              captures.forEach(append);
            }
            for (final (i, value) in inputs.indexed) {
              final destination = target
                  .signature
                  .parameters[i + (target.kind.hasReceiver || lexical ? 0 : 1)];
              if (destination == .never) {
                throw UnsupportedError(
                  'Native Never parameter: ${target.name}',
                );
              }
              final pending = <Instruction>[];
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
              Equals(:final left, :final right, :final negated) => Equals(
                left,
                right,
                negated: negated,
              ),
              _ => throw StateError('Expected a member call.'),
            };
            invocations[call] = target;
            _operands[call] = [...arguments, ...types];
            if (join == null || target.returnType == .never) {
              instructions[current]!.add(call);
              final returned = join == null ? null : Jump(missing);
              ends[current] = handler == null
                  ? returned ?? Unreachable(call)
                  : Invoke(call, onReturn: returned, onThrow: edge(handler));
              continue;
            }
            if (target.returnType == .voidType && result != .voidType) {
              throw UnsupportedError(
                'Native void member result: ${target.name}',
              );
            }
            if (result != .voidType &&
                layouts.representation(result) == .reference &&
                layouts.isBoxable(target.returnType)) {
              _resultTypes[call] = target.returnType;
            }
            append(call);
            final conversions = <Instruction>[];
            final value = result == .voidType
                ? null
                : convert(call, result, conversions);
            conversions.forEach(append);
            ends[current] = Jump(join, [?value]);
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
        if (instruction
            case LoadField(field: final field, :final receiver) ||
                StoreField(field: final field, :final receiver)
            when field.isLate) {
          final (valueField, boundField) = layouts.instances.slots(field);
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

          void append(Instruction operation) =>
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
            final flag = LoadField(boundField, receiver);
            append(flag);
            ends[block] = Branch(flag, Jump(failed), Jump(commit));
            fail(failed, message);
            enter(commit);
          }

          final join = Block(
            instruction is LoadField ? [instruction.type] : [],
          );
          blocks.add(join);
          if (instruction case StoreField(:final value)) {
            final conversions = <Instruction>[];
            var stored = convert(value, field.type, conversions);
            conversions.forEach(append);
            if (field.type.freeTypeParameters.isNotEmpty) {
              final widened = TypeView(stored, .object.nullable);
              append(widened);
              final pending = <Instruction>[];
              final arguments = _ownerArguments(
                _receiverType(receiver, pending),
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
            if (field.isFinal) {
              requireUnbound(
                "Field '${field.name}' has already been initialized.",
              );
            }
            final write = StoreField(valueField, receiver, value);
            _operands[write] = [receiver, stored];
            append(write);
            append(
              StoreField(boundField, receiver, const Constant.boolean(true)),
            );
            ends[block] = Jump(join);
          } else {
            final bound = fresh(), initialize = fresh();
            final flag = LoadField(boundField, receiver);
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
              if (field.isFinal) {
                requireUnbound(
                  "Field '${field.name}' has been assigned during initialization.",
                );
              }
              final write = StoreField(valueField, receiver, value);
              final conversions = <Instruction>[];
              final stored = convert(value, field.type, conversions);
              conversions.forEach(append);
              _operands[write] = [receiver, stored];
              append(write);
              append(
                StoreField(boundField, receiver, const Constant.boolean(true)),
              );
              ends[block] = Jump(join, [value]);
            } else {
              fail(block, "Field '${field.name}' has not been initialized.");
            }
          }
          block = join;
          body = instructions[block] = [instruction];
          aliases.add(instruction);
          _operands[instruction] = join.parameters;
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
            _receiverType(receiver, body),
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
        if (instruction case ReifyType(:final template)) {
          _operands[instruction] = [_reify(template, body)];
        }
        if (instruction is ObjectRuntimeType) runtimeType(instruction, body);
        if (instruction case TypeTest(:final operand, :final testedType)) {
          final kind = tests[instruction] = layouts.typeTest(
            operand.type,
            testedType,
          );
          if (kind == .subtype) {
            final actual = ObjectRuntimeType(operand, direct: true);
            runtimeType(actual, body);
            body.add(actual);
            _operands[instruction] = [actual, _reify(testedType, body)];
          }
        }
        if (instruction
            case TypeCast(:final operand) || NullCheck(:final operand)) {
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
        Return(value: final value?)
            when function.target.returnType != .voidType =>
          Return(convert(value, function.target.returnType, body)),
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
