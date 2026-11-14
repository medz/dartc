import 'package:dartc/ir.dart';

import 'program_flow.dart';
import 'memory_layout.dart';
import 'program_pass.dart';

/// Runs semantic passes with fresh facts after every program change.
///
/// The caller supplies the pipeline order. Shrinking passes converge together
/// before and after each expansion. Pass state belongs to one compilation, so
/// later rounds use new facts while retaining spent expansion budgets.
/// Retained definitions never become new entry points.
final class ProgramOptimizer(Iterable<ProgramPass> passes) {
  /// The execution order, including each pass's convergence policy.
  final List<ProgramPass> passes = .unmodifiable(passes);

  /// Optimizes [program] under the supplied semantic and open-entry contracts.
  ///
  /// Returns stable facts bound to the final program. Rewriting always restarts
  /// analysis from [entries] and [openEntries], never from the old call closure.
  /// [memoryLayoutFor] selects storage for each graph being analyzed; a rewrite
  /// must not silently reuse the replaced graph's layout decisions.
  ProgramFlowFacts run(
    IrProgram program,
    Iterable<FlowEntry> entries, {
    Iterable<FunctionTarget> openEntries = const [],
    Iterable<FunctionTarget> escapingReturns = const [],
    FlowMemoryLayout Function(IrProgram)? memoryLayoutFor,
  }) {
    final initial = [
      for (final entry in entries)
        (
          target: entry.target,
          arguments: List.of(entry.arguments, growable: false),
        ),
    ];
    final open = Set<FunctionTarget>.unmodifiable(openEntries);
    final escaping = Set<FunctionTarget>.unmodifiable(escapingReturns);
    ProgramFlowFacts analyze(IrProgram input) => ProgramFlow(
      input,
      initial,
      openEntries: open,
      escapingReturns: escaping,
      memoryLayout: memoryLayoutFor?.call(input),
    ).facts;
    var facts = analyze(program);
    final stages = [
      for (final pass in passes) (expands: pass.expandsCode, run: pass.bind()),
    ];
    bool apply(ProgramTransform transform) {
      final before = facts.program;
      final after = transform(facts);
      facts.checkProgram(before);
      if (identical(before, after)) return false;
      facts = analyze(after);
      return true;
    }

    bool converge(List<ProgramTransform> reductions) {
      var progress = false;
      bool changed;
      do {
        changed = false;
        for (final transform in reductions) {
          changed |= apply(transform);
        }
        progress |= changed;
      } while (changed);
      return progress;
    }

    bool changed;
    do {
      changed = false;
      final reductions = <ProgramTransform>[];
      for (final stage in stages) {
        if (stage.expands) {
          changed |= converge(reductions);
          changed |= apply(stage.run);
        } else {
          reductions.add(stage.run);
        }
      }
      changed |= converge(reductions);
    } while (changed);
    return facts;
  }
}
