import 'package:dartc/ir.dart';

import 'flow_value.dart';
import 'function_rewrite.dart';
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
        final removed = <Instruction>{};
        for (final block in function.blocks) {
          for (final operation in [
            ...block.instructions,
            if (block.end case Invoke(:final operation)) operation,
          ]) {
            if (operation case PointerAddress(
              pointer: final PointerFromAddress pointer,
            )) {
              replacements[operation] = pointer.address;
              removed.add(pointer);
            }
          }
        }
        final rewritten = replacements.isEmpty
            ? function
            : FunctionRewrite(
                function,
                replacements: replacements,
                discardable: removed,
              ).run();
        changed |= !identical(function, rewritten);
        functions.add(rewritten);
      }
      return changed
          ? IrProgram(
              program.classes,
              functions,
              globals: program.globals,
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
    final functions = <IrFunction>[];
    for (final function in program.functions) {
      if (!facts.definitions.contains(function.target)) {
        functions.add(function);
        continue;
      }
      final rewritten = simplifyFunction(facts, function);
      changed |= !identical(function, rewritten);
      functions.add(rewritten);
    }
    return changed
        ? IrProgram(
            program.classes,
            functions,
            globals: program.globals,
            externals: program.externals,
          )
        : program;
  }
}

/// Applies the common value and control-flow rewrite to selected executions.
IrFunction simplifyFunction(
  ProgramFlowFacts facts,
  IrFunction function, {
  Set<Object>? activations,
  Set<Instruction> discardable = const {},
  Map<Instruction, Instruction>? instructionSources,
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
  for (final block in function.blocks) {
    final reached = [
      for (final activation in selected)
        if (facts.reachesBlock(block, activation: activation)) activation,
    ];
    if (reached.isEmpty) continue;
    if (block.end case final Throw throwing when throwing.onThrow != null) {
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
  return FunctionRewrite(
    function,
    replacements: replacements,
    nonReturning: nonReturning,
    discardable: removable,
    nonThrowing: nonThrowing,
    directThrows: directThrows,
  ).run(instructionSources: instructionSources);
}
