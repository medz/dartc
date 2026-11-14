import 'package:dartc/ir.dart';

import 'function_rewrite.dart';
import 'program_flow.dart';
import 'program_pass.dart';

/// Binds proven dispatch targets using their own defaults and generic signature.
final class const ProgramCallSpecialization() extends ProgramPass {
  @override
  IrProgram run(ProgramFlowFacts facts) {
    facts.checkProgram(facts.program);
    var changed = false;
    final functions = <IrFunction>[];
    for (final function in facts.program.functions) {
      final operations = <Instruction, Instruction>{};
      if (facts.definitions.contains(function.target)) {
        for (final block in function.blocks) {
          for (final operation in [
            ...block.instructions,
            if (block.end case Invoke(:final operation)) operation,
          ]) {
            // Equality also applies the null rule and optional negation.
            if (operation is Equals ||
                operation is! InstanceCall &&
                    operation is! DynamicDispatch &&
                    operation is! FunctionCall &&
                    operation.implicitMember == null ||
                !facts.reachesOperation(operation) ||
                facts.hasUnknownCall(operation)) {
              continue;
            }
            final targets = facts.targetsOf(operation);
            if (targets.length != 1) continue;
            final target = targets.single;
            if (operation is FunctionCall) {
              if (facts.valueOf(operation.function).constant
                  case final FunctionConstant value) {
                final binding = value.resolveInvocation(
                  operation.typeArguments,
                );
                final destination = binding.target;
                final body = facts.program.implementationOf(destination)!;
                final signature = binding.owner == null
                    ? destination.signature
                    : destination.signatureFor(binding.owner!);
                final applied = signature.instantiate(binding.typeArguments);
                final inputs = applied.bind<Value>(
                  operation.positional,
                  operation.named,
                  (slot) => body.defaults[slot]!,
                );
                if (inputs.indexed.every(
                      (entry) =>
                          applied.parameters[entry.$1].accepts(entry.$2.type),
                    ) &&
                    operation.type.accepts(applied.result)) {
                  operations[operation] = destination.kind == .initializer
                      ? Construct(
                          destination,
                          inputs,
                          instantiatedType: binding.owner,
                        )
                      : DirectCall(
                          destination,
                          inputs,
                          ownerType: binding.owner,
                          typeArguments: binding.typeArguments,
                        );
                  continue;
                }
              }
              if (operation.target != target) {
                operations[operation] = FunctionCall(
                  operation.function,
                  operation.positional,
                  operation.named,
                  operation.typeArguments,
                  target,
                );
              }
              continue;
            }
            if (operation is DynamicDispatch &&
                (operation.failure == target ||
                    operation.getterCalls.containsValue(target))) {
              operations[operation] = DirectCall(
                target,
                operation.inputs,
                typeArguments: operation.typeArguments,
              );
              continue;
            }
            final (
              receiver,
              selector,
              positional,
              named,
              types,
            ) = switch (operation) {
              InstanceCall(
                :final receiver,
                :final member,
                :final positional,
                :final named,
                :final typeArguments,
              ) =>
                (receiver, member.selector, positional, named, typeArguments),
              DynamicDispatch(
                :final receiver,
                :final selector,
                :final positional,
                :final named,
                :final typeArguments,
              ) =>
                (receiver, selector, positional, named, typeArguments),
              _ when operation.implicitMember != null => (
                operation.inputs.first,
                operation.implicitMember!.selector,
                operation.inputs.skip(1).toList(),
                const <String, Value>{},
                const <ValueType>[],
              ),
              _ => throw StateError('Expected a dispatch operation.'),
            };
            if (!target.kind.isVirtual || target.selector != selector) {
              continue;
            }
            final owner = _receiverOwner(facts, receiver, target.owner!);
            if (owner == null) continue;
            final signature = target.signatureFor(owner);
            if (!signature.acceptsShape(positional.length, named.keys)) {
              continue;
            }
            final arguments = types.isEmpty && operation is DynamicDispatch
                ? signature.defaultTypeArguments
                : types;
            if (arguments.length != signature.typeParameters.length) continue;
            final environment = {
              ...target.environmentFor(owner),
              for (final (i, type) in arguments.indexed)
                target.typeParameters[i]: type,
            };
            if (target.typeParameters.indexed.any(
              (entry) => !entry.$2.bound
                  .substitute(environment)
                  .accepts(arguments[entry.$1]),
            )) {
              continue;
            }
            final bound = signature.instantiate(arguments);
            final body = facts.program.implementationOf(target)!;
            final inputs = bound.bind<Value>(
              positional,
              named,
              (slot) => body.defaults[slot]!,
            );
            if (inputs.indexed.any(
                  (entry) => !bound.parameters[entry.$1].accepts(entry.$2.type),
                ) ||
                !operation.type.accepts(bound.result)) {
              continue;
            }
            operations[operation] = DirectCall(
              target,
              [
                owner.accepts(receiver.type)
                    ? receiver
                    : UncheckedCast(receiver, owner),
                ...inputs,
              ],
              ownerType: owner,
              typeArguments: arguments,
            );
          }
        }
      }
      final rewritten = operations.isEmpty
          ? function
          : FunctionRewrite(function, operations: operations).run();
      changed |= !identical(rewritten, function);
      functions.add(rewritten);
    }
    return changed
        ? IrProgram(
            facts.program.classes,
            functions,
            globals: facts.program.globals,
            externals: facts.program.externals,
          )
        : facts.program;
  }
}

ClassType? _receiverOwner(
  ProgramFlowFacts facts,
  Value receiver,
  ClassType declaration,
) {
  if (declaration.typeParameters.isEmpty && receiver.type is ClassType) {
    final owner = (receiver.type as ClassType).asInstanceOf(declaration);
    if (owner != null) return owner;
  }
  final actual = facts.valueOf(receiver);
  if (actual.isBottom || actual.unknownTypes.isNotEmpty) return null;
  final owners = <ClassType>{};
  for (final type in actual.types) {
    final owner = type is ClassType ? type.asInstanceOf(declaration) : null;
    if (owner == null) return null;
    owners.add(owner);
  }
  return owners.length == 1 ? owners.single : null;
}
