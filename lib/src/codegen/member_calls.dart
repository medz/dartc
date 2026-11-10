import 'package:dartc/ir.dart';

/// Resolves native member entries for the concrete classes in a compilation.
final class MemberCalls(
  final IrProgram program,
  final Set<FunctionTarget> definitions,
  final FunctionTarget invalid,
) {
  final _instances = {
    for (final target in definitions)
      ...?program.implementationOf(target)?.instantiatedClasses,
  };

  Map<ClassType, FunctionTarget> targetsFor(
    ValueType receiver,
    MemberSelector selector, {
    bool hasBuiltin = false,
  }) {
    if (!hasBuiltin &&
        (receiver == ValueType.object || receiver == ValueType.typeType)) {
      throw UnsupportedError(
        'Native built-in member unavailable: ${receiver.dartName}.${selector.name}',
      );
    }
    final targets = <ClassType, FunctionTarget>{};
    for (final type in _instances) {
      if (receiver.nonNullable case final ClassType owner
          when type.asInstanceOf(owner.declaration) == null) {
        continue;
      }
      final lookup = program.lookupMember(type, selector);
      if (lookup.target case final target?) {
        if (!definitions.contains(target)) {
          throw ArgumentError('Missing member definition: ${target.name}');
        }
        targets[type] = target;
      } else if (!hasBuiltin ||
          lookup.unmodeledBoundary != null ||
          lookup.unsupportedForwarder) {
        throw UnsupportedError(
          'Native member unavailable: ${type.dartName}.${selector.name}',
        );
      }
    }
    if (!hasBuiltin && targets.isEmpty) {
      throw UnsupportedError(
        'Native receiver classes unavailable: ${selector.name}',
      );
    }
    return targets;
  }
}
