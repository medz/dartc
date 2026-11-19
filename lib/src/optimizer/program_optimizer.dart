import 'package:dartc/ir.dart';

import 'program_flow.dart';
import 'memory_layout.dart';
import 'program_pass.dart';

/// Runs semantic passes with fresh facts after every program change.
///
/// Keeps an unspecialized implementation graph while optimizing a candidate.
/// New source-site realizations discard the entire candidate and its facts;
/// roots, recursive bodies and shared callers are reanalyzed from that graph.
/// Semantic passes retain their supplied order and compilation-wide budgets.
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
  /// [initialMemory] binds stable native getters to their actual entry bytes.
  ProgramFlowFacts run(
    IrProgram program,
    Iterable<FlowEntry> entries, {
    Iterable<FunctionTarget> openEntries = const [],
    Iterable<FunctionTarget> escapingReturns = const [],
    Map<NativeCallbackTarget, FunctionTarget> nativeEntries = const {},
    FlowMemoryLayout Function(IrProgram)? memoryLayoutFor,
    FunctionTarget? allocationFailure,
    FunctionTarget? managedAllocator,
    Map<FunctionTarget, List<int?>> initialMemory = const {},
  }) {
    var initial = [
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
    final memory = Map<FunctionTarget, List<int?>>.unmodifiable({
      for (final entry in initialMemory.entries)
        entry.key: List<int?>.unmodifiable(entry.value),
    });
    ProgramFlowFacts analyze(IrProgram input) => ProgramFlow(
      input,
      initial,
      openEntries: open,
      escapingReturns: escaping,
      nativeEntries: callbacks,
      memoryLayout: memoryLayoutFor?.call(input),
      allocationFailure: allocationFailure,
      managedAllocator: managedAllocator,
      initialMemory: memory,
    ).facts;
    final stages = [
      for (final pass in passes) (kind: pass.kind, run: pass.bind()),
    ];
    final realized = <Object, ProgramRealization>{};
    List<ProgramRealization> discoverRealizations(ProgramTransform transform) {
      final added = <ProgramRealization>[];
      for (final recipe in transform.realizations) {
        if (!realized.containsKey(recipe.key)) {
          realized[recipe.key] = recipe;
          added.add(recipe);
        }
      }
      return added;
    }

    final sourceStages = stages.where((stage) => stage.kind != .lowering).toList();
    final loweringStages = stages.where((stage) => stage.kind == .lowering).toList();
    IrProgram normalize(IrProgram input) {
      while (true) {
        // Materializing captures can hide lexical calls and prevent SSA promotion.
        // Exhaust source-level normalization before choosing physical storage.
        bool changed;
        do {
          changed = false;
          for (final stage in sourceStages) {
            final next = stage.run.normalize(input);
            changed |= !identical(next, input);
            input = next;
          }
        } while (changed);
        final source = input;
        for (final stage in loweringStages) {
          input = stage.run.normalize(input);
        }
        if (identical(input, source)) return input;
      }
    }

    var facts = analyze(normalize(program));
    bool apply(ProgramTransform transform) {
      final before = facts.program;
      final after = transform(facts);
      facts.checkProgram(before);
      var changed = !identical(before, after);
      for (var index = 0; index < initial.length; index++) {
        final entry = initial[index];
        final arguments = entry.arguments.map(transform.rebindEntry).toList();
        if (arguments.indexed.any(
          (argument) => !identical(argument.$2, entry.arguments[argument.$1]),
        )) {
          initial[index] = (target: entry.target, arguments: arguments);
          changed = true;
        }
      }
      if (!changed) return false;
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

    void closeImplementations() {
      bool lowered;
      do {
        lowered = false;
        final recipes = <ProgramRealization>[];
        void flush() {
          if (recipes.isEmpty) return;
          final before = facts.program;
          for (final stage in stages) {
            stage.run.rebase(before);
          }
          var after = before;
          for (final recipe in recipes) {
            after = recipe.apply(after);
          }
          recipes.clear();
          if (identical(before, after)) {
            throw StateError(
              'Canonical source recipes did not realize the requested implementation.',
            );
          }
          lowered = true;
          facts = analyze(normalize(after));
        }

        for (final stage in stages) {
          if (stage.kind != .lowering || stage.run.requiresRetainedUse) continue;
          if (!stage.run.isReplayable) {
            flush();
            lowered |= apply(stage.run);
            continue;
          }
          // Every owner observes this same graph and its actual demand. Only
          // canonical recipes are composed; no changed graph consumes facts
          // from a previous member of the batch.
          final before = facts.program;
          final after = stage.run(facts);
          facts.checkProgram(before);
          final added = discoverRealizations(stage.run);
          if (!identical(before, after)) {
            if (added.isEmpty) {
              throw StateError(
                'An implementation change requires a new canonical source recipe.',
              );
            }
            recipes.addAll(added);
          }
        }
        flush();
      } while (lowered);
    }

    closeImplementations();
    var canonical = facts.program;
    List<FlowEntry> savedEntries() => [
      for (final entry in initial)
        (target: entry.target, arguments: List.unmodifiable(entry.arguments)),
    ];
    var canonicalEntries = savedEntries();
    while (true) {
      optimize();
      final recipes = <ProgramRealization>[];
      for (final stage in stages) {
        if (stage.kind != .lowering) continue;
        // Discovery may create templates, but the changed candidate is never
        // solved with bodies specialized before those calls existed.
        final before = facts.program;
        final after = stage.run(facts);
        facts.checkProgram(before);
        final added = discoverRealizations(stage.run);
        if (identical(before, after)) continue;
        if (added.isEmpty) {
          throw StateError(
            'An implementation change requires a new canonical source recipe. '
            'Repeated or unmapped realization cannot reuse specialized bodies.',
          );
        }
        recipes.addAll(added);
      }
      if (recipes.isEmpty) return facts;
      for (final bound in stages) {
        bound.run.rebase(canonical);
      }
      for (final recipe in recipes) {
        canonical = recipe.apply(canonical);
      }
      // These are the original supplied entry values with identity-only
      // rebinding, never invocation values collected from candidate facts.
      initial = [
        for (final entry in canonicalEntries)
          (target: entry.target, arguments: List.of(entry.arguments)),
      ];
      facts = analyze(normalize(canonical));
      closeImplementations();
      canonical = facts.program;
      canonicalEntries = savedEntries();
    }
  }
}
