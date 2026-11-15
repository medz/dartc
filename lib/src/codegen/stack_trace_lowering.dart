import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';

/// Expands retained stack snapshots into ordinary runtime calls.
///
/// Shrinking passes first remove snapshots with no observer. Frame values are
/// bound to this function's allocated frame during emission, never to host PCs.
final class StackTraceLowering(final FunctionTarget capture)
    extends ProgramPass {
  @override
  bool get expandsCode => true;

  @override
  IrProgram run(ProgramFlowFacts facts) {
    facts.checkProgram(facts.program);
    return lower(facts.program);
  }

  /// Expands snapshots without optimizing the caller's supplied IR.
  IrProgram lower(IrProgram program) {
    final declaration = program.implementationOf(capture);
    if (declaration is! IrFunction ||
        capture.signature != FunctionType(.stackTrace, [.integer, .integer])) {
      throw ArgumentError('Stack capture requires a supplied Dart body.');
    }
    var changed = false;
    final functions = <IrFunction>[];
    for (final function in program.functions) {
      final operations = <Instruction, Instruction>{
        for (final block in function.blocks)
          for (final operation in block.instructions)
            if (operation is CaptureStackTrace)
              operation: DirectCall(capture, [
                FrameValue(.callerStackPointer),
                FrameValue(.returnAddress),
              ]),
      };
      final rewritten = operations.isEmpty
          ? function
          : FunctionRewrite(function, operations: operations).run();
      changed |= !identical(function, rewritten);
      functions.add(rewritten);
    }
    return changed
        ? IrProgram(
            program.classes,
            functions,
            globals: program.globals,
            externals: program.externals,
          )
        : program;
  }
}
