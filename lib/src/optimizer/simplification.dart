import 'package:dartc/ir.dart';

import 'flow_value.dart';
import 'trace_demand.dart';
import 'function_rewrite.dart';
import 'loop_ranges.dart';
import 'program_flow.dart';
import 'program_pass.dart';

/// Replaces proven values and removes computations without execution obligations.
final class const ProgramSimplification() extends ProgramPass {
  @override
  ProgramTransform bind() => ProgramTransform(
    run,
    normalize: (program) {
      final functions = <IrFunction>[];
      var changed = false;
      for (final function in program.functions) {
        final replacements = <Value, Value>{};
        final operations = <Instruction, Instruction>{};
        final removed = <Instruction>{};
        final terminators = <Block, Terminator>{};
        final expressions = <Object, List<Instruction>>{};
        late final dominance = ValueDominance(function);
        final pending = [function.entry], visited = <Block>{};
        while (pending.isNotEmpty) {
          final block = pending.removeLast();
          if (!visited.add(block)) continue;
          // These decisions hold for every legal invocation, before any call
          // closure exists. Do not expand implementation bodies behind a
          // syntactically unreachable edge.
          if (block.end case Branch(
            condition: ScalarConstant(value: final bool condition),
            :final ifTrue,
            :final ifFalse,
          )) {
            final selected = condition ? ifTrue : ifFalse;
            terminators[block] = selected;
            pending.add(selected.target);
          } else {
            pending.addAll(block.successors.map((edge) => edge.target));
          }
          if (block.end case Branch(
            condition: final TypeTest test,
            :final ifTrue,
            :final ifFalse,
          )) {
            Jump narrow(Jump edge, bool outcome) {
              final value = test.refinement(outcome);
              if (value == null) return edge;
              final arguments = [
                for (final (index, argument) in edge.arguments.indexed)
                  if (identical(argument, test.operand) &&
                      edge.target.parameters[index].type.accepts(value.type))
                    value
                  else
                    argument,
              ];
              return arguments.indexed.any(
                    (entry) => !identical(entry.$2, edge.arguments[entry.$1]),
                  )
                  ? Jump(edge.target, arguments)
                  : edge;
            }

            final yes = narrow(ifTrue, true), no = narrow(ifFalse, false);
            if (!identical(yes, ifTrue) || !identical(no, ifFalse)) {
              terminators[block] = Branch(test, yes, no);
            }
          }
          for (final operation in [
            ...block.instructions,
            if (block.end case Invoke(:final operation)) operation,
          ]) {
            // A widening view changes a static interface, not the value being
            // tested. Preserve the producer's proof before type lowering picks
            // a runtime implementation from a broader declaration.
            switch (operation) {
              case TypeTest(:final operand, :final testedType, :final negated):
                final input = _unviewed(operand);
                if (!identical(input, operand)) {
                  operations[operation] = TypeTest(
                    input,
                    testedType,
                    negated: negated,
                  );
                }
              case ObjectRuntimeType(:final operand, :final direct):
                final input = _unviewed(operand);
                if (!identical(input, operand)) {
                  operations[operation] = ObjectRuntimeType(
                    input,
                    direct: direct,
                  );
                }
              default:
                break;
            }
            if (operation case PointerAddress(
              pointer: final PointerFromAddress pointer,
            )) {
              replacements[operation] = pointer.address;
              removed.add(pointer);
              continue;
            }
            final key = _expression(operation, replacements);
            if (key == null) continue;
            final previous = expressions.putIfAbsent(key, () => []);
            final shared = previous
                .where((value) => dominance.before(value, operation))
                .firstOrNull;
            if (shared != null) {
              replacements[operation] = shared;
              removed.add(operation);
            } else {
              previous.add(operation);
            }
          }
        }
        final rewritten =
            replacements.isEmpty && operations.isEmpty && terminators.isEmpty
            ? function
            : FunctionRewrite(
                function,
                executionShapes: program.executionShapes,
                replacements: replacements,
                operations: operations,
                discardable: removed,
                terminators: terminators,
              ).run();
        changed |= !identical(function, rewritten);
        functions.add(rewritten);
      }
      return changed
          ? IrProgram(
              program.classes,
              functions,
              globals: program.globals,
              nativeBoundaries: program.nativeBoundaries,
              executionShapes: program.executionShapes,
              externals: program.externals,
            )
          : program;
    },
  );

