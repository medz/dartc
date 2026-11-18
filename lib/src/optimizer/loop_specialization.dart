import 'package:dartc/ir.dart';

import 'region_specialization.dart';
import 'program_flow.dart';
import 'program_pass.dart';
import 'loop_ranges.dart';

/// Exposes individual executions of loops with a proven finite integer counter.
///
/// Each peel retains the original loop as its continuation. Fresh shared facts
/// then remove known computation before another execution is exposed. The code
/// growth budget bounds expansion, never the solver or the program's execution.
/// Exit values become block parameters, keeping code after the loop shared.
final class const ProgramLoopSpecialization({final int maxCodeGrowth = 64})
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
        if (maxCodeGrowth != 0 && facts.definitions.contains(function.target)) {
          final originalSize = _size(function);
          ({IrFunction body, int cost, Object key})? selected;
          for (final loop in LoopRanges(function).loops) {
            final entries = loop.entries.where(facts.reachesEdge).toSet();
            if (entries.isEmpty ||
                loop.prove(
                      (value) => switch (facts.valueOf(value).integers) {
                        final range? when range.constant != null => range,
                        _ => null,
                      },
                      (operation) => facts
                          .effectsOf(operation)
                          .every((effect) => effect == .mayThrow),
                    ) ==
                    null) {
              continue;
            }
            final peeled = specializeRegion(
              function,
              loop.header,
              loop.blocks,
              entries,
              executionShapes: facts.program.executionShapes,
            );
            final growth = _size(peeled) - originalSize;
            final cost = growth < 0 ? 0 : growth;
            final key = regionExpansionKey(function, loop.header, entries);
            if (!budget.permits(function.target, key, cost)) continue;
            if (selected == null || cost < selected.cost) {
              selected = (body: peeled, cost: cost, key: key);
            }
          }
          if (selected != null) {
            rewritten = selected.body;
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

int _size(IrFunction function) => function.blocks.fold(
  0,
  (size, block) =>
      size + block.parameters.length + block.instructions.length + 1,
);
