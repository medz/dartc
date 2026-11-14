import 'package:dartc/ir.dart';

import 'program_flow.dart';
import 'memory_layout.dart';
import 'program_pass.dart';

/// Runs semantic passes with fresh facts after every program change.
///
/// The caller supplies the pipeline order. Shrinking passes converge together
/// before and after each expansion; expansion budgets are spent only once.
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
    final reductions = <ProgramPass>[];
    bool apply(ProgramPass pass) {
      final before = facts.program;
      final after = pass.run(facts);
      facts.checkProgram(before);
      if (identical(before, after)) return false;
      facts = analyze(after);
      return true;
    }

    void converge() {
      bool changed;
      do {
        changed = false;
        for (final pass in reductions) {
          changed |= apply(pass);
        }
      } while (changed);
    }

    for (final pass in passes) {
      if (pass.repeatUntilStable) {
        reductions.add(pass);
      } else {
        converge();
        apply(pass);
      }
    }
    converge();
    return facts;
  }
}
