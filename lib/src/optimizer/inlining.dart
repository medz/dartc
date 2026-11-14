import 'package:dartc/ir.dart';

import 'function_rewrite.dart';
import 'program_flow.dart';
import 'program_pass.dart';

/// Expands known direct and lexical calls without changing their entry values.
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
        count +
        block.instructions.length +
        (block == function.entry ? 0 : block.parameters.length) +
        (function.blocks.length == 1 && block.end is Return ? 0 : 1),
  );
  bool allocates(Instruction operation) =>
      facts.effectsOf(operation).contains(Effect.allocates);

  ({IrFunction body, int copies, int allocations}) expand(IrFunction function) {
    if (expanded[function.target] case final result?) return result;
    visiting.add(function.target);
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

    IrFunction rewrite(IrFunction input, {required bool sourceFacts}) {
      final sites =
          <
            Instruction,
            ({
              IrFunction body,
              List<Value> arguments,
              Map<TypeParameterType, ValueType> environment,
              Jump? handler,
            })
          >{};
      final dominance = ValueDominance(input);
      MakeClosure? closureOf(FunctionCall call) {
        Value unwrap(Value value) {
          while (true) {
            switch (value) {
              case TypeView(:final operand) || UncheckedCast(:final operand):
                value = operand;
              default:
                return value;
            }
          }
        }

        final literal = unwrap(call.function);
        if (literal is MakeClosure) return literal;
        if (!sourceFacts) return null;
        for (final equivalent in facts.equivalentsOf(call.function)) {
          final literal = unwrap(equivalent);
          if (literal is MakeClosure && dominance.before(literal, call)) {
            return literal;
          }
        }
        return null;
      }

      for (final block in input.blocks) {
        for (final (operation, handler) in [
          for (final operation in block.instructions) (operation, null),
          if (block.end case Invoke(:final operation, :final onThrow))
            (operation, onThrow),
        ]) {
          if (sourceFacts && !facts.reachesOperation(operation)) continue;
          final FunctionTarget target;
          final List<Value> arguments;
          final Map<TypeParameterType, ValueType> environment;
          if (operation is DirectCall && sourceFacts) {
            if (!_entryChecksProved(operation, facts)) continue;
            target = operation.target;
            arguments = operation.inputs;
            environment = {
              if (operation.ownerType case final owner?)
                ...target.environmentFor(owner),
              for (final (i, type) in operation.typeArguments.indexed)
                target.typeParameters[i]: type,
            };
          } else if (operation is FunctionCall) {
            final closure = closureOf(operation);
            if (closure == null) continue;
            target = closure.target;
            final declaration = program.implementationOf(target);
            if (declaration == null) continue;
            environment = {
              for (final (i, type) in operation.typeArguments.indexed)
                target.typeParameters[i]: type,
            };
            arguments = [
              operation.function,
              ...closure.inputs,
              ...target.signature
                  .instantiate(operation.typeArguments)
                  .bind<Value>(
                    operation.positional,
                    operation.named,
                    (slot) => declaration.defaults[slot]!,
                  ),
            ];
          } else {
            continue;
          }
          if (visiting.contains(target)) continue;
          final source = program.implementationOf(target);
          if (source is! IrFunction ||
              source.bodyKind != .synchronous ||
              target.kind == .initializer ||
              target.awaiterCapture != null) {
            continue;
          }
          final candidate = expand(source);
          if (candidate.body.closures.isNotEmpty) continue;
          var views = 0, boxes = 0;
          for (final (i, parameter) in source.entry.parameters.indexed) {
            final type = parameter.type.substitute(environment);
            final argument = arguments[i];
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
          allocations += candidate.allocations + boxes;
          if (sourceFacts && allocates(operation)) allocations--;
          sites[operation] = (
            body: candidate.body,
            arguments: arguments,
            environment: environment,
            handler: handler,
          );
        }
      }
      return sites.isEmpty
          ? input
          : FunctionRewrite(
              input,
              inlined: sites,
              discardable: {
                if (sourceFacts)
                  for (final block in input.blocks)
                    for (final operation in [
                      ...block.instructions,
                      if (block.end case Invoke(:final operation)) operation,
                    ])
                      if (facts.canDiscard(operation)) operation,
              },
            ).run();
    }

    var body = function;
    if (executable && function.bodyKind == .synchronous) {
      body = rewrite(body, sourceFacts: true);
      // Copied callees can expose the caller's closure literal and its shared cells.
      while (!identical(body, function) && budget > 0) {
        final next = rewrite(body, sourceFacts: false);
        if (identical(next, body)) break;
        body = next;
      }
      if (!identical(body, function)) {
        final closures = {
          for (final block in body.blocks)
            ...block.instructions.whereType<MakeClosure>(),
        };
        body = FunctionRewrite(body, discardable: closures).run();
        final retained = body.blocks.fold(
          0,
          (count, block) =>
              count + block.instructions.whereType<MakeClosure>().length,
        );
        allocations -= closures.length - retained;
      }
    }
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
