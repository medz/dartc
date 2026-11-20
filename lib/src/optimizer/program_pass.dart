import 'package:dartc/ir.dart';

import 'program_flow.dart';
import 'flow_value.dart';

/// A stable implementation choice reconstructed in the current semantic graph.
///
/// The owning lowerer must use actual source operations, operands, lexical types
/// and continuations from [apply]'s argument. Candidate SSA values, flow facts
/// and narrowed invocation snapshots cannot be retained in this recipe. A
/// context-specific choice must preserve its origin path, or the owner must
/// establish that applying it to the shared source site preserves all inputs.
final class ProgramRealization(
  final Object key,
  final IrProgram Function(IrProgram) apply,
);

/// One compilation's transforms, sharing their bounded work state.
final class ProgramTransform(
  final IrProgram Function(ProgramFlowFacts) _run, {
  IrProgram Function(IrProgram)? normalize,
  this.requiresRetainedUse = false,
  Constant Function(Constant)? rebindEntryConstant,
  Iterable<ProgramRealization> Function()? realizations,
  void Function(IrProgram)? rebase,
}) {
  /// Discover this replayable implementation after eliminating unobserved uses.
  /// Replaying a retained site restores its full effects on the canonical graph.
  final bool requiresRetainedUse;

  final _normalize = normalize;
  final _rebindEntryConstant = rebindEntryConstant;
  final _realizations = realizations;
  final _rebase = rebase;

  /// Available source-site implementations; registering one creates no roots.
  Iterable<ProgramRealization> get realizations =>
      _realizations?.call() ?? const [];

  /// Whether every implementation change has an owner-supplied source recipe.
  /// This allows discovery on one immutable graph before applying a batch.
  bool get isReplayable => _realizations != null;

  /// Invalidates graph-owned installation caches after discarding a candidate.
  /// Compilation-wide identities and expansion accounting must remain intact.
  void rebase(IrProgram canonical) => _rebase?.call(canonical);

  /// Resolves locally known structure before whole-program analysis.
  /// No entry-state assumptions or facts from another graph may be used here.
  IrProgram normalize(IrProgram program) =>
      _normalize?.call(program) ?? program;

  /// Rewrites a graph using its current execution facts.
  IrProgram call(ProgramFlowFacts facts) => _run(facts);

  /// Updates supplied entry values after this transform has changed the graph.
  /// Implementations may change; semantic identity and type must remain equal.
  FlowValue rebindEntry(FlowValue value) => _rebindEntryConstant == null
      ? value
      : value.rebindConstants(_rebindEntryConstant);
}

/// The point at which a transform may change the current program.
enum ProgramPassKind() {
  /// Removes work or exposes facts without spending an expansion budget.
  reduction,

  /// Adds semantic code under a budget shared by the whole compilation.
  expansion,

  /// Realizes executable implementations and records replayable source choices.
  lowering,
}

/// Compilation-wide region growth accounting with free replay of the same copy.
final class ProgramExpansionBudget(final int limit) {
  final _remaining = <FunctionTarget, int>{};
  final _charged = <(FunctionTarget, Object), int>{};

  this {
    RangeError.checkNotNegative(limit, 'limit');
  }

  bool permits(FunctionTarget owner, Object key, int cost) =>
      cost - (_charged[(owner, key)] ?? 0) <= remaining(owner);

  int remaining(FunctionTarget owner) => _remaining[owner] ?? limit;

  void charge(FunctionTarget owner, Object key, int cost) {
    final previous = _charged[(owner, key)] ?? 0;
    if (cost < 0 || !permits(owner, key, cost)) {
      throw StateError('Expansion exceeds its compilation growth budget.');
    }
    if (cost <= previous) return;
    _charged[(owner, key)] = cost;
    _remaining[owner] = remaining(owner) - (cost - previous);
  }
}

/// A semantic transformation consuming facts for exactly one immutable program.
///
/// Returns the same program when unchanged. Changed graphs invalidate all
/// previous facts; the driver solves the new graph from its original entries.
abstract class const ProgramPass() {
  /// The scheduling contract; implementation edges precede semantic rewrites.
  ProgramPassKind get kind => .reduction;

  /// Starts one compilation; expansion budgets survive every subsequent rewrite.
  ProgramTransform bind() => ProgramTransform(run);

  /// Transforms one graph with fresh work state for a standalone invocation.
  IrProgram run(ProgramFlowFacts facts);
}
