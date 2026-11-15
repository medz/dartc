import 'package:dartc/ir.dart';

import 'program_flow.dart';
import 'memory_layout.dart';
import 'program_pass.dart';

/// Runs semantic passes with fresh facts after every program change.
///
/// Semantic passes retain their supplied order and converge before lowerings.
/// Each lowering reenters semantic optimization with the same pass instances and
/// budgets. New implementation dependencies receive fresh facts before emission.
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
  /// [allocationFailure] supplies the same ordinary failure body used by target
  /// allocation; its exception values and state remain visible to handlers.
  ProgramFlowFacts run(
    IrProgram program,
    Iterable<FlowEntry> entries, {
    Iterable<FunctionTarget> openEntries = const [],
    Iterable<FunctionTarget> escapingReturns = const [],
    Map<NativeCallbackTarget, FunctionTarget> nativeEntries = const {},
    FlowMemoryLayout Function(IrProgram)? memoryLayoutFor,
    FunctionTarget? allocationFailure,
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
    final callbacks = Map<NativeCallbackTarget, FunctionTarget>.unmodifiable(
      nativeEntries,
    );
    ProgramFlowFacts analyze(IrProgram input) => ProgramFlow(
      input,
      initial,
      openEntries: open,
      escapingReturns: escaping,
      nativeEntries: callbacks,
      memoryLayout: memoryLayoutFor?.call(input),
      allocationFailure: allocationFailure,
    ).facts;
    final stages = [
      for (final pass in passes) (kind: pass.kind, run: pass.bind()),
    ];
    IrProgram normalize(IrProgram input) {
      bool changed;
      do {
        changed = false;
        for (final stage in stages) {
          final next = stage.run.normalize(input);
          changed |= !identical(next, input);
          input = next;
        }
      } while (changed);
      return input;
    }

    var facts = analyze(normalize(program));
    bool apply(ProgramTransform transform) {
      final before = facts.program;
      final after = transform(facts);
      facts.checkProgram(before);
      if (identical(before, after)) return false;
      facts = analyze(normalize(after));
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

    void optimize() {
      bool changed;
      do {
        changed = false;
        final reductions = <ProgramTransform>[];
        for (final stage in stages) {
          switch (stage.kind) {
            case .expansion:
              changed |= converge(reductions);
              changed |= apply(stage.run);
            case .reduction:
              reductions.add(stage.run);
            case .lowering:
              break;
          }
        }
        changed |= converge(reductions);
      } while (changed);
    }

    optimize();
    bool lowered;
    do {
      lowered = false;
      for (final stage in stages) {
        if (stage.kind == .lowering && apply(stage.run)) {
          lowered = true;
          optimize();
        }
      }
    } while (lowered);
    return facts;
  }
}
