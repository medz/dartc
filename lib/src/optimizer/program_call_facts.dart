import 'package:dartc/ir.dart';

/// Executable call and receiver facts bound to one immutable program.
///
/// These queries do not authorize adding internal implementations as roots.
/// Any new executable edge requires a fresh solve of its real caller and inputs.
abstract interface class const ProgramCallFacts() {
  IrProgram get program;
  Set<FunctionTarget> get definitions;

  /// Rejects graph replacement or changes to the analysis input contract.
  void checkProgram(IrProgram program);

  /// Whether an independently callable entry's declared inputs are covered.
  bool coversEntry(FunctionTarget target);

  /// Whether an observed receiver can have this actual nominal class.
  /// Values introduced outside the source graph have only their static bound;
  /// that conservative answer does not establish an analyzed execution edge.
  bool allows(Value receiver, ClassType actual);

  /// Executable implementations reached at this operation, including adapters.
  /// A callable's language identity is not a substitute for its execution body.
  Set<FunctionTarget> executionTargetsOf(Instruction operation);
}