  @override
  IrProgram run(ProgramFlowFacts facts) {
    final program = facts.program;
    facts.checkProgram(program);
    var changed = false;
    final traces = demandedTraces(facts);
    final functions = <IrFunction>[];
    for (final function in program.functions) {
      if (!facts.definitions.contains(function.target)) {
        functions.add(function);
        continue;
      }
      final rewritten = simplifyFunction(
        facts,
        function,
        demandedTraces: traces,
      );
      changed |= !identical(function, rewritten);
      functions.add(rewritten);
    }
    return changed
        ? IrProgram(
            program.classes,
            functions,
            globals: program.globals,
            nativeBoundaries: program.nativeBoundaries,
            executionShapes: program.executionShapes,
            externals: program.externals,
          )
        : program;
  }
}

Value _unviewed(Value value) {
  while (true) {
    final operand = switch (value) {
      TypeView(:final operand) || UncheckedCast(:final operand)
          when value.type.accepts(operand.type) =>
        operand,
      _ => null,
    };
    if (operand == null) return value;
    value = operand;
  }
}

Object? _expression(Instruction operation, Map<Value, Value> replacements) {
  if (operation.effects.isNotEmpty) return null;
  final properties = switch (operation) {
    IntBinary(:final operator, :final checked) => (operator, checked),
    NumericBinary(:final operator) => operator,
    Equals(:final negated) => negated,
    FloatBitCast(:final width) => width,
    NumericRoundToDouble(:final rounding) => rounding,
    RecordGet(:final slot) => slot,
    TypeTest(:final testedType, :final negated) => (testedType, negated),
    Identical() ||
    NumericNegate() ||
    NumericToDouble() ||
    NumericSquareRoot() ||
    TypeView() ||
    UncheckedCast() ||
    PointerAddress() => (),
    _ => null,
  };
  if (properties == null) return null;
  Object? inputs;
  for (var value in operation.inputs) {
    while (replacements.containsKey(value)) {
      value = replacements[value]!;
    }
    inputs = (inputs, value is Constant ? value.structuralKey : value);
  }
  return (operation.runtimeType, operation.type, properties, inputs);
}

