import 'package:dartc/ir.dart';

import 'flow_value.dart';
import 'program_flow.dart';
import 'program_pass.dart';
import 'region_specialization.dart';

/// Exposes known type-test outcomes without joining unrelated incoming values.
final class const ProgramBranchSpecialization({final int maxCodeGrowth = 64})
    extends ProgramPass {
  @override
  ProgramPassKind get kind => .expansion;

  @override
  IrProgram run(ProgramFlowFacts facts) => bind()(facts);

  @override
  ProgramTransform bind() {
    RangeError.checkNotNegative(maxCodeGrowth, 'maxCodeGrowth');
    final budget = ProgramExpansionBudget(maxCodeGrowth);
    return ProgramTransform((facts) {
      facts.checkProgram(facts.program);
      var changed = false;
      final functions = <IrFunction>[];
      for (final function in facts.program.functions) {
        var rewritten = function;
        if (maxCodeGrowth > 0 && facts.definitions.contains(function.target)) {
          final dominance = ValueDominance(function);
          final candidates =
              <
                ({
                  Block header,
                  Set<Block> region,
                  Jump edge,
                  int cost,
                  Object key,
                })
              >[];
          for (final header in function.blocks) {
            if (header.end case Branch(condition: final TypeTest test)
                when test.operand is BlockParameter &&
                    header.parameters.contains(test.operand) &&
                    header.instructions.contains(test) &&
                    test.testedType.freeTypeParameters.isEmpty &&
                    facts.valueOf(test).constant == null) {
              final region = {
                header,
                for (final block in function.blocks)
                  if (dominance.atEntry(test.operand, block)) block,
              };
              final cost = region.fold(
                0,
                (sum, block) =>
                    sum +
                    block.parameters.length +
                    block.instructions.length +
                    1,
              );
              final slot = header.parameters.indexOf(
                test.operand as BlockParameter,
              );
              for (final owner in function.blocks) {
                if (region.contains(owner)) continue;
                for (final edge in owner.successors) {
                  if (edge.target != header || !facts.reachesEdge(edge)) {
                    continue;
                  }
                  final value = _incoming(facts, owner, edge.arguments[slot]);
                  final checked = value.check(
                    test.testedType,
                    runtimeTypes: true,
                  );
                  if (!value.isBottom &&
                      (!checked.mayFail || checked.value.isBottom)) {
                    final key = regionExpansionKey(function, header, {edge});
                    if (!budget.permits(function.target, key, cost)) continue;
                    candidates.add((
                      header: header,
                      region: region,
                      edge: edge,
                      cost: cost,
                      key: key,
                    ));
                  }
                }
              }
            }
          }
          if (candidates.isNotEmpty) {
            candidates.sort((a, b) => a.cost.compareTo(b.cost));
            final selected = candidates.first;
            rewritten = specializeRegion(
              function,
              selected.header,
              selected.region,
              {selected.edge},
              executionShapes: facts.program.executionShapes,
            );
            budget.charge(function.target, selected.key, selected.cost);
            changed = true;
          }
        }
        functions.add(rewritten);
      }
      return changed
          ? IrProgram(
              facts.program.classes,
              functions,
              globals: facts.program.globals,
              nativeBoundaries: facts.program.nativeBoundaries,
              executionShapes: facts.program.executionShapes,
              externals: facts.program.externals,
            )
          : facts.program;
    });
  }
}

FlowValue _incoming(ProgramFlowFacts facts, Block owner, Value value) {
  if (value is! UnwindValue) return facts.valueOf(value);
  return switch (owner.end) {
    Invoke(:final operation) =>
      value == UnwindValue.exception
          ? facts.failureOf(operation).exception
          : facts.failureOf(operation).stackTrace,
    Throw(:final exception, :final stackTrace) =>
      value == UnwindValue.exception
          ? facts.valueOf(exception)
          : stackTrace == null
          ? FlowValue.unknown(.stackTrace)
          : facts.valueOf(stackTrace),
    _ => FlowValue.unknown(value.type),
  };
}
