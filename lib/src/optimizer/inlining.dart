import 'package:dartc/ir.dart';

import 'function_rewrite.dart';
import 'program_flow.dart';
import 'program_pass.dart';
import 'simplification.dart';
import 'storage_elimination.dart';

/// Expands known direct and lexical calls without changing their entry values.
///
/// Callees are expanded before their callers, independently of declaration order.
/// Costs include additional allocation effects, copied operations and argument views.
/// Limits must be nonnegative; zero disables expansion. Callees must be
/// synchronous bodies that can be copied with their parameter and type bindings.
/// Arguments retain evaluation order, effects and exceptional continuations.
///
/// Each compilation retains a per-function size limit. Shrinking a graph frees
/// space for later expansion without raising that limit.
final class const DirectCallInlining({
  final int maxCalleeCost = 12,
  final int maxCallerGrowth = 64,
}) extends ProgramPass {
  @override
  ProgramPassKind get kind => .expansion;

  @override
  IrProgram run(ProgramFlowFacts facts) => bind()(facts);

  @override
  ProgramTransform bind() {
    RangeError.checkNotNegative(maxCalleeCost, 'maxCalleeCost');
    RangeError.checkNotNegative(maxCallerGrowth, 'maxCallerGrowth');
    final limits = <FunctionTarget, int>{};
    IrProgram inline(IrProgram program, ProgramFlowFacts? facts) {
      facts?.checkProgram(program);
      if (maxCalleeCost == 0 || maxCallerGrowth == 0) return program;
      return _inlineSelected(
        program,
        facts,
        maxCalleeCost,
        maxCallerGrowth,
        limits,
      );
    }

    return ProgramTransform(
      (facts) => inline(facts.program, facts),
      normalize: (program) => inline(program, null),
    );
  }
}

