import 'package:dartc/ir.dart';

import 'program_flow.dart';

/// One compilation's transform, retaining only its own bounded work state.
typedef ProgramTransform = IrProgram Function(ProgramFlowFacts facts);

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
  ProgramTransform bind() => run;

  /// Transforms one graph with fresh work state for a standalone invocation.
  IrProgram run(ProgramFlowFacts facts);
}
