import 'package:dartc/ir.dart';

import 'program_flow.dart';

/// A semantic transformation consuming facts for exactly one immutable program.
///
/// Returns the same program when unchanged. Changed graphs invalidate all
/// previous facts; the driver solves the new graph from its original entries.
abstract interface class ProgramPass() {
  /// Whether this pass joins the transformations solved to a common fixed point.
  ///
  /// Repeated passes must make progress toward a fixed point. Expansion passes
  /// can instead run once, with shrinking passes scheduled after them.
  bool get repeatUntilStable;

  /// Transforms the checked program described by [facts].
  IrProgram run(ProgramFlowFacts facts);
}
