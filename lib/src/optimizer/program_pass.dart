import 'package:dartc/ir.dart';

import 'program_flow.dart';

/// One compilation's transforms, sharing their bounded work state.
final class ProgramTransform(
  final IrProgram Function(ProgramFlowFacts) _run, {
  IrProgram Function(IrProgram)? normalize,
}) {
  final _normalize = normalize;

  /// Resolves locally known structure before whole-program analysis.
  /// No entry-state assumptions or facts from another graph may be used here.
  IrProgram normalize(IrProgram program) =>
      _normalize?.call(program) ?? program;

  /// Rewrites a graph using its current execution facts.
  IrProgram call(ProgramFlowFacts facts) => _run(facts);
}

/// The point at which a transform may change the current program.
enum ProgramPassKind() {
  /// Removes work or exposes facts without spending an expansion budget.
  reduction,

  /// Adds semantic code under a budget shared by the whole compilation.
  expansion,

  /// Chooses an implementation after semantic optimizations have converged.
  lowering,
}

/// A semantic transformation consuming facts for exactly one immutable program.
///
/// Returns the same program when unchanged. Changed graphs invalidate all
/// previous facts; the driver solves the new graph from its original entries.
abstract class const ProgramPass() {
  /// The scheduling contract; lowerings run only at a semantic fixed point.
  ProgramPassKind get kind => .reduction;

  /// Starts one compilation; expansion budgets survive every subsequent rewrite.
  ProgramTransform bind() => ProgramTransform(run);

  /// Transforms one graph with fresh work state for a standalone invocation.
  IrProgram run(ProgramFlowFacts facts);
}
