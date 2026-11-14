import 'package:dartc/ir.dart';

import 'program_flow.dart';

/// One compilation's transform, retaining only its own bounded work state.
typedef ProgramTransform = IrProgram Function(ProgramFlowFacts facts);

/// A semantic transformation consuming facts for exactly one immutable program.
///
/// Returns the same program when unchanged. Changed graphs invalidate all
/// previous facts; the driver solves the new graph from its original entries.
abstract class const ProgramPass() {
  /// Whether shrinking passes must converge before this pass can add code.
  bool get expandsCode => false;

  /// Starts one compilation; expansion budgets survive every subsequent rewrite.
  ProgramTransform bind() => run;

  /// Transforms one graph with fresh work state for a standalone invocation.
  IrProgram run(ProgramFlowFacts facts);
}