/// Applies the common value and control-flow rewrite to selected executions.
IrFunction simplifyFunction(
  ProgramFlowFacts facts,
  IrFunction function, {
  Set<Object>? activations,
  Set<Instruction> discardable = const {},
  Map<Instruction, Instruction>? instructionSources,
  Set<Throw>? demandedTraces,
}) {
  facts.checkProgram(facts.program);
  if (!identical(facts.program.implementationOf(function.target), function)) {
    throw ArgumentError('Simplification requires the analyzed function.');
  }
  if (activations != null && activations.isEmpty) {
    throw ArgumentError('Simplification requires at least one execution.');
  }
  final selected = <Object?>[...?activations, if (activations == null) null];
  FlowValue valueOf(Value value, List<Object?> executions) => executions.fold(
    const FlowValue.bottom(),
    (result, activation) =>
        result.join(facts.valueOf(value, activation: activation)),
  );
  Set<Value> equivalentsOf(Value value, List<Object?> executions) {
    Set<Value>? common;
    for (final activation in executions) {
      if (facts.valueOf(value, activation: activation).isBottom) continue;
      final local = facts.equivalentsOf(value, activation: activation);
      common = common == null ? local : common.intersection(local);
    }
    return common ?? const {};
  }

  final dominance = ValueDominance(function);
  final order = <Value, int>{};
  for (final block in function.blocks) {
    for (final value in <Value>[
      ...block.parameters,
      ...block.instructions,
      if (block.end case Invoke(:final operation)) operation,
    ]) {
      order[value] = order.length;
    }
  }
  final replacements = <Value, Value>{};
  final nonReturning = <Instruction>{};
  final removable = {...discardable};
  final nonThrowing = <Instruction>{};
  final directThrows = <Throw>{};
  final terminators = <Block, Terminator>{};
  for (final block in function.blocks) {
    final reached = [
      for (final activation in selected)
        if (facts.reachesBlock(block, activation: activation)) activation,
    ];
    if (reached.isEmpty) continue;
    if (block.end case final Throw throwing
        when throwing.isRecorded &&
            throwing.stackTrace != null &&
            demandedTraces != null &&
            !demandedTraces.contains(throwing)) {
      terminators[block] = Throw.recorded(
        throwing.exception,
        null,
        onThrow: throwing.onThrow,
      );
    }
    if ((terminators[block] ?? block.end) case final Throw throwing
        when throwing.onThrow != null) {
      final exception = valueOf(throwing.exception, reached);
      // Unknown class bounds can admit Error subclasses through interfaces.
      if (throwing.isRecorded ||
          !exception.isBottom &&
              exception.unknownTypes.every(
                (bound) => [
                  ValueType.number,
                  ValueType.boolean,
                  ValueType.string,
                ].any((scalar) => scalar.accepts(bound)),
              ) &&
              !exception.types.any(ValueType.error.accepts)) {
        directThrows.add(throwing);
      }
    }
    for (final value in <Value>[
      ...block.parameters,
      ...block.instructions,
      if (block.end case Invoke(:final operation)) operation,
    ]) {
      final executions = [
        for (final activation in reached)
          if (value is! Instruction ||
              facts.reachesOperation(value, activation: activation))
            activation,
      ];
      if (executions.isEmpty) continue;
      if (valueOf(value, executions).constant case final constant?
          when value.type.accepts(constant.type)) {
        replacements[value] = constant;
      } else {
        for (final alternative in equivalentsOf(value, executions)) {
          if (identical(alternative, value) ||
              !value.type.accepts(alternative.type) ||
              !dominance.before(alternative, value)) {
            continue;
          }
          if (alternative is! Constant &&
              dominance.before(value, alternative) &&
              order[alternative]! >= order[value]!) {
            continue;
          }
          replacements[value] = alternative;
          break;
        }
      }
      if (value is Instruction) {
        if (executions.every(
          (activation) => facts.canDiscard(value, activation: activation),
        )) {
          removable.add(value);
        }
        final exits = [
          for (final activation in executions)
            facts.exitsOf(value, activation: activation),
        ];
        if (exits.every((exit) => !exit.normal)) nonReturning.add(value);
        if (exits.every((exit) => !exit.exceptional)) nonThrowing.add(value);
      }
    }
  }
  // Value equivalence is not a proof that an unchecked descriptor satisfies a
  // binder's bound. Keep the semantic checkpoint while the body depends on it;
  // complete literal evidence can still remove the check through the verifier.
  for (final binding in function.typeBindings) {
    if (binding.check.inputs.any((input) => input is! TypeConstant)) {
      replacements.remove(binding.value);
    }
  }
  late final liveness = ValueLiveness.source(function);
  for (final loop in LoopRanges(function).loops) {
    final proof = loop.prove(
      (value) => valueOf(value, selected).integers,
      (operation) => selected.every(
        (activation) => facts
            .effectsOf(operation, activation: activation)
            .every((effect) => effect == .mayThrow),
      ),
    );
    final exit = proof?.discardedExit(liveness, removable.contains);
    if (exit != null) terminators[loop.header] = exit;
  }
  return FunctionRewrite(
    function,
    executionShapes: facts.program.executionShapes,
    replacements: replacements,
    nonReturning: nonReturning,
    discardable: removable,
    nonThrowing: nonThrowing,
    directThrows: directThrows,
    terminators: terminators,
  ).run(instructionSources: instructionSources);
}
