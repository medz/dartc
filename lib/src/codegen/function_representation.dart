import 'package:dartc/ir.dart';

import 'program_layout.dart';
import 'checked_casts.dart';
import 'type_values.dart';

/// Places allocating representation changes before register and root analysis.
final class FunctionRepresentation(
  final IrFunction function,
  final ProgramLayout layouts,
  CheckedCasts casts, {
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

  List<Value> argumentsOf(Jump edge) => _arguments[edge] ?? edge.arguments;

  Iterable<Jump> successors(Block block) => switch (ends[block]!) {
    final Jump jump => [jump],
    Branch(:final ifTrue, :final ifFalse) => [ifTrue, ifFalse],
    Invoke(:final onReturn, :final onThrow) => [?onReturn, onThrow],
    Throw(:final onThrow) ||
    ExhaustivenessFailure(:final onThrow) => [?onThrow],
    _ => block.successors,
  };

  this {
    bool needsBox(Value value, ValueType type) {
      if (value is TestedValue) value = value.test.operand;
      return value is! Constant &&
          (value.type == .integer || value.type == .floating) &&
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

    blocks.addAll(function.blocks);
    for (final block in function.blocks) {
      final body = instructions[block] = <Instruction>[];
      final source = switch (block.end) {
        Invoke(:final operation) => block.instructions.followedBy([operation]),
        _ => block.instructions,
      };
      for (final instruction in source) {
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
          if (block.end
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
      ends[block] ??= switch (block.end) {
        Return(value: final value?)
            when function.target.returnType != .voidType =>
          Return(convert(value, function.target.returnType, body)),
        final Jump jump => edge(jump),
        Branch(:final condition, :final ifTrue, :final ifFalse) => Branch(
          condition,
          edge(ifTrue),
          edge(ifFalse),
        ),
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
    }
    instructions[function.entry]!.insertAll(0, _prologue);
  }
}
