import 'package:dartc/ir.dart';

import 'function_rewrite.dart';
import 'program_flow.dart';
import 'program_pass.dart';

/// Expands bounded direct calls in the executable bodies selected by analysis.
///
/// Callees are expanded before their callers, independently of declaration order.
/// Costs include actual allocation effects, copied operations and argument views.
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
  final expanded =
      <FunctionTarget, ({IrFunction body, int copies, int allocations})>{};
  final visiting = <FunctionTarget>{};
  int copies(IrFunction function) => function.blocks.fold(
    0,
    (count, block) =>
        count + block.instructions.length + block.parameters.length + 1,
  );
  bool allocates(Instruction operation) =>
      facts.effectsOf(operation).contains(Effect.allocates);

  ({IrFunction body, int copies, int allocations}) expand(IrFunction function) {
    if (expanded[function.target] case final result?) return result;
    visiting.add(function.target);
    final sites = <DirectCall, ({IrFunction body, Jump? handler})>{};
    var budget = maxCallerGrowth, allocations = 0;
    final executable = facts.definitions.contains(function.target);
    if (executable) {
      for (final block in function.blocks) {
        for (final operation in [
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ]) {
          if (allocates(operation)) allocations++;
        }
      }
    }
    if (executable && function.bodyKind == .synchronous) {
      for (final block in function.blocks) {
        for (final (operation, handler) in [
          for (final operation in block.instructions) (operation, null),
          if (block.end case Invoke(:final operation, :final onThrow))
            (operation, onThrow),
        ]) {
          if (operation is! DirectCall ||
              visiting.contains(operation.target) ||
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
          final candidate = expand(body);
          final environment = {
            if (operation.ownerType case final owner?)
              ...body.target.environmentFor(owner),
            for (final (i, type) in operation.typeArguments.indexed)
              body.target.typeParameters[i]: type,
          };
          var views = 0, boxes = 0;
          for (final (i, parameter) in body.entry.parameters.indexed) {
            final type = parameter.type.substitute(environment);
            final argument = operation.inputs[i];
            if (type == argument.type) continue;
            views++;
            if (TypeView(argument, type).effects.contains(Effect.allocates)) {
              boxes++;
            }
          }
          final cost =
              candidate.copies + views + 11 * (candidate.allocations + boxes);
          final growth =
              candidate.copies +
              views +
              (handler == null ? 0 : 2 * candidate.copies);
          if (cost > maxCalleeCost || growth > budget) continue;
          budget -= growth;
          allocations +=
              candidate.allocations + boxes - (allocates(operation) ? 1 : 0);
          sites[operation] = (body: candidate.body, handler: handler);
        }
      }
    }
    final body = sites.isEmpty
        ? function
        : FunctionRewrite(function, inlined: sites).run();
    visiting.remove(function.target);
    return expanded[function.target] = (
      body: body,
      copies: copies(body),
      allocations: allocations,
    );
  }

  final functions = [
    for (final function in program.functions) expand(function).body,
  ];
  return functions.indexed.any(
        (entry) => !identical(entry.$2, program.functions[entry.$1]),
      )
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
