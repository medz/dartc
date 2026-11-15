import 'package:dartc/ir.dart';

import 'function_rewrite.dart';
import 'program_flow.dart';
import 'program_pass.dart';

/// Replaces proven values and removes computations without execution obligations.
final class const ProgramSimplification() extends ProgramPass {
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
      final discardable = <Instruction>{};
      final nonThrowing = <Instruction>{};
      final directThrows = <Throw>{};
      for (final block in function.blocks) {
        if (!facts.reachesBlock(block)) continue;
        if (block.end case final Throw throwing when throwing.onThrow != null) {
          final exception = facts.valueOf(throwing.exception);
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
          if (value is Instruction && !facts.reachesOperation(value)) continue;
          if (facts.valueOf(value).constant case final constant?
              when value.type.accepts(constant.type)) {
            replacements[value] = constant;
          } else {
            for (final alternative in facts.equivalentsOf(value)) {
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
            if (facts.canDiscard(value)) discardable.add(value);
            final exits = facts.exitsOf(value);
            if (!exits.normal) nonReturning.add(value);
            if (!exits.exceptional) nonThrowing.add(value);
          }
        }
      }
      final rewritten = FunctionRewrite(
        function,
        replacements: replacements,
        nonReturning: nonReturning,
        discardable: discardable,
        nonThrowing: nonThrowing,
        directThrows: directThrows,
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
  }
}
