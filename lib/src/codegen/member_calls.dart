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

  Map<ClassType, FunctionTarget> targetsFor(FunctionTarget member) {
    if (member.owner == ValueType.object) {
      throw UnsupportedError('Native Object member dispatch: ${member.name}');
    }
    final targets = <ClassType, FunctionTarget>{};
    for (final type in _instances) {
      if (type.asInstanceOf(member.owner!) == null) continue;
      final lookup = program.lookupMember(type, member.selector);
      final target = lookup.target;
      if (target == null) {
        throw UnsupportedError(
          'Native member unavailable: ${type.dartName}.${member.name}',
        );
      }
      if (!definitions.contains(target)) {
        throw ArgumentError('Missing member definition: ${target.name}');
      }
      targets[type] = target;
    }
    if (targets.isEmpty) {
      throw UnsupportedError(
        'Native receiver classes unavailable: ${member.name}',
      );
    }
    return targets;
  }
}
