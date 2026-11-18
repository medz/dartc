import 'package:dartc/ir.dart';
import 'package:dartc/optimizer.dart';

import 'native_views.dart';

/// Exposes native view allocation, ownership and copying before specialization.
final class NativeViewLowering(
  final NativeViews storage, {

  /// The supplied ordinary byte-copy body, taking two C addresses and a length.
  final FunctionTarget? copyBytes,
}) extends ProgramPass {
  @override
  ProgramPassKind get kind => .lowering;

  @override
  IrProgram run(ProgramFlowFacts facts) {
    facts.checkProgram(facts.program);
    return lower(facts.program, facts.definitions);
  }

  /// Rewrites reached implementations while preserving their caller and handler.
  IrProgram lower(IrProgram program, Iterable<FunctionTarget> definitions) {
    storage.register(program.classes);
    final selected = definitions.toSet();
    var changed = false;
    final functions = <IrFunction>[];
    for (final function in program.functions) {
      if (!selected.contains(function.target)) {
        functions.add(function);
        continue;
      }
      final operations = <Instruction, Instruction>{};
      for (final block in function.blocks) {
        for (final operation in [
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ]) {
          switch (operation) {
            case NativeView(
              type: final ClassType type,
              :final address,
              :final owner,
              :final copy,
            ):
              final view = storage.view(type);
              operations[operation] = address == null || copy
                  ? DirectCall(storage.owned(type, copy: copy), [
                      address ?? const Constant.integer(0),
                      owner,
                    ])
                  : Construct(view.initializer, [address, owner]);
            case NativeAddress(:final view):
              operations[operation] = LoadField(
                storage.view(view.type as ClassType).address,
                view,
              );
            case CopyNative(
              :final destination,
              :final source,
              :final nativeType,
            ):
              final target = copyBytes;
              if (target == null ||
                  program.implementationOf(target) is! IrFunction ||
                  target.signature !=
                      FunctionType(.voidType, [.integer, .integer, .integer])) {
                throw UnsupportedError(
                  'Native copying requires the supplied ordinary address-based byte-copy body.',
                );
              }
              operations[operation] = DirectCall(target, [
                destination,
                source,
                Constant.integer(storage.layout.of(nativeType).size),
              ]);
            default:
              break;
          }
        }
      }
      final rewritten = operations.isEmpty
          ? function
          : FunctionRewrite(function, executionShapes: program.executionShapes, operations: operations).run();
      changed |= !identical(rewritten, function);
      functions.add(rewritten);
    }
    return storage.normalize(
      program,
      rewrittenFunctions: changed ? functions : null,
    );
  }
}