IrProgram _inlineSelected(
  IrProgram program,
  ProgramFlowFacts? facts,
  int maxCalleeCost,
  int maxCallerGrowth,
  Map<FunctionTarget, int> limits,
) {
  final discardableStorage = facts == null ? null : storageDiscardable(facts);
  final expanded =
      <FunctionTarget, ({IrFunction body, int copies, int allocations})>{};
  final visiting = <FunctionTarget>[];
  final recursive = <FunctionTarget>{};
  int copies(IrFunction function) => function.blocks.fold(
    0,
    (count, block) =>
        count +
        block.instructions.length +
        (block == function.entry ? 0 : block.parameters.length) +
        (function.blocks.length == 1 && block.end is Return ? 0 : 1),
  );
  bool allocates(Instruction operation) =>
      (facts?.effectsOf(operation) ?? operation.effects).contains(
        Effect.allocates,
      );

  ({IrFunction body, int copies, int allocations}) expand(IrFunction function) {
    if (expanded[function.target] case final result?) return result;
    visiting.add(function.target);
    final size = copies(function);
    final limit = limits.putIfAbsent(
      function.target,
      () => size + maxCallerGrowth,
    );
    var budget = limit > size ? limit - size : 0, allocations = 0;
    final executable =
        facts == null || facts.definitions.contains(function.target);
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
      final incoming = <Block, List<Jump>>{};
      for (final block in input.blocks) {
        for (final edge in block.successors) {
          (incoming[edge.target] ??= []).add(edge);
        }
      }
      final aliases = <Value, Value>{
        for (final block in input.blocks)
          if (incoming[block]?.singleOrNull case final edge?)
            for (final (index, parameter) in block.parameters.indexed)
              parameter: edge.arguments[index],
      };
      final owned = {
        for (final block in input.blocks) ...[
          ...block.instructions,
          if (block.end case Invoke(:final operation)) operation,
        ],
      };
      ({MakeClosure closure, Value receiver})? closureOf(FunctionCall call) {
        final receiverValues = <Value>[];
        Value unwrap(Value value) {
          final visited = <Value>{};
          while (visited.add(value)) {
            receiverValues.add(value);
            switch (value) {
              case TypeView(:final operand) || UncheckedCast(:final operand):
                value = operand;
              default:
                final origin = aliases[value];
                if (origin == null) return value;
                value = origin;
            }
          }
          return value;
        }

        final literal = unwrap(call.function);
        if (literal is MakeClosure) {
          final receiver = receiverValues
              .where(
                (value) =>
                    literal.type.accepts(value.type) &&
                    dominance.before(value, call),
              )
              .firstOrNull;
          if (receiver != null) return (closure: literal, receiver: receiver);
        }
        if (!sourceFacts) return null;
        for (final equivalent in facts!.equivalentsOf(call.function)) {
          final literal = unwrap(equivalent);
          if (literal is MakeClosure && dominance.before(literal, call)) {
            return (closure: literal, receiver: literal);
          }
        }
        final callable = facts.valueOf(call.function);
        if (callable.objects.isEmpty ||
            callable.unknownTypes.isNotEmpty ||
            callable.constants.isNotEmpty ||
            callable.addresses.isNotEmpty) {
          return null;
        }
        final origins = {for (final object in callable.objects) object.site};
        if (origins.singleOrNull case final MakeClosure closure
            when owned.contains(closure) &&
                closure.inputs.every(
                  (value) => dominance.before(value, call),
                )) {
          final state = facts.pointStateOf(call)!.before;
          for (final object in callable.objects) {
            final captures = state.capturesOf(object);
            if (captures == null || captures.length != closure.inputs.length) {
              return null;
            }
            for (final (index, value) in closure.inputs.indexed) {
              final actual = captures[index], current = facts.valueOf(value);
              if (!(actual.constant != null &&
                      current.constant != null &&
                      actual.constant!.structuralKey ==
                          current.constant!.structuralKey) &&
                  !actual.sources.any(current.sources.contains)) {
                return null;
              }
            }
          }
          // Invoke results are available through their normal-edge parameter.
          if (closure.type.accepts(literal.type)) {
            return (closure: closure, receiver: literal);
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
          if (sourceFacts && !facts!.reachesOperation(operation)) continue;
          final FunctionTarget target;
          final List<Value> arguments;
          final Map<TypeParameterType, ValueType> environment;
          if (operation is DirectCall && sourceFacts) {
            if (!_entryChecksProved(operation, facts!)) continue;
            target = operation.target;
            arguments = operation.inputs;
            environment = {
              if (operation.ownerType case final owner?)
                ...target.environmentFor(owner),
              for (final (i, type) in operation.typeArguments.indexed)
                target.typeParameters[i]: type,
            };
          } else if (operation is FunctionCall) {
            final binding = closureOf(operation);
            if (binding == null) continue;
            final closure = binding.closure;
            target = closure.target;
            final declaration = program.implementationOf(target);
            if (declaration == null) continue;
            environment = {
              for (final (i, type) in operation.typeArguments.indexed)
                target.typeParameters[i]: type,
            };
            arguments = [
              binding.receiver,
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
          final cycle = visiting.indexOf(target);
          if (cycle >= 0) {
            recursive.addAll(visiting.skip(cycle));
            continue;
          }
          final source = program.implementationOf(target);
          if (source is! IrFunction ||
              source.bodyKind != .synchronous ||
              target.kind == .initializer ||
              target.awaiterCapture != null ||
              source.observesCallerFrame) {
            continue;
          }
          var candidate = expand(source);
          if (recursive.contains(target)) continue;
          if (sourceFacts) {
            final activations = facts!
                .callActivationsOf(operation)
                .intersection(facts.activationsOf(target).toSet());
            if (activations.isNotEmpty) {
              final origins = <Instruction, Instruction>{};
              final specialized = simplifyFunction(
                facts,
                source,
                activations: activations,
                discardable: discardableStorage!(
                  source,
                  activations: activations,
                ),
                instructionSources: origins,
              );
              var allocations = 0;
              for (final block in specialized.blocks) {
                for (final operation in [
                  ...block.instructions,
                  if (block.end case Invoke(:final operation)) operation,
                ]) {
                  final origin = facts.owns(operation)
                      ? operation
                      : origins[operation];
                  if (origin == null
                      ? operation.effects.contains(Effect.allocates)
                      : activations.any(
                          (activation) => facts
                              .effectsOf(origin, activation: activation)
                              .contains(Effect.allocates),
                        )) {
                    allocations++;
                  }
                }
              }
              final cost = copies(specialized);
              if (!identical(specialized, source) &&
                  specialized.closures.isEmpty &&
                  cost + 11 * allocations <
                      candidate.copies + 11 * candidate.allocations) {
                candidate = (
                  body: specialized,
                  copies: cost,
                  allocations: allocations,
                );
              }
            }
          }
          if (candidate.body.closures.isNotEmpty) continue;
          late final live = ValueLiveness.source(candidate.body)
              .liveIn[candidate.body.entry]!;
          if (arguments.indexed.any(
            (entry) =>
                entry.$2 is CallFrameValue &&
                live.contains(candidate.body.entry.parameters[entry.$1]),
          )) {
            continue;
          }
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
          final extraAllocations =
              candidate.allocations +
              boxes -
              (sourceFacts && allocates(operation) ? 1 : 0);
          final cost =
              candidate.copies +
              views +
              11 * (extraAllocations > 0 ? extraAllocations : 0);
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
                      if (facts!.canDiscard(operation)) operation,
              },
            ).run();
    }

    var body = function;
    if (executable && function.bodyKind == .synchronous) {
      body = rewrite(body, sourceFacts: facts != null);
      // Copied callees can expose the caller's closure literal and its shared cells.
      while (!identical(body, function) && budget > 0) {
        final next = rewrite(body, sourceFacts: false);
        if (identical(next, body)) break;
        body = next;
      }
      if (!identical(body, function)) {
        final closures = {
          for (final block in body.blocks)
            ...[
              ...block.instructions,
              if (block.end case Invoke(:final operation)) operation,
            ].whereType<MakeClosure>(),
        };
        body = FunctionRewrite(body, discardable: closures).run();
        final retained = body.blocks.fold(
          0,
          (count, block) =>
              count +
              [
                ...block.instructions,
                if (block.end case Invoke(:final operation)) operation,
              ].whereType<MakeClosure>().length,
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
