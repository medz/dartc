import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';

/// Expands retained stack snapshots into ordinary runtime calls.
///
/// Runtime dependencies enter analysis before destructive specialization. Frame
/// values bind to this function's allocated frame, never to host PCs.
final class StackTraceLowering(final FunctionTarget capture)
    extends ProgramPass {
  @override
  ProgramPassKind get kind => .lowering;

  @override
  ProgramTransform bind() {
    final recipes = <IrOrigin, ProgramRealization>{};
    return ProgramTransform((facts) {
      facts.checkProgram(facts.program);
      final definitions = facts.definitions;
      return _lower(facts.program, (function, operation) {
        if (!definitions.contains(function.target) || !facts.reachesOperation(operation)) return false;
        final source = function.originOf(operation).source;
        recipes.putIfAbsent(source, () => ProgramRealization(
          (StackTraceLowering, source),
          (canonical) => _lower(canonical, (owner, site) =>
              owner.originOf(site).source == source),
        ));
        return true;
      });
    }, realizations: () => recipes.values, requiresRetainedUse: true);
  }

  @override
  IrProgram run(ProgramFlowFacts facts) => bind()(facts);

  /// Expands snapshots without optimizing the caller's supplied IR.
  IrProgram lower(IrProgram program) => _lower(program, (_, _) => true);

  IrProgram _lower(
    IrProgram program,
    bool Function(IrFunction, CaptureStackTrace) selected,
  ) {
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
          for (final operation in [
            ...block.instructions,
            if (block.end case Invoke(:final operation)) operation,
          ])
            if (operation is CaptureStackTrace && selected(function, operation))
              operation: DirectCall(capture, [
                FrameValue(.callerStackPointer),
                FrameValue(.returnAddress),
              ]),
      };
      final rewritten = operations.isEmpty
          ? function
          : FunctionRewrite(function, executionShapes: program.executionShapes, operations: operations).run();
      changed |= !identical(function, rewritten);
      functions.add(rewritten);
    }
    return changed
        ? IrProgram(
            program.classes,
            functions,
            globals: program.globals,
            nativeBoundaries: program.nativeBoundaries,
            executionShapes: program.executionShapes,
            externals: program.externals,
          )
        : program;
  }
}
