import 'package:dartc/ir.dart';

/// Selects direct and nominal virtual call dependencies starting at [roots].
///
/// Virtual calls select implementations on classes constructed by reachable
/// bodies, constructor tear-offs, constants or [instantiatedTypes] supplied by
/// the caller. Dynamic selectors retain methods, accessors and noSuchMethod.
/// Each invocation starts from these roots; previous retained definitions are
/// never implicit roots after an IR transformation. The read-only result belongs
/// only to this [program] and these input facts. Redirecting factories select
/// their effective body. Direct targets with missing bodies remain in the set.
Set<FunctionTarget> reachableDefinitions(
  IrProgram program,
  Iterable<FunctionTarget> roots, {
  Iterable<ClassType> instantiatedTypes = const [],
}) {
  final pending = roots.toList(), reached = <FunctionTarget>{};
  final instances = {for (final type in instantiatedTypes) type.declaration};
  final members = <({ValueType receiver, MemberSelector selector})>{};
  void select(
    ClassType type,
    ({ValueType receiver, MemberSelector selector}) member,
  ) {
    if (!member.receiver.mayHaveInstance(type)) return;
    final target = program.lookupMember(type, member.selector).target;
    if (target != null) pending.add(target);
  }

  while (pending.isNotEmpty) {
    final target = pending.removeLast().implementation;
    if (!reached.add(target)) continue;
    final body = program.implementationOf(target);
    if (body == null) continue;
    pending.addAll(body.callees);
    if (body is IrFunction) {
      pending.addAll(body.closures);
      for (final global in body.globals) {
        if (global.initializer case final initializer?) {
          pending.add(initializer);
        }
      }
    }
    for (final type in [
      ...body.instantiatedClasses,
      if (body.recordTypes.isNotEmpty)
        for (final declaration in program.classes)
          if (declaration.recordStorage) declaration.type,
    ]) {
      if (instances.add(type)) {
        for (final member in members) {
          select(type, member);
        }
      }
    }
    for (final member in [
      for (final member in body.virtualMembers)
        (receiver: member.receiver, selector: member.target.selector),
      ...body.implicitMembers,
    ]) {
      if (members.add(member)) {
        for (final type in instances) {
          select(type, member);
        }
      }
    }
  }
  return Set.unmodifiable(reached);
}
