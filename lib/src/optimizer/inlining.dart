import 'package:dartc/ir.dart';

import 'function_rewrite.dart';
import 'program_flow.dart';
import 'program_pass.dart';

/// Expands bounded direct calls in the executable bodies selected by analysis.
///
/// Costs include copied operations, argument views and logical frame metadata.
/// Limits must be nonnegative; zero disables expansion. Callees must be
/// synchronous bodies that can be copied with their parameter and type bindings.
/// Arguments retain evaluation order, effects and exceptional continuations.
///
/// This expansion runs once per pipeline position; subsequent shrinking passes
/// may simplify its results without resetting and repeatedly spending its budget.
final class const DirectCallInlining({
  final int maxCalleeCost = 12,
  final int maxCallerGrowth = 64,
}) implements ProgramPass {
  @override
  bool get repeatUntilStable => false;

  @override
  IrProgram run(ProgramFlowFacts facts) {
    facts.checkProgram(facts.program);
    RangeError.checkNotNegative(maxCalleeCost, 'maxCalleeCost');
    RangeError.checkNotNegative(maxCallerGrowth, 'maxCallerGrowth');
    if (maxCalleeCost == 0 || maxCallerGrowth == 0) return facts.program;
    return _inlineSelected(
      facts.program,
      facts,
      maxCalleeCost,
      maxCallerGrowth,
    );
  }
}

IrProgram _inlineSelected(
  IrProgram program,
  ProgramFlowFacts facts,
  int maxCalleeCost,
  int maxCallerGrowth,
) {
  var changed = false;
  final functions = <IrFunction>[];
  for (final function in program.functions) {
    final sites = <DirectCall, ({IrFunction body, Jump? handler})>{};
    var budget = maxCallerGrowth;
    if (facts.definitions.contains(function.target) &&
        function.bodyKind == .synchronous) {
      for (final block in function.blocks) {
        for (final (operation, handler) in [
          for (final operation in block.instructions) (operation, null),
          if (block.end case Invoke(:final operation, :final onThrow))
            (operation, onThrow),
        ]) {
          if (operation is! DirectCall ||
              operation.target == function.target ||
              !facts.reachesOperation(operation)) {
            continue;
          }
          final body = program.implementationOf(operation.target);
          if (body is! IrFunction ||
              body.bodyKind != .synchronous ||
              body.target.kind == .initializer ||
              body.target.enclosing != null ||
              body.target.awaiterCapture != null ||
              body.closures.isNotEmpty ||
              !_entryChecksProved(operation, facts)) {
            continue;
          }
          var copies = 0, allocations = 0;
          for (final block in body.blocks) {
            copies += block.instructions.length + block.parameters.length + 1;
            for (final operation in [
              ...block.instructions,
              if (block.end case Invoke(:final operation)) operation,
            ]) {
              if (operation.effects.contains(Effect.allocates)) allocations++;
            }
          }
          final cost = copies + 11 * allocations;
          final growth = copies + (handler == null ? 0 : 2 * copies);
          if (cost > maxCalleeCost || growth > budget) continue;
          budget -= growth;
          sites[operation] = (body: body, handler: handler);
        }
      }
    }
    if (sites.isEmpty) {
      functions.add(function);
    } else {
      functions.add(FunctionRewrite(function, inlined: sites).run());
      changed = true;
    }
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

bool _entryChecksProved(DirectCall call, ProgramFlowFacts facts) {
  final target = call.target;
  if (target.covariantParameters.isEmpty) return true;
  final owner = target.owner!;
  final receiver = facts.valueOf(call.inputs.first);
  for (final slot in target.covariantParameters) {
    final parameter = target.signature.parameters[slot];
    final ownerDependent = parameter.freeTypeParameters.any(
      owner.typeParameters.contains,
    );
    if (ownerDependent && receiver.unknownTypes.isNotEmpty) return false;
    final actualTypes = receiver.types.whereType<ClassType>().toList();
    if (actualTypes.isEmpty) return false;
    for (final type in actualTypes) {
      final environment = {
        ...target.environmentFor(type),
        for (final (i, type) in call.typeArguments.indexed)
          target.typeParameters[i]: type,
      };
      final actual = facts.valueOf(call.inputs[target.argumentOffset + slot]);
      if (actual.isBottom ||
          actual.check(parameter.substitute(environment)).mayFail) {
        return false;
      }
    }
  }
  return true;
}
