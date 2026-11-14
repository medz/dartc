import 'package:dartc/ir.dart';

import 'function_rewrite.dart';
import 'program_flow.dart';
import 'program_pass.dart';

/// Binds proven dispatch targets using their own defaults and generic signature.
final class const ProgramCallSpecialization() implements ProgramPass {
  @override
  bool get repeatUntilStable => true;

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
            if (operation is! InstanceCall && operation is! DynamicDispatch ||
                !facts.reachesOperation(operation) ||
                facts.hasUnknownCall(operation)) {
              continue;
            }
            final targets = facts.targetsOf(operation);
            if (targets.length != 1) continue;
            final target = targets.single;
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
              _ => throw StateError('Expected a dispatch operation.'),
            };
            if (!target.kind.isVirtual ||
                target.selector != selector ||
                receiver.type is! ClassType) {
              continue;
            }
            final owner = (receiver.type as ClassType).asInstanceOf(
              target.owner!,
            );
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
              [receiver, ...inputs],
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
