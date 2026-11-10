import 'package:dartc/ir.dart';

import 'program_layout.dart';

/// Places allocating representation changes before register and root analysis.
final class FunctionRepresentation(
  final IrFunction function,
  final ProgramLayout layouts, {
  FunctionTarget? captureTrace,
}) {
  final blocks = <Block>[];
  final instructions = <Block, List<Instruction>>{};
  final ends = <Block, Terminator>{};
  final _operands = <Instruction, List<Value>>{};
  final boxes = <Instruction, Value>{};
  final introduced = <Instruction>{};
  late final entryParameters = function.target.typeParameters.isEmpty
      ? function.entry.parameters
      : [
          ...function.entry.parameters,
          ...Block(
            layouts
                .entryTypes(function.target)
                .skip(function.entry.parameters.length),
          ).parameters,
        ];

  List<BlockParameter> parametersOf(Block block) =>
      block == function.entry ? entryParameters : block.parameters;

  Value _reify(ValueType type, List<Instruction> into) {
    final index = type is TypeParameterType
        ? function.target.typeParameters.indexOf(type)
        : -1;
    if (index >= 0) {
      return entryParameters[function.entry.parameters.length + index];
    }
    if (type.freeTypeParameters.isEmpty) return layouts.types.constant(type);
    final (:target, :parameters) = layouts.types.instantiate(type);
    if (!parameters.every(function.target.typeParameters.contains)) {
      throw UnsupportedError('Native type requires a class environment: $type');
    }
    final call = DirectCall(target, [
      for (final parameter in parameters) _reify(parameter, into),
    ]);
    into.add(call);
    return call;
  }

  Iterable<Value> inputsOf(Instruction instruction) =>
      _operands[instruction] ?? instruction.inputs;

  Iterable<Jump> successors(Block block) => switch (ends[block]!) {
    final Jump jump => [jump],
    Branch(:final ifTrue, :final ifFalse) => [ifTrue, ifFalse],
    Invoke(:final onReturn, :final onThrow) => [?onReturn, onThrow],
    Throw(:final onThrow) ||
    ExhaustivenessFailure(:final onThrow) => [?onThrow],
    _ => block.successors,
  };

  this {
    bool needsBox(Value value, ValueType type) =>
        value is! Constant &&
        (value.type == .integer || value.type == .floating) &&
        layouts.representation(type) == .reference;

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

    Jump edge(Jump jump) {
      if (!jump.arguments.indexed.any(
        (item) => needsBox(item.$2, jump.target.parameters[item.$1].type),
      )) {
        return jump;
      }
      // Keep conversions on their chosen edge and refinements on the source edge.
      final block = Block(jump.arguments.map((v) => v.type));
      blocks.add(block);
      final body = instructions[block] = <Instruction>[];
      final arguments = [
        for (final (i, value) in block.parameters.indexed)
          convert(value, jump.target.parameters[i].type, body),
      ];
      ends[block] = Jump(jump.target, arguments);
      block.finish(ends[block]!);
      return Jump(block, jump.arguments);
    }

    blocks.addAll(function.blocks);
    for (final block in function.blocks) {
      final body = instructions[block] = <Instruction>[];
      final source = switch (block.end) {
        Invoke(:final operation) => block.instructions.followedBy([operation]),
        _ => block.instructions,
      };
      for (final instruction in source) {
        if (instruction case ReifyType(:final template)) {
          _operands[instruction] = [_reify(template, body)];
        }
        if (instruction case TypeView(:final operand, :final type)
            when needsBox(operand, type)) {
          boxes[instruction] = operand;
        }
        final destinations = switch (instruction) {
          DirectCall(:final target) => layouts.entryTypes(target),
          Construct(:final initializer) => initializer.signature.parameters,
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
            if (instruction case DirectCall(:final typeArguments))
              for (final type in typeArguments) _reify(type, body),
          ];
          var changed =
              instruction is DirectCall && instruction.typeArguments.isNotEmpty;
          for (final (i, input) in inputs.indexed) {
            final value = convert(input, destinations[i], body);
            changed |= value != input;
            inputs[i] = value;
          }
          if (changed) _operands[instruction] = inputs;
        }
        body.add(instruction);
      }
      ends[block] = switch (block.end) {
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
  }
}
